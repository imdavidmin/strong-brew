import AppKit

// Renders the app icon into an .iconset directory: make-icon <out.iconset>
// Compiled together with ../Icons.swift for `sparkle`.

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let scale = size / 1024
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: scale, y: scale)

        // Background squircle on Apple's 1024 grid (824pt body, 100pt margin).
        let body = NSRect(x: 100, y: 100, width: 824, height: 824)
        let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowBlurRadius = 24
        shadow.set()
        NSColor.black.setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(colors: [NSColor(srgbRed: 0.14, green: 0.11, blue: 0.38, alpha: 1),
                            NSColor(srgbRed: 0.42, green: 0.20, blue: 0.75, alpha: 1)])!
            .draw(in: squircle, angle: 90)

        // Bolt, tinted with a warm gradient.
        if let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 470, weight: .bold)) {
            let s = symbol.size
            let rect = NSRect(x: 512 - s.width / 2, y: 505 - s.height / 2, width: s.width, height: s.height)
            let bolt = NSImage(size: s, flipped: false) { r in
                symbol.draw(in: r)
                NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.62, blue: 0.11, alpha: 1),
                                    NSColor(srgbRed: 1.0, green: 0.90, blue: 0.35, alpha: 1)])!
                    .draw(in: r, angle: 90)
                return true
            }
            // Mask the gradient to the symbol shape.
            let masked = NSImage(size: s, flipped: false) { r in
                symbol.draw(in: r)
                bolt.draw(in: r, from: .zero, operation: .sourceIn, fraction: 1)
                return true
            }
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = NSColor(srgbRed: 1, green: 0.8, blue: 0.3, alpha: 0.7)
            glow.shadowBlurRadius = 40
            glow.set()
            masked.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor(srgbRed: 1, green: 0.95, blue: 0.75, alpha: 1).setFill()
        sparkle(center: CGPoint(x: 735, y: 735), radius: 70).fill()
        sparkle(center: CGPoint(x: 285, y: 290), radius: 52).fill()
        sparkle(center: CGPoint(x: 760, y: 360), radius: 34).fill()
        sparkle(center: CGPoint(x: 280, y: 720), radius: 28).fill()
        return true
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let image = drawIcon(size: CGFloat(px))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
