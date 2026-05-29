import AppKit

// Programmatic entry point — no storyboard, no Info.plist required to launch from
// the CLI (`swift run`). A proper .app bundle / Info.plist comes with the Xcode
// packaging step in the distribution phase.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
