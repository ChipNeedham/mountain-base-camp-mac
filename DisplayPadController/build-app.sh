#!/bin/bash
set -e

APP_NAME="DisplayPad Controller"
BUNDLE_NAME="DisplayPadController"
BUILD_DIR=".build/release"
APP_DIR="${BUNDLE_NAME}.app"

echo "=== Building Release ==="
swift build -c release 2>&1

echo ""
echo "=== Creating App Bundle ==="
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy binary
cp "${BUILD_DIR}/${BUNDLE_NAME}" "${APP_DIR}/Contents/MacOS/${BUNDLE_NAME}"

# Copy Info.plist
cp Info.plist "${APP_DIR}/Contents/"

# Copy libusb dylib so the app is self-contained
LIBUSB_PATH=$(brew --prefix libusb)/lib/libusb-1.0.0.dylib
if [ -f "$LIBUSB_PATH" ]; then
    cp "$LIBUSB_PATH" "${APP_DIR}/Contents/MacOS/"
    # Fix the rpath to look in the same directory as the binary
    install_name_tool -change "$LIBUSB_PATH" @executable_path/libusb-1.0.0.dylib "${APP_DIR}/Contents/MacOS/${BUNDLE_NAME}"
    # Also try the canonical path
    install_name_tool -change /opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib @executable_path/libusb-1.0.0.dylib "${APP_DIR}/Contents/MacOS/${BUNDLE_NAME}" 2>/dev/null || true
    echo "Bundled libusb"
else
    echo "WARNING: libusb not found at $LIBUSB_PATH"
fi

echo ""
echo "=== Signing with Entitlements ==="
codesign --force --sign - --entitlements DisplayPadController.entitlements --deep "${APP_DIR}"

echo ""
echo "=== Verifying ==="
codesign -dv --entitlements - "${APP_DIR}" 2>&1 | head -20

echo ""
echo "=== Done ==="
echo "App bundle: $(pwd)/${APP_DIR}"
echo ""
echo "To install: cp -r '${APP_DIR}' /Applications/"
echo "To run:     open '${APP_DIR}'"
