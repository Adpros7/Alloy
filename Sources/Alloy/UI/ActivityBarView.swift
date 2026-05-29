import AppKit

/// The thin vertical icon bar on the far left, on real Liquid Glass. The selected
/// item sits in a glass capsule that slides between icons.
final class ActivityBarView: NSView {
    var onSelect: ((Int) -> Void)?

    private let panel = GlassPanelView(cornerRadius: 0)
    private let stack = NSStackView()
    private var buttons: [NSButton] = []
    private let selectionPill = Glass.pill(cornerRadius: 11, tint: NSColor(hex: 0x528BFF).withAlphaComponent(0.22))
    private(set) var selectedIndex = 0

    private static let items: [(symbol: String, tip: String)] = [
        ("doc.on.doc", "Explorer"),
        ("magnifyingglass", "Search"),
        ("arrow.triangle.branch", "Source Control"),
        ("play.circle", "Run and Debug"),
        ("puzzlepiece.extension", "Extensions"),
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
        selectionPill.translatesAutoresizingMaskIntoConstraints = true
        host.addSubview(selectionPill)   // behind the icons

        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)

        for (i, item) in Self.items.enumerated() {
            let b = makeButton(symbol: item.symbol, tip: item.tip, tag: i)
            buttons.append(b)
            stack.addArrangedSubview(b)
        }

        let gear = makeButton(symbol: "gearshape", tip: "Settings", tag: -1)
        host.addSubview(gear)

        NSLayoutConstraint.activate([
            // Inset from the top so the window traffic lights have room.
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 38),
            stack.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            gear.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -12),
            gear.centerXAnchor.constraint(equalTo: host.centerXAnchor),
        ])
        updateSelection(0)
    }

    private func makeButton(symbol: String, tip: String, tag: Int) -> NSButton {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 19, weight: .regular))
        let b = NSButton(image: img ?? NSImage(), target: self, action: #selector(tapped(_:)))
        b.tag = tag
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imagePosition = .imageOnly
        b.contentTintColor = Theme.activityBarFg
        b.toolTip = tip
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 40),
            b.heightAnchor.constraint(equalToConstant: 38),
        ])
        return b
    }

    @objc private func tapped(_ sender: NSButton) {
        guard sender.tag >= 0 else { return }   // gear → settings (later)
        updateSelection(sender.tag)
        onSelect?(sender.tag)
    }

    private func updateSelection(_ index: Int) {
        selectedIndex = index
        for (i, b) in buttons.enumerated() {
            b.contentTintColor = (i == index) ? Theme.activityBarActiveFg : Theme.activityBarFg
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        stack.layoutSubtreeIfNeeded()
        guard selectedIndex < buttons.count else { selectionPill.isHidden = true; return }
        let b = buttons[selectedIndex]
        let f = panel.body.convert(b.bounds, from: b)
        selectionPill.isHidden = false
        selectionPill.frame = f.insetBy(dx: 2, dy: 3)
    }
}
