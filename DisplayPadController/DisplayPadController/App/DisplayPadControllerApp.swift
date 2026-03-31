import SwiftUI

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

        // Hotplug monitoring
        hotplugMonitor.onDeviceConnected = { [manager, configStore] in
            guard manager.connectionState == .disconnected else { return }
            if configStore.config.autoConnect {
                manager.connect()
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
