import AppKit

/// The main editor area: a tab bar above a scrolling editor view. Owns the set of
/// open documents and switches the editor between them.
final class EditorPaneViewController: NSViewController {
    let tabBar = TabBarView()
    let editorView = EditorTextView()
    private let scrollView = NSScrollView()

    private(set) var documents: [Document] = []
    private(set) var current = -1

    var onCursorChange: ((_ line: Int, _ col: Int) -> Void)?
    var onActiveDocumentChange: ((Document?) -> Void)?

    var activeDocument: Document? {
        guard current >= 0, current < documents.count else { return nil }
        return documents[current]
    }

    override func loadView() {
        let root = NSView()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.editorBackground
        scrollView.documentView = editorView

        root.addSubview(tabBar)
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: root.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 36),

            scrollView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        self.view = root

        editorView.onCursorChange = { [weak self] line, col in self?.onCursorChange?(line, col) }
        editorView.onEdit = { [weak self] in self?.refreshTabs() }
        tabBar.onSelect = { [weak self] i in self?.selectTab(i) }
        tabBar.onClose = { [weak self] i in self?.close(index: i) }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        editorView.updateFrameSize()
    }

    // MARK: - Document management

    func newDocument() {
        let doc = Document(untitledWith: "")
        documents.append(doc)
        show(documents.count - 1)
    }

    func open(_ url: URL) {
        if let existing = documents.firstIndex(where: { $0.url == url }) {
            show(existing); return
        }
        do {
            let doc = try Document(url: url)
            documents.append(doc)
            show(documents.count - 1)
        } catch {
            NSSound.beep()
        }
    }

    func saveCurrent() {
        guard let doc = activeDocument else { return }
        if doc.url == nil {
            let panel = NSSavePanel()
            panel.begin { [weak self] resp in
                guard resp == .OK, let url = panel.url else { return }
                try? doc.save(to: url)
                self?.refreshTabs()
            }
        } else {
            try? doc.save()
            refreshTabs()
        }
    }

    func closeCurrent() { if current >= 0 { close(index: current) } }

    private func close(index: Int) {
        guard index >= 0, index < documents.count else { return }
        documents.remove(at: index)
        if documents.isEmpty {
            current = -1
            editorView.document = nil
            onActiveDocumentChange?(nil)
            refreshTabs()
        } else {
            show(min(index, documents.count - 1))
        }
    }

    private func selectTab(_ index: Int) { show(index) }

    private func show(_ index: Int) {
        guard index >= 0, index < documents.count else { return }
        current = index
        let doc = documents[index]
        editorView.document = doc
        view.window?.makeFirstResponder(editorView)
        refreshTabs()
        onActiveDocumentChange?(doc)
    }

    private func refreshTabs() {
        tabBar.setTabs(documents.map { ($0.displayName, $0.isDirty) }, active: current)
    }
}
