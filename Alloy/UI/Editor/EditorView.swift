import AppKit
import CoreText

/// The core editor viewport. An NSView subclass that:
///  - Renders only visible lines using CoreText (viewport virtualization)
///  - Handles all text input through NSTextInputClient (IME, dead keys, composition)
///  - Manages scrolling via an NSScrollView parent
///  - Draws syntax highlight tokens as colored CTLine runs
///
/// Performance contract: draw() allocates CTLine objects only for the ~50 lines
/// in the viewport. Everything outside the scroll window is skipped entirely.
final class EditorView: NSView, NSTextInputClient {

    // MARK: - Public state

    weak var document: Document? {
        didSet { fullReload() }
    }

    var theme: EditorTheme = .current {
        didSet {
            updateGeometry()
            needsDisplay = true
        }
    }

    // MARK: - Private state

    private var selection = Selection.zero
    private var _markedRange: NSRange = .init(location: NSNotFound, length: 0)
    private var markedText: String = ""

    // Layout cache — invalidated on any geometry or content change.
    private var lineCount: Int = 0
    private var totalContentHeight: CGFloat = 0
    private var gutterWidth: CGFloat = 48

    // The enclosing scroll view drives our visible rect.
    private var scrollView: NSScrollView? { enclosingScrollView }

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.isOpaque = true
        // Accept first responder so we receive keyDown / mouseDown.
    }

    // MARK: - First responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    // MARK: - Layout

    private func updateGeometry() {
        guard let doc = document else { return }
        lineCount = doc.buffer.lineCount
        let digitCount = max(3, "\(lineCount)".count)
        gutterWidth = CGFloat(digitCount) * theme.font.maximumAdvancement.width + 24
        totalContentHeight = CGFloat(lineCount) * theme.lineHeight + theme.lineHeight
        // Resize self inside the clip view so NSScrollView knows the content extent.
        let visibleWidth = scrollView?.frame.width ?? frame.width
        setFrameSize(NSSize(width: visibleWidth, height: max(totalContentHeight, scrollView?.frame.height ?? 400)))
    }

    private func fullReload() {
        updateGeometry()
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard let doc = document else {
            theme.background.setFill()
            dirtyRect.fill()
            return
        }

        // Fill background.
        theme.background.setFill()
        bounds.fill()

        // Fill gutter background.
        theme.gutterBackground.setFill()
        NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height).fill()

        // Separator between gutter and text.
        NSColor(white: 0.5, alpha: 0.15).setFill()
        NSRect(x: gutterWidth - 1, y: 0, width: 1, height: bounds.height).fill()

        let lh = theme.lineHeight
        let visibleRect = scrollView?.documentVisibleRect ?? bounds
        let firstVisible = max(0, Int(floor(visibleRect.minY / lh)))
        let lastVisible  = min(lineCount - 1, Int(ceil(visibleRect.maxY / lh)))

        guard firstVisible <= lastVisible else { return }

        let textX = gutterWidth + 8

        for lineIdx in firstVisible...lastVisible {
            let y = CGFloat(lineIdx) * lh
            let lineRect = NSRect(x: gutterWidth, y: y, width: bounds.width - gutterWidth, height: lh)

            // Active line highlight.
            if selection.cursors.contains(where: { doc.buffer.lineIndex(forByteOffset: $0.active) == lineIdx }) {
                theme.lineHighlight.setFill()
                lineRect.fill()
            }

            // Draw line text.
            if let lineText = doc.buffer.lineString(lineIdx), !lineText.isEmpty {
                drawLine(lineText, atX: textX, y: y + (lh - theme.font.ascender) / 2 + theme.font.ascender - lh + lh * 0.15, lh: lh, ctx: ctx)
            }

            // Draw line number in gutter.
            drawLineNumber(lineIdx + 1, y: y, lh: lh, isActive: selection.cursors.contains(where: {
                doc.buffer.lineIndex(forByteOffset: $0.active) == lineIdx
            }))
        }

        // Draw cursors.
        drawCursors(firstVisible: firstVisible, lastVisible: lastVisible, doc: doc, lh: lh, textX: textX)
    }

    private func drawLine(_ text: String, atX x: CGFloat, y: CGFloat, lh: CGFloat, ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.font,
            .foregroundColor: theme.foreground
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)

        ctx.saveGState()
        // CoreText draws from baseline upward; NSView coords are bottom-up.
        // We flip the CTM for the line drawing then restore.
        ctx.translateBy(x: x, y: y + theme.font.ascender)
        ctx.scaleBy(x: 1, y: -1)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private func drawLineNumber(_ number: Int, y: CGFloat, lh: CGFloat, isActive: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: theme.font.pointSize - 1, weight: .regular),
            .foregroundColor: isActive ? theme.gutterActiveForeground : theme.gutterForeground
        ]
        let str = "\(number)" as NSString
        let size = str.size(withAttributes: attrs)
        let x = gutterWidth - size.width - 8
        str.draw(at: NSPoint(x: x, y: y + (lh - size.height) / 2), withAttributes: attrs)
    }

    private func drawCursors(firstVisible: Int, lastVisible: Int, doc: Document, lh: CGFloat, textX: CGFloat) {
        guard window?.firstResponder === self else { return }

        for cursor in selection.cursors {
            let line = doc.buffer.lineIndex(forByteOffset: cursor.active)
            guard line >= firstVisible && line <= lastVisible else { continue }

            let lineStartByte = doc.buffer.byteOffset(forLine: line)
            let colByte = cursor.active - lineStartByte
            let lineText = doc.buffer.lineString(line) ?? ""
            let prefix = String(lineText.utf8.prefix(colByte)) ?? ""
            let prefixWidth = (prefix as NSString).size(withAttributes: [.font: theme.font]).width

            let x = textX + prefixWidth
            let y = CGFloat(line) * lh
            let cursorRect = NSRect(x: x, y: y, width: 2, height: lh)
            theme.cursor.setFill()
            cursorRect.fill()
        }
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        guard let doc = document else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let byteOffset = byteOffset(at: loc, doc: doc)
        selection = Selection(at: byteOffset)
        needsDisplay = true
        _ = window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let doc = document else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let byteOffset = byteOffset(at: loc, doc: doc)
        selection.extendTo(byteOffset)
        needsDisplay = true
    }

    private func byteOffset(at point: NSPoint, doc: Document) -> Int {
        let lh = theme.lineHeight
        let lineIdx = max(0, min(Int(point.y / lh), doc.buffer.lineCount - 1))
        let xInText = point.x - gutterWidth - 8
        guard xInText >= 0 else {
            return doc.buffer.byteOffset(forLine: lineIdx)
        }
        let lineText = doc.buffer.lineString(lineIdx) ?? ""
        // Walk UTF-8 code units to find the column that best matches xInText.
        var cumulativeWidth: CGFloat = 0
        var bytePos = doc.buffer.byteOffset(forLine: lineIdx)
        for char in lineText {
            let charStr = String(char)
            let w = (charStr as NSString).size(withAttributes: [.font: theme.font]).width
            if cumulativeWidth + w / 2 > xInText { break }
            cumulativeWidth += w
            bytePos += charStr.utf8.count
        }
        return bytePos
    }

    // MARK: - Keyboard handling (non-IME)

    override func keyDown(with event: NSEvent) {
        // Regular printable input goes through NSTextInputClient / insertText.
        // Special keys are handled here.
        let chars = event.charactersIgnoringModifiers ?? ""
        let mods = event.modifierFlags

        switch chars {
        case "\r", "\n":
            insertText("\n", replacementRange: .init(location: NSNotFound, length: 0))
        case "\u{7F}":  // Backspace
            deleteBackward()
        case String(UnicodeScalar(NSDeleteFunctionKey)!):  // Forward delete
            deleteForward()
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!):
            moveCursor(direction: .left, selecting: mods.contains(.shift), byWord: mods.contains(.option))
        case String(UnicodeScalar(NSRightArrowFunctionKey)!):
            moveCursor(direction: .right, selecting: mods.contains(.shift), byWord: mods.contains(.option))
        case String(UnicodeScalar(NSUpArrowFunctionKey)!):
            moveCursor(direction: .up, selecting: mods.contains(.shift), byWord: false)
        case String(UnicodeScalar(NSDownArrowFunctionKey)!):
            moveCursor(direction: .down, selecting: mods.contains(.shift), byWord: false)
        default:
            // Let NSTextInputClient handle printable characters.
            inputContext?.handleEvent(event)
        }
    }

    private enum MoveDirection { case left, right, up, down }

    private func moveCursor(direction: MoveDirection, selecting: Bool, byWord: Bool) {
        guard let doc = document else { return }
        let buf = doc.buffer
        let cur = selection.primary.active

        let newPos: Int
        switch direction {
        case .left:
            newPos = max(0, cur - 1)
        case .right:
            newPos = min(buf.byteCount, cur + 1)
        case .up:
            let line = buf.lineIndex(forByteOffset: cur)
            if line == 0 { newPos = 0 } else {
                let col = cur - buf.byteOffset(forLine: line)
                let prevLine = line - 1
                let prevLen = buf.lineByteLength(prevLine)
                newPos = buf.byteOffset(forLine: prevLine) + min(col, prevLen)
            }
        case .down:
            let line = buf.lineIndex(forByteOffset: cur)
            if line >= buf.lineCount - 1 { newPos = buf.byteCount } else {
                let col = cur - buf.byteOffset(forLine: line)
                let nextLine = line + 1
                let nextLen = buf.lineByteLength(nextLine)
                newPos = buf.byteOffset(forLine: nextLine) + min(col, nextLen)
            }
        }

        if selecting {
            selection.extendTo(newPos)
        } else {
            selection.moveTo(newPos)
        }
        needsDisplay = true
        scrollCursorToVisible()
    }

    private func deleteBackward() {
        guard let doc = document else { return }
        let cur = selection.primary
        if !cur.isEmpty {
            doc.applyEdit(atByte: cur.start, deleting: cur.end - cur.start, inserting: "")
            selection.adjustForEdit(atByte: cur.start, deleting: cur.end - cur.start, inserting: 0)
            selection.moveTo(cur.start)
        } else if cur.active > 0 {
            // Delete one UTF-8 code point behind the cursor.
            let text = doc.buffer.fullText()
            let byteIdx = text.utf8.index(text.utf8.startIndex, offsetBy: cur.active, limitedBy: text.utf8.endIndex) ?? text.utf8.endIndex
            var start = byteIdx
            if start > text.utf8.startIndex {
                text.utf8.formIndex(before: &start)
                // Walk back to character boundary.
                while start > text.utf8.startIndex && (text.utf8[start] & 0xC0) == 0x80 {
                    text.utf8.formIndex(before: &start)
                }
            }
            let deleteStart = text.utf8.distance(from: text.utf8.startIndex, to: start)
            let deleteCount = cur.active - deleteStart
            doc.applyEdit(atByte: deleteStart, deleting: deleteCount, inserting: "")
            selection.moveTo(deleteStart)
        }
        updateGeometry()
        needsDisplay = true
    }

    private func deleteForward() {
        guard let doc = document else { return }
        let cur = selection.primary
        if !cur.isEmpty {
            doc.applyEdit(atByte: cur.start, deleting: cur.end - cur.start, inserting: "")
            selection.moveTo(cur.start)
        } else if cur.active < doc.buffer.byteCount {
            doc.applyEdit(atByte: cur.active, deleting: 1, inserting: "")
        }
        updateGeometry()
        needsDisplay = true
    }

    private func scrollCursorToVisible() {
        guard let doc = document else { return }
        let line = doc.buffer.lineIndex(forByteOffset: selection.primary.active)
        let lh = theme.lineHeight
        let cursorRect = NSRect(x: 0, y: CGFloat(line) * lh, width: 100, height: lh)
        scrollToVisible(cursorRect)
    }

    // MARK: - NSTextInputClient (IME / dead key composition)

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let doc = document else { return }
        let text: String
        if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else if let s = string as? String {
            text = s
        } else { return }

        markedText = ""
        _markedRange = NSRange(location: NSNotFound, length: 0)

        let cur = selection.primary
        if !cur.isEmpty {
            doc.applyEdit(atByte: cur.start, deleting: cur.end - cur.start, inserting: text)
            selection.adjustForEdit(atByte: cur.start, deleting: cur.end - cur.start, inserting: text.utf8.count)
            selection.moveTo(cur.start + text.utf8.count)
        } else {
            doc.applyEdit(atByte: cur.active, deleting: 0, inserting: text)
            selection.moveTo(cur.active + text.utf8.count)
        }
        updateGeometry()
        needsDisplay = true
        scrollCursorToVisible()
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let s = string as? String { markedText = s }
        else if let a = string as? NSAttributedString { markedText = a.string }
        _markedRange = selectedRange
        needsDisplay = true
    }

    func unmarkText() {
        markedText = ""
        _markedRange = NSRange(location: NSNotFound, length: 0)
        needsDisplay = true
    }

    func selectedRange() -> NSRange {
        let cur = selection.primary
        return NSRange(location: cur.start, length: cur.end - cur.start)
    }

    func markedRange() -> NSRange { _markedRange }

    func hasMarkedText() -> Bool { !markedText.isEmpty }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let doc = document else { return nil }
        let text = doc.buffer.fullText()
        let nsText = text as NSString
        let safeRange = NSRange(location: max(0, range.location), length: min(range.length, nsText.length - range.location))
        guard safeRange.length > 0 else { return nil }
        actualRange?.pointee = safeRange
        return NSAttributedString(string: nsText.substring(with: safeRange), attributes: [.font: theme.font])
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle, .underlineColor, .backgroundColor]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let doc = document else { return .zero }
        let line = doc.buffer.lineIndex(forByteOffset: range.location)
        let y = CGFloat(line) * theme.lineHeight
        let screenRect = window?.convertToScreen(convert(NSRect(x: gutterWidth + 8, y: y, width: 2, height: theme.lineHeight), to: nil)) ?? .zero
        return screenRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        guard let doc = document else { return 0 }
        let local = convert(point, from: nil)
        return byteOffset(at: local, doc: doc)
    }

    // MARK: - Undo / Redo actions

    @objc func undo(_ sender: Any?) {
        document?.undo()
        updateGeometry()
        needsDisplay = true
    }

    @objc func redo(_ sender: Any?) {
        document?.redo()
        updateGeometry()
        needsDisplay = true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(undo(_:)) || aSelector == #selector(redo(_:)) { return true }
        return super.responds(to: aSelector)
    }
}
