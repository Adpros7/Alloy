import AppKit
import QuartzCore

/// Bottom status bar on Liquid Glass. Git branch on the left; cursor position,
/// indentation, encoding, EOL and language on the right — matching VS Code.
final class StatusBarView: NSView {
    private let panel = GlassPanelView(cornerRadius: 0, clear: true, prominence: .sheet)
    private let branchHoverPill = Glass.pill(cornerRadius: 9, tint: NSColor.white.withAlphaComponent(0.08))
    private var branchHovered = false
    private var trackingArea: NSTrackingArea?

    /// Tapped to show the branch switcher / push / pull menu.
    var onBranchClick: (() -> Void)?

    private let branchButton  = StatusBarView.makeButton("⎇ main")
    private let positionLabel = StatusBarView.makeLabel("Ln 1, Col 1")
    private let indentLabel   = StatusBarView.makeLabel("Spaces: 4")
    private let encodingLabel = StatusBarView.makeLabel("UTF-8")
    private let eolLabel      = StatusBarView.makeLabel("LF")
    private let langLabel     = StatusBarView.makeLabel("Plain Text")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let host = panel.body
        branchHoverPill.translatesAutoresizingMaskIntoConstraints = true
        branchHoverPill.isHidden = true
        branchHoverPill.alphaValue = 0
        host.addSubview(branchHoverPill)

        branchButton.target = self
        branchButton.action = #selector(branchTapped)

        let left = NSStackView(views: [branchButton])
        left.orientation = .horizontal; left.spacing = 12
        left.translatesAutoresizingMaskIntoConstraints = false

        let right = NSStackView(views: [positionLabel, indentLabel, encodingLabel, eolLabel, langLabel])
        right.orientation = .horizontal; right.spacing = 16
        right.translatesAutoresizingMaskIntoConstraints = false

        host.addSubview(left); host.addSubview(right)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 14),
            left.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -14),
            right.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ])
    }

    @objc private func branchTapped() { onBranchClick?() }

    override func layout() {
        super.layout()
        let frame = panel.body.convert(branchButton.bounds, from: branchButton)
        branchHoverPill.frame = frame.insetBy(dx: -8, dy: -3)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = panel.body.convert(event.locationInWindow, from: nil)
        setBranchHovered(panel.body.convert(branchButton.bounds, from: branchButton).insetBy(dx: -8, dy: -5).contains(point))
    }

    override func mouseExited(with event: NSEvent) {
        setBranchHovered(false)
    }

    private func setBranchHovered(_ hovered: Bool) {
        guard branchHovered != hovered else { return }
        branchHovered = hovered
        needsLayout = true
        layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if hovered {
                branchHoverPill.isHidden = false
                branchHoverPill.animator().alphaValue = 1
            } else {
                branchHoverPill.animator().alphaValue = 0
            }
        } completionHandler: { [weak self] in
            if self?.branchHovered == false { self?.branchHoverPill.isHidden = true }
        }
    }

    func setCursor(line: Int, col: Int) { positionLabel.stringValue = "Ln \(line), Col \(col)" }
    func setLanguage(_ id: String) { langLabel.stringValue = Self.pretty(id) }
    func setBranch(_ text: String) {
        branchButton.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: Theme.statusBarForeground,
            .font: Theme.uiFontSmall,
        ])
    }

    private static func pretty(_ id: String) -> String {
        switch id {
        case "plaintext": return "Plain Text"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        case "json": return "JSON"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = Theme.uiFontSmall
        l.textColor = Theme.statusBarForeground
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    /// A borderless button styled to read like the surrounding status text.
    private static func makeButton(_ text: String) -> NSButton {
        let b = NSButton(title: text, target: nil, action: nil)
        b.isBordered = false
        b.bezelStyle = .inline
        b.font = Theme.uiFontSmall
        b.contentTintColor = Theme.statusBarForeground
        b.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: Theme.statusBarForeground,
            .font: Theme.uiFontSmall,
        ])
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }
}
