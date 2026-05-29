import AppKit

/// Editor tab strip on Liquid Glass. The active tab sits in a glass capsule pill.
final class TabBarView: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?

    private let panel = GlassPanelView(cornerRadius: 0)
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.body.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.body.leadingAnchor),
            stack.topAnchor.constraint(equalTo: panel.body.topAnchor),
            stack.bottomAnchor.constraint(equalTo: panel.body.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setTabs(_ tabs: [(title: String, dirty: Bool)], active: Int) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, tab) in tabs.enumerated() {
            let item = TabItemView(index: i, title: tab.title, dirty: tab.dirty, active: i == active)
            item.onSelect = { [weak self] in self?.onSelect?(i) }
            item.onClose = { [weak self] in self?.onClose?(i) }
            stack.addArrangedSubview(item)
        }
    }
}

/// A single tab: a glass pill (when active) behind a filename + close/dirty button.
final class TabItemView: NSView {
    let index: Int
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    init(index: Int, title: String, dirty: Bool, active: Bool) {
        self.index = index
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        if active {
            let pill = Glass.pill(cornerRadius: 9, tint: NSColor.white.withAlphaComponent(0.10))
            pill.translatesAutoresizingMaskIntoConstraints = false
            addSubview(pill)
            NSLayoutConstraint.activate([
                pill.leadingAnchor.constraint(equalTo: leadingAnchor),
                pill.trailingAnchor.constraint(equalTo: trailingAnchor),
                pill.topAnchor.constraint(equalTo: topAnchor),
                pill.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        let label = NSTextField(labelWithString: title)
        label.font = Theme.uiFont
        label.textColor = active ? Theme.tabActiveForeground : Theme.tabInactiveForeground
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let close = NSButton(title: dirty ? "●" : "✕", target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.font = NSFont.systemFont(ofSize: dirty ? 13 : 10)
        close.contentTintColor = active ? Theme.tabActiveForeground : Theme.tabInactiveForeground
        close.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(close)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onSelect?() }
    @objc private func closeTapped() { onClose?() }
}
