import AppKit
import QuartzCore

/// Readable primary navigation. It uses labels because this is a work tool, not
/// a mystery-meat icon strip.
final class ActivityBarView: NSView {
    var onSelect: ((Int) -> Void)?

    private let panel = GlassPanelView(cornerRadius: 0, clear: true, prominence: .sheet)
    private let stack = NSStackView()
    private var buttons: [NSButton] = []
    private let hoverPill = Glass.pill(cornerRadius: 8, tint: NSColor.white.withAlphaComponent(0.06), prominence: .raised)
    private(set) var selectedIndex = 0
    private var hoveredIndex: Int?
    private var trackingArea: NSTrackingArea?

    private static let items: [(symbol: String, fallback: String, title: String, tip: String)] = [
        ("doc.on.doc", "doc", "Explorer", "Explorer"),
        ("magnifyingglass", "magnifyingglass", "Search", "Search"),
        ("point.3.filled.connected.trianglepath.dotted", "arrow.triangle.branch", "Source Control", "Source Control"),
        ("play.circle", "play", "Run and Debug", "Run and Debug"),
        ("puzzlepiece.extension", "puzzlepiece", "Extensions", "Extensions"),
    ]

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
        hoverPill.translatesAutoresizingMaskIntoConstraints = true
        hoverPill.isHidden = true
        hoverPill.alphaValue = 0
        host.addSubview(hoverPill)   // behind the icons

        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)

        for (i, item) in Self.items.enumerated() {
            let b = makeButton(symbol: item.symbol, fallback: item.fallback, title: item.title, tip: item.tip, tag: i)
            buttons.append(b)
            stack.addArrangedSubview(b)
        }

        let gear = makeButton(symbol: "gearshape", fallback: "gear", title: "Settings", tip: "Settings", tag: -1)
        host.addSubview(gear)

        NSLayoutConstraint.activate([
            // Inset from the top so the window traffic lights have room.
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 38),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8),
            gear.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -12),
            gear.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 8),
            gear.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8),
        ])
        updateSelection(0)
    }

    private func makeButton(symbol: String, fallback: String, title: String, tip: String, tag: Int) -> NSButton {
        let img = Self.symbolImage(named: symbol, fallback: fallback, tip: tip)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        let b = NSButton(title: title, target: self, action: #selector(tapped(_:)))
        b.image = img
        b.tag = tag
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imagePosition = .imageLeading
        b.alignment = .left
        b.font = Theme.uiFont
        b.contentTintColor = Theme.activityBarFg
        b.toolTip = tip
        setTitleColor(for: b, color: Theme.activityBarFg)
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 132),
            b.heightAnchor.constraint(equalToConstant: 34),
        ])
        return b
    }

    @objc private func tapped(_ sender: NSButton) {
        guard sender.tag >= 0 else { return }   // gear → settings (later)
        updateSelection(sender.tag)
        onSelect?(sender.tag)
    }

    /// Programmatically set the highlighted item (without firing `onSelect`).
    func select(_ index: Int) {
        guard index >= 0, index < buttons.count else { return }
        updateSelection(index)
    }

    private func updateSelection(_ index: Int) {
        selectedIndex = index
        refreshButtonColors()
    }

    override func layout() {
        super.layout()
        stack.layoutSubtreeIfNeeded()
        guard let hoveredIndex, hoveredIndex < buttons.count else { return }
        let b = buttons[hoveredIndex]
        let f = panel.body.convert(b.bounds, from: b)
        hoverPill.frame = f.insetBy(dx: 0, dy: 2)
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
        let next = buttons.firstIndex { button in
            panel.body.convert(button.bounds, from: button).contains(point)
        }
        setHoveredIndex(next)
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredIndex(nil)
    }

    private func setHoveredIndex(_ index: Int?) {
        guard hoveredIndex != index else { return }
        hoveredIndex = index
        refreshButtonColors()
        needsLayout = true
        layoutSubtreeIfNeeded()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if index == nil {
                hoverPill.animator().alphaValue = 0
            } else {
                hoverPill.isHidden = false
                hoverPill.animator().alphaValue = 1
            }
        } completionHandler: { [weak self] in
            if self?.hoveredIndex == nil { self?.hoverPill.isHidden = true }
        }
    }

    private func refreshButtonColors() {
        for (i, b) in buttons.enumerated() {
            let active = i == selectedIndex || i == hoveredIndex
            let color = active ? Theme.activityBarActiveFg : Theme.activityBarFg
            b.contentTintColor = color
            setTitleColor(for: b, color: color)
        }
    }

    private func setTitleColor(for button: NSButton, color: NSColor) {
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [
            .foregroundColor: color,
            .font: Theme.uiFont,
        ])
    }

    private static func symbolImage(named symbol: String, fallback: String, tip: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: tip)
    }
}
