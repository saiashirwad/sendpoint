import AppKit

/// The status item's glyph: the app icon redrawn as a template image, so the
/// menu bar shows the same speech bubble as the Dock and the website rather
/// than a stock symbol. Colour is dropped; the icon's shapes become alpha.
enum MenuBarIcon {
    /// The icon's art is laid out on a 1024-unit canvas like the app icon.
    private static let canvas: CGFloat = 1024
    private static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)

    static func image(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Fit the 824-unit tile to the image, dropping the canvas margin.
            let scale = rect.width / tile.width
            context.translateBy(x: -tile.minX * scale, y: -tile.minY * scale)
            context.scaleBy(x: scale, y: scale)
            draw(in: context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sendpoint"
        return image
    }

    private static func draw(in context: CGContext) {
        context.setFillColor(CGColor(gray: 0, alpha: 0.18))
        context.addPath(CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil))
        context.fillPath()

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(bubble)
        context.fillPath()

        // Text lines are knocked out of the bubble: the two quiet lines
        // faintly, the highlighted one fully.
        context.setBlendMode(.destinationOut)
        context.setFillColor(CGColor(gray: 0, alpha: 0.22))
        context.addPath(CGPath(roundedRect: CGRect(x: 292, y: 356, width: 440, height: 42), cornerWidth: 21, cornerHeight: 21, transform: nil))
        context.addPath(CGPath(roundedRect: CGRect(x: 292, y: 546, width: 380, height: 42), cornerWidth: 21, cornerHeight: 21, transform: nil))
        context.fillPath()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 292, y: 451, width: 348, height: 42), cornerWidth: 21, cornerHeight: 21, transform: nil))
        context.fillPath()
        context.setBlendMode(.normal)
    }

    /// The speech bubble from `Resources/AppIcon.svg`, in the same coordinates.
    private static var bubble: CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 296, y: 262))
        path.addLine(to: CGPoint(x: 728, y: 262))
        path.addArc(tangent1End: CGPoint(x: 812, y: 262), tangent2End: CGPoint(x: 812, y: 346), radius: 84)
        path.addLine(to: CGPoint(x: 812, y: 598))
        path.addArc(tangent1End: CGPoint(x: 812, y: 682), tangent2End: CGPoint(x: 728, y: 682), radius: 84)
        path.addLine(to: CGPoint(x: 420, y: 682))
        path.addLine(to: CGPoint(x: 318, y: 778))
        path.addLine(to: CGPoint(x: 336, y: 682))
        path.addLine(to: CGPoint(x: 296, y: 682))
        path.addArc(tangent1End: CGPoint(x: 212, y: 682), tangent2End: CGPoint(x: 212, y: 598), radius: 84)
        path.addLine(to: CGPoint(x: 212, y: 346))
        path.addArc(tangent1End: CGPoint(x: 212, y: 262), tangent2End: CGPoint(x: 296, y: 262), radius: 84)
        path.closeSubpath()
        return path
    }
}
