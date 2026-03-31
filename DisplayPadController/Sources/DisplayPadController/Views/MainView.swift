import SwiftUI

struct MainView: View {
    @Environment(DisplayPadManager.self) private var manager
    @Environment(ConfigStore.self) private var configStore
    @Environment(MacroEngine.self) private var macroEngine

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            StatusBarView()
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // Key grid
            KeyGridView()
                .padding()
        }
        .frame(minWidth: 640, minHeight: 340)
    }
}

struct StatusBarView: View {
    @Environment(DisplayPadManager.self) private var manager
    @Environment(ConfigStore.self) private var configStore
    @Environment(MacroEngine.self) private var macroEngine

    var body: some View {
        HStack {
            // Connection indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.system(.body, design: .monospaced))

            Spacer()

            // Push icons button
            Button("Push Icons") {
                pushAllIcons()
            }
            .disabled(manager.connectionState != .connected)

            // Connect/Disconnect button
            Button(connectButtonTitle) {
                if manager.connectionState == .connected {
                    manager.disconnect()
                } else if manager.connectionState == .disconnected {
                    manager.connect()
                }
            }
            .disabled(isConnecting)
        }
    }

    private var statusColor: Color {
        switch manager.connectionState {
        case .connected: .green
        case .disconnected: .red
        case .connecting, .booting: .orange
        }
    }

    private var statusText: String {
        switch manager.connectionState {
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .booting(let msg): msg
        }
    }

    private var connectButtonTitle: String {
        manager.connectionState == .connected ? "Disconnect" : "Connect"
    }

    private var isConnecting: Bool {
        if case .connecting = manager.connectionState { return true }
        if case .booting = manager.connectionState { return true }
        return false
    }

    private func pushAllIcons() {
        for keyIndex in 0..<DisplayPadProtocol.numKeys {
            if let reg = macroEngine.registrations[keyIndex] {
                let config = reg.config
                switch config.iconSource {
                case .sfSymbol(let name) where !name.isEmpty:
                    manager.setKeySFSymbol(keyIndex: keyIndex, name: name)
                case .text(let text) where !text.isEmpty:
                    manager.setKeyText(keyIndex: keyIndex, text: text)
                case .file(let path):
                    if let img = NSImage(contentsOfFile: path) {
                        manager.setKeyImage(keyIndex: keyIndex, image: img)
                    } else {
                        manager.setKeyText(keyIndex: keyIndex, text: config.label.isEmpty ? "K\(keyIndex + 1)" : config.label)
                    }
                default:
                    manager.setKeyText(keyIndex: keyIndex, text: config.label.isEmpty ? "K\(keyIndex + 1)" : config.label)
                }
            } else {
                manager.clearKey(keyIndex: keyIndex)
            }
        }
    }
}
