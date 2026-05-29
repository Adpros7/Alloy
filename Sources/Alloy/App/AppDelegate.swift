import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var workbench: WorkbenchViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIcon.image()
        buildMainMenu()

        workbench = WorkbenchViewController()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Alloy"
        // Keep the app on a cohesive black canvas; the glass reads by refracting
        // app content instead of whatever wallpaper happens to be behind it.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = NSColor(hex: 0x050607)
        window.hasShadow = true
        window.styleMask.insert(.fullSizeContentView)
        window.contentViewController = workbench
        // Setting a contentViewController makes the window adopt the view's fitting
        // size; force our intended size and a sane minimum so it doesn't collapse.
        window.minSize = NSSize(width: 860, height: 540)
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()

        NSApp.activate(ignoringOtherApps: true)

        openInitialContent()

        // Optional launch hook (used by dev/tests): ALLOY_PANEL selects an activity
        // panel by index (0 Explorer · 2 Source Control · …).
        if let raw = ProcessInfo.processInfo.environment["ALLOY_PANEL"], let idx = Int(raw) {
            workbench.selectPanel(idx)
        }
    }

    /// `Alloy [path]` — open a file or folder; otherwise open the current directory.
    private func openInitialContent() {
        let fm = FileManager.default
        let pathArg = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }
        guard let pathArg else {
            // From `run.sh`/CLI the working dir is the project; from a Finder /
            // `open` launch it is "/", so fall back to the home folder there.
            let cwd = fm.currentDirectoryPath
            let folder = (cwd == "/") ? NSHomeDirectory() : cwd
            workbench.openFolder(URL(fileURLWithPath: folder))
            workbench.newDocument()
            return
        }
        let url = URL(fileURLWithPath: pathArg).standardizedFileURL
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            workbench.openFolder(url)
            workbench.newDocument()
        } else {
            workbench.openFolder(url.deletingLastPathComponent())
            workbench.openFile(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Menu actions (routed to the workbench)

    @objc func newDocument(_ sender: Any?)   { workbench.newDocument() }
    @objc func openDocument(_ sender: Any?)  { workbench.openDocumentPanel() }
    @objc func openFolder(_ sender: Any?)    { workbench.openFolderPanel() }
    @objc func saveDocument(_ sender: Any?)  { workbench.saveCurrent() }
    @objc func closeTab(_ sender: Any?)      { workbench.closeCurrent() }
    @objc func toggleSidebar(_ sender: Any?) { workbench.toggleSidebar() }
    @objc func toggleTerminal(_ sender: Any?) { workbench.toggleTerminal() }

    // MARK: - Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Alloy", action: nil, keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Alloy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Alloy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        add(fileMenu, "New File", #selector(newDocument(_:)), "n")
        add(fileMenu, "Open…", #selector(openDocument(_:)), "o")
        add(fileMenu, "Open Folder…", #selector(openFolder(_:)), "o", [.command, .shift])
        fileMenu.addItem(.separator())
        add(fileMenu, "Save", #selector(saveDocument(_:)), "s")
        add(fileMenu, "Close Editor", #selector(closeTab(_:)), "w")
        fileItem.submenu = fileMenu

        // Edit menu — standard responder-chain actions (give us undo/cut/copy/paste free).
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        add(editMenu, "Undo", Selector(("undo:")), "z")
        add(editMenu, "Redo", Selector(("redo:")), "z", [.command, .shift])
        editMenu.addItem(.separator())
        add(editMenu, "Cut", #selector(NSText.cut(_:)), "x")
        add(editMenu, "Copy", #selector(NSText.copy(_:)), "c")
        add(editMenu, "Paste", #selector(NSText.paste(_:)), "v")
        add(editMenu, "Select All", #selector(NSText.selectAll(_:)), "a")
        editItem.submenu = editMenu

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        add(viewMenu, "Toggle Sidebar", #selector(toggleSidebar(_:)), "b")
        add(viewMenu, "Toggle Terminal", #selector(toggleTerminal(_:)), "`", [.command])
        viewItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector,
                     _ key: String, _ mods: NSEvent.ModifierFlags = .command) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        menu.addItem(item)
    }
}
