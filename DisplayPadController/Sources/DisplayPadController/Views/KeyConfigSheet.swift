import SwiftUI
import UniformTypeIdentifiers

struct KeyConfigSheet: View {
    let keyIndex: Int
    @Environment(ConfigStore.self) private var configStore
    @Environment(MacroEngine.self) private var macroEngine
    @Environment(\.dismiss) private var dismiss

    @State private var keyConfig: KeyConfig

    init(keyIndex: Int) {
        self.keyIndex = keyIndex
        _keyConfig = State(initialValue: KeyConfig())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Key \(keyIndex + 1) Configuration")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                // Macro type
                Picker("Type", selection: $keyConfig.type) {
                    ForEach(MacroType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                // Label
                TextField("Label", text: $keyConfig.label)

                // Icon source
                Section("Icon") {
                    iconPicker
                }

                // Type-specific options
                switch keyConfig.type {
                case .spotify:
                    spotifyOptions
                case .shell:
                    shellOptions
                case .app:
                    appOptions
                case .api:
                    apiOptions
                case .keystroke:
                    keystrokeOptions
                case .none:
                    EmptyView()
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            // Footer
            HStack {
                Button("Remove", role: .destructive) {
                    configStore.removeKeyConfig(for: keyIndex)
                    macroEngine.loadFromConfig(configStore)
                    dismiss()
                }

                Spacer()

                Button("Save") {
                    configStore.setKeyConfig(keyConfig, for: keyIndex)
                    macroEngine.loadFromConfig(configStore)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 500)
        .onAppear {
            keyConfig = configStore.keyConfig(for: keyIndex) ?? KeyConfig()
        }
    }

    // MARK: - Icon Picker

    @ViewBuilder
    private var iconPicker: some View {
        Picker("Source", selection: iconSourceBinding) {
            Text("SF Symbol").tag("sfSymbol")
            Text("Custom Image").tag("file")
            Text("Text").tag("text")
            Text("None").tag("none")
        }

        switch keyConfig.iconSource {
        case .sfSymbol(let name):
            TextField("SF Symbol Name", text: sfSymbolBinding)
            if !name.isEmpty {
                HStack {
                    Text("Preview:")
                    Image(systemName: name)
                        .font(.title)
                }
            }
        case .file:
            HStack {
                Text(filePathDisplay)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose...") {
                    chooseImageFile()
                }
            }
        case .text:
            TextField("Icon Text", text: iconTextBinding)
        default:
            EmptyView()
        }
    }

    // MARK: - Macro Type Options

    @ViewBuilder
    private var spotifyOptions: some View {
        Picker("Command", selection: spotifyActionBinding) {
            Text("Play/Pause").tag("playPause")
            Text("Next Track").tag("next")
            Text("Previous Track").tag("previous")
            Text("Volume Up").tag("volumeUp")
            Text("Volume Down").tag("volumeDown")
            Text("Now Playing").tag("nowPlaying")
        }
    }

    @ViewBuilder
    private var shellOptions: some View {
        TextField("Command", text: Binding(
            get: { keyConfig.command ?? "" },
            set: { keyConfig.command = $0 }
        ))
    }

    @ViewBuilder
    private var appOptions: some View {
        TextField("Application Name", text: Binding(
            get: { keyConfig.appName ?? "" },
            set: { keyConfig.appName = $0 }
        ))
    }

    @ViewBuilder
    private var apiOptions: some View {
        TextField("URL", text: Binding(
            get: { keyConfig.url ?? "" },
            set: { keyConfig.url = $0 }
        ))
        Picker("Method", selection: Binding(
            get: { keyConfig.method ?? "GET" },
            set: { keyConfig.method = $0 }
        )) {
            Text("GET").tag("GET")
            Text("POST").tag("POST")
            Text("PUT").tag("PUT")
            Text("DELETE").tag("DELETE")
        }
        TextField("Body (JSON)", text: Binding(
            get: { keyConfig.body ?? "" },
            set: { keyConfig.body = $0 }
        ), axis: .vertical)
        .lineLimit(3...6)
    }

    @ViewBuilder
    private var keystrokeOptions: some View {
        TextField("AppleScript", text: Binding(
            get: { keyConfig.keystrokeScript ?? "" },
            set: { keyConfig.keystrokeScript = $0 }
        ), axis: .vertical)
        .lineLimit(3...6)
    }

    // MARK: - Bindings

    private var iconSourceBinding: Binding<String> {
        Binding(
            get: {
                switch keyConfig.iconSource {
                case .sfSymbol: return "sfSymbol"
                case .file: return "file"
                case .text: return "text"
                default: return "none"
                }
            },
            set: { newValue in
                switch newValue {
                case "sfSymbol": keyConfig.iconSource = .sfSymbol("")
                case "file": keyConfig.iconSource = .file("")
                case "text": keyConfig.iconSource = .text("")
                default: keyConfig.iconSource = .none
                }
            }
        )
    }

    private var sfSymbolBinding: Binding<String> {
        Binding(
            get: {
                if case .sfSymbol(let name) = keyConfig.iconSource { return name }
                return ""
            },
            set: { keyConfig.iconSource = .sfSymbol($0) }
        )
    }

    private var iconTextBinding: Binding<String> {
        Binding(
            get: {
                if case .text(let text) = keyConfig.iconSource { return text }
                return ""
            },
            set: { keyConfig.iconSource = .text($0) }
        )
    }

    private var spotifyActionBinding: Binding<String> {
        Binding(
            get: { keyConfig.action ?? "playPause" },
            set: { keyConfig.action = $0 }
        )
    }

    private var filePathDisplay: String {
        if case .file(let path) = keyConfig.iconSource, !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        return "No file selected"
    }

    private func chooseImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            keyConfig.iconSource = .file(url.path)
        }
    }
}
