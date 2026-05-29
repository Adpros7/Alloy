import AppKit

/// A lazily-loaded node in the file tree.
final class FileNode {
    let url: URL
    let isDirectory: Bool
    private var didLoad = false
    private var cached: [FileNode] = []

    init(url: URL) {
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    var name: String { url.lastPathComponent }

    var children: [FileNode] {
        if !didLoad { load() }
        return cached
    }

    private func load() {
        didLoad = true
        guard isDirectory else { return }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        cached = entries
            .map { FileNode(url: $0) }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory } // dirs first
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }
}

/// The Explorer sidebar: a header plus a file tree (NSOutlineView).
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onOpenFile: ((URL) -> Void)?

    private let headerLabel = NSTextField(labelWithString: "EXPLORER")
    private let outline = NSOutlineView()
    private var root: FileNode?

    override func loadView() {
        let container = NSView()

        headerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = Theme.sidebarHeaderFg
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .init("name"))
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
        outline.indentationPerLevel = 14
        outline.selectionHighlightStyle = .none

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        container.addSubview(headerLabel)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 30),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),

            scroll.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.view = container
    }

    func setRoot(_ url: URL) {
        root = FileNode(url: url)
        headerLabel.stringValue = url.lastPathComponent.uppercased()
        outline.reloadData()
    }

    @objc private func rowClicked() {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? FileNode else { return }
        if node.isDirectory {
            if outline.isItemExpanded(node) { outline.collapseItem(node) }
            else { outline.expandItem(node) }
        } else {
            onOpenFile?(node.url)
        }
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return root?.children.count ?? 0 }
        return (item as? FileNode)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return root!.children[index] }
        return (item as! FileNode).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory ?? false
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        HoverOutlineRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let img = NSImageView()
            img.translatesAutoresizingMaskIntoConstraints = false
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.font = Theme.uiFont
            tf.lineBreakMode = .byTruncatingTail
            c.addSubview(img); c.addSubview(tf)
            c.imageView = img; c.textField = tf
            NSLayoutConstraint.activate([
                img.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                img.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                img.widthAnchor.constraint(equalToConstant: 16),
                img.heightAnchor.constraint(equalToConstant: 16),
                tf.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 5),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()

        cell.textField?.stringValue = node.name
        cell.textField?.textColor = Theme.sidebarForeground
        let symbol = node.isDirectory ? "folder.fill" : "doc.text"
        cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = node.isDirectory ? Theme.tabActiveBorder : Theme.sidebarHeaderFg
        return cell
    }
}
