import AppKit

/// Embeds EditorView inside an NSScrollView and owns the gutter view.
final class EditorViewController: NSViewController {

    private(set) lazy var scrollView = NSScrollView()
    private(set) lazy var editorView = EditorView()
    private(set) lazy var gutterView = GutterView()

    var document: Document? {
        get { editorView.document }
        set {
            editorView.document = newValue
            gutterView.document = newValue
        }
    }

    var theme: EditorTheme {
        get { editorView.theme }
        set {
            editorView.theme = newValue
            gutterView.theme = newValue
        }
    }

    override func loadView() {
        // Outer container that holds the gutter + scroll view side by side.
        let container = NSView()
        container.wantsLayer = true
        self.view = container

        // Gutter lives at x=0, fixed width.
        gutterView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(gutterView)

        // Scroll view fills the rest.
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = editorView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gutterView.topAnchor.constraint(equalTo: container.topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gutterView.widthAnchor.constraint(equalToConstant: 52),

            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Forward scroll notifications to gutter for synchronized scrolling.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrolled),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )
    }

    @objc private func scrolled() {
        gutterView.scrollOffset = scrollView.documentVisibleRect.origin.y
        gutterView.needsDisplay = true
    }

    // MARK: - Responder chain actions

    @objc func newFile() { /* handled by workspace */ }
    @objc func saveFile() { try? document?.save() }
    @objc func saveFileAs() {
        let panel = NSSavePanel()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            try? self?.document?.saveAs(url: url)
        }
    }
    @objc func toggleSidebar() {
        (parent as? MainWindowController)?.toggleSidebar()
    }
    @objc func toggleTerminal() {
        (parent as? MainWindowController)?.toggleTerminal()
    }
}
