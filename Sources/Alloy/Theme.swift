import AppKit

/// Color + font theme. Phase 1 ships a single built-in "One Dark" theme; later
/// phases load VS Code JSON themes via ThemeLoader (see README).
enum Theme {
    // MARK: Editor
    static let editorBackground   = NSColor(hex: 0x282C34)
    static let editorForeground   = NSColor(hex: 0xABB2BF)
    static let selection          = NSColor(hex: 0x3E4451)
    static let caret              = NSColor(hex: 0x528BFF)
    static let currentLine        = NSColor(hex: 0x2C313A)

    // MARK: Gutter
    static let gutterBackground   = NSColor(hex: 0x282C34)
    static let lineNumber         = NSColor(hex: 0x495162)
    static let lineNumberActive   = NSColor(hex: 0xABB2BF)

    // MARK: Chrome
    static let activityBarBackground = NSColor(hex: 0x333842)
    static let activityBarFg         = NSColor(hex: 0x858B98)
    static let activityBarActiveFg   = NSColor(hex: 0xFFFFFF)
    static let sidebarBackground     = NSColor(hex: 0x21252B)
    static let sidebarForeground     = NSColor(hex: 0xBBBBBB)
    static let sidebarHeaderFg       = NSColor(hex: 0x8A909C)
    static let statusBarBackground   = NSColor(hex: 0x21252B)
    static let statusBarForeground   = NSColor(hex: 0xBBBBBB)
    static let tabBarBackground      = NSColor(hex: 0x21252B)
    static let tabActiveBackground   = NSColor(hex: 0x282C34)
    static let tabInactiveForeground = NSColor(hex: 0x808691)
    static let tabActiveForeground   = NSColor(hex: 0xFFFFFF)
    static let tabActiveBorder       = NSColor(hex: 0x528BFF)
    static let divider               = NSColor(hex: 0x181A1F)

    // MARK: Git / Source Control (VS Code default decoration colors)
    static let gitAdded     = NSColor(hex: 0x587C0C)   // editorGutter.addedBackground
    static let gitModified  = NSColor(hex: 0x0C7D9D)   // editorGutter.modifiedBackground
    static let gitDeleted   = NSColor(hex: 0x94151B)   // editorGutter.deletedBackground
    static let gitAddedFg    = NSColor(hex: 0x81B88B)  // gitDecoration.addedResourceForeground
    static let gitModifiedFg = NSColor(hex: 0xE2C08D)  // gitDecoration.modifiedResourceForeground
    static let gitDeletedFg  = NSColor(hex: 0xC74E39)  // gitDecoration.deletedResourceForeground
    static let gitUntrackedFg = NSColor(hex: 0x73C991) // gitDecoration.untrackedResourceForeground

    // MARK: Fonts
    static let editorFontSize: CGFloat = 13
    static var editorFont: NSFont {
        // Prefer SF Mono; fall back to Menlo which is always present.
        NSFont(name: "SF Mono", size: editorFontSize)
            ?? NSFont(name: "Menlo", size: editorFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }
    static var uiFont: NSFont { NSFont.systemFont(ofSize: 12) }
    static var uiFontSmall: NSFont { NSFont.systemFont(ofSize: 11) }
}

extension NSColor {
    /// Construct from a 0xRRGGBB integer.
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
