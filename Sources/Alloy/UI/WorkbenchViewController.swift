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
    private let sidebar = SidebarContainerViewController()
    private let editorPane = EditorPaneViewController()
    private let panel = PanelViewController()
    private let statusBar = StatusBarView()

    /// The repository for the open folder, if any.
    private var git: GitService?
    private let gitQueue = DispatchQueue(label: "com.alloy.workbench.git")

    private var splitVC: NSSplitViewController!
    private var sidebarItem: NSSplitViewItem!
    private var mainArea: NSSplitViewController!
    private var panelItem: NSSplitViewItem!

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.isOpaque = true
        root.layer?.backgroundColor = NSColor(hex: 0x050607).cgColor

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
        sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 220
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
            // Flush, integrated app chrome. Liquid lift happens inside controls,
            // not as a frame jutting around the window edge.
            activityBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            activityBar.topAnchor.constraint(equalTo: root.topAnchor),
            activityBar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            activityBar.widthAnchor.constraint(equalToConstant: 148),

            splitView.leadingAnchor.constraint(equalTo: activityBar.trailingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: root.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 26),
        ])

        self.view = root
        wireUp()
    }

    private func wireUp() {
        sidebar.explorer.onOpenFile = { [weak self] url in self?.editorPane.open(url) }
        sidebar.sourceControl.onOpenFile = { [weak self] url in self?.editorPane.open(url) }
        sidebar.sourceControl.onChanged = { [weak self] in self?.refreshGit() }

        editorPane.onCursorChange = { [weak self] line, col in self?.statusBar.setCursor(line: line, col: col) }
        editorPane.onActiveDocumentChange = { [weak self] doc in
            self?.statusBar.setLanguage(doc?.languageId ?? "plaintext")
        }
        editorPane.onWorkingTreeChange = { [weak self] in self?.refreshGit() }

        statusBar.onBranchClick = { [weak self] in self?.showBranchMenu() }

        activityBar.onSelect = { [weak self] index in
            guard let self else { return }
            self.sidebar.show(index: index)
            if self.sidebarItem.isCollapsed { self.sidebarItem.animator().isCollapsed = false }
            if index == 2 { self.sidebar.sourceControl.refresh() }
        }
    }

    // MARK: - Git

    private func refreshGit() {
        editorPane.refreshGitDecorations()
        sidebar.sourceControl.refresh()
        guard let git else { statusBar.setBranch("⎇ —"); return }
        gitQueue.async { [weak self] in
            let branch = git.branch() ?? "—"
            let ab = git.aheadBehind()
            DispatchQueue.main.async {
                var text = "⎇ \(branch)"
                if let ab, ab.ahead > 0 || ab.behind > 0 { text += "  ↓\(ab.behind) ↑\(ab.ahead)" }
                self?.statusBar.setBranch(text)
            }
        }
    }

    private func showBranchMenu() {
        guard let git else { return }
        gitQueue.async { [weak self] in
            let current = git.branch()
            let branches = git.branches()
            DispatchQueue.main.async {
                guard let self else { return }
                let menu = NSMenu()
                if branches.isEmpty {
                    menu.addItem(NSMenuItem(title: "No branches", action: nil, keyEquivalent: ""))
                }
                for b in branches {
                    let item = NSMenuItem(title: b, action: #selector(self.checkoutBranch(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = b
                    item.state = (b == current) ? .on : .off
                    menu.addItem(item)
                }
                menu.addItem(.separator())
                let pull = NSMenuItem(title: "Pull", action: #selector(self.pullFromMenu), keyEquivalent: "")
                let push = NSMenuItem(title: "Push", action: #selector(self.pushFromMenu), keyEquivalent: "")
                pull.target = self; push.target = self
                menu.addItem(pull); menu.addItem(push)
                menu.popUp(positioning: nil,
                           at: NSPoint(x: 12, y: self.statusBar.bounds.height + 4),
                           in: self.statusBar)
            }
        }
    }

    @objc private func checkoutBranch(_ sender: NSMenuItem) {
        guard let git, let name = sender.representedObject as? String, name != git.branch() else { return }
        gitQueue.async { [weak self] in
            let ok = git.checkout(name)
            DispatchQueue.main.async {
                if !ok { NSSound.beep() }
                self?.refreshGit()
            }
        }
    }

    @objc private func pushFromMenu() { sidebar.sourceControl.performPush() }
    @objc private func pullFromMenu() { sidebar.sourceControl.performPull() }

    // MARK: - Commands (called from AppDelegate menu actions)

    func openFolder(_ url: URL) {
        sidebar.explorer.setRoot(url)
        git = GitService.discover(at: url)
        editorPane.git = git
        sidebar.sourceControl.setRepo(git)
        refreshGit()
    }
    func openFile(_ url: URL) { editorPane.open(url) }
    func newDocument() { editorPane.newDocument() }

    /// Select an activity-bar panel programmatically (e.g. from a launch argument).
    func selectPanel(_ index: Int) {
        activityBar.select(index)
        sidebar.show(index: index)
        if sidebarItem.isCollapsed { sidebarItem.animator().isCollapsed = false }
        if index == 2 { sidebar.sourceControl.refresh() }
    }
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
