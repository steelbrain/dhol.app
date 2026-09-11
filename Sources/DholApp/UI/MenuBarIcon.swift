import AppKit

/// The menu bar glyph: the same drum as the app icon, reduced to a silhouette
/// that still reads at 16 points.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            NSColor.black.setFill()

            // Barrel, seen from the same three-quarter angle as the app icon.
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 4, y: 14.8))
            body.curve(
                to: NSPoint(x: 15, y: 12.6),
                controlPoint1: NSPoint(x: 8, y: 15.5),
                controlPoint2: NSPoint(x: 12, y: 14.2)
            )
            body.line(to: NSPoint(x: 15, y: 3.4))
            body.curve(
                to: NSPoint(x: 4, y: 1.2),
                controlPoint1: NSPoint(x: 12, y: 1.8),
                controlPoint2: NSPoint(x: 8, y: 0.5)
            )
            body.close()
            body.fill()

            // Far rim, so the silhouette ends in a drum head rather than a
            // flat cut.
            NSBezierPath(ovalIn: NSRect(x: 12.8, y: 3.4, width: 4.4, height: 9.2)).fill()
            // Near rim.
            NSBezierPath(ovalIn: NSRect(x: 0.8, y: 1.2, width: 6.4, height: 13.6)).fill()

            // Knock out the near drum head. Without this the glyph is just a
            // barrel; the opening is what makes it read as a drum. The handler
            // can be asked to draw straight into a caller's context, so put the
            // compositing mode back rather than leaving everything drawn after
            // this punching holes too.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2.4, y: 3.6, width: 3.2, height: 8.8)).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
