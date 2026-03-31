#!/usr/bin/env python3
"""Probe DisplayPad init handshake. Run: sudo venv/bin/python probe_device.py"""

import ctypes
import ctypes.util
import sys
import time

libusb_path = ctypes.util.find_library("usb-1.0") or "/opt/homebrew/lib/libusb-1.0.dylib"
libusb = ctypes.cdll.LoadLibrary(libusb_path)

VP = ctypes.c_void_p
U8 = ctypes.c_uint8
U16 = ctypes.c_uint16
I = ctypes.c_int
PI = ctypes.POINTER(I)
PU8 = ctypes.POINTER(U8)

libusb.libusb_init.argtypes = [ctypes.POINTER(VP)]; libusb.libusb_init.restype = I
libusb.libusb_exit.argtypes = [VP]; libusb.libusb_exit.restype = None
libusb.libusb_open_device_with_vid_pid.argtypes = [VP, U16, U16]; libusb.libusb_open_device_with_vid_pid.restype = VP
libusb.libusb_close.argtypes = [VP]; libusb.libusb_close.restype = None
libusb.libusb_kernel_driver_active.argtypes = [VP, I]; libusb.libusb_kernel_driver_active.restype = I
libusb.libusb_detach_kernel_driver.argtypes = [VP, I]; libusb.libusb_detach_kernel_driver.restype = I
libusb.libusb_claim_interface.argtypes = [VP, I]; libusb.libusb_claim_interface.restype = I
libusb.libusb_control_transfer.argtypes = [VP, U8, U8, U16, U16, PU8, U16, ctypes.c_uint]; libusb.libusb_control_transfer.restype = I
libusb.libusb_interrupt_transfer.argtypes = [VP, U8, PU8, I, PI, ctypes.c_uint]; libusb.libusb_interrupt_transfer.restype = I
libusb.libusb_error_name.argtypes = [I]; libusb.libusb_error_name.restype = ctypes.c_char_p

ctx = VP()
libusb.libusb_init(ctypes.byref(ctx))
handle = libusb.libusb_open_device_with_vid_pid(ctx, 0x3282, 0x0009)
if not handle:
    print("Cannot open. Quit Spotify/Chrome, unplug/replug, sudo.")
    sys.exit(1)
print("Opened DisplayPad!")

# Detach and claim
for i in [0, 1, 3]:
    if libusb.libusb_kernel_driver_active(handle, i) == 1:
        libusb.libusb_detach_kernel_driver(handle, i)
        print(f"  Detached kernel from intf {i}")
    rc = libusb.libusb_claim_interface(handle, i)
    print(f"  Claimed intf {i}: rc={rc}")

# INIT_MSG without report ID (64 bytes) and with report ID (65 bytes)
INIT_NO_RID = bytes.fromhex(
    "11800000010000000000000000000000"
    "00000000000000000000000000000000"
    "00000000000000000000000000000000"
    "00000000000000000000000000000000"
)
INIT_WITH_RID = b'\x00' + INIT_NO_RID

xfer = ctypes.c_int(0)
resp = (U8 * 64)()

def errname(rc):
    return libusb.libusb_error_name(rc).decode() if rc else "OK"

def try_read(label, timeout=2000):
    """Try reading from EP 0x83."""
    rc = libusb.libusb_interrupt_transfer(handle, 0x83, resp, 64, ctypes.byref(xfer), timeout)
    if rc == 0:
        d = bytes(resp[:xfer.value])
        print(f"  {label} READ OK ({xfer.value}b): {d.hex()}")
        if d[0] == 0x11:
            print("  >>> INIT ACKNOWLEDGED! <<<")
        return True
    print(f"  {label} read: {errname(rc)}")
    return False

# ── Method 1: Interrupt OUT (no report ID) then read ──
print("\n=== Method 1: Interrupt OUT (64 bytes, no report ID) ===")
buf = (U8 * len(INIT_NO_RID))(*INIT_NO_RID)
rc = libusb.libusb_interrupt_transfer(handle, 0x04, buf, len(INIT_NO_RID), ctypes.byref(xfer), 2000)
print(f"  Write: {errname(rc)} ({xfer.value}b)")
try_read("M1", 3000)

# ── Method 2: HID SET_REPORT on interface 3 (no report ID in data) ──
print("\n=== Method 2: SET_REPORT Output (intf 3, no RID in data) ===")
buf = (U8 * len(INIT_NO_RID))(*INIT_NO_RID)
# SET_REPORT: bmReqType=0x21, bReq=0x09, wValue=0x0200 (Output, RID 0), wIndex=3
rc = libusb.libusb_control_transfer(handle, 0x21, 0x09, 0x0200, 3, buf, len(INIT_NO_RID), 2000)
print(f"  SET_REPORT: {rc} ({errname(rc) if rc < 0 else f'{rc} bytes'})")
try_read("M2", 3000)

# ── Method 3: HID SET_REPORT with report ID in data ──
print("\n=== Method 3: SET_REPORT Output (intf 3, RID 0x00 in data) ===")
buf = (U8 * len(INIT_WITH_RID))(*INIT_WITH_RID)
rc = libusb.libusb_control_transfer(handle, 0x21, 0x09, 0x0200, 3, buf, len(INIT_WITH_RID), 2000)
print(f"  SET_REPORT: {rc} ({errname(rc) if rc < 0 else f'{rc} bytes'})")
try_read("M3", 3000)

# ── Method 4: SET_REPORT Feature report ──
print("\n=== Method 4: SET_REPORT Feature (intf 3) ===")
buf = (U8 * len(INIT_NO_RID))(*INIT_NO_RID)
# wValue=0x0300 (Feature, RID 0)
rc = libusb.libusb_control_transfer(handle, 0x21, 0x09, 0x0300, 3, buf, len(INIT_NO_RID), 2000)
print(f"  SET_REPORT: {rc} ({errname(rc) if rc < 0 else f'{rc} bytes'})")
try_read("M4", 3000)

# ── Method 5: Interrupt OUT with report ID then rapid poll ──
print("\n=== Method 5: Interrupt OUT (65 bytes with RID) + rapid poll ===")
buf = (U8 * len(INIT_WITH_RID))(*INIT_WITH_RID)
rc = libusb.libusb_interrupt_transfer(handle, 0x04, buf, len(INIT_WITH_RID), ctypes.byref(xfer), 2000)
print(f"  Write: {errname(rc)} ({xfer.value}b)")
for attempt in range(5):
    time.sleep(0.1)
    if try_read(f"M5-{attempt}", 500):
        break

# ── Method 6: Just poll EP 0x83 for any data (maybe device sends something on plug) ──
print("\n=== Method 6: Just read EP 0x83 (no init, check for unsolicited data) ===")
try_read("M6", 2000)

libusb.libusb_close(handle)
libusb.libusb_exit(ctx)
print("\nDone!")
