import Foundation
import os

private let logger = Logger(subsystem: "com.displaypad.controller", category: "shell")

/// Execute a shell command.
struct ShellAction: MacroAction {
    let command: String

    var name: String { "Shell: \(command)" }

    func execute() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        do {
            try process.run()
        } catch {
            logger.error("Shell command failed: \(error.localizedDescription)")
        }
    }
}

/// Launch an application by name.
struct AppLaunchAction: MacroAction {
    let appName: String

    var name: String { "Launch: \(appName)" }

    func execute() {
        let script = "tell application \"\(appName)\" to activate"
        AppleScriptRunner.run(script)
    }
}

/// Simulate keystrokes via AppleScript.
struct KeystrokeAction: MacroAction {
    let script: String

    var name: String { "Keystroke" }

    func execute() {
        AppleScriptRunner.run(script)
    }
}

/// Make an HTTP API call.
struct APICallAction: MacroAction {
    let url: String
    let method: String
    let headers: [String: String]
    let body: String?

    var name: String { "\(method) \(url)" }

    func execute() {
        guard let url = URL(string: url) else {
            logger.error("Invalid URL: \(self.url)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.httpBody = body.data(using: .utf8)
        }

        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                logger.error("API call failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                logger.info("API response: \(http.statusCode)")
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
    }
}
