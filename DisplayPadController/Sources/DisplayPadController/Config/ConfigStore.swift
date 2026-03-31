import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.displaypad.controller", category: "config")

/// Persistent configuration storage.
///
/// Reads/writes JSON config at ~/.config/displaypad/config.json.
/// Compatible with the Python DisplayPad app's config format.
@Observable
final class ConfigStore {
    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/displaypad")
    static let configURL = configDir.appendingPathComponent("config.json")

    var config: AppConfig

    init() {
        config = Self.load()
    }

    static func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            logger.info("No config found, using defaults")
            return .default
        }

        do {
            let data = try Data(contentsOf: configURL)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            logger.info("Loaded config with \(config.keys.count) keys")
            return config
        } catch {
            logger.error("Failed to load config: \(error.localizedDescription)")
            return .default
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: Self.configDir,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: Self.configURL, options: .atomic)
            logger.info("Config saved")
        } catch {
            logger.error("Failed to save config: \(error.localizedDescription)")
        }
    }

    /// Get config for a key index, or nil if not configured.
    func keyConfig(for index: Int) -> KeyConfig? {
        config.keys[String(index)]
    }

    /// Set config for a key index.
    func setKeyConfig(_ keyConfig: KeyConfig, for index: Int) {
        config.keys[String(index)] = keyConfig
        save()
    }

    /// Remove config for a key index.
    func removeKeyConfig(for index: Int) {
        config.keys.removeValue(forKey: String(index))
        save()
    }
}
