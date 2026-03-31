import AppKit

/// Converts images and colors to BGR pixel buffers for the DisplayPad.
///
/// The DisplayPad expects 102x102 pixels in BGR byte order, packed into a
/// 31438-byte buffer (with zero padding after the pixel data).
enum BGRBuffer {

    /// Create a solid color BGR buffer.
    static func solidColor(r: UInt8, g: UInt8, b: UInt8) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: DisplayPadProtocol.packetSize)
        for i in 0..<DisplayPadProtocol.numTotalPixels {
            buffer[i * 3]     = b   // BGR order
            buffer[i * 3 + 1] = g
            buffer[i * 3 + 2] = r
        }
        return buffer
    }

    /// Convert an NSImage to a 102x102 BGR pixel buffer.
    static func fromImage(_ image: NSImage) -> [UInt8] {
        let size = DisplayPadProtocol.iconSize

        // Render the image into a 102x102 RGBA bitmap
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: size * 4,
            bitsPerPixel: 32
        ) else {
            return solidColor(r: 0, g: 0, b: 0)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        let drawRect = NSRect(x: 0, y: 0, width: size, height: size)

        // Fill with black background
        NSColor.black.setFill()
        drawRect.fill()

        // Draw image scaled to fit
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        // Convert RGBA to BGR
        guard let pixelData = bitmapRep.bitmapData else {
            return solidColor(r: 0, g: 0, b: 0)
        }

        var buffer = [UInt8](repeating: 0, count: DisplayPadProtocol.packetSize)
        for y in 0..<size {
            for x in 0..<size {
                let srcOffset = (y * size + x) * 4
                let dstOffset = (y * size + x) * 3
                let r = pixelData[srcOffset]
                let g = pixelData[srcOffset + 1]
                let b = pixelData[srcOffset + 2]
                buffer[dstOffset]     = b   // BGR
                buffer[dstOffset + 1] = g
                buffer[dstOffset + 2] = r
            }
        }

        return buffer
    }

    /// Render text as a 102x102 BGR icon.
    static func fromText(
        _ text: String,
        backgroundColor: NSColor = .darkGray,
        textColor: NSColor = .white,
        fontSize: CGFloat = 14
    ) -> [UInt8] {
        let size = CGFloat(DisplayPadProtocol.iconSize)

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        // Background
        backgroundColor.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        // Text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.boundingRect(
            with: NSSize(width: size - 8, height: size),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textRect = NSRect(
            x: 4,
            y: (size - textSize.height) / 2,
            width: size - 8,
            height: textSize.height
        )
        attrString.draw(in: textRect)

        image.unlockFocus()
        return fromImage(image)
    }

    /// Render an SF Symbol as a 102x102 BGR icon.
    static func fromSFSymbol(
        _ name: String,
        backgroundColor: NSColor = .darkGray,
        tintColor: NSColor = .white
    ) -> [UInt8] {
        let size = CGFloat(DisplayPadProtocol.iconSize)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        backgroundColor.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .medium)
            let configured = symbol.withSymbolConfiguration(config) ?? symbol
            let tinted = configured.tinted(with: tintColor)
            let symbolSize = tinted.size
            let x = (size - symbolSize.width) / 2
            let y = (size - symbolSize.height) / 2
            tinted.draw(in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height))
        }

        image.unlockFocus()
        return fromImage(image)
    }
}

// MARK: - NSImage Tinting

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let tinted = self.copy() as! NSImage
        tinted.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: tinted.size)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }
}
