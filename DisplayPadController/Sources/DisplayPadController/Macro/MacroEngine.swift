import AppKit
import os

private let logger = Logger(subsystem: "com.displaypad.controller", category: "macro")

/// Protocol for executable macro actions.
protocol MacroAction {
    var name: String { get }
    func execute()
}

/// Manages macro registrations and dispatches key events.
@Observable
final class MacroEngine {
    struct Registration {
        let config: KeyConfig
        let action: MacroAction?
        let icon: NSImage?
    }

    private(set) var registrations: [Int: Registration] = [:]

    /// Build registrations from config.
    func loadFromConfig(_ configStore: ConfigStore) {
        registrations.removeAll()

        for (key, keyConfig) in configStore.config.keys {
            guard let index = Int(key) else { continue }
            let action = MacroActionFactory.create(from: keyConfig)
            let icon = IconFactory.createIcon(from: keyConfig)
            registrations[index] = Registration(config: keyConfig, action: action, icon: icon)
        }

        logger.info("Loaded \(self.registrations.count) macros")
    }

    /// Handle a key press (keyNumber is 1-based from device).
    func handleKeyDown(_ keyNumber: Int) {
        let keyIndex = keyNumber - 1
        guard let reg = registrations[keyIndex], let action = reg.action else { return }
        logger.info("Key \(keyNumber) -> \(action.name)")
        DispatchQueue.global(qos: .userInitiated).async {
            action.execute()
        }
    }

    /// Handle a key release.
    func handleKeyUp(_ keyNumber: Int) {
        // Future: support hold/release actions
    }
}

// MARK: - Action Factory

enum MacroActionFactory {
    static func create(from config: KeyConfig) -> MacroAction? {
        switch config.type {
        case .none:
            return nil
        case .spotify:
            guard let action = config.action else { return nil }
            return SpotifyAction(command: action)
        case .shell:
            guard let command = config.command else { return nil }
            return ShellAction(command: command)
        case .app:
            guard let appName = config.appName else { return nil }
            return AppLaunchAction(appName: appName)
        case .keystroke:
            guard let script = config.keystrokeScript else { return nil }
            return KeystrokeAction(script: script)
        case .api:
            guard let url = config.url else { return nil }
            return APICallAction(
                url: url,
                method: config.method ?? "GET",
                headers: config.headers ?? [:],
                body: config.body
            )
        }
    }
}

// MARK: - Icon Factory

enum IconFactory {
    static func createIcon(from config: KeyConfig) -> NSImage? {
        switch config.iconSource {
        case .sfSymbol(let name):
            return NSImage(systemSymbolName: name, accessibilityDescription: config.label)
        case .file(let path):
            return NSImage(contentsOfFile: path)
        case .text(let text):
            // For text icons, we create the image inline
            let size = CGFloat(DisplayPadProtocol.iconSize)
            let image = NSImage(size: NSSize(width: size, height: size))
            image.lockFocus()
            NSColor.darkGray.setFill()
            NSRect(x: 0, y: 0, width: size, height: size).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            (text as NSString).draw(at: NSPoint(x: 8, y: size / 2 - 10), withAttributes: attrs)
            image.unlockFocus()
            return image
        case .bundled(let name):
            return NSImage(named: name)
        case .none:
            return nil
        }
    }
}
