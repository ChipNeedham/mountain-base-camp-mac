import AppKit
import os
import Observation

private let logger = Logger(subsystem: "com.displaypad.controller", category: "manager")

/// Connection state for the DisplayPad.
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case booting(String)
    case connected
}

/// Central coordinator for DisplayPad device communication.
///
/// Owns the USB context, device handle, and worker queue. All USB I/O runs
/// on a single serial dispatch queue. State is published to SwiftUI via @Observable.
@Observable
final class DisplayPadManager {

    // MARK: - Published State

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var bootStatus: String = ""
    private(set) var keyPressed: [Bool] = Array(repeating: false, count: DisplayPadProtocol.numKeys)

    // MARK: - Private

    private var context: LibUSBContext?
    private var device: USBDeviceHandle?
    private let buttonPoller = ButtonPoller()
    private let usbQueue = DispatchQueue(label: "com.displaypad.usb", qos: .userInitiated)
    private var isRunning = false
    private var transferQueue: [(keyIndex: Int, pixelData: [UInt8])] = []
    private let queueLock = NSLock()

    var onKeyDown: ((Int) -> Void)?    // key number 1-12
    var onKeyUp: ((Int) -> Void)?      // key number 1-12

    init() {
        buttonPoller.onKeyDown = { [weak self] keyNum in
            guard let self else { return }
            let idx = keyNum - 1
            if idx >= 0, idx < DisplayPadProtocol.numKeys {
                DispatchQueue.main.async { self.keyPressed[idx] = true }
            }
            self.onKeyDown?(keyNum)
        }
        buttonPoller.onKeyUp = { [weak self] keyNum in
            guard let self else { return }
            let idx = keyNum - 1
            if idx >= 0, idx < DisplayPadProtocol.numKeys {
                DispatchQueue.main.async { self.keyPressed[idx] = false }
            }
            self.onKeyUp?(keyNum)
        }
    }

    // MARK: - Connection

    /// Connect to the DisplayPad. Runs boot sequence on USB queue.
    func connect() {
        guard connectionState == .disconnected else { return }
        updateState(.connecting)

        usbQueue.async { [weak self] in
            guard let self else { return }
            do {
                let ctx = try LibUSBContext()
                self.context = ctx

                let dev = try USBDeviceHandle(context: ctx)
                self.device = dev

                // Boot (blocks ~36s)
                self.updateState(.booting("Booting..."))
                BootSequence.run(device: dev) { status in
                    self.updateState(.booting(status))
                }

                self.updateState(.connected)
                self.isRunning = true
                self.runWorkerLoop()

            } catch {
                logger.error("Connection failed: \(error.localizedDescription)")
                self.updateState(.disconnected)
            }
        }
    }

    /// Disconnect from the device.
    func disconnect() {
        isRunning = false
        usbQueue.async { [weak self] in
            self?.device?.close()
            self?.device = nil
            self?.context = nil
            self?.buttonPoller.reset()
            DispatchQueue.main.async {
                self?.connectionState = .disconnected
                self?.keyPressed = Array(repeating: false, count: DisplayPadProtocol.numKeys)
            }
        }
    }

    // MARK: - Image API

    /// Queue an image for transfer to a key.
    func setKeyImage(keyIndex: Int, image: NSImage) {
        let pixelData = BGRBuffer.fromImage(image)
        enqueueTransfer(keyIndex: keyIndex, pixelData: pixelData)
    }

    /// Queue a solid color for a key.
    func setKeyColor(keyIndex: Int, r: UInt8, g: UInt8, b: UInt8) {
        let pixelData = BGRBuffer.solidColor(r: r, g: g, b: b)
        enqueueTransfer(keyIndex: keyIndex, pixelData: pixelData)
    }

    /// Queue a text icon for a key.
    func setKeyText(keyIndex: Int, text: String, background: NSColor = .darkGray) {
        let pixelData = BGRBuffer.fromText(text, backgroundColor: background)
        enqueueTransfer(keyIndex: keyIndex, pixelData: pixelData)
    }

    /// Queue an SF Symbol icon for a key.
    func setKeySFSymbol(keyIndex: Int, name: String, background: NSColor = .darkGray) {
        let pixelData = BGRBuffer.fromSFSymbol(name, backgroundColor: background)
        enqueueTransfer(keyIndex: keyIndex, pixelData: pixelData)
    }

    /// Clear a key (set to black).
    func clearKey(keyIndex: Int) {
        setKeyColor(keyIndex: keyIndex, r: 0, g: 0, b: 0)
    }

    /// Clear all keys.
    func clearAll() {
        for i in 0..<DisplayPadProtocol.numKeys {
            clearKey(keyIndex: i)
        }
    }

    // MARK: - Private

    private func enqueueTransfer(keyIndex: Int, pixelData: [UInt8]) {
        queueLock.lock()
        transferQueue.append((keyIndex: keyIndex, pixelData: pixelData))
        queueLock.unlock()
    }

    private func dequeueTransfer() -> (keyIndex: Int, pixelData: [UInt8])? {
        queueLock.lock()
        defer { queueLock.unlock() }
        return transferQueue.isEmpty ? nil : transferQueue.removeFirst()
    }

    /// Worker loop: process transfer queue, poll buttons. Runs on USB queue.
    private func runWorkerLoop() {
        guard let device else { return }

        while isRunning {
            if let item = dequeueTransfer() {
                ImageTransfer.transfer(
                    device: device,
                    keyIndex: item.keyIndex,
                    pixelData: item.pixelData,
                    buttonHandler: { [weak self] data in
                        self?.buttonPoller.processButtonData(data)
                    }
                )
            } else {
                // Poll for button events
                if let data = device.readControl(timeout: 100) {
                    if data[0] == 0x01 {
                        buttonPoller.processButtonData(data)
                    }
                }
            }
        }
    }

    private func updateState(_ state: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = state
            if case .booting(let status) = state {
                self?.bootStatus = status
            }
        }
    }
}
