import Foundation
import os

private let logger = Logger(subsystem: "com.displaypad.controller", category: "spotify")

/// Spotify control via AppleScript.
struct SpotifyAction: MacroAction {
    let command: String

    var name: String { "Spotify: \(command)" }

    func execute() {
        let script: String
        switch command {
        case "playPause":
            script = "tell application \"Spotify\" to playpause"
        case "next":
            script = "tell application \"Spotify\" to next track"
        case "previous":
            script = "tell application \"Spotify\" to previous track"
        case "volumeUp":
            script = "tell application \"Spotify\" to set sound volume to (sound volume + 10)"
        case "volumeDown":
            script = "tell application \"Spotify\" to set sound volume to (sound volume - 10)"
        case "nowPlaying":
            script = """
            tell application "Spotify"
                set trackName to name of current track
                set artistName to artist of current track
                display notification trackName with title artistName
            end tell
            """
        default:
            logger.warning("Unknown Spotify command: \(command)")
            return
        }

        AppleScriptRunner.run(script)
    }
}
