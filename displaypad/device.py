"""
Mountain DisplayPad USB HID communication layer.

Protocol reverse-engineered from JeLuF/mountain-displaypad (Node.js).
Uses libusb via ctypes (hidapi can't see the device on macOS).

All USB I/O runs on a single worker thread to avoid macOS libusb
concurrency issues with interrupt transfers.

Two USB interfaces are used:
  - Interface 1, EP 0x02 OUT: Display data (1024-byte HID reports)
  - Interface 3, EP 0x04 OUT / EP 0x83 IN: Control (64-byte HID reports)
"""

import ctypes
import ctypes.util
import time
import threading
from collections import deque
from PIL import Image

VENDOR_ID = 0x3282
PRODUCT_ID = 0x0009

ICON_SIZE = 102
NUM_KEYS = 12
NUM_KEYS_PER_ROW = 6
NUM_TOTAL_PIXELS = ICON_SIZE * ICON_SIZE  # 10404
PIXEL_DATA_SIZE = NUM_TOTAL_PIXELS * 3     # 31212 (BGR, 3 bytes/pixel)
PACKET_SIZE = 31438                         # padded pixel buffer
HEADER_SIZE = 306                           # image header (all zeros)
CHUNK_SIZE = 1024

# 64-byte init command (no report ID — libusb sends raw)
INIT_MSG = bytes.fromhex(
    "11800000010000000000000000000000"
    "00000000000000000000000000000000"
    "00000000000000000000000000000000"
    "00000000000000000000000000000000"
)
INIT_1024 = INIT_MSG + bytes(CHUNK_SIZE - len(INIT_MSG))

# 64-byte image transfer command (no report ID)
# Byte 4 is overwritten with key index before sending
IMG_MSG = bytes.fromhex(
    "21000000003d000065650000000000000000000000000000000000000000000000"
    "0000000000000000000000000000000000000000000000000000000000000000"
)

# Button bit masks: data[42] bits for keys 1-7, data[47] bits for keys 8-12
KEY_MASKS = {
    1:  (42, 0x02),
    2:  (42, 0x04),
    3:  (42, 0x08),
    4:  (42, 0x10),
    5:  (42, 0x20),
    6:  (42, 0x40),
    7:  (42, 0x80),
    8:  (47, 0x01),
    9:  (47, 0x02),
    10: (47, 0x04),
    11: (47, 0x08),
    12: (47, 0x10),
}


def _init_libusb():
    """Load libusb and set up all function signatures (required on ARM64)."""
    VP = ctypes.c_void_p
    U8 = ctypes.c_uint8
    U16 = ctypes.c_uint16
    I = ctypes.c_int
    PI = ctypes.POINTER(I)
    PU8 = ctypes.POINTER(U8)

    path = ctypes.util.find_library("usb-1.0") or "/opt/homebrew/lib/libusb-1.0.dylib"
    lib = ctypes.cdll.LoadLibrary(path)

    for name, at, rt in [
        ("libusb_init", [ctypes.POINTER(VP)], I),
        ("libusb_exit", [VP], None),
        ("libusb_open_device_with_vid_pid", [VP, U16, U16], VP),
        ("libusb_close", [VP], None),
        ("libusb_kernel_driver_active", [VP, I], I),
        ("libusb_detach_kernel_driver", [VP, I], I),
        ("libusb_claim_interface", [VP, I], I),
        ("libusb_release_interface", [VP, I], I),
        ("libusb_control_transfer", [VP, U8, U8, U16, U16, PU8, U16, ctypes.c_uint], I),
        ("libusb_interrupt_transfer", [VP, U8, PU8, I, PI, ctypes.c_uint], I),
        ("libusb_error_name", [I], ctypes.c_char_p),
        ("libusb_reset_device", [VP], I),
        ("libusb_clear_halt", [VP, U8], I),
    ]:
        getattr(lib, name).argtypes = at
        getattr(lib, name).restype = rt

    return lib


_libusb = _init_libusb()
_VP = ctypes.c_void_p
_U8 = ctypes.c_uint8
_PU8 = ctypes.POINTER(_U8)


def rgb_to_bgr_buffer(image):
    """Convert a PIL Image to a BGR byte buffer for the DisplayPad."""
    img = image.convert("RGB").resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
    pixels = img.load()

    buf = bytearray(PACKET_SIZE)
    offset = 0
    for y in range(ICON_SIZE):
        for x in range(ICON_SIZE):
            r, g, b = pixels[x, y]
            buf[offset] = b
            buf[offset + 1] = g
            buf[offset + 2] = r
            offset += 3

    return bytes(buf)


def solid_color_buffer(r, g, b):
    """Create a solid color BGR buffer for one key."""
    buf = bytearray(PACKET_SIZE)
    offset = 0
    for _ in range(NUM_TOTAL_PIXELS):
        buf[offset] = b
        buf[offset + 1] = g
        buf[offset + 2] = r
        offset += 3
    return bytes(buf)


class DisplayPad:
    """Interface to the Mountain DisplayPad device via libusb.

    All USB I/O runs on a single worker thread.
    """

    def __init__(self):
        self._ctx = None
        self._handle = None
        self.initialized = False
        self._key_state = [False] * (NUM_KEYS + 1)
        self._on_key_down = None
        self._on_key_up = None
        self._worker_thread = None
        self._running = False
        self._queue = deque()
        self._lock = threading.Lock()
        self._first_transfer = True
        self._xfer = ctypes.c_int(0)  # persistent, shared (matches test_multikey.py)

    # ── Low-level USB I/O (only called from worker thread or during init) ──

    def _write_ep(self, ep, data, timeout=5000):
        buf = (_U8 * len(data))(*data)
        return _libusb.libusb_interrupt_transfer(
            self._handle, ep, buf, len(data), ctypes.byref(self._xfer), timeout
        )

    def _read_ep83(self, timeout=500):
        resp = (_U8 * 64)()
        rc = _libusb.libusb_interrupt_transfer(
            self._handle, 0x83, resp, 64, ctypes.byref(self._xfer), timeout
        )
        if rc == 0:
            return bytes(resp[:self._xfer.value])
        return None

    def _set_report(self, data, intf):
        buf = (_U8 * len(data))(*data)
        return _libusb.libusb_control_transfer(
            self._handle, 0x21, 0x09, 0x0200, intf,
            buf, len(data), 3000
        )

    # ── Connection ──

    def open(self):
        """Open connection to the DisplayPad. Blocks during boot."""
        self._ctx = _VP()
        rc = _libusb.libusb_init(ctypes.byref(self._ctx))
        if rc != 0:
            raise RuntimeError(f"libusb_init failed: {rc}")

        self._handle = _libusb.libusb_open_device_with_vid_pid(
            self._ctx, VENDOR_ID, PRODUCT_ID
        )
        if not self._handle:
            _libusb.libusb_exit(self._ctx)
            self._ctx = None
            raise RuntimeError(
                "DisplayPad not found. Check USB connection and permissions.\n"
                f"Looking for VID={VENDOR_ID:#06x} PID={PRODUCT_ID:#06x}\n"
                "You may need to run with sudo."
            )

        for intf in [0, 1, 3]:
            if _libusb.libusb_kernel_driver_active(self._handle, intf) == 1:
                _libusb.libusb_detach_kernel_driver(self._handle, intf)
            rc = _libusb.libusb_claim_interface(self._handle, intf)
            if rc != 0:
                raise RuntimeError(f"Failed to claim interface {intf}: {rc}")

        self._boot()

        self._running = True
        self._worker_thread = threading.Thread(target=self._worker_loop, daemon=True)
        self._worker_thread.start()

    def _boot(self):
        """Boot sequence: A→B→C. C is what actually gets ACK, but A/B prime the device."""
        start = time.time()

        # Strategy A: EP 0x04
        print("[boot] A: EP 0x04 init...")
        self._write_ep(0x04, INIT_MSG)
        t = time.time()
        while time.time() - t < 15:
            d = self._read_ep83(500)
            if d and d[0] == 0x11:
                print(f"[boot] INIT ACK! ({time.time()-start:.0f}s)")
                self.initialized = True
                return
            if d and d[0] == 0xFF:
                print(f"[boot] ffaa ({time.time()-start:.0f}s)")

        # Strategy B: EP 0x04 + EP 0x02
        print("[boot] B: EP 0x04 + EP 0x02...")
        self._write_ep(0x04, INIT_MSG)
        self._write_ep(0x02, INIT_1024)
        t = time.time()
        while time.time() - t < 10:
            d = self._read_ep83(500)
            if d and d[0] == 0x11:
                print(f"[boot] INIT ACK! ({time.time()-start:.0f}s)")
                self.initialized = True
                return
            if d and d[0] == 0xFF:
                print(f"[boot] ffaa ({time.time()-start:.0f}s)")

        # Strategy C: SET_REPORT + re-send on ffaa
        print("[boot] C: SET_REPORT + ffaa re-init...")
        self._set_report(INIT_MSG, intf=3)
        t = time.time()
        while time.time() - t < 15:
            d = self._read_ep83(500)
            if d and d[0] == 0x11:
                print(f"[boot] INIT ACK! ({time.time()-start:.0f}s)")
                self.initialized = True
                return
            if d and d[0] == 0xFF:
                self._write_ep(0x04, INIT_MSG)
                self._write_ep(0x02, INIT_1024)

        print(f"[boot] No ACK ({time.time()-start:.0f}s), proceeding anyway")
        self.initialized = True

    def close(self):
        self._running = False
        if self._worker_thread:
            self._worker_thread.join(timeout=2.0)
        if self._handle:
            for intf in [0, 1, 3]:
                _libusb.libusb_release_interface(self._handle, intf)
            _libusb.libusb_close(self._handle)
            self._handle = None
        if self._ctx:
            _libusb.libusb_exit(self._ctx)
            self._ctx = None
        self.initialized = False

    # ── Worker thread ──

    def _worker_loop(self):
        while self._running:
            item = None
            with self._lock:
                if self._queue:
                    item = self._queue.popleft()

            if item:
                key_index, pixel_data = item
                self._transfer_image(key_index, pixel_data)
            else:
                self._poll_buttons()

    def _poll_buttons(self):
        d = self._read_ep83(100)
        if d and d[0] == 0x01:
            self._process_buttons(d)
        elif d and d[0] != 0x01:
            pass  # non-button data during idle

    def _transfer_image(self, key_index, pixel_data):
        """Send image using local closure functions (matches working inline test)."""
        handle = self._handle
        xfer = ctypes.c_int(0)

        def write_ep(ep, data, timeout=5000):
            buf = (_U8 * len(data))(*data)
            return _libusb.libusb_interrupt_transfer(
                handle, ep, buf, len(data), ctypes.byref(xfer), timeout
            )

        def read83(timeout=500):
            resp = (_U8 * 64)()
            rc = _libusb.libusb_interrupt_transfer(
                handle, 0x83, resp, 64, ctypes.byref(xfer), timeout
            )
            if rc == 0:
                return bytes(resp[:xfer.value])
            return None

        def set_report(data, intf):
            buf = (_U8 * len(data))(*data)
            return _libusb.libusb_control_transfer(
                handle, 0x21, 0x09, 0x0200, intf, buf, len(data), 3000
            )

        print(f"[xfer] Key {key_index}...")

        # IMG command
        IMG = bytearray(64)
        IMG[0] = 0x21
        IMG[4] = key_index
        IMG[5] = 0x3d
        IMG[8] = 0x65
        IMG[9] = 0x65
        rc = write_ep(0x04, bytes(IMG))
        if rc != 0:
            print(f"[xfer]   IMG failed (rc={rc}), skipping")
            return

        # Wait for ACK
        acked = False
        for _ in range(20):
            d = read83(500)
            if d is None:
                continue
            if d[0] == 0x21 and d[1] == 0x00 and d[2] == 0x00:
                print(f"[xfer]   IMG ACK!")
                acked = True
                break
            elif d[0] == 0x01:
                self._process_buttons(d)

        if not acked:
            print(f"[xfer]   No ACK, skipping")
            return

        # Pixel chunks
        header = bytes(HEADER_SIZE)
        full_data = header + pixel_data
        ok = 0
        for i in range(0, len(full_data), CHUNK_SIZE):
            chunk = full_data[i:i + CHUNK_SIZE]
            if len(chunk) < CHUNK_SIZE:
                chunk = chunk + bytes(CHUNK_SIZE - len(chunk))
            if write_ep(0x02, chunk) == 0:
                ok += 1
        print(f"[xfer]   Chunks: {ok}/31")

        # Re-send
        for i in range(0, len(full_data), CHUNK_SIZE):
            chunk = full_data[i:i + CHUNK_SIZE]
            if len(chunk) < CHUNK_SIZE:
                chunk = chunk + bytes(CHUNK_SIZE - len(chunk))
            write_ep(0x02, chunk)
        print(f"[xfer]   Re-send done")

        # Completion wait
        done = False
        for _ in range(15):
            d = read83(1000)
            if d is None:
                continue
            if d[0] == 0x21 and d[1] == 0x00 and d[2] == 0xFF:
                print(f"[xfer]   Key {key_index} DONE!")
                done = True
                break
            elif d[0] == 0xFF:
                print(f"[xfer]   ffaa")
            elif d[0] == 0x01:
                self._process_buttons(d)

        if not done:
            print(f"[xfer]   Completion timeout, re-init")
            set_report(INIT_MSG, intf=3)
            write_ep(0x04, INIT_MSG)
            write_ep(0x02, INIT_1024)
            time.sleep(3)
            for _ in range(20):
                d = read83(200)
                if d is None:
                    break

    # ── Public API ──

    def set_key_image(self, key_index, image):
        pixel_data = rgb_to_bgr_buffer(image)
        with self._lock:
            self._queue.append((key_index, pixel_data))

    def set_key_color(self, key_index, r, g, b):
        pixel_data = solid_color_buffer(r, g, b)
        with self._lock:
            self._queue.append((key_index, pixel_data))

    def clear_key(self, key_index):
        self.set_key_color(key_index, 0, 0, 0)

    def clear_all(self):
        for i in range(NUM_KEYS):
            self.clear_key(i)

    def on_key_down(self, callback):
        self._on_key_down = callback

    def on_key_up(self, callback):
        self._on_key_up = callback

    def start_listening(self):
        pass

    def _process_buttons(self, data):
        for key_num, (byte_idx, mask) in KEY_MASKS.items():
            if byte_idx < len(data):
                pressed = bool(data[byte_idx] & mask)
                was_pressed = self._key_state[key_num]

                if pressed and not was_pressed:
                    self._key_state[key_num] = True
                    print(f"[btn] Key {key_num} DOWN")
                    if self._on_key_down:
                        try:
                            self._on_key_down(key_num)
                        except Exception as e:
                            print(f"[btn] callback error: {e}")
                elif not pressed and was_pressed:
                    self._key_state[key_num] = False
                    print(f"[btn] Key {key_num} UP")
                    if self._on_key_up:
                        try:
                            self._on_key_up(key_num)
                        except Exception as e:
                            print(f"[btn] callback error: {e}")
