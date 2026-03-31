import Foundation

/// Parses button events from EP 0x83 responses and tracks key state changes.
final class ButtonPoller {
    private var keyStates = [Bool](repeating: false, count: DisplayPadProtocol.numKeys + 1)

    var onKeyDown: ((Int) -> Void)?   // key number 1-12
    var onKeyUp: ((Int) -> Void)?     // key number 1-12

    /// Process a button data packet (byte[0] == 0x01) from EP 0x83.
    func processButtonData(_ data: [UInt8]) {
        for keyNum in 1...DisplayPadProtocol.numKeys {
            let (offset, mask) = DisplayPadProtocol.keyMasks[keyNum]
            guard offset < data.count else { continue }

            let pressed = (data[offset] & mask) != 0
            let wasPressed = keyStates[keyNum]

            if pressed && !wasPressed {
                keyStates[keyNum] = true
                onKeyDown?(keyNum)
            } else if !pressed && wasPressed {
                keyStates[keyNum] = false
                onKeyUp?(keyNum)
            }
        }
    }

    /// Reset all key states to unpressed.
    func reset() {
        keyStates = [Bool](repeating: false, count: DisplayPadProtocol.numKeys + 1)
    }

    /// Check if a specific key is currently pressed.
    func isPressed(keyNumber: Int) -> Bool {
        guard keyNumber >= 1, keyNumber <= DisplayPadProtocol.numKeys else { return false }
        return keyStates[keyNumber]
    }
}
