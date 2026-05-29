import AppKit

/// Liquid Glass building blocks.
///
/// On macOS 26+ these use the real `NSGlassEffectView` — which *refracts* the
/// backdrop (lensing at the edges + specular highlight), exactly like the system
/// Tahoe chrome — not just the Gaussian blur of `NSVisualEffectView`. We make the
/// window non-opaque (see AppDelegate) so this glass genuinely bends the desktop
/// and content behind it. Pre-26 systems fall back to a vibrant material so the
/// app still builds and reads as glass.

/// A glass-backed panel you add content into via `body`. Use `cornerRadius: 0`
/// for full-bleed chrome, or a positive radius for a floating capsule.
final class GlassPanelView: NSView {
    /// Add your subviews here (constrain them to `body`).
    let body = NSView()

    init(cornerRadius: CGFloat = 0, tint: NSColor? = nil, clear: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26.0, *) {
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
    /// A standalone floating glass capsule used as a decorative background (e.g.
    /// the active-tab pill, the activity-bar selection). Returns an empty glass
    /// shape; place your labels/icons as siblings above it.
    static func pill(cornerRadius: CGFloat, tint: NSColor? = nil) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.tintColor = tint
            glass.style = .regular
            glass.translatesAutoresizingMaskIntoConstraints = false
            return glass
        } else {
            let fx = NSVisualEffectView()
            fx.material = .hudWindow
            fx.blendingMode = .withinWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerRadius = cornerRadius
            fx.layer?.masksToBounds = true
            fx.translatesAutoresizingMaskIntoConstraints = false
            return fx
        }
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
