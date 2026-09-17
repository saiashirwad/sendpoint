import AppKit

/// The status item's glyph: the app icon redrawn as a template image so its
/// line-and-capture mark stays crisp at menu-bar size. Colour is dropped; the
/// magenta recording dot becomes part of the monochrome template.
enum MenuBarIcon {
    /// The icon's art is laid out on a 1024-unit canvas like the app icon;
    /// this tile is the part of it that is drawn.
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

        // The four quiet text lines stay secondary to the selected passage.
        context.setFillColor(CGColor(gray: 0, alpha: 0.46))
        context.addPath(pill(x: 292, y: 278, width: 340, height: 48))
        context.addPath(pill(x: 292, y: 368, width: 394, height: 48))
        context.addPath(pill(x: 292, y: 608, width: 394, height: 48))
        context.addPath(pill(x: 292, y: 698, width: 292, height: 48))
        context.fillPath()

        // The selected passage, focus brackets, and recording dot are the
        // recognizable core of the supplied mark.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(pill(x: 310, y: 480, width: 360, height: 66))
        context.addEllipse(in: CGRect(x: 764, y: 487, width: 54, height: 54))
        context.fillPath()

        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(26)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(bracket(x: 250, opensRight: true))
        context.addPath(bracket(x: 730, opensRight: false))
        context.strokePath()
    }

    private static func pill(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGPath {
        CGPath(
            roundedRect: CGRect(x: x, y: y, width: width, height: height),
            cornerWidth: height / 2,
            cornerHeight: height / 2,
            transform: nil
        )
    }

    private static func bracket(x: CGFloat, opensRight: Bool) -> CGPath {
        let inward: CGFloat = opensRight ? 32 : -32
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x + inward, y: 458))
        path.addLine(to: CGPoint(x: x, y: 458))
        path.addLine(to: CGPoint(x: x, y: 568))
        path.addLine(to: CGPoint(x: x + inward, y: 568))
        return path
    }
}
