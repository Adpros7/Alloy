import AppKit

/// A button whose click is delivered to a closure — convenient for per-row actions
/// in the changes list, where each cell needs its own handler.
final class ClosureButton: NSButton {
    var onClick: (() -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); target = self; action = #selector(fire) }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { onClick?() }
}

/// One collapsible section of the changes list ("Staged Changes" / "Changes").
private final class SCMSection {
    let title: String
    let staged: Bool
    var changes: [GitChange] = []
    init(title: String, staged: Bool) { self.title = title; self.staged = staged }
}

/// The Source Control panel (⌃⇧G): commit box on top, then the staged/unstaged
/// change lists. Mirrors VS Code's SCM view. Uses `GitService` (the git CLI).
final class SourceControlViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    var onOpenFile: ((URL) -> Void)?
    /// Fired after any mutation (stage/commit/discard/push/pull) so the workbench
    /// can refresh the status bar and editor gutter.
    var onChanged: (() -> Void)?

    private(set) var git: GitService?

    private let headerLabel = NSTextField(labelWithString: "SOURCE CONTROL")
    private let commitField = NSTextField()
    private let commitButton = NSButton(title: "Commit", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "No source control providers registered.")
    private let outline = NSOutlineView()

    private let stagedSection = SCMSection(title: "STAGED CHANGES", staged: true)
    private let unstagedSection = SCMSection(title: "CHANGES", staged: false)
    private var sections: [SCMSection] = []

    private let bg = DispatchQueue(label: "com.alloy.scm")

    // MARK: - Setup

    override func loadView() {
        let container = NSView()

        headerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = Theme.sidebarHeaderFg
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        commitField.placeholderString = "Message (⌘↵ to commit)"
        commitField.font = Theme.uiFont
        commitField.translatesAutoresizingMaskIntoConstraints = false
        commitField.bezelStyle = .roundedBezel
        commitField.target = self
        commitField.action = #selector(commitTapped)   // fires on Return

        commitButton.bezelStyle = .rounded
        commitButton.controlSize = .small
        commitButton.target = self
        commitButton.action = #selector(commitTapped)
        commitButton.translatesAutoresizingMaskIntoConstraints = false
        commitButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Commit")
        commitButton.imagePosition = .imageLeading

        let toolbar = makeToolbar()

        emptyLabel.font = Theme.uiFontSmall
        emptyLabel.textColor = Theme.sidebarHeaderFg
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        let column = NSTableColumn(identifier: .init("scm"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowSizeStyle = .small
        outline.backgroundColor = .clear
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(rowClicked)
        outline.focusRingType = .none
        outline.indentationPerLevel = 12
        outline.autoresizesOutlineColumn = false
        outline.selectionHighlightStyle = .none
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        container.addSubview(headerLabel)
        container.addSubview(commitField)
        container.addSubview(commitButton)
        container.addSubview(toolbar)
        container.addSubview(emptyLabel)
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 30),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            commitField.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            commitField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            commitField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            commitButton.topAnchor.constraint(equalTo: commitField.bottomAnchor, constant: 6),
            commitButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            toolbar.centerYAnchor.constraint(equalTo: commitButton.centerYAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            emptyLabel.topAnchor.constraint(equalTo: commitButton.bottomAnchor, constant: 16),
            emptyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: commitButton.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    private func makeToolbar() -> NSView {
        func btn(_ symbol: String, _ tip: String, _ sel: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                             target: self, action: sel)
            b.isBordered = false
            b.bezelStyle = .regularSquare
            b.toolTip = tip
            b.contentTintColor = Theme.sidebarHeaderFg
            return b
        }
        let stack = NSStackView(views: [
            btn("plus", "Stage All Changes", #selector(stageAllTapped)),
            btn("arrow.clockwise", "Refresh", #selector(refreshTapped)),
            btn("arrow.down", "Pull", #selector(pullTapped)),
            btn("arrow.up", "Push", #selector(pushTapped)),
        ])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    // MARK: - Public API

    func setRepo(_ git: GitService?) {
        self.git = git
        refresh()
    }

    /// Recompute status off the main thread, then reload the list.
    func refresh() {
        guard let git else {
            sections = []
            emptyLabel.stringValue = "Open a folder under Git to use Source Control."
            emptyLabel.isHidden = false
            outline.reloadData()
            return
        }
        bg.async { [weak self] in
            let changes = git.status()
            DispatchQueue.main.async {
                guard let self else { return }
                self.stagedSection.changes = changes.filter { $0.isStaged }
                self.unstagedSection.changes = changes.filter { $0.isUnstaged }
                self.sections = [self.stagedSection, self.unstagedSection].filter { !$0.changes.isEmpty }
                let total = self.stagedSection.changes.count + self.unstagedSection.changes.count
                self.emptyLabel.stringValue = "No changes."
                self.emptyLabel.isHidden = total != 0
                self.outline.reloadData()
                self.outline.expandItem(nil, expandChildren: true)
                for s in self.sections { self.outline.expandItem(s) }
            }
        }
    }

    // MARK: - Actions

    @objc private func commitTapped() {
        guard let git else { return }
        let msg = commitField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { NSSound.beep(); return }
        bg.async { [weak self] in
            guard let self else { return }
            // VS Code commits staged changes; if nothing is staged, stage everything.
            if self.stagedSection.changes.isEmpty { git.stageAll() }
            let ok = git.commit(message: msg)
            DispatchQueue.main.async {
                if ok { self.commitField.stringValue = "" } else { NSSound.beep() }
                self.refresh()
                self.onChanged?()
            }
        }
    }

    @objc private func stageAllTapped() { mutate { $0.stageAll() } }
    @objc private func refreshTapped() { refresh() }

    @objc private func pushTapped() { performPush() }
    @objc private func pullTapped() { performPull() }

    func performPush() { remoteOp("Push") { $0.push() } }
    func performPull() { remoteOp("Pull") { $0.pull() } }

    private func remoteOp(_ name: String, _ op: @escaping (GitService) -> (ok: Bool, message: String)) {
        guard let git else { return }
        bg.async { [weak self] in
            let result = op(git)
            DispatchQueue.main.async {
                if !result.ok {
                    let alert = NSAlert()
                    alert.messageText = "\(name) failed"
                    alert.informativeText = result.message.isEmpty ? "git \(name.lowercased()) returned an error." : result.message
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                self?.refresh()
                self?.onChanged?()
            }
        }
    }

    private func mutate(_ op: @escaping (GitService) -> Void) {
        guard let git else { return }
        bg.async { [weak self] in
            op(git)
            DispatchQueue.main.async { self?.refresh(); self?.onChanged?() }
        }
    }

    // MARK: - Row interaction

    @objc private func rowClicked() {
        let row = outline.clickedRow
        guard row >= 0 else { return }
        if let change = outline.item(atRow: row) as? GitChange {
            onOpenFile?(URL(fileURLWithPath: git!.root.appendingPathComponent(change.path).path))
        } else if let section = outline.item(atRow: row) as? SCMSection {
            if outline.isItemExpanded(section) { outline.collapseItem(section) }
            else { outline.expandItem(section) }
        }
    }

    private func toggleStage(_ change: GitChange) {
        mutate { change.isStaged ? $0.unstage(change.path) : $0.stage(change.path) }
    }

    private func discard(_ change: GitChange) {
        let alert = NSAlert()
        alert.messageText = "Discard changes to \(change.path)?"
        alert.informativeText = "This is irreversible."
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        mutate { $0.discard(change.path) }
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return sections.count }
        if let s = item as? SCMSection { return s.changes.count }
        return 0
    }

    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return sections[index] }
        return (item as! SCMSection).changes[index]
    }

    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is SCMSection
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ ov: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        HoverOutlineRowView()
    }

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let section = item as? SCMSection { return sectionView(section) }
        if let change = item as? GitChange { return changeView(change) }
        return nil
    }

    private func sectionView(_ section: SCMSection) -> NSView {
        let row = NSView()
        let label = NSTextField(labelWithString: "\(section.title)  \(section.changes.count)")
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Theme.sidebarHeaderFg
        label.translatesAutoresizingMaskIntoConstraints = false

        let action = ClosureButton()
        action.isBordered = false
        action.bezelStyle = .regularSquare
        action.image = NSImage(systemSymbolName: section.staged ? "minus" : "plus",
                               accessibilityDescription: section.staged ? "Unstage all" : "Stage all")
        action.contentTintColor = Theme.sidebarHeaderFg
        action.toolTip = section.staged ? "Unstage All" : "Stage All"
        action.translatesAutoresizingMaskIntoConstraints = false
        action.onClick = { [weak self] in
            self?.mutate { git in
                if section.staged { for c in section.changes { git.unstage(c.path) } }
                else { git.stageAll() }
            }
        }

        row.addSubview(label); row.addSubview(action)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 2),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            action.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -6),
            action.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            action.widthAnchor.constraint(equalToConstant: 18),
        ])
        return row
    }

    private func changeView(_ change: GitChange) -> NSView {
        let row = NSView()

        let name = (change.path as NSString).lastPathComponent
        let dir  = (change.path as NSString).deletingLastPathComponent

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = Theme.uiFont
        nameLabel.textColor = Self.color(for: change)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let dirLabel = NSTextField(labelWithString: dir)
        dirLabel.font = Theme.uiFontSmall
        dirLabel.textColor = Theme.sidebarHeaderFg
        dirLabel.lineBreakMode = .byTruncatingHead
        dirLabel.translatesAutoresizingMaskIntoConstraints = false
        dirLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)

        let badge = NSTextField(labelWithString: change.badge)
        badge.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        badge.textColor = Self.color(for: change)
        badge.alignment = .center
        badge.translatesAutoresizingMaskIntoConstraints = false

        let stageBtn = ClosureButton()
        stageBtn.isBordered = false
        stageBtn.bezelStyle = .regularSquare
        stageBtn.image = NSImage(systemSymbolName: change.isStaged ? "minus" : "plus",
                                 accessibilityDescription: change.isStaged ? "Unstage" : "Stage")
        stageBtn.contentTintColor = Theme.sidebarForeground
        stageBtn.toolTip = change.isStaged ? "Unstage Changes" : "Stage Changes"
        stageBtn.translatesAutoresizingMaskIntoConstraints = false
        stageBtn.onClick = { [weak self] in self?.toggleStage(change) }

        row.addSubview(nameLabel); row.addSubview(dirLabel)
        row.addSubview(badge); row.addSubview(stageBtn)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 2),
            nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            dirLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            dirLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            dirLabel.trailingAnchor.constraint(lessThanOrEqualTo: stageBtn.leadingAnchor, constant: -6),

            stageBtn.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -2),
            stageBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            stageBtn.widthAnchor.constraint(equalToConstant: 18),

            badge.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            badge.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 12),
        ])
        return row
    }

    // MARK: - Context menu (right-click a change to open / stage / discard)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outline.clickedRow
        guard row >= 0, let change = outline.item(atRow: row) as? GitChange else { return }
        let open = NSMenuItem(title: "Open File", action: #selector(ctxOpen), keyEquivalent: "")
        let stage = NSMenuItem(title: change.isStaged ? "Unstage Changes" : "Stage Changes",
                               action: #selector(ctxStage), keyEquivalent: "")
        let discardItem = NSMenuItem(title: "Discard Changes", action: #selector(ctxDiscard), keyEquivalent: "")
        for it in [open, stage, discardItem] { it.target = self; it.representedObject = change; menu.addItem(it) }
    }

    @objc private func ctxOpen(_ sender: NSMenuItem) {
        guard let change = sender.representedObject as? GitChange, let git else { return }
        onOpenFile?(git.root.appendingPathComponent(change.path))
    }
    @objc private func ctxStage(_ sender: NSMenuItem) {
        guard let change = sender.representedObject as? GitChange else { return }
        toggleStage(change)
    }
    @objc private func ctxDiscard(_ sender: NSMenuItem) {
        guard let change = sender.representedObject as? GitChange else { return }
        discard(change)
    }

    private static func color(for change: GitChange) -> NSColor {
        if change.badge == "U" { return Theme.gitUntrackedFg }
        switch change.badge {
        case "A": return Theme.gitAddedFg
        case "D": return Theme.gitDeletedFg
        case "M", "R", "C": return Theme.gitModifiedFg
        default: return Theme.sidebarForeground
        }
    }
}
