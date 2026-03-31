import Foundation
import IOKit
import IOKit.usb
import os

private let logger = Logger(subsystem: "com.displaypad.controller", category: "hotplug")

/// Monitors for USB hotplug events for the DisplayPad device.
///
/// Uses IOKit matching notifications (not HID Manager) to detect plug/unplug.
/// This works even though IOKit HID Manager can't see the device directly.
final class HotplugMonitor {
    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    var onDeviceConnected: (() -> Void)?
    var onDeviceDisconnected: (() -> Void)?

    func startMonitoring() {
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        matchingDict[kUSBVendorID] = DisplayPadProtocol.vendorID
        matchingDict[kUSBProductID] = DisplayPadProtocol.productID

        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notifyPort else {
            logger.error("Failed to create IONotificationPort")
            return
        }

        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        // Device added notification
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let addResult = IOServiceAddMatchingNotification(
            notifyPort,
            kIOFirstMatchNotification,
            matchingDict.copy() as! CFDictionary,
            { refCon, iterator in
                guard let refCon else { return }
                let monitor = Unmanaged<HotplugMonitor>.fromOpaque(refCon).takeUnretainedValue()
                // Drain the iterator
                var service = IOIteratorNext(iterator)
                var found = false
                while service != 0 {
                    found = true
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                if found {
                    logger.info("DisplayPad connected")
                    DispatchQueue.main.async {
                        monitor.onDeviceConnected?()
                    }
                }
            },
            selfPtr,
            &addedIterator
        )

        if addResult == KERN_SUCCESS {
            // Drain the initial iterator (required by IOKit)
            var service = IOIteratorNext(addedIterator)
            while service != 0 {
                IOObjectRelease(service)
                service = IOIteratorNext(addedIterator)
            }
            logger.info("Monitoring for DisplayPad connection")
        }

        // Device removed notification
        let removeResult = IOServiceAddMatchingNotification(
            notifyPort,
            kIOTerminatedNotification,
            matchingDict as CFDictionary,
            { refCon, iterator in
                guard let refCon else { return }
                let monitor = Unmanaged<HotplugMonitor>.fromOpaque(refCon).takeUnretainedValue()
                var service = IOIteratorNext(iterator)
                var found = false
                while service != 0 {
                    found = true
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                if found {
                    logger.info("DisplayPad disconnected")
                    DispatchQueue.main.async {
                        monitor.onDeviceDisconnected?()
                    }
                }
            },
            selfPtr,
            &removedIterator
        )

        if removeResult == KERN_SUCCESS {
            var service = IOIteratorNext(removedIterator)
            while service != 0 {
                IOObjectRelease(service)
                service = IOIteratorNext(removedIterator)
            }
            logger.info("Monitoring for DisplayPad disconnection")
        }
    }

    func stopMonitoring() {
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
