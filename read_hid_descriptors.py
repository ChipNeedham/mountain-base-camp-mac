#!/usr/bin/env python3
"""Read HID report descriptors from DisplayPad to understand protocol.
Run: sudo venv/bin/python read_hid_descriptors.py
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

# Read HID Report Descriptor for each interface
# GET_DESCRIPTOR: bmRequestType=0x81, bRequest=0x06, wValue=0x2200 (Report desc), wIndex=interface
for intf in [0, 1, 3]:
    print(f"\n{'='*60}")
    print(f"Interface {intf} - HID Report Descriptor")
    print(f"{'='*60}")

    buf = (U8 * 4096)()
    # Try different descriptor sizes
    rc = libusb.libusb_control_transfer(
        handle, 0x81, 0x06, 0x2200, intf, buf, 4096, 3000
    )

    if rc > 0:
        data = bytes(buf[:rc])
        print(f"Got {rc} bytes")
        print(f"Raw hex: {data.hex()}")
    else:
        print(f"Failed: {rc} ({errname(rc)})")

print("\nDone!")
libusb.libusb_close(handle)
libusb.libusb_exit(ctx)
sys.exit(0)

# dead code below
print(f"\n{'='*60}")
print("Current EP 0x83 data (first 3 reads):")
print(f"{'='*60}")

# Send init first so device is alive
INIT = bytes.fromhex(
    "11800000010000000000000000000000"
    "00000000000000000000000000000000"
    "00000000000000000000000000000000"
    "00000000000000000000000000000000"
)
xfer = ctypes.c_int(0)
set_buf = (U8 * 64)(*INIT)
libusb.libusb_control_transfer(handle, 0x21, 0x09, 0x0200, 3, set_buf, 64, 3000)

# Wait for boot
print("Waiting 12s for boot...")
time.sleep(12)

# Send second init via interrupt OUT
int_buf = (U8 * 65)(*(b'\x00' + INIT))
libusb.libusb_interrupt_transfer(handle, 0x04, int_buf, 65, ctypes.byref(xfer), 3000)
time.sleep(1)

resp = (U8 * 64)()
for i in range(3):
    rc = libusb.libusb_interrupt_transfer(handle, 0x83, resp, 64, ctypes.byref(xfer), 2000)
    if rc == 0:
        d = bytes(resp[:xfer.value])
        print(f"  Read {i}: ({xfer.value}b) {d.hex()}")

libusb.libusb_close(handle)
libusb.libusb_exit(ctx)


def parse_hid_report_descriptor(data):
    """Parse and print HID report descriptor items."""
    i = 0
    indent = 0
    while i < len(data):
        byte = data[i]

        # Short item
        bSize = byte & 0x03
        bType = (byte >> 2) & 0x03
        bTag = (byte >> 4) & 0x0F

        if bSize == 3:
            bSize = 4  # size 3 means 4 bytes

        if i + 1 + bSize > len(data):
            break

        value_bytes = data[i+1:i+1+bSize]
        if bSize == 1:
            value = value_bytes[0]
        elif bSize == 2:
            value = int.from_bytes(value_bytes, 'little')
        elif bSize == 4:
            value = int.from_bytes(value_bytes, 'little')
        else:
            value = 0

        type_names = {0: "Main", 1: "Global", 2: "Local"}
        type_name = type_names.get(bType, f"Reserved({bType})")

        # Tag names
        tag_name = ""
        if bType == 0:  # Main
            tags = {0x08: "Input", 0x09: "Output", 0x0B: "Feature",
                    0x0A: "Collection", 0x0C: "End Collection"}
            tag_name = tags.get(bTag, f"Main({bTag:#x})")
            if bTag == 0x0A:
                coll_types = {0: "Physical", 1: "Application", 2: "Logical"}
                tag_name += f" ({coll_types.get(value, f'type {value}')})"
                indent += 2
            elif bTag == 0x0C:
                indent = max(0, indent - 2)
        elif bType == 1:  # Global
            tags = {0x00: "Usage Page", 0x01: "Logical Minimum", 0x02: "Logical Maximum",
                    0x03: "Physical Minimum", 0x04: "Physical Maximum",
                    0x07: "Report Size", 0x08: "Report ID", 0x09: "Report Count",
                    0x05: "Unit Exponent", 0x06: "Unit"}
            tag_name = tags.get(bTag, f"Global({bTag:#x})")
            if bTag == 0x00:  # Usage Page
                pages = {0x01: "Generic Desktop", 0x07: "Keyboard", 0x08: "LED",
                         0x09: "Button", 0x0C: "Consumer", 0xFF00: "Vendor"}
                page_name = pages.get(value, f"{value:#06x}")
                tag_name += f" ({page_name})"
        elif bType == 2:  # Local
            tags = {0x00: "Usage", 0x01: "Usage Minimum", 0x02: "Usage Maximum"}
            tag_name = tags.get(bTag, f"Local({bTag:#x})")

        prefix = " " * indent
        val_hex = value_bytes.hex() if value_bytes else ""
        print(f"  {prefix}{tag_name}: {value} (0x{value:04x}) [{val_hex}]")

        i += 1 + bSize
