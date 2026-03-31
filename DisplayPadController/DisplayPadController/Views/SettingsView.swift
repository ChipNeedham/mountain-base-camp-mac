import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(ConfigStore.self) private var configStore
    @Environment(DisplayPadManager.self) private var manager

    var body: some View {
        @Bindable var store = configStore

        Form {
            Section("Connection") {
                Toggle("Auto-connect when device is plugged in",
                       isOn: $store.config.autoConnect)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { configStore.config.launchAtLogin },
                    set: { newValue in
                        configStore.config.launchAtLogin = newValue
                        setLaunchAtLogin(newValue)
                        configStore.save()
                    }
                ))
            }

            Section("About") {
                LabeledContent("Config Location") {
                    Text(ConfigStore.configURL.path)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 280)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                print("Launch at login error: \(error)")
            }
        }
    }
}
