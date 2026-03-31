import Foundation
import os

private let logger = Logger(subsystem: "com.displaypad.controller", category: "applescript")

/// Helper for running AppleScript commands.
enum AppleScriptRunner {
    static func run(_ source: String) {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            logger.error("Failed to create AppleScript")
            return
        }
        script.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript error: \(error)")
        }
    }

    static func runReturningString(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript error: \(error)")
            return nil
        }
        return result.stringValue
    }
}
