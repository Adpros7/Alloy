import AppKit

/// Namespace for @objc action selectors routed from the menu bar and keybindings.
/// Each method walks the responder chain via NSApp.sendAction — the active
/// MainWindowController or EditorViewController handles it.
@objc final class AppCommands: NSObject {

    @objc static func newFile() {
        NSApp.sendAction(#selector(newFile), to: nil, from: nil)
    }

    @objc static func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                // Post to the first window controller that can handle it.
                for window in NSApp.windows {
                    if let wc = window.windowController as? MainWindowController {
                        wc.openFile(url)
                        break
                    }
                }
            }
        }
    }

    @objc static func saveFile() {
        NSApp.sendAction(#selector(saveFile), to: nil, from: nil)
    }

    @objc static func saveFileAs() {
        NSApp.sendAction(#selector(saveFileAs), to: nil, from: nil)
    }

    @objc static func toggleSidebar() {
        NSApp.sendAction(#selector(toggleSidebar), to: nil, from: nil)
    }

    @objc static func toggleTerminal() {
        NSApp.sendAction(#selector(toggleTerminal), to: nil, from: nil)
    }

    @objc static func openCommandPalette() {
        NSApp.sendAction(#selector(openCommandPalette), to: nil, from: nil)
    }

    @objc static func quickOpen() {
        NSApp.sendAction(#selector(quickOpen), to: nil, from: nil)
    }
}
