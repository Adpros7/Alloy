import AppKit

final class AlloyApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        // KeyBindingManager gets first crack at every key event.
        if event.type == .keyDown {
            if KeyBindingManager.shared.handleKeyDown(event) { return }
        }
        super.sendEvent(event)
    }
}

@main
struct AlloyEntryPoint {
    static func main() {
        let app = AlloyApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
