import AppKit

// Menu bar icons are drawn as template images so macOS tints them for
// light/dark menu bars.
enum MenuBarIcon {
    static let awake = template(size: NSSize(width: 22, height: 18)) { rect in
        drawSymbol("bolt.fill", pointSize: 14, weight: .bold, centeredAt: CGPoint(x: rect.midX, y: rect.midY))
        sparkle(center: CGPoint(x: 18, y: 14), radius: 3.5).fill()
        sparkle(center: CGPoint(x: 4.5, y: 4.5), radius: 2.8).fill()
        sparkle(center: CGPoint(x: 19, y: 6), radius: 1.8).fill()
    }

    static let asleep = template(size: NSSize(width: 20, height: 18)) { rect in
        drawSymbol("zzz", pointSize: 14, weight: .semibold, centeredAt: CGPoint(x: rect.midX, y: rect.midY))
    }

    private static func template(size: NSSize, draw: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()
            draw(rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, centeredAt center: CGPoint) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight)) else { return }
        let s = symbol.size
        symbol.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
    }
}

/// Four-pointed star with concave sides.
func sparkle(center c: CGPoint, radius r: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let points = [CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x + r, y: c.y),
                  CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x - r, y: c.y)]
    // Pulling the control point slightly out from the centre fattens the arms.
    path.move(to: points[0])
    var previous = points[0]
    for p in points.dropFirst() + [points[0]] {
        let control = CGPoint(x: c.x + (previous.x + p.x - 2 * c.x) * 0.15,
                              y: c.y + (previous.y + p.y - 2 * c.y) * 0.15)
        path.curve(to: p, controlPoint1: control, controlPoint2: control)
        previous = p
    }
    path.close()
    return path
}
