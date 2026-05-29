import AppKit

/// The resolved set of colors and font used to render one editor viewport.
/// Loaded from a VSCode-format JSON theme file or from the built-in defaults.
struct EditorTheme {

    var font: NSFont
    var lineHeight: CGFloat  // derived from font metrics

    // Structural colors
    var background: NSColor
    var foreground: NSColor
    var lineHighlight: NSColor
    var selection: NSColor
    var cursor: NSColor
    var invisibles: NSColor

    // Gutter
    var gutterBackground: NSColor
    var gutterForeground: NSColor
    var gutterActiveForeground: NSColor

    // Syntax token colors — indexed by HighlightScope raw value
    var tokenColors: [UInt8: NSColor]

    func color(forScope scope: UInt8) -> NSColor {
        tokenColors[scope] ?? foreground
    }

    // MARK: - Built-in themes

    static let oneDark: EditorTheme = {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let metrics = font.ascender + abs(font.descender) + font.leading
        let lineHeight = ceil(metrics * 1.5)

        var tokens: [UInt8: NSColor] = [:]
        tokens[1]  = NSColor(hex: "#C678DD")  // keyword
        tokens[2]  = NSColor(hex: "#C678DD")  // keyword.control
        tokens[3]  = NSColor(hex: "#56B6C2")  // keyword.operator
        tokens[4]  = NSColor(hex: "#98C379")  // string
        tokens[5]  = NSColor(hex: "#E5C07B")  // string.escape
        tokens[6]  = NSColor(hex: "#D19A66")  // number
        tokens[7]  = NSColor(hex: "#7F848E").withAlphaComponent(0.7)  // comment
        tokens[8]  = NSColor(hex: "#7F848E")  // comment.doc
        tokens[9]  = NSColor(hex: "#E5C07B")  // type
        tokens[10] = NSColor(hex: "#E5C07B")  // type.builtin
        tokens[11] = NSColor(hex: "#61AFEF")  // function
        tokens[12] = NSColor(hex: "#61AFEF")  // function.call
        tokens[13] = NSColor(hex: "#56B6C2")  // function.builtin
        tokens[14] = NSColor(hex: "#ABB2BF")  // variable
        tokens[15] = NSColor(hex: "#E06C75")  // variable.builtin (self/this)
        tokens[16] = NSColor(hex: "#E06C75")  // parameter
        tokens[17] = NSColor(hex: "#E06C75")  // property
        tokens[18] = NSColor(hex: "#56B6C2")  // operator
        tokens[19] = NSColor(hex: "#ABB2BF")  // punctuation
        tokens[20] = NSColor(hex: "#D19A66")  // constant
        tokens[21] = NSColor(hex: "#56B6C2")  // constant.builtin

        return EditorTheme(
            font: font,
            lineHeight: lineHeight,
            background: NSColor(hex: "#282C34"),
            foreground: NSColor(hex: "#ABB2BF"),
            lineHighlight: NSColor(white: 1, alpha: 0.04),
            selection: NSColor(hex: "#3E4451"),
            cursor: NSColor(hex: "#528BFF"),
            invisibles: NSColor(genericGamma22White: 1, alpha: 0.15),
            gutterBackground: NSColor(hex: "#21252B"),
            gutterForeground: NSColor(hex: "#636D83"),
            gutterActiveForeground: NSColor(hex: "#ABB2BF"),
            tokenColors: tokens
        )
    }()

    static let light: EditorTheme = {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let metrics = font.ascender + abs(font.descender) + font.leading
        let lineHeight = ceil(metrics * 1.5)

        var tokens: [UInt8: NSColor] = [:]
        tokens[1]  = NSColor(hex: "#0000FF")  // keyword
        tokens[2]  = NSColor(hex: "#AF00DB")  // keyword.control
        tokens[3]  = NSColor(hex: "#000000")  // keyword.operator
        tokens[4]  = NSColor(hex: "#A31515")  // string
        tokens[6]  = NSColor(hex: "#098658")  // number
        tokens[7]  = NSColor(hex: "#008000")  // comment
        tokens[8]  = NSColor(hex: "#008000")  // comment.doc
        tokens[9]  = NSColor(hex: "#267F99")  // type
        tokens[11] = NSColor(hex: "#795E26")  // function
        tokens[12] = NSColor(hex: "#795E26")  // function.call
        tokens[15] = NSColor(hex: "#0070C1")  // variable.builtin
        tokens[16] = NSColor(hex: "#001080")  // parameter
        tokens[17] = NSColor(hex: "#001080")  // property

        return EditorTheme(
            font: font,
            lineHeight: lineHeight,
            background: NSColor(hex: "#FFFFFF"),
            foreground: NSColor(hex: "#000000"),
            lineHighlight: NSColor(genericGamma22White: 0, alpha: 0.04),
            selection: NSColor(hex: "#ADD6FF"),
            cursor: NSColor(hex: "#000000"),
            invisibles: NSColor(genericGamma22White: 0, alpha: 0.2),
            gutterBackground: NSColor(hex: "#F5F5F5"),
            gutterForeground: NSColor(hex: "#237893"),
            gutterActiveForeground: NSColor(hex: "#0B216F"),
            tokenColors: tokens
        )
    }()

    static var current: EditorTheme {
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .oneDark
        }
        return .light
    }
}

// MARK: - NSColor hex init

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let n = UInt64(s, radix: 16) ?? 0
        let r = CGFloat((n >> 16) & 0xFF) / 255
        let g = CGFloat((n >> 8)  & 0xFF) / 255
        let b = CGFloat( n        & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
