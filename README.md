# Mountain DisplayPad — macOS Controller

Native macOS app for the [Mountain DisplayPad](https://mountain.gg/keypads/displaypad/) — a 12-key macro keypad with individual 102x102 IPS LCD displays.

Mountain's official Base Camp software is Windows-only and the product is EOL. This project reverse-engineers the USB protocol to provide full macOS support as a native Swift app.

## Features

- **Native Swift/SwiftUI app** — menu bar icon, no dock clutter
- **USB hotplug detection** — auto-connects when the DisplayPad is plugged in
- **Custom key icons** — SF Symbols, text labels, or custom images on each key
- **Macro engine** with support for:
  - Spotify control (play/pause, next, previous, volume up/down, now playing)
  - Shell commands
  - App launcher
  - Keystroke simulation (AppleScript)
  - HTTP API calls
- **Persistent config** at `~/.config/displaypad/config.json`
- **Launch at login** via SMAppService
- **Self-contained** — bundles libusb, no runtime dependencies

## Requirements

- macOS 14+
- Apple Silicon Mac
- [Xcode](https://developer.apple.com/xcode/) (for building)
- [Homebrew](https://brew.sh) + libusb (`brew install libusb`)

## Install

```bash
git clone git@github.com:ChipNeedham/mountain-displaypad-mac.git
cd mountain-displaypad-mac/DisplayPadController
bash install.sh
```

The installer builds the app, installs a LaunchDaemon (for USB permissions), and starts the background service. You'll be prompted for your admin password once.

A GUI installer is also available — double-click `Install DisplayPad.app` or run `bash gui-install.sh`.

## Uninstall

```bash
cd DisplayPadController
bash uninstall.sh
```

## Development

Open in Xcode:

```bash
cd DisplayPadController
open Package.swift
```

For USB access during development: **Product > Scheme > Edit Scheme > Run > Options > Debug process as root**.

## How It Works

### USB Protocol

Reverse-engineered from [JeLuF/mountain-displaypad](https://github.com/JeLuF/mountain-displaypad). Uses libusb (via C interop) since macOS IOKit HID Manager can't see the device.

| | Interface | Endpoint | Purpose |
|---|---|---|---|
| Display | 1 | EP 0x02 OUT | Image data (1024-byte reports) |
| Control | 3 | EP 0x04 OUT | Commands (64-byte reports) |
| Input | 3 | EP 0x83 IN | Button events, ACKs |

### Boot Sequence

The device requires ~35 seconds to fully initialize after USB enumeration. The boot sequence sends INIT commands via three strategies (EP 0x04, EP 0x02, SET_REPORT) and waits for an ACK.

### Image Transfer

Each key receives a 102x102 BGR pixel image via: IMG command (EP 0x04) → ACK → 31 chunks of 1024 bytes (EP 0x02) → re-send chunks → completion ACK. The first key after boot always requires a re-init cycle.

## Project Structure

```
DisplayPadController/
├── Package.swift
├── Sources/
│   ├── CLibUSB/                    # libusb C module map
│   └── DisplayPadController/
│       ├── App/                    # SwiftUI app entry, menu bar
│       ├── Config/                 # AppConfig, ConfigStore
│       ├── Device/                 # DisplayPadManager, HotplugMonitor
│       ├── Image/                  # BGRBuffer (image → pixel conversion)
│       ├── Macro/                  # MacroEngine, Spotify, Shell, API actions
│       ├── USB/                    # Protocol, Boot, ImageTransfer, ButtonPoller
│       ├── Utilities/              # AppleScriptRunner
│       └── Views/                  # MainView, KeyGrid, KeyConfig, Settings
├── install.sh                      # CLI installer
├── gui-install.sh                  # GUI installer
├── uninstall.sh
└── build-app.sh                    # Build signed .app bundle
```

## Credits

- Protocol reverse engineering: [JeLuF/mountain-displaypad](https://github.com/JeLuF/mountain-displaypad)
- Related: [Mountain-BC/DisplayPad.SDK.Demo](https://github.com/Mountain-BC/DisplayPad.SDK.Demo)
