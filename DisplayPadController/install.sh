#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_NAME="DisplayPadController"
DAEMON_LABEL="com.displaypad.controller"
DAEMON_PLIST_SRC="${SCRIPT_DIR}/${DAEMON_LABEL}.plist"
DAEMON_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
BIN_INSTALL="/usr/local/bin/${BUNDLE_NAME}"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║   DisplayPad Controller — Installer  ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# ── Check dependencies ──

check_dep() {
    if ! command -v "$1" &>/dev/null; then
        echo "❌  Missing: $1"
        echo "   $2"
        exit 1
    fi
}

check_dep swift "Install Xcode or Xcode Command Line Tools: xcode-select --install"
check_dep brew  "Install Homebrew: https://brew.sh"

if ! brew list libusb &>/dev/null; then
    echo "Installing libusb..."
    brew install libusb
fi

echo "✓  Dependencies OK (swift, libusb)"
echo ""

# ── Build ──

echo "Building release binary..."
cd "$SCRIPT_DIR"
arch -arm64 swift build -c release 2>&1 | tail -1

BUILD_DIR=".build/release"
if [ ! -f "${BUILD_DIR}/${BUNDLE_NAME}" ]; then
    echo "❌  Build failed"
    exit 1
fi

echo "✓  Build complete"
echo ""

# ── Bundle libusb with the binary ──

LIBUSB_SRC="$(brew --prefix libusb)/lib/libusb-1.0.0.dylib"

# ── Install ──

echo "Installing to /usr/local/bin (requires admin password)..."
echo ""

sudo bash -c "
    set -e

    # Install binary
    mkdir -p /usr/local/bin /usr/local/lib
    cp '${BUILD_DIR}/${BUNDLE_NAME}' '${BIN_INSTALL}'
    chmod 755 '${BIN_INSTALL}'

    # Bundle libusb alongside
    if [ -f '${LIBUSB_SRC}' ]; then
        cp '${LIBUSB_SRC}' /usr/local/lib/libusb-1.0.0.dylib
    fi

    # Install LaunchDaemon
    cp '${DAEMON_PLIST_SRC}' '${DAEMON_PLIST}'
    chown root:wheel '${DAEMON_PLIST}'
    chmod 644 '${DAEMON_PLIST}'

    # Stop existing if running
    launchctl bootout system/${DAEMON_LABEL} 2>/dev/null || true
    sleep 1

    # Start
    launchctl bootstrap system '${DAEMON_PLIST}'
"

echo ""
echo "  ✓  Installed binary to ${BIN_INSTALL}"
echo "  ✓  Installed service (runs as root for USB access)"
echo "  ✓  Service started"
echo ""
echo "  ┌─────────────────────────────────────────────────┐"
echo "  │  DisplayPad Controller is running!               │"
echo "  │                                                   │"
echo "  │  • Auto-starts on boot                           │"
echo "  │  • Auto-connects when device is plugged in       │"
echo "  │  • Config: ~/.config/displaypad/config.json      │"
echo "  │  • Logs:   tail -f /tmp/displaypad-controller.log│"
echo "  │                                                   │"
echo "  │  To uninstall: bash uninstall.sh                 │"
echo "  └─────────────────────────────────────────────────┘"
echo ""
