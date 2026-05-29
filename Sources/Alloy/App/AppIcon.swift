import AppKit

/// Renders the Alloy app icon programmatically (per the README design): a deep
/// charcoal squircle with two interlocked chevrons — Swift orange + Rust amber —
/// blending to warm gold at the central bond. Set as the dock icon at launch;
/// no asset catalog needed for the SwiftPM build.
enum AppIcon {
    static func image(size: CGFloat = 512) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        defer { img.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)

        // Squircle background with a subtle vertical sheen.
        let corner = size * 0.2237
        let bg = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        bg.addClip()
        if let grad = NSGradient(colors: [NSColor(hex: 0x16161C), NSColor(hex: 0x0C0C10)]) {
            grad.draw(in: rect, angle: -90)
        } else {
            NSColor(hex: 0x0E0E12).setFill(); bg.fill()
        }

        let cx = size / 2, cy = size / 2
        let h = size * 0.40          // chevron vertical span
        let depth = size * 0.20      // how far the arms reach back
        let lw = size * 0.115        // stroke width

        func chevron(tipX: CGFloat, color: NSColor, glow: Bool) {
            let p = NSBezierPath()
            p.lineWidth = lw
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.move(to: NSPoint(x: tipX - depth, y: cy + h / 2))
            p.line(to: NSPoint(x: tipX, y: cy))
            p.line(to: NSPoint(x: tipX - depth, y: cy - h / 2))
            if glow {
                NSColor(hex: 0xE8A050).withAlphaComponent(0.35).setStroke()
                let g = p.copy() as! NSBezierPath
                g.lineWidth = lw * 1.7
                g.stroke()
            }
            color.setStroke()
            p.stroke()
        }

        // Left chevron (Swift orange), right chevron (Rust amber), overlapping at center.
        chevron(tipX: cx * 0.92, color: NSColor(hex: 0xF05138), glow: false)
        chevron(tipX: cx * 1.20, color: NSColor(hex: 0xCE422B), glow: true)

        // Molten-gold bond highlight where they meet.
        let bondR = size * 0.045
        let bond = NSBezierPath(ovalIn: NSRect(x: cx * 0.92 - bondR, y: cy - bondR,
                                               width: bondR * 2, height: bondR * 2))
        NSColor(hex: 0xE8A050).withAlphaComponent(0.9).setFill()
        bond.fill()

        return img
    }
}
