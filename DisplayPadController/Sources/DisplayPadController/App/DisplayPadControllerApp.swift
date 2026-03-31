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
        // No icon source — use label as text
        manager.setKeyText(keyIndex: keyIndex, text: config.label.isEmpty ? "K\(keyIndex + 1)" : config.label)
    }
}

@main
struct DisplayPadControllerApp: App {
    @State private var manager = DisplayPadManager()
    @State private var configStore = ConfigStore()
    @State private var macroEngine = MacroEngine()
    @State private var hotplugMonitor = HotplugMonitor()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(manager)
                .environment(configStore)
                .environment(macroEngine)
                .onAppear { setup() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 720, height: 400)

        Settings {
            SettingsView()
                .environment(configStore)
                .environment(manager)
        }
    }

    private func setup() {
        // Wire macro engine to device manager
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

        // Hotplug monitoring
        hotplugMonitor.onDeviceConnected = { [manager, configStore] in
            if configStore.config.autoConnect {
                // Disconnect first (no-op if already disconnected), then reconnect after delay
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

        // Auto-connect on launch
        if configStore.config.autoConnect {
            manager.connect()
        }
    }
}
