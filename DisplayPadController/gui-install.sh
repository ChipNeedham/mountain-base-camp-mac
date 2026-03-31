#!/bin/bash
# GUI installer for DisplayPad Controller
# Uses osascript for native macOS dialogs — no terminal needed.
# Double-click this file or run: bash gui-install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_NAME="DisplayPadController"
DAEMON_LABEL="com.displaypad.controller"
DAEMON_PLIST_SRC="${SCRIPT_DIR}/${DAEMON_LABEL}.plist"
DAEMON_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
BIN_INSTALL="/usr/local/bin/${BUNDLE_NAME}"
BUILD_DIR="${SCRIPT_DIR}/.build/release"
LOG="/tmp/displaypad-install.log"

# ── Helper: show macOS dialog ──
dialog() {
    osascript -e "display dialog \"$1\" with title \"DisplayPad Controller\" buttons {\"OK\"} default button \"OK\" with icon caution" 2>/dev/null || true
}

info() {
    osascript -e "display dialog \"$1\" with title \"DisplayPad Controller\" buttons {\"OK\"} default button \"OK\"" 2>/dev/null || true
}

progress() {
    osascript -e "display notification \"$1\" with title \"DisplayPad Controller\"" 2>/dev/null || true
}

confirm() {
    local result
    result=$(osascript -e "display dialog \"$1\" with title \"DisplayPad Controller\" buttons {\"Cancel\", \"Install\"} default button \"Install\"" 2>/dev/null) || exit 0
}

# ── Check dependencies ──
if ! command -v swift &>/dev/null; then
    dialog "Xcode is required but not installed.\n\nPlease install Xcode from the App Store, then run this installer again."
    exit 1
fi

if ! command -v brew &>/dev/null; then
    dialog "Homebrew is required but not installed.\n\nVisit https://brew.sh to install it, then run this installer again."
    exit 1
fi

if ! brew list libusb &>/dev/null; then
    progress "Installing libusb..."
    brew install libusb >> "$LOG" 2>&1
fi

# ── Confirm ──
confirm "DisplayPad Controller will be installed as a background service that:\n\n• Runs automatically at startup\n• Auto-connects when your DisplayPad is plugged in\n• Controls Spotify and runs macros from your key config\n\nYou'll be prompted for your admin password."

# ── Build ──
progress "Building DisplayPad Controller..."
cd "$SCRIPT_DIR"
arch -arm64 swift build -c release >> "$LOG" 2>&1

if [ ! -f "${BUILD_DIR}/${BUNDLE_NAME}" ]; then
    dialog "Build failed. Check ${LOG} for details."
    exit 1
fi

# ── Install with admin privileges via osascript ──
LIBUSB_SRC="$(brew --prefix libusb)/lib/libusb-1.0.0.dylib"

INSTALL_SCRIPT="
mkdir -p /usr/local/bin /usr/local/lib
cp '${BUILD_DIR}/${BUNDLE_NAME}' '${BIN_INSTALL}'
chmod 755 '${BIN_INSTALL}'
if [ -f '${LIBUSB_SRC}' ]; then
    cp '${LIBUSB_SRC}' /usr/local/lib/libusb-1.0.0.dylib
fi
cp '${DAEMON_PLIST_SRC}' '${DAEMON_PLIST}'
chown root:wheel '${DAEMON_PLIST}'
chmod 644 '${DAEMON_PLIST}'
launchctl bootout system/${DAEMON_LABEL} 2>/dev/null; true
sleep 1
launchctl bootstrap system '${DAEMON_PLIST}'
"

# This shows the native macOS admin password prompt
osascript -e "do shell script \"${INSTALL_SCRIPT}\" with administrator privileges" 2>>"$LOG"

if [ $? -ne 0 ]; then
    dialog "Installation failed. Check ${LOG} for details."
    exit 1
fi

info "DisplayPad Controller installed successfully!\n\n• Running as a background service\n• Auto-starts on boot\n• Config: ~/.config/displaypad/config.json\n• Logs: /tmp/displaypad-controller.log\n\nPlug in your DisplayPad and it will connect automatically."
