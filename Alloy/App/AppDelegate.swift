import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenuBar()
        openNewWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        openNewWindow()
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if let wc = windowController {
            for url in urls { wc.openFile(url) }
        } else {
            openNewWindow(initialURLs: urls)
        }
    }

    // MARK: - Window management

    @discardableResult
    private func openNewWindow(initialURLs: [URL] = []) -> MainWindowController {
        let wc = MainWindowController()
        windowController = wc
        wc.showWindow(nil)
        for url in initialURLs { wc.openFile(url) }
        return wc
    }

    // MARK: - Menu bar

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // Alloy app menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Alloy", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Alloy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Alloy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "New File", action: #selector(AppCommands.newFile), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "Open…", action: #selector(AppCommands.openFile), keyEquivalent: "o"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Save", action: #selector(AppCommands.saveFile), keyEquivalent: "s"))
        let saveAs = NSMenuItem(title: "Save As…", action: #selector(AppCommands.saveFileAs), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Edit menu (standard)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z"))
        (editMenu.items.last!).keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // View menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(NSMenuItem(title: "Toggle Sidebar", action: #selector(AppCommands.toggleSidebar), keyEquivalent: "b"))
        viewMenu.addItem(NSMenuItem(title: "Toggle Terminal", action: #selector(AppCommands.toggleTerminal), keyEquivalent: "`"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(NSMenuItem(title: "Command Palette…", action: #selector(AppCommands.openCommandPalette), keyEquivalent: "P"))
        viewMenu.addItem(NSMenuItem(title: "Go to File…", action: #selector(AppCommands.quickOpen), keyEquivalent: "p"))
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        // Window menu
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "New Window", action: #selector(newWindow), keyEquivalent: "n"))
        (windowMenu.items.last!).keyEquivalentModifierMask = [.command, .shift]
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func newWindow() {
        openNewWindow()
    }
}
