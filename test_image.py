#!/usr/bin/env python3
"""
DisplayPad image transfer test — multi-strategy init.
Tries:
  A) Init via EP 0x04 interrupt OUT (how node-hid actually sends it)
  B) Init on BOTH interfaces (EP 0x04 + EP 0x02) per not-coded fork
  C) Re-init when ffaa keepalive received
  D) SET_REPORT fallback

Run: sudo venv/bin/python test_image.py
"""

import ctypes
import ctypes.util
import sys
import time

libusb_path = ctypes.util.find_library("usb-1.0") or "/opt/homebrew/lib/libusb-1.0.dylib"
libusb = ctypes.cdll.LoadLibrary(libusb_path)

VP = ctypes.c_void_p; U8 = ctypes.c_uint8; U16 = ctypes.c_uint16
I = ctypes.c_int; PI = ctypes.POINTER(I); PU8 = ctypes.POINTER(U8)

for name, at, rt in [
    ("libusb_init", [ctypes.POINTER(VP)], I),
    ("libusb_exit", [VP], None),
    ("libusb_open_device_with_vid_pid", [VP, U16, U16], VP),
    ("libusb_close", [VP], None),
    ("libusb_kernel_driver_active", [VP, I], I),
    ("libusb_detach_kernel_driver", [VP, I], I),
    ("libusb_claim_interface", [VP, I], I),
    ("libusb_control_transfer", [VP, U8, U8, U16, U16, PU8, U16, ctypes.c_uint], I),
    ("libusb_interrupt_transfer", [VP, U8, PU8, I, PI, ctypes.c_uint], I),
    ("libusb_error_name", [I], ctypes.c_char_p),
]:
    getattr(libusb, name).argtypes = at
    getattr(libusb, name).restype = rt

def errname(rc):
    return libusb.libusb_error_name(rc).decode() if rc else "OK"

ICON_SIZE = 102
PACKET_SIZE = 31438
HEADER_SIZE = 306
CHUNK_SIZE = 1024

ctx = VP()
libusb.libusb_init(ctypes.byref(ctx))
handle = libusb.libusb_open_device_with_vid_pid(ctx, 0x3282, 0x0009)
if not handle:
    print("Cannot open."); sys.exit(1)
print("Opened!")

for i in [0, 1, 3]:
    if libusb.libusb_kernel_driver_active(handle, i) == 1:
        libusb.libusb_detach_kernel_driver(handle, i)
    libusb.libusb_claim_interface(handle, i)
print("Claimed interfaces 0, 1, 3.")

xfer = ctypes.c_int(0)

def set_report(data, intf):
    buf = (U8 * len(data))(*data)
    return libusb.libusb_control_transfer(handle, 0x21, 0x09, 0x0200, intf, buf, len(data), 3000)

def write_ep(ep, data, timeout=5000):
    buf = (U8 * len(data))(*data)
    rc = libusb.libusb_interrupt_transfer(handle, ep, buf, len(data), ctypes.byref(xfer), timeout)
    return rc, xfer.value

def read83(timeout=500):
    resp = (U8 * 64)()
    rc = libusb.libusb_interrupt_transfer(handle, 0x83, resp, 64, ctypes.byref(xfer), timeout)
    if rc == 0:
        return bytes(resp[:xfer.value])
    return None

# 64-byte init command (no report ID)
INIT_DATA = bytes.fromhex(
    "11800000010000000000000000000000"
    "00000000000000000000000000000000"
    "00000000000000000000000000000000"
    "00000000000000000000000000000000"
)
# Same init padded to 1024 bytes for display interface
INIT_1024 = INIT_DATA + bytes(1024 - len(INIT_DATA))

def drain_and_find(target_byte, timeout_total=3.0, label=""):
    """Read EP 0x83 looking for a specific first byte. Print everything seen."""
    start = time.time()
    while time.time() - start < timeout_total:
        d = read83(500)
        if d is None:
            continue
        tag = f"[{d[0]:#04x}]"
        if d[0] == target_byte:
            print(f"    {label}{tag} FOUND! {d[:12].hex()}")
            return d
        elif d[0] == 0xFF:
            print(f"    {label}{tag} ffaa keepalive")
        elif d[0] == 0x01:
            pass  # button data, skip
        else:
            print(f"    {label}{tag} {d[:12].hex()}")
    return None

# ══════════════════════════════════════════════════════════════
# Strategy A: Init via interrupt OUT EP 0x04 (mimics node-hid)
# ══════════════════════════════════════════════════════════════
print("\n" + "="*60)
print("Strategy A: Init via EP 0x04 (interrupt OUT, 64 bytes)")
print("="*60)

rc, n = write_ep(0x04, INIT_DATA)
print(f"  EP 0x04 write: {errname(rc)} ({n}b)")

print("  Polling for 0x11 ACK (20s)...")
d = drain_and_find(0x11, timeout_total=20.0, label="A: ")

if d and d[0] == 0x11:
    print("  >>> Strategy A: INIT ACK received! <<<")
else:
    # ══════════════════════════════════════════════════════════
    # Strategy B: Init on BOTH interfaces
    # ══════════════════════════════════════════════════════════
    print("\n" + "="*60)
    print("Strategy B: Init on BOTH EP 0x04 + EP 0x02")
    print("="*60)

    rc1, n1 = write_ep(0x04, INIT_DATA)
    rc2, n2 = write_ep(0x02, INIT_1024)
    print(f"  EP 0x04: {errname(rc1)} ({n1}b), EP 0x02: {errname(rc2)} ({n2}b)")

    print("  Polling for 0x11 ACK (15s)...")
    d = drain_and_find(0x11, timeout_total=15.0, label="B: ")

    if d and d[0] == 0x11:
        print("  >>> Strategy B: INIT ACK received! <<<")
    else:
        # ══════════════════════════════════════════════════════
        # Strategy C: SET_REPORT + re-init on ffaa
        # ══════════════════════════════════════════════════════
        print("\n" + "="*60)
        print("Strategy C: SET_REPORT intf 3, then re-init on ffaa")
        print("="*60)

        rc = set_report(INIT_DATA, intf=3)
        print(f"  SET_REPORT intf 3: {rc} bytes")

        print("  Waiting for boot + watching for ffaa (20s)...")
        start = time.time()
        found_init = False
        reinit_count = 0
        while time.time() - start < 20:
            d2 = read83(500)
            if d2 is None:
                continue
            if d2[0] == 0x11:
                print(f"    >>> INIT ACK! ({time.time()-start:.1f}s) <<<")
                found_init = True
                d = d2
                break
            elif d2[0] == 0xFF and reinit_count < 3:
                reinit_count += 1
                print(f"    ffaa #{reinit_count} — re-sending init via EP 0x04...")
                write_ep(0x04, INIT_DATA)
                # Also try display interface
                write_ep(0x02, INIT_1024)
            elif d2[0] != 0x01:
                print(f"    [{d2[0]:#04x}] {d2[:8].hex()}")

        if not found_init:
            print("  No INIT ACK from any strategy.")
            print("  Proceeding to IMG anyway (device may still accept commands)...")

# ══════════════════════════════════════════════════════════════
# IMG command (64 bytes, no report ID) → EP 0x04
# ══════════════════════════════════════════════════════════════
print("\n" + "="*60)
print("IMG command for key 0")
print("="*60)

IMG_DATA = bytearray(64)
IMG_DATA[0] = 0x21
IMG_DATA[4] = 0x00   # key index
IMG_DATA[5] = 0x3d
IMG_DATA[8] = 0x65
IMG_DATA[9] = 0x65

rc, n = write_ep(0x04, bytes(IMG_DATA))
print(f"  EP 0x04: {errname(rc)} ({n}b)")

print("  Waiting for IMG ACK (0x21 d[2]==0x00)...")
img_acked = False
for _ in range(20):
    d = read83(500)
    if d is None:
        continue
    if d[0] == 0x21:
        print(f"    IMG resp: {d[:12].hex()}")
        if d[1] == 0x00 and d[2] == 0x00:
            print("    >>> IMG ACK! Ready for pixels <<<")
            img_acked = True
            break
    elif d[0] == 0xFF:
        print(f"    ffaa — re-sending IMG...")
        write_ep(0x04, bytes(IMG_DATA))
    elif d[0] != 0x01:
        print(f"    [{d[0]:#04x}] {d[:12].hex()}")

if not img_acked:
    print("  No IMG ACK. Sending pixels anyway...")

# ══════════════════════════════════════════════════════════════
# Pixel transfer — RED
# ══════════════════════════════════════════════════════════════
print("\n" + "="*60)
print("Pixel transfer (RED) to EP 0x02")
print("="*60)

header = bytes(HEADER_SIZE)
pixel_data = bytearray(PACKET_SIZE)
for i in range(ICON_SIZE * ICON_SIZE):
    pixel_data[i*3]     = 0x00  # B
    pixel_data[i*3 + 1] = 0x00  # G
    pixel_data[i*3 + 2] = 0xFF  # R (BGR format)
full_data = header + bytes(pixel_data)

ok = 0; fail = 0
for i in range(0, len(full_data), CHUNK_SIZE):
    chunk = full_data[i:i+CHUNK_SIZE]
    if len(chunk) < CHUNK_SIZE:
        chunk = chunk + bytes(CHUNK_SIZE - len(chunk))
    rc, n = write_ep(0x02, chunk)
    if rc == 0:
        ok += 1
    else:
        fail += 1
        if fail <= 3: print(f"    Chunk {i//CHUNK_SIZE}: {errname(rc)}")
        if fail > 5: break
print(f"  Chunks: {ok} ok, {fail} fail")

# Re-send full payload in chunks (JS does single write, we chunk it)
if fail == 0:
    print("  Re-sending full payload...")
    for i in range(0, len(full_data), CHUNK_SIZE):
        chunk = full_data[i:i+CHUNK_SIZE]
        if len(chunk) < CHUNK_SIZE:
            chunk = chunk + bytes(CHUNK_SIZE - len(chunk))
        write_ep(0x02, chunk)
    print("  Done.")

# Wait for completion
print("  Waiting for completion (0x21 d[2]==0xff)...")
for _ in range(10):
    d = read83(1000)
    if d is None: continue
    if d[0] == 0x21:
        print(f"    {d[:12].hex()}")
        if d[1] == 0x00 and d[2] == 0xFF:
            print("    >>> IMAGE DONE! <<<")
            break
    elif d[0] != 0x01:
        print(f"    [{d[0]:#04x}] {d[:8].hex()}")

# ══════════════════════════════════════════════════════════════
# Buttons
# ══════════════════════════════════════════════════════════════
print("\n=== Buttons (Ctrl+C to quit) ===")
try:
    while True:
        d = read83(1000)
        if d and d[0] == 0x01:
            masks = {1:(42,0x02),2:(42,0x04),3:(42,0x08),4:(42,0x10),
                     5:(42,0x20),6:(42,0x40),7:(42,0x80),
                     8:(47,0x01),9:(47,0x02),10:(47,0x04),11:(47,0x08),12:(47,0x10)}
            pressed = [k for k,(bi,m) in masks.items() if bi < len(d) and d[bi] & m]
            if pressed: print(f"  Keys: {pressed}")
except KeyboardInterrupt:
    pass

libusb.libusb_close(handle)
libusb.libusb_exit(ctx)
