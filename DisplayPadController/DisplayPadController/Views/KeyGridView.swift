import SwiftUI

struct KeyGridView: View {
    @Environment(DisplayPadManager.self) private var manager
    @Environment(ConfigStore.self) private var configStore
    @Environment(MacroEngine.self) private var macroEngine
    @State private var editingKeyIndex: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<DisplayPadProtocol.numKeys, id: \.self) { index in
                KeyButtonView(
                    keyIndex: index,
                    config: configStore.keyConfig(for: index),
                    isPressed: manager.keyPressed[safe: index] ?? false,
                    registration: macroEngine.registrations[index]
                ) {
                    editingKeyIndex = index
                }
            }
        }
        .sheet(item: $editingKeyIndex) { index in
            KeyConfigSheet(keyIndex: index)
                .environment(configStore)
                .environment(macroEngine)
        }
    }
}

// Make Int conform to Identifiable for sheet presentation
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// Safe array subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct KeyButtonView: View {
    let keyIndex: Int
    let config: KeyConfig?
    let isPressed: Bool
    let registration: MacroEngine.Registration?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Icon preview
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                        .aspectRatio(1, contentMode: .fit)

                    if let icon = registration?.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        iconView
                    }
                }
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .brightness(isPressed ? 0.2 : 0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)

                // Label
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        guard let config, config.type != .none else {
            return Color(.darkGray).opacity(0.5)
        }
        return Color(hex: config.backgroundColor) ?? Color(.darkGray)
    }

    private var label: String {
        config?.label.isEmpty == false ? config!.label : "Key \(keyIndex + 1)"
    }

    @ViewBuilder
    private var iconView: some View {
        if let config {
            switch config.iconSource {
            case .sfSymbol(let name):
                Image(systemName: name)
                    .font(.title2)
                    .foregroundStyle(.white)
            case .text(let text):
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            default:
                Text("\(keyIndex + 1)")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }
        } else {
            Text("\(keyIndex + 1)")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}

// MARK: - Color from hex string

extension Color {
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let num = UInt64(str, radix: 16) else { return nil }
        self.init(
            red: Double((num >> 16) & 0xFF) / 255,
            green: Double((num >> 8) & 0xFF) / 255,
            blue: Double(num & 0xFF) / 255
        )
    }
}
