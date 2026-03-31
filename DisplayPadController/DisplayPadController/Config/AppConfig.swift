import Foundation

/// Source for a key's icon.
enum IconSource: Codable, Equatable {
    case sfSymbol(String)
    case bundled(String)
    case file(String)
    case text(String)
    case none

    enum CodingKeys: String, CodingKey {
        case type, value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sfSymbol(let name):
            try container.encode("sfSymbol", forKey: .type)
            try container.encode(name, forKey: .value)
        case .bundled(let name):
            try container.encode("bundled", forKey: .type)
            try container.encode(name, forKey: .value)
        case .file(let path):
            try container.encode("file", forKey: .type)
            try container.encode(path, forKey: .value)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .value)
        case .none:
            try container.encode("none", forKey: .type)
            try container.encode("", forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        switch type {
        case "sfSymbol": self = .sfSymbol(value)
        case "bundled":  self = .bundled(value)
        case "file":     self = .file(value)
        case "text":     self = .text(value)
        default:         self = .none
        }
    }
}

/// Macro type enumeration.
enum MacroType: String, Codable, CaseIterable, Identifiable {
    case none
    case spotify
    case shell
    case app
    case keystroke
    case api

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:      return "None"
        case .spotify:   return "Spotify"
        case .shell:     return "Shell Command"
        case .app:       return "Launch App"
        case .keystroke: return "Keystroke"
        case .api:       return "API Call"
        }
    }
}

/// Configuration for a single key.
struct KeyConfig: Codable, Equatable {
    var type: MacroType = .none
    var label: String = ""
    var action: String?
    var url: String?
    var method: String?
    var headers: [String: String]?
    var body: String?
    var command: String?
    var appName: String?
    var keystrokeScript: String?
    var iconSource: IconSource = .none
    var backgroundColor: String = "#333333"
}

/// Full application configuration.
struct AppConfig: Codable {
    var keys: [String: KeyConfig] = [:]
    var autoConnect: Bool = true
    var launchAtLogin: Bool = false

    /// Default config with 6 Spotify keys.
    static let `default`: AppConfig = {
        var config = AppConfig()
        let spotifyKeys: [(String, String, String)] = [
            ("0", "play.fill",     "playPause"),
            ("1", "forward.fill",  "next"),
            ("2", "backward.fill", "previous"),
            ("3", "speaker.wave.3.fill", "volumeUp"),
            ("4", "speaker.wave.1.fill", "volumeDown"),
            ("5", "music.note",    "nowPlaying"),
        ]
        for (idx, symbol, action) in spotifyKeys {
            config.keys[idx] = KeyConfig(
                type: .spotify,
                label: action,
                action: action,
                iconSource: .sfSymbol(symbol)
            )
        }
        return config
    }()
}
