#!/bin/bash

DAEMON_LABEL="com.displaypad.controller"
DAEMON_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
BIN_INSTALL="/usr/local/bin/DisplayPadController"

echo ""
echo "  Uninstalling DisplayPad Controller..."
echo ""

sudo bash -c "
    launchctl bootout system/${DAEMON_LABEL} 2>/dev/null || true
    rm -f '${DAEMON_PLIST}'
    rm -f '${BIN_INSTALL}'
    echo '  ✓  Service stopped and removed'
    echo '  ✓  Binary removed'
"

echo ""
echo "  Config preserved at: ~/.config/displaypad/config.json"
echo "  To remove config:    rm -rf ~/.config/displaypad"
echo ""
