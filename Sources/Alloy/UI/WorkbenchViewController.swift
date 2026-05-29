import AppKit

/// Top-level workbench layout:
///
///   [ActivityBar | NSSplitView(sidebar | editor) ]
///   [ StatusBar (full width)                      ]
///
/// The sidebar is a vibrant `NSSplitViewItem` (system Liquid Glass material);
/// the activity bar and status bar are behind-window glass panels.
final class WorkbenchViewController: NSViewController {
    private let activityBar = ActivityBarView()
    private let sidebar = SidebarViewController()
    private let editorPane = EditorPaneViewController()
    private let panel = PanelViewController()
    private let statusBar = StatusBarView()

    private var splitVC: NSSplitViewController!
    private var sidebarItem: NSSplitViewItem!
    private var mainArea: NSSplitViewController!
    private var panelItem: NSSplitViewItem!

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        // Main area: a vertical split of editor (top) + collapsible panel (bottom).
        mainArea = NSSplitViewController()
        mainArea.splitView.isVertical = false
        let editorItem = NSSplitViewItem(viewController: editorPane)
        panelItem = NSSplitViewItem(viewController: panel)
        panelItem.canCollapse = true
        panelItem.isCollapsed = true
        panelItem.minimumThickness = 120
        panelItem.preferredThicknessFraction = 0.32
        mainArea.addSplitViewItem(editorItem)
        mainArea.addSplitViewItem(panelItem)
        addChild(mainArea)

        // Outer split: sidebar + main area.
        splitVC = NSSplitViewController()
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 520
        sidebarItem.canCollapse = true
        let mainItem = NSSplitViewItem(viewController: mainArea)
        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(mainItem)
        addChild(splitVC)

        let splitView = splitVC.view
        splitView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(activityBar)
        root.addSubview(splitView)
        root.addSubview(statusBar)

        NSLayoutConstraint.activate([
            // Activity bar: left, from top down to the status bar.
            activityBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            activityBar.topAnchor.constraint(equalTo: root.topAnchor),
            activityBar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            activityBar.widthAnchor.constraint(equalToConstant: 48),

            // Split view: between activity bar and right edge, down to status bar.
            splitView.leadingAnchor.constraint(equalTo: activityBar.trailingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: root.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            // Status bar: full width along the bottom.
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])

        self.view = root
        wireUp()
    }

    private func wireUp() {
        sidebar.onOpenFile = { [weak self] url in self?.editorPane.open(url) }
        editorPane.onCursorChange = { [weak self] line, col in self?.statusBar.setCursor(line: line, col: col) }
        editorPane.onActiveDocumentChange = { [weak self] doc in
            self?.statusBar.setLanguage(doc?.languageId ?? "plaintext")
        }
        activityBar.onSelect = { [weak self] _ in
            // Phase 1: every activity item ensures the sidebar is visible.
            // Switching panel content (Search/SCM/Extensions) comes in later phases.
            guard let self else { return }
            if self.sidebarItem.isCollapsed { self.sidebarItem.animator().isCollapsed = false }
        }
    }

    // MARK: - Commands (called from AppDelegate menu actions)

    func openFolder(_ url: URL) { sidebar.setRoot(url) }
    func newDocument() { editorPane.newDocument() }
    func saveCurrent() { editorPane.saveCurrent() }
    func closeCurrent() { editorPane.closeCurrent() }
    func toggleSidebar() { sidebarItem.animator().isCollapsed.toggle() }

    func toggleTerminal() {
        if panelItem.isCollapsed {
            panel.ensureStarted()
            panelItem.animator().isCollapsed = false
            DispatchQueue.main.async { [weak self] in self?.panel.focusTerminal() }
        } else {
            panelItem.animator().isCollapsed = true
        }
    }

    func openDocumentPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            self?.editorPane.open(url)
        }
    }

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            self?.openFolder(url)
        }
    }
}
