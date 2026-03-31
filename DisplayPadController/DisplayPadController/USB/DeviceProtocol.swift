import Foundation

/// Protocol constants for the Mountain DisplayPad USB HID device.
/// Reverse-engineered from JeLuF/mountain-displaypad (Node.js).
enum DisplayPadProtocol {
    static let vendorID: UInt16 = 0x3282
    static let productID: UInt16 = 0x0009

    static let iconSize = 102
    static let numKeys = 12
    static let keysPerRow = 6
    static let numTotalPixels = iconSize * iconSize       // 10404
    static let pixelDataSize = numTotalPixels * 3          // 31212
    static let packetSize = 31438
    static let headerSize = 306
    static let chunkSize = 1024

    static let epDisplayOut: UInt8 = 0x02   // Interface 1
    static let epControlOut: UInt8 = 0x04   // Interface 3
    static let epControlIn: UInt8 = 0x83    // Interface 3

    static let claimedInterfaces: [Int32] = [0, 1, 3]

    /// 64-byte INIT command (no report ID — libusb sends raw).
    static let initMessage: [UInt8] = {
        var msg = [UInt8](repeating: 0, count: 64)
        msg[0] = 0x11
        msg[1] = 0x80
        msg[4] = 0x01
        return msg
    }()

    /// 1024-byte padded INIT for EP 0x02.
    static let initPadded: [UInt8] = {
        var data = initMessage
        data.append(contentsOf: [UInt8](repeating: 0, count: chunkSize - initMessage.count))
        return data
    }()

    /// Build a 64-byte IMG command for the given key index.
    static func makeImageCommand(keyIndex: UInt8) -> [UInt8] {
        var cmd = [UInt8](repeating: 0, count: 64)
        cmd[0] = 0x21
        cmd[4] = keyIndex
        cmd[5] = 0x3d
        cmd[8] = 0x65
        cmd[9] = 0x65
        return cmd
    }

    /// Button bit masks: (byteOffset, bitMask) indexed by key number 1-12.
    static let keyMasks: [(offset: Int, mask: UInt8)] = [
        (0, 0),         // placeholder index 0
        (42, 0x02),     // key 1
        (42, 0x04),     // key 2
        (42, 0x08),     // key 3
        (42, 0x10),     // key 4
        (42, 0x20),     // key 5
        (42, 0x40),     // key 6
        (42, 0x80),     // key 7
        (47, 0x01),     // key 8
        (47, 0x02),     // key 9
        (47, 0x04),     // key 10
        (47, 0x08),     // key 11
        (47, 0x10),     // key 12
    ]
}
