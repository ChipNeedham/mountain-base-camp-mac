import Foundation

/// Errors specific to the DisplayPad USB communication.
enum DisplayPadError: LocalizedError {
    case libusbInitFailed(rc: Int32)
    case deviceNotFound
    case interfaceClaimFailed(interface: Int32, rc: Int32)
    case bootTimeout
    case transferFailed(keyIndex: Int, phase: String, rc: Int32)
    case deviceDisconnected

    var errorDescription: String? {
        switch self {
        case .libusbInitFailed(let rc):
            return "libusb initialization failed (rc=\(rc))"
        case .deviceNotFound:
            return "DisplayPad not found. Check USB connection and permissions.\n"
                + "Looking for VID=0x\(String(DisplayPadProtocol.vendorID, radix: 16)) "
                + "PID=0x\(String(DisplayPadProtocol.productID, radix: 16))\n"
                + "You may need to run with sudo."
        case .interfaceClaimFailed(let intf, let rc):
            return "Failed to claim interface \(intf) (rc=\(rc))"
        case .bootTimeout:
            return "Device boot timed out"
        case .transferFailed(let key, let phase, let rc):
            return "Transfer failed for key \(key) at \(phase) (rc=\(rc))"
        case .deviceDisconnected:
            return "Device disconnected"
        }
    }
}

/// Manages the libusb context lifecycle.
final class LibUSBContext {
    private(set) var ctx: OpaquePointer?

    init() throws {
        let rc = libusb_init(&ctx)
        guard rc == 0 else {
            throw DisplayPadError.libusbInitFailed(rc: rc)
        }
    }

    deinit {
        if let ctx {
            libusb_exit(ctx)
        }
    }
}
