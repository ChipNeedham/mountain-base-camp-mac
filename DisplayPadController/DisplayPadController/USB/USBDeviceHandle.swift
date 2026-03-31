import Foundation

/// Low-level wrapper around a libusb device handle.
///
/// All methods are synchronous and must be called from the USB serial queue.
/// Uses local buffer variables for each transfer (not stored properties) to avoid
/// the ARM64 ctypes/GC issue discovered in the Python implementation.
final class USBDeviceHandle {
    private let context: LibUSBContext
    private(set) var handle: OpaquePointer?

    init(context: LibUSBContext) throws {
        self.context = context

        handle = libusb_open_device_with_vid_pid(
            context.ctx,
            DisplayPadProtocol.vendorID,
            DisplayPadProtocol.productID
        )
        guard handle != nil else {
            throw DisplayPadError.deviceNotFound
        }

        // Detach kernel drivers and claim interfaces
        for intf in DisplayPadProtocol.claimedInterfaces {
            if libusb_kernel_driver_active(handle, intf) == 1 {
                libusb_detach_kernel_driver(handle, intf)
            }
            let rc = libusb_claim_interface(handle, intf)
            guard rc == 0 else {
                throw DisplayPadError.interfaceClaimFailed(interface: intf, rc: rc)
            }
        }
    }

    deinit {
        close()
    }

    func close() {
        guard let h = handle else { return }
        for intf in DisplayPadProtocol.claimedInterfaces {
            libusb_release_interface(h, intf)
        }
        libusb_close(h)
        handle = nil
    }

    // MARK: - Interrupt Transfers

    /// Write data to an interrupt OUT endpoint.
    @discardableResult
    func interruptWrite(endpoint: UInt8, data: [UInt8], timeout: UInt32 = 5000) -> Int32 {
        guard let h = handle else { return -99 }
        var transferred: Int32 = 0
        var buffer = data
        return libusb_interrupt_transfer(h, endpoint, &buffer, Int32(data.count), &transferred, timeout)
    }

    /// Read data from an interrupt IN endpoint. Returns nil on timeout/error.
    func interruptRead(endpoint: UInt8, maxLength: Int = 64, timeout: UInt32 = 500) -> [UInt8]? {
        guard let h = handle else { return nil }
        var buffer = [UInt8](repeating: 0, count: maxLength)
        var transferred: Int32 = 0
        let rc = libusb_interrupt_transfer(h, endpoint, &buffer, Int32(maxLength), &transferred, timeout)
        guard rc == 0, transferred > 0 else { return nil }
        return Array(buffer.prefix(Int(transferred)))
    }

    // MARK: - Control Transfers

    /// Send a SET_REPORT control transfer (HID output report).
    @discardableResult
    func setReport(data: [UInt8], interface: UInt16, timeout: UInt32 = 3000) -> Int32 {
        guard let h = handle else { return -99 }
        var buffer = data
        return libusb_control_transfer(
            h,
            0x21,       // bmRequestType: host-to-device, class, interface
            0x09,       // bRequest: SET_REPORT
            0x0200,     // wValue: output report, report ID 0
            interface,  // wIndex: interface number
            &buffer,
            UInt16(data.count),
            timeout
        )
    }

    // MARK: - Convenience

    /// Write to EP 0x04 (control out).
    @discardableResult
    func writeControl(_ data: [UInt8], timeout: UInt32 = 5000) -> Int32 {
        interruptWrite(endpoint: DisplayPadProtocol.epControlOut, data: data, timeout: timeout)
    }

    /// Write to EP 0x02 (display out).
    @discardableResult
    func writeDisplay(_ data: [UInt8], timeout: UInt32 = 5000) -> Int32 {
        interruptWrite(endpoint: DisplayPadProtocol.epDisplayOut, data: data, timeout: timeout)
    }

    /// Read from EP 0x83 (control in).
    func readControl(timeout: UInt32 = 500) -> [UInt8]? {
        interruptRead(endpoint: DisplayPadProtocol.epControlIn, timeout: timeout)
    }

    /// SET_REPORT on interface 3.
    @discardableResult
    func setReportControl(_ data: [UInt8]) -> Int32 {
        setReport(data: data, interface: 3)
    }
}
