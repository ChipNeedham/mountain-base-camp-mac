#!/usr/bin/env python3
"""
Test sending images to multiple keys sequentially.
Replicates the EXACT sequence from the working test_image.py.
No threading, no GUI — pure sequential USB I/O.

Run: sudo venv/bin/python test_multikey.py
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
print("Claimed.")

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

INIT_DATA = bytes.fromhex(
    "11800000010000000000000000000000"
    "00000000000000000000000000000000"
    "00000000000000000000000000000000"
    "00000000000000000000000000000000"
)
INIT_1024 = INIT_DATA + bytes(CHUNK_SIZE - len(INIT_DATA))

# ══════════════════════════════════════════════════════
# BOOT SEQUENCE — replicate successful test exactly
# ══════════════════════════════════════════════════════
print("\n=== BOOT ===")

# Strategy A: EP 0x04 init
print("[A] EP 0x04 init...")
write_ep(0x04, INIT_DATA)
start = time.time()
while time.time() - start < 15:
    d = read83(500)
    if d and d[0] == 0x11:
        print(f"  INIT ACK at {time.time()-start:.1f}s!")
        break
    if d and d[0] == 0xFF:
        print(f"  ffaa at {time.time()-start:.0f}s")
else:
    print("  No ACK (15s)")

# Strategy B: Both interfaces
print("[B] EP 0x04 + EP 0x02 init...")
write_ep(0x04, INIT_DATA)
write_ep(0x02, INIT_1024)
start2 = time.time()
while time.time() - start2 < 10:
    d = read83(500)
    if d and d[0] == 0x11:
        print(f"  INIT ACK!")
        break
    if d and d[0] == 0xFF:
        print(f"  ffaa at {time.time()-start2:.0f}s")
else:
    print("  No ACK (10s)")

# Strategy C: SET_REPORT + ffaa handling
print("[C] SET_REPORT + ffaa re-init...")
set_report(INIT_DATA, intf=3)
start3 = time.time()
while time.time() - start3 < 15:
    d = read83(500)
    if d and d[0] == 0x11:
        print(f"  INIT ACK!")
        break
    if d and d[0] == 0xFF:
        print(f"  ffaa at {time.time()-start3:.0f}s, re-sending both...")
        write_ep(0x04, INIT_DATA)
        write_ep(0x02, INIT_1024)
else:
    print("  No ACK (15s)")

total_boot = time.time() - start
print(f"\nBoot total: {total_boot:.0f}s")

# ══════════════════════════════════════════════════════
# IMAGE TRANSFER — 3 keys with different colors
# ══════════════════════════════════════════════════════
COLORS = [
    (0, "RED",   0x00, 0x00, 0xFF),  # BGR red
    (1, "GREEN", 0x00, 0xFF, 0x00),  # BGR green
    (2, "BLUE",  0xFF, 0x00, 0x00),  # BGR blue
]

for key_idx, name, cb, cg, cr in COLORS:
    print(f"\n=== KEY {key_idx}: {name} ===")

    # IMG command
    IMG = bytearray(64)
    IMG[0] = 0x21
    IMG[4] = key_idx
    IMG[5] = 0x3d
    IMG[8] = 0x65
    IMG[9] = 0x65

    rc, n = write_ep(0x04, bytes(IMG))
    print(f"  IMG cmd: {errname(rc)} ({n}b)")
    if rc != 0:
        print(f"  FAILED, skipping")
        continue

    # Wait for ACK
    acked = False
    for _ in range(20):
        d = read83(500)
        if d is None:
            continue
        if d[0] == 0x21 and d[1] == 0x00 and d[2] == 0x00:
            print(f"  IMG ACK!")
            acked = True
            break
        elif d[0] == 0xFF:
            print(f"  ffaa during ACK wait")
        elif d[0] != 0x01:
            print(f"  [{d[0]:#04x}] {d[:8].hex()}")

    if not acked:
        print(f"  No ACK, skipping")
        continue

    # Pixel data
    header = bytes(HEADER_SIZE)
    pixels = bytearray(PACKET_SIZE)
    for i in range(ICON_SIZE * ICON_SIZE):
        pixels[i*3]     = cb
        pixels[i*3 + 1] = cg
        pixels[i*3 + 2] = cr
    full_data = header + bytes(pixels)

    # Send chunks
    ok = 0
    for i in range(0, len(full_data), CHUNK_SIZE):
        chunk = full_data[i:i+CHUNK_SIZE]
        if len(chunk) < CHUNK_SIZE:
            chunk = chunk + bytes(CHUNK_SIZE - len(chunk))
        rc, n = write_ep(0x02, chunk)
        if rc == 0:
            ok += 1
    print(f"  Chunks: {ok}/31")

    # Re-send full payload
    for i in range(0, len(full_data), CHUNK_SIZE):
        chunk = full_data[i:i+CHUNK_SIZE]
        if len(chunk) < CHUNK_SIZE:
            chunk = chunk + bytes(CHUNK_SIZE - len(chunk))
        write_ep(0x02, chunk)
    print(f"  Re-send done")

    # Wait for completion
    done = False
    for _ in range(15):
        d = read83(1000)
        if d is None:
            continue
        if d[0] == 0x21 and d[1] == 0x00 and d[2] == 0xFF:
            print(f"  >>> {name} DONE! <<<")
            done = True
            break
        elif d[0] == 0xFF:
            print(f"  ffaa (device reset?)")
        elif d[0] != 0x01:
            print(f"  [{d[0]:#04x}] {d[:8].hex()}")

    if not done:
        print(f"  Completion timeout for {name}")
        # Try re-init before next key
        print(f"  Re-init before next key...")
        set_report(INIT_DATA, intf=3)
        write_ep(0x04, INIT_DATA)
        write_ep(0x02, INIT_1024)
        time.sleep(3)
        # Drain
        for _ in range(20):
            d = read83(200)
            if d is None:
                break

print("\n=== Buttons (Ctrl+C) ===")
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
