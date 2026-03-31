import SwiftUI
import AppKit
import os

private let appLogger = Logger(subsystem: "com.displaypad.controller", category: "app")

/// Push all configured icons to the device after connection.
private func pushAllIcons(manager: DisplayPadManager, macroEngine: MacroEngine, configStore: ConfigStore) {
    appLogger.info("Auto-pushing icons for \(macroEngine.registrations.count) registrations")

    for keyIndex in 0..<DisplayPadProtocol.numKeys {
        if let reg = macroEngine.registrations[keyIndex] {
            let config = reg.config
            appLogger.info("Key \(keyIndex): pushing (type=\(config.type.rawValue), icon=\(String(describing: config.iconSource)))")
            pushKeyIcon(manager: manager, keyIndex: keyIndex, config: config)
        } else {
            manager.clearKey(keyIndex: keyIndex)
        }
    }
}

private func pushKeyIcon(manager: DisplayPadManager, keyIndex: Int, config: KeyConfig) {
    switch config.iconSource {
    case .sfSymbol(let name):
        if name.isEmpty {
            manager.setKeyText(keyIndex: keyIndex, text: config.label.isEmpty ? "K\(keyIndex + 1)" : config.label)
        } else {
            manager.setKeySFSymbol(keyIndex: keyIndex, name: name)
        }
    case .text(let text):
        manager.setKeyText(keyIndex: keyIndex, text: text.isEmpty ? config.label : text)
    case .file(let path):
        if let img = NSImage(contentsOfFile: path) {
            manager.setKeyImage(keyIndex: keyIndex, image: img)
        } else {
            manager.setKeyText(keyIndex: keyIndex, text: config.label.isEmpty ? "K\(keyIndex + 1)" : config.label)
        }
    case .bundled(let name):
        if let img = NSImage(named: name) {
            manager.setKeyImage(keyIndex: keyIndex, image: img)
        } else {
            manager.setKeyText(keyIndex: keyIndex, text: config.label)
        }
    case .none:
        manager.setKeyText(keyIndex: keyIndex, text: config.label.isEmpty ? "K\(keyIndex + 1)" : config.label)
    }
}

@main
struct DisplayPadControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var manager = DisplayPadManager()
    @State private var configStore = ConfigStore()
    @State private var macroEngine = MacroEngine()
    @State private var hotplugMonitor = HotplugMonitor()
    @State private var hasSetup = false

    var body: some Scene {
        // Menu bar icon
        MenuBarExtra {
            MenuBarMenu()
                .environment(manager)
                .environment(configStore)
                .environment(macroEngine)
                .onAppear { setupOnce() }
        } label: {
            menuBarLabel
        }

        // Main window (opened from menu bar)
        Window("DisplayPad Controller", id: "main") {
            MainView()
                .environment(manager)
                .environment(configStore)
                .environment(macroEngine)
        }
        .defaultSize(width: 720, height: 400)

        Settings {
            SettingsView()
                .environment(configStore)
                .environment(manager)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        switch manager.connectionState {
        case .connected:
            Image(systemName: "keyboard.fill")
        case .disconnected:
            Image(systemName: "keyboard")
        case .connecting, .booting:
            Image(systemName: "keyboard.badge.ellipsis")
        }
    }

    private func setupOnce() {
        guard !hasSetup else { return }
        hasSetup = true

        macroEngine.loadFromConfig(configStore)

        manager.onKeyDown = { keyNum in
            macroEngine.handleKeyDown(keyNum)
        }
        manager.onKeyUp = { keyNum in
            macroEngine.handleKeyUp(keyNum)
        }
        manager.onConnected = { [manager, macroEngine, configStore] in
            pushAllIcons(manager: manager, macroEngine: macroEngine, configStore: configStore)
        }

        hotplugMonitor.onDeviceConnected = { [manager, configStore] in
            if configStore.config.autoConnect {
                manager.disconnect()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    manager.connect()
                }
            }
        }
        hotplugMonitor.onDeviceDisconnected = {
            manager.disconnect()
        }
        hotplugMonitor.startMonitoring()

        if configStore.config.autoConnect {
            manager.connect()
        }
    }
}

// MARK: - App Delegate (hide dock icon, keep only menu bar)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — menu bar only
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Menu Bar Dropdown

struct MenuBarMenu: View {
    @Environment(DisplayPadManager.self) private var manager
    @Environment(ConfigStore.self) private var configStore
    @Environment(MacroEngine.self) private var macroEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status
        Text(statusText)
            .font(.headline)

        Divider()

        // Connect / Disconnect
        if manager.connectionState == .connected {
            Button("Disconnect") {
                manager.disconnect()
            }

            Button("Push Icons") {
                pushAllIcons(manager: manager, macroEngine: macroEngine, configStore: configStore)
            }
        } else if manager.connectionState == .disconnected {
            Button("Connect") {
                manager.connect()
            }
        } else {
            Text("Connecting...")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Open Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        SettingsLink {
            Text("Settings...")
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        switch manager.connectionState {
        case .connected: "DisplayPad Connected"
        case .disconnected: "DisplayPad Disconnected"
        case .connecting: "Connecting..."
        case .booting(let msg): msg
        }
    }
}
