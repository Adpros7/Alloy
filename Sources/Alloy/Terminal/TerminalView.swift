import AppKit

/// Renders a `TerminalGrid` with CoreText and turns key events into the byte
/// sequences a PTY expects. Lives as the document view of an NSScrollView so the
/// scrollback is naturally scrollable.
final class TerminalView: NSView {
    let grid: TerminalGrid

    var onInput: ((Data) -> Void)?
    var onResize: ((_ rows: Int, _ cols: Int) -> Void)?

    // Fonts
    private let baseFont: NSFont
    private let boldFont: NSFont
    private let italicFont: NSFont
    private let cellWidth: CGFloat
    private let cellHeight: CGFloat
    private let leftPad: CGFloat = 6
    private let topPad: CGFloat = 4

    init(grid: TerminalGrid) {
        self.grid = grid
        let f = NSFont(name: "SF Mono", size: 12)
            ?? NSFont(name: "Menlo", size: 12)
            ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        self.baseFont = f
        let fm = NSFontManager.shared
        self.boldFont = fm.convert(f, toHaveTrait: .boldFontMask)
        self.italicFont = fm.convert(f, toHaveTrait: .italicFontMask)
        self.cellWidth = ceil(("M" as NSString).size(withAttributes: [.font: f]).width)
        self.cellHeight = ceil(NSLayoutManager().defaultLineHeight(for: f))
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Geometry

    /// Recompute rows/cols from the visible area; resize grid + notify the PTY.
    func updateGeometry() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let cols = max(1, Int((clip.bounds.width - leftPad) / cellWidth))
        let rows = max(1, Int((clip.bounds.height - topPad) / cellHeight))
        if rows != grid.rows || cols != grid.cols {
            grid.resize(rows: rows, cols: cols)
            onResize?(rows, cols)
        }
        refresh()
    }

    /// Resize the document view to the content and repaint, scrolling to bottom.
    func refresh() {
        let height = max(CGFloat(grid.totalLines) * cellHeight + topPad,
                         enclosingScrollView?.contentView.bounds.height ?? 0)
        let width = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        setFrameSize(NSSize(width: width, height: height))
        needsDisplay = true
        scrollToBottom()
    }

    private func scrollToBottom() {
        guard let scroll = enclosingScrollView else { return }
        let maxY = max(0, bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { updateGeometry() }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        TerminalPalette.defaultBackground.setFill()
        dirtyRect.fill()

        let total = grid.totalLines
        let first = max(0, Int((dirtyRect.minY - topPad) / cellHeight))
        let last = min(total - 1, Int((dirtyRect.maxY - topPad) / cellHeight))
        guard first <= last else { return }

        let focused = (window?.firstResponder === self)
        let cursorLine = grid.cursorRenderLine

        for line in first...last {
            let cells = grid.renderLine(line)
            let y = topPad + CGFloat(line) * cellHeight
            for (c, cell) in cells.enumerated() {
                let x = leftPad + CGFloat(c) * cellWidth
                let isCursor = grid.cursorVisible && line == cursorLine && c == grid.cursorCol

                var fg = cell.fg, bg = cell.bg
                if cell.attrs.contains(.inverse) { swap(&fg, &bg) }
                var fgColor = TerminalPalette.resolve(fg, attrs: cell.attrs, isForeground: true)
                let bgColor = TerminalPalette.resolve(bg, attrs: cell.attrs, isForeground: false)

                let rect = NSRect(x: x, y: y, width: cellWidth, height: cellHeight)
                if isCursor && focused {
                    TerminalPalette.cursor.setFill(); rect.fill()
                    fgColor = TerminalPalette.defaultBackground
                } else if bgColor != TerminalPalette.defaultBackground {
                    bgColor.setFill(); rect.fill()
                }

                if cell.scalar != " " || (isCursor && focused) {
                    let font = cell.attrs.contains(.bold) ? boldFont
                        : (cell.attrs.contains(.italic) ? italicFont : baseFont)
                    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fgColor]
                    if cell.attrs.contains(.underline) { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    (String(cell.scalar) as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                }

                if isCursor && !focused {
                    TerminalPalette.cursor.setStroke()
                    rect.insetBy(dx: 0.5, dy: 0.5).frame()
                }
            }
        }
    }

    // MARK: - Mouse / focus

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    // MARK: - Keyboard → bytes

    override func keyDown(with event: NSEvent) {
        if let data = bytes(for: event) { onInput?(data) }
    }

    @objc func paste(_ sender: Any?) {
        if let s = NSPasteboard.general.string(forType: .string) { onInput?(Data(s.utf8)) }
    }

    private func bytes(for event: NSEvent) -> Data? {
        let flags = event.modifierFlags
        if flags.contains(.command) { return nil }  // let the menu handle ⌘ shortcuts

        guard let raw = event.charactersIgnoringModifiers, let scalar = raw.unicodeScalars.first else {
            return event.characters.map { Data($0.utf8) }
        }
        let appCK = grid.applicationCursorKeys
        func csi(_ s: String) -> Data { Data(("\u{1b}[" + s).utf8) }
        func ss3(_ s: String) -> Data { Data(("\u{1b}O" + s).utf8) }

        switch Int(scalar.value) {
        case 0xF700: return appCK ? ss3("A") : csi("A")   // up
        case 0xF701: return appCK ? ss3("B") : csi("B")   // down
        case 0xF703: return appCK ? ss3("C") : csi("C")   // right
        case 0xF702: return appCK ? ss3("D") : csi("D")   // left
        case 0xF729: return csi("H")                      // home
        case 0xF72B: return csi("F")                      // end
        case 0xF72C: return csi("5~")                     // page up
        case 0xF72D: return csi("6~")                     // page down
        case 0xF728: return csi("3~")                     // forward delete
        default: break
        }

        if flags.contains(.control), scalar.value < 128 {
            let v = scalar.value
            if (0x40...0x5F).contains(v) || (0x61...0x7A).contains(v) {
                return Data([UInt8(v & 0x1F)])            // Ctrl-letter → control code
            }
        }

        switch scalar.value {
        case 0x0D: return Data([0x0D])                    // return
        case 0x09: return Data([0x09])                    // tab
        case 0x1B: return Data([0x1B])                    // esc
        case 0x7F, 0x08: return Data([0x7F])              // delete/backspace
        default: return event.characters.map { Data($0.utf8) }
        }
    }
}
