import Foundation
import os

private let logger = Logger(subsystem: "com.displaypad.controller", category: "transfer")

/// Handles per-key image transfer to the DisplayPad.
///
/// The first key transfer after boot always fails completion and requires re-init.
/// Subsequent keys succeed normally.
enum ImageTransfer {

    /// Transfer pixel data to a single key. Handles completion wait and re-init if needed.
    ///
    /// - Parameters:
    ///   - device: The USB device handle.
    ///   - keyIndex: Key index (0-11).
    ///   - pixelData: BGR pixel buffer (31438 bytes, from BGRBuffer).
    ///   - buttonHandler: Optional callback for button events received during transfer.
    /// - Returns: true if transfer completed or sent successfully.
    @discardableResult
    static func transfer(
        device: USBDeviceHandle,
        keyIndex: Int,
        pixelData: [UInt8],
        buttonHandler: (([UInt8]) -> Void)? = nil
    ) -> Bool {
        logger.info("Key \(keyIndex)...")

        // IMG command via EP 0x04
        let imgCmd = DisplayPadProtocol.makeImageCommand(keyIndex: UInt8(keyIndex))
        let rc = device.writeControl(imgCmd)
        if rc != 0 {
            logger.error("Key \(keyIndex): IMG failed (rc=\(rc))")
            return false
        }

        // Wait for IMG ACK
        var acked = false
        for _ in 0..<20 {
            guard let data = device.readControl(timeout: 500) else { continue }
            if data.count >= 3, data[0] == 0x21, data[1] == 0x00, data[2] == 0x00 {
                logger.debug("Key \(keyIndex): IMG ACK")
                acked = true
                break
            }
            if data[0] == 0x01 {
                buttonHandler?(data)
            }
        }

        guard acked else {
            logger.error("Key \(keyIndex): No ACK")
            return false
        }

        // Build full payload: 306-byte header + pixel data
        let header = [UInt8](repeating: 0, count: DisplayPadProtocol.headerSize)
        var fullData = header + pixelData
        // Ensure we have enough data for full chunks
        let totalChunks = (fullData.count + DisplayPadProtocol.chunkSize - 1) / DisplayPadProtocol.chunkSize
        let paddedSize = totalChunks * DisplayPadProtocol.chunkSize
        if fullData.count < paddedSize {
            fullData.append(contentsOf: [UInt8](repeating: 0, count: paddedSize - fullData.count))
        }

        // Send pixel chunks
        var chunkOK = 0
        for i in stride(from: 0, to: fullData.count, by: DisplayPadProtocol.chunkSize) {
            let end = min(i + DisplayPadProtocol.chunkSize, fullData.count)
            let chunk = Array(fullData[i..<end])
            if device.writeDisplay(chunk) == 0 {
                chunkOK += 1
            }
        }
        logger.debug("Key \(keyIndex): Chunks \(chunkOK)/\(totalChunks)")

        // Re-send entire payload (firmware requirement)
        for i in stride(from: 0, to: fullData.count, by: DisplayPadProtocol.chunkSize) {
            let end = min(i + DisplayPadProtocol.chunkSize, fullData.count)
            let chunk = Array(fullData[i..<end])
            device.writeDisplay(chunk)
        }
        logger.debug("Key \(keyIndex): Re-send done")

        // Wait for completion: 15 reads × 1000ms
        var done = false
        for _ in 0..<15 {
            guard let data = device.readControl(timeout: 1000) else { continue }
            if data.count >= 3, data[0] == 0x21, data[1] == 0x00, data[2] == 0xFF {
                logger.info("Key \(keyIndex): DONE")
                done = true
                break
            }
            if data[0] == 0xFF {
                // ffaa keepalive, continue waiting
            }
            if data[0] == 0x01 {
                buttonHandler?(data)
            }
        }

        if !done {
            logger.info("Key \(keyIndex): Completion timeout, re-init")
            reinit(device: device)
        }

        return true
    }

    // MARK: - Re-init

    /// Re-initialize the device between transfers (after completion timeout).
    /// Matches the working test_multikey.py sequence exactly.
    private static func reinit(device: USBDeviceHandle) {
        device.setReportControl(DisplayPadProtocol.initMessage)
        device.writeControl(DisplayPadProtocol.initMessage)
        device.writeDisplay(DisplayPadProtocol.initPadded)
        Thread.sleep(forTimeInterval: 3)

        // Drain
        for _ in 0..<20 {
            guard device.readControl(timeout: 200) != nil else { break }
        }
    }
}
