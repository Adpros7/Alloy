import AppKit

/// The bottom panel (currently: the integrated terminal). The terminal session is
/// created lazily the first time the panel is revealed.
final class PanelViewController: NSViewController {
    private var session: TerminalSession?
    private let scrollView = NSScrollView()
    private let headerBar = GlassPanelView(cornerRadius: 0)
    private let titleLabel = NSTextField(labelWithString: "TERMINAL")

    override func loadView() {
        let root = NSView()

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = Theme.sidebarHeaderFg
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.body.addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = TerminalPalette.defaultBackground

        root.addSubview(headerBar)
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: root.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: headerBar.body.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.body.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        self.view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        session?.view.updateGeometry()
    }

    /// Spawn the shell the first time the panel becomes visible.
    func ensureStarted() {
        guard session == nil else { return }
        let s = TerminalSession()
        scrollView.documentView = s.view
        s.onExit = { [weak self] in
            // Shell exited — drop the session so a fresh one spawns next time.
            self?.scrollView.documentView = nil
            self?.session = nil
        }
        s.start()
        session = s
        DispatchQueue.main.async { [weak self] in self?.session?.view.updateGeometry() }
    }

    func focusTerminal() {
        if let v = session?.view { view.window?.makeFirstResponder(v) }
    }
}
