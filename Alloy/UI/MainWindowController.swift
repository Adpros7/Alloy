import AppKit

/// The root window controller. Owns the workspace and lays out:
///   [ActivityBar | Sidebar] [TabBar / EditorView / Terminal]
final class MainWindowController: NSWindowController, NSWindowDelegate, TabBarViewDelegate {

    private let workspace = Workspace()
    private var editorVC: EditorViewController?
    private var tabBarView: TabBarView?
    private var sidebarVisible = true

    private lazy var splitView: NSSplitView = {
        let sv = NSSplitView()
        sv.isVertical = true
        sv.dividerStyle = .thin
        sv.autosaveName = "MainSplit"
        return sv
    }()

    // MARK: - Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.setFrameAutosaveName("AlloyMainWindow")
        self.init(window: window)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
        buildLayout()
        workspace.newUntitledDocument()
        syncEditorToActiveDocument()
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }

        // Outer vertical stack: tab bar on top, editor + terminal below.
        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.spacing = 0
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(outerStack)

        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            outerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Tab bar.
        let tab = TabBarView()
        tab.delegate = self
        tab.tabGroup = workspace.tabGroup
        tab.workspace = workspace
        tab.translatesAutoresizingMaskIntoConstraints = false
        tab.heightAnchor.constraint(equalToConstant: 35).isActive = true
        outerStack.addArrangedSubview(tab)
        tabBarView = tab

        // Main horizontal split: sidebar | editor.
        splitView.translatesAutoresizingMaskIntoConstraints = false
        outerStack.addArrangedSubview(splitView)

        // Sidebar placeholder (Phase 1: empty dark panel).
        let sidebarPlaceholder = NSView()
        sidebarPlaceholder.wantsLayer = true
        sidebarPlaceholder.layer?.backgroundColor = NSColor(hex: "#21252B").cgColor
        sidebarPlaceholder.widthAnchor.constraint(equalToConstant: 240).isActive = true
        splitView.addArrangedSubview(sidebarPlaceholder)

        // Editor area.
        let evc = EditorViewController()
        evc.view.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(evc.view)
        editorVC = evc

        // Status bar.
        let statusBar = buildStatusBar()
        statusBar.heightAnchor.constraint(equalToConstant: 22).isActive = true
        outerStack.addArrangedSubview(statusBar)

        // Apply theme.
        let theme = EditorTheme.current
        editorVC?.theme = theme
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = theme.background.cgColor
    }

    private func buildStatusBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(hex: "#007ACC").cgColor

        let label = NSTextField(labelWithString: "Alloy")
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    // MARK: - Document sync

    private func syncEditorToActiveDocument() {
        editorVC?.document = workspace.activeDocument
        tabBarView?.reload()
    }

    func openFile(_ url: URL) {
        do {
            try workspace.openDocument(at: url)
            syncEditorToActiveDocument()
            window?.title = url.lastPathComponent
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Sidebar / Terminal toggles

    func toggleSidebar() {
        sidebarVisible.toggle()
        if let sv = splitView.arrangedSubviews.first {
            sv.isHidden = !sidebarVisible
        }
    }

    func toggleTerminal() {
        // Terminal panel — Phase 2.
    }

    @objc func openSettings() {
        // Settings window — Phase 1 stub.
        let alert = NSAlert()
        alert.messageText = "Settings"
        alert.informativeText = "Full settings UI is coming in a future phase."
        alert.runModal()
    }

    // MARK: - TabBarViewDelegate

    func tabBarView(_ bar: TabBarView, didSelectTab documentID: DocumentID) {
        workspace.tabGroup.activate(documentID)
        syncEditorToActiveDocument()
    }

    func tabBarView(_ bar: TabBarView, didCloseTab documentID: DocumentID) {
        workspace.closeDocument(documentID)
        if workspace.documents.isEmpty {
            workspace.newUntitledDocument()
        }
        syncEditorToActiveDocument()
    }

    // MARK: - Responder chain actions

    @objc func newFile() {
        workspace.newUntitledDocument()
        syncEditorToActiveDocument()
    }

    @objc func saveFile() {
        if workspace.activeDocument?.fileURL != nil {
            try? workspace.activeDocument?.save()
        } else {
            saveFileAs()
        }
    }

    @objc func saveFileAs() {
        editorVC?.saveFileAs()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let dirty = workspace.documents.values.filter { $0.isDirty }
        guard !dirty.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes?"
        alert.informativeText = "\(dirty.count) document(s) have unsaved changes."
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            dirty.forEach { try? $0.save() }
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}
