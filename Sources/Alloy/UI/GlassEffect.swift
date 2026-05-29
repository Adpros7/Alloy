import AppKit

/// Liquid Glass building blocks.
///
/// On macOS 26+ these use the real `NSGlassEffectView` — which *refracts* the
/// backdrop (lensing at the edges + specular highlight), exactly like the system
/// Tahoe chrome — not just the Gaussian blur of `NSVisualEffectView`. We make the
/// window non-opaque (see AppDelegate) so this glass genuinely bends the desktop
/// and content behind it. Pre-26 systems fall back to a vibrant material so the
/// app still builds and reads as glass.

enum GlassProminence {
    case sheet
    case raised
    case floating
}

/// A glass-backed panel you add content into via `body`. Large surfaces stay
/// quiet; the raised "liquid" read is reserved for selected and clickable parts.
final class GlassPanelView: NSView {
    /// Add your subviews here (constrain them to `body`).
    let body = NSView()

    init(
        cornerRadius: CGFloat = 0,
        tint: NSColor? = nil,
        clear: Bool = false,
        prominence: GlassProminence = .sheet
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        if prominence == .sheet, clear {
            let backing = NSView()
            backing.translatesAutoresizingMaskIntoConstraints = false
            backing.wantsLayer = true
            backing.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
            backing.layer?.cornerRadius = cornerRadius
            backing.layer?.borderWidth = 1
            backing.layer?.borderColor = NSColor.white.withAlphaComponent(0.055).cgColor
            backing.layer?.masksToBounds = true
            addSubview(backing)
            pinToEdges(backing)

            body.translatesAutoresizingMaskIntoConstraints = false
            backing.addSubview(body)
            NSLayoutConstraint.activate([
                body.leadingAnchor.constraint(equalTo: backing.leadingAnchor),
                body.trailingAnchor.constraint(equalTo: backing.trailingAnchor),
                body.topAnchor.constraint(equalTo: backing.topAnchor),
                body.bottomAnchor.constraint(equalTo: backing.bottomAnchor),
            ])
        } else if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.tintColor = tint
            glass.style = clear ? .clear : .regular
            glass.translatesAutoresizingMaskIntoConstraints = false
            // The glass view sizes its contentView to fill itself.
            body.autoresizingMask = [.width, .height]
            glass.contentView = body
            addSubview(glass)
            pinToEdges(glass)
        } else {
            let fx = NSVisualEffectView()
            fx.material = .underWindowBackground
            fx.blendingMode = .behindWindow
            fx.state = .active
            fx.translatesAutoresizingMaskIntoConstraints = false
            if cornerRadius > 0 {
                fx.wantsLayer = true
                fx.layer?.cornerRadius = cornerRadius
                fx.layer?.masksToBounds = true
            }
            addSubview(fx)
            pinToEdges(fx)
            body.translatesAutoresizingMaskIntoConstraints = false
            fx.addSubview(body)
            NSLayoutConstraint.activate([
                body.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
                body.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
                body.topAnchor.constraint(equalTo: fx.topAnchor),
                body.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
            ])
        }

        if prominence != .sheet || !clear {
            let chrome = LiquidGlassChromeView(cornerRadius: cornerRadius, prominence: prominence)
            addSubview(chrome)
            pinToEdges(chrome)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func pinToEdges(_ v: NSView) {
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: leadingAnchor),
            v.trailingAnchor.constraint(equalTo: trailingAnchor),
            v.topAnchor.constraint(equalTo: topAnchor),
            v.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

enum Glass {
    /// A standalone glass hover surface. Keep this subtle: it should read like a
    /// macOS material response, not a cartoon bubble.
    static func pill(
        cornerRadius: CGFloat,
        tint: NSColor? = nil,
        prominence: GlassProminence = .floating
    ) -> NSView {
        let shape = GlassShapeView(cornerRadius: cornerRadius, tint: tint, prominence: prominence)
        shape.translatesAutoresizingMaskIntoConstraints = false
        return shape
    }

    /// Wrap a cluster of glass pieces so the system merges them when close (the
    /// "liquid" coalescing). Content is set as the container's contentView.
    static func container(_ content: NSView, spacing: CGFloat = 18) -> NSView {
        content.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 26.0, *) {
            let c = NSGlassEffectContainerView()
            c.spacing = spacing
            c.translatesAutoresizingMaskIntoConstraints = false
            c.contentView = content
            content.autoresizingMask = [.width, .height]
            return c
        }
        return content
    }
}

/// A decorative glass surface with no content. AppKit supplies backdrop
/// refraction; the overlay is deliberately quiet.
private final class GlassShapeView: NSView {
    init(cornerRadius: CGFloat, tint: NSColor?, prominence: GlassProminence) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.tintColor = tint
            glass.style = .regular
            glass.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glass)
            pinToEdges(glass)
        } else {
            let fx = NSVisualEffectView()
            fx.material = .hudWindow
            fx.blendingMode = .withinWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerRadius = cornerRadius
            fx.layer?.masksToBounds = true
            fx.translatesAutoresizingMaskIntoConstraints = false
            addSubview(fx)
            pinToEdges(fx)
        }

        let chrome = LiquidGlassChromeView(cornerRadius: cornerRadius, prominence: prominence)
        addSubview(chrome)
        pinToEdges(chrome)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func pinToEdges(_ v: NSView) {
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: leadingAnchor),
            v.trailingAnchor.constraint(equalTo: trailingAnchor),
            v.topAnchor.constraint(equalTo: topAnchor),
            v.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

/// Drawn highlights only: no gradient fills. This is restrained on purpose:
/// professional app chrome should not look inflated.
private final class LiquidGlassChromeView: NSView {
    private struct Style {
        let fillAlpha: CGFloat
        let castAlpha: CGFloat
        let shadowAlpha: CGFloat
        let shadowBlur: CGFloat
        let shadowOffset: CGFloat
        let outerRimAlpha: CGFloat
        let innerRimAlpha: CGFloat
        let darkRimAlpha: CGFloat
        let shineAlpha: CGFloat
    }

    private let cornerRadius: CGFloat
    private let prominence: GlassProminence

    init(cornerRadius: CGFloat, prominence: GlassProminence) {
        self.cornerRadius = cornerRadius
        self.prominence = prominence
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 2, bounds.height > 2 else { return }

        let style = styleForProminence()
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let radius = effectiveRadius(in: rect)
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        drawCastShadow(shape, style: style)
        drawGlassBody(shape, rect: rect, radius: radius, style: style)
        drawSpecularStreaks(rect: rect, radius: radius, style: style)
    }

    private func styleForProminence() -> Style {
        switch prominence {
        case .sheet:
            return Style(
                fillAlpha: 0.012,
                castAlpha: 0.004,
                shadowAlpha: 0.06,
                shadowBlur: 8,
                shadowOffset: -1,
                outerRimAlpha: 0.16,
                innerRimAlpha: 0.05,
                darkRimAlpha: 0.08,
                shineAlpha: 0.0
            )
        case .raised:
            return Style(
                fillAlpha: 0.026,
                castAlpha: 0.006,
                shadowAlpha: 0.08,
                shadowBlur: 10,
                shadowOffset: -1,
                outerRimAlpha: 0.18,
                innerRimAlpha: 0.06,
                darkRimAlpha: 0.06,
                shineAlpha: 0.0
            )
        case .floating:
            return Style(
                fillAlpha: 0.035,
                castAlpha: 0.008,
                shadowAlpha: 0.10,
                shadowBlur: 12,
                shadowOffset: -1,
                outerRimAlpha: 0.22,
                innerRimAlpha: 0.08,
                darkRimAlpha: 0.05,
                shineAlpha: 0.0
            )
        }
    }

    private func effectiveRadius(in rect: NSRect) -> CGFloat {
        let maximum = min(rect.width, rect.height) / 2
        if cornerRadius <= 0 { return 0 }
        return min(cornerRadius, maximum)
    }

    private func drawCastShadow(_ shape: NSBezierPath, style: Style) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(style.shadowAlpha)
        shadow.shadowBlurRadius = style.shadowBlur
        shadow.shadowOffset = NSSize(width: 0, height: style.shadowOffset)
        shadow.set()
        NSColor.white.withAlphaComponent(style.castAlpha).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGlassBody(_ shape: NSBezierPath, rect: NSRect, radius: CGFloat, style: Style) {
        NSColor.white.withAlphaComponent(style.fillAlpha).setFill()
        shape.fill()

        shape.lineWidth = 1.15
        NSColor.white.withAlphaComponent(style.outerRimAlpha).setStroke()
        shape.stroke()

        let inner = NSBezierPath(
            roundedRect: rect.insetBy(dx: 2, dy: 2),
            xRadius: max(0, radius - 2),
            yRadius: max(0, radius - 2)
        )
        inner.lineWidth = 0.9
        NSColor.white.withAlphaComponent(style.innerRimAlpha).setStroke()
        inner.stroke()

        guard prominence != .sheet else { return }

        let darkInner = NSBezierPath(
            roundedRect: rect.insetBy(dx: 3, dy: 3),
            xRadius: max(0, radius - 3),
            yRadius: max(0, radius - 3)
        )
        darkInner.lineWidth = 0.6
        NSColor.black.withAlphaComponent(style.darkRimAlpha).setStroke()
        darkInner.stroke()
    }

    private func drawSpecularStreaks(rect: NSRect, radius: CGFloat, style: Style) {
        guard rect.width > 28, rect.height > 16 else { return }
        guard prominence != .sheet else { return }
        guard style.shineAlpha > 0 else { return }

        let topY = rect.maxY - max(4, min(9, rect.height * 0.18))
        let leftX = rect.minX + max(7, min(radius + 2, rect.width * 0.22))
        let shineSpan = min(rect.width * (prominence == .floating ? 0.55 : 0.34), prominence == .floating ? 150 : 96)
        let rightX = min(rect.maxX - 10, leftX + shineSpan)
        let midX = (leftX + rightX) / 2

        let topShine = NSBezierPath()
        topShine.move(to: NSPoint(x: leftX, y: topY))
        topShine.curve(
            to: NSPoint(x: rightX, y: topY - 0.8),
            controlPoint1: NSPoint(x: midX - shineSpan * 0.28, y: rect.maxY - 2.0),
            controlPoint2: NSPoint(x: midX + shineSpan * 0.28, y: rect.maxY - 2.2)
        )
        topShine.lineCapStyle = .round
        topShine.lineWidth = max(0.9, min(1.9, rect.height * 0.060))
        NSColor.white.withAlphaComponent(style.shineAlpha).setStroke()
        topShine.stroke()

        guard prominence == .floating, rect.height > 24 else { return }

        let lowerCaustic = NSBezierPath()
        lowerCaustic.move(to: NSPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.24))
        lowerCaustic.curve(
            to: NSPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.16),
            controlPoint1: NSPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.10),
            controlPoint2: NSPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.24)
        )
        lowerCaustic.lineCapStyle = .round
        lowerCaustic.lineWidth = 1.15
        NSColor.white.withAlphaComponent(style.shineAlpha * 0.34).setStroke()
        lowerCaustic.stroke()

        guard rect.height > 42 else { return }

        let lowerShade = NSBezierPath()
        lowerShade.move(to: NSPoint(x: rect.minX + 4, y: rect.minY + 3))
        lowerShade.curve(
            to: NSPoint(x: rect.maxX - 4, y: rect.minY + 4),
            controlPoint1: NSPoint(x: rect.minX + rect.width * 0.28, y: rect.minY - 1),
            controlPoint2: NSPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY + 1)
        )
        lowerShade.lineCapStyle = .round
        lowerShade.lineWidth = 1
        NSColor.black.withAlphaComponent(style.darkRimAlpha * 0.58).setStroke()
        lowerShade.stroke()
    }
}
