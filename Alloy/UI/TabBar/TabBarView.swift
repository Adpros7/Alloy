import AppKit

protocol TabBarViewDelegate: AnyObject {
    func tabBarView(_ bar: TabBarView, didSelectTab documentID: DocumentID)
    func tabBarView(_ bar: TabBarView, didCloseTab documentID: DocumentID)
}

/// A horizontal strip of tab buttons matching VS Code's tab bar aesthetic.
final class TabBarView: NSView {

    weak var delegate: TabBarViewDelegate?
    weak var tabGroup: TabGroup? { didSet { reload() } }
    weak var workspace: Workspace? { didSet { reload() } }

    private var theme: EditorTheme = .current

    private var tabViews: [TabItemView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 35) }

    func reload() {
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews = []

        guard let tabGroup = tabGroup, let workspace = workspace else { return }

        var x: CGFloat = 0
        for docID in tabGroup.tabs {
            let doc = workspace.documents[docID]
            let tv = TabItemView(
                documentID: docID,
                title: doc?.displayName ?? "Untitled",
                isDirty: doc?.isDirty ?? false,
                isActive: docID == tabGroup.activeDocumentID,
                theme: theme
            )
            tv.frame = NSRect(x: x, y: 0, width: tv.intrinsicContentSize.width, height: 35)
            tv.onSelect = { [weak self] id in
                guard let self else { return }
                self.delegate?.tabBarView(self, didSelectTab: id)
            }
            tv.onClose = { [weak self] id in
                guard let self else { return }
                self.delegate?.tabBarView(self, didCloseTab: id)
            }
            addSubview(tv)
            tabViews.append(tv)
            x += tv.frame.width
        }

        layer?.backgroundColor = theme.gutterBackground.cgColor
        needsDisplay = true
    }
}

// MARK: - Individual tab item

private final class TabItemView: NSView {

    let documentID: DocumentID
    var onSelect: ((DocumentID) -> Void)?
    var onClose: ((DocumentID) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var isActive: Bool
    private var isDirty: Bool
    private let theme: EditorTheme

    override var intrinsicContentSize: NSSize {
        let w = max(120, titleLabel.intrinsicContentSize.width + 56)
        return NSSize(width: w, height: 35)
    }

    init(documentID: DocumentID, title: String, isDirty: Bool, isActive: Bool, theme: EditorTheme) {
        self.documentID = documentID
        self.isDirty = isDirty
        self.isActive = isActive
        self.theme = theme
        super.init(frame: .zero)

        wantsLayer = true

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: isActive ? .medium : .regular)
        titleLabel.textColor = isActive ? theme.foreground : theme.gutterForeground
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: isDirty ? "circle.fill" : "xmark", accessibilityDescription: "Close")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = theme.gutterForeground
        closeButton.frame = NSRect(x: 0, y: 0, width: 16, height: 16)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        layer?.backgroundColor = isActive ? theme.background.cgColor : theme.gutterBackground.withAlphaComponent(0.7).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onSelect?(documentID)
    }

    @objc private func closeTapped() {
        onClose?(documentID)
    }
}
