import Foundation
import os

private let logger = Logger(subsystem: "com.displaypad.controller", category: "boot")

/// Runs the multi-strategy boot sequence on the DisplayPad.
///
/// The device requires ~36 seconds to fully boot. Strategy A and B prime the device,
/// and Strategy C (SET_REPORT + ffaa re-init) typically delivers the INIT ACK.
enum BootSequence {

    /// Run the full boot sequence. Returns true if INIT ACK was received.
    @discardableResult
    static func run(device: USBDeviceHandle, progress: ((String) -> Void)? = nil) -> Bool {
        let start = Date()

        // Strategy A: EP 0x04 init, wait 15s
        logger.info("Strategy A: EP 0x04 init...")
        progress?("Boot: Strategy A...")
        device.writeControl(DisplayPadProtocol.initMessage)

        if pollForAck(device: device, duration: 15, start: start, progress: progress) {
            return true
        }

        // Strategy B: EP 0x04 + EP 0x02 init, wait 10s
        logger.info("Strategy B: EP 0x04 + EP 0x02 init...")
        progress?("Boot: Strategy B...")
        device.writeControl(DisplayPadProtocol.initMessage)
        device.writeDisplay(DisplayPadProtocol.initPadded)

        if pollForAck(device: device, duration: 10, start: start, progress: progress) {
            return true
        }

        // Strategy C: SET_REPORT + re-send on ffaa, wait 15s
        logger.info("Strategy C: SET_REPORT + ffaa re-init...")
        progress?("Boot: Strategy C...")
        device.setReportControl(DisplayPadProtocol.initMessage)

        let strategyStart = Date()
        while Date().timeIntervalSince(strategyStart) < 15 {
            guard let data = device.readControl(timeout: 500) else { continue }

            if data[0] == 0x11 {
                let elapsed = Date().timeIntervalSince(start)
                logger.info("INIT ACK! (\(Int(elapsed))s)")
                progress?("Boot complete (\(Int(elapsed))s)")
                return true
            }

            if data[0] == 0xFF {
                logger.debug("ffaa, re-sending init...")
                device.writeControl(DisplayPadProtocol.initMessage)
                device.writeDisplay(DisplayPadProtocol.initPadded)
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        logger.warning("No ACK after \(Int(elapsed))s, proceeding anyway")
        progress?("Boot: no ACK, proceeding")
        return false
    }

    // MARK: - Private

    private static func pollForAck(
        device: USBDeviceHandle,
        duration: TimeInterval,
        start: Date,
        progress: ((String) -> Void)?
    ) -> Bool {
        let pollStart = Date()
        while Date().timeIntervalSince(pollStart) < duration {
            guard let data = device.readControl(timeout: 500) else { continue }

            if data[0] == 0x11 {
                let elapsed = Date().timeIntervalSince(start)
                logger.info("INIT ACK! (\(Int(elapsed))s)")
                progress?("Boot complete (\(Int(elapsed))s)")
                return true
            }

            if data[0] == 0xFF {
                let elapsed = Date().timeIntervalSince(start)
                logger.debug("ffaa at \(Int(elapsed))s")
            }
        }
        return false
    }
}
