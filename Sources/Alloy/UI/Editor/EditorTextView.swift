import AppKit
import CoreText

/// The text editing surface: a flipped NSView that draws the gutter, the visible
/// lines (CoreText via NSAttributedString), the selection, and a blinking caret.
/// Text storage lives entirely in the Rust rope (`Document.buffer`). Caret and
/// selection anchor are tracked as global UTF-8 byte offsets.
final class EditorTextView: NSView, NSTextInputClient {

    // MARK: Public hooks
    var onCursorChange: ((_ line: Int, _ col: Int) -> Void)?
    var onEdit: (() -> Void)?

    /// Git change markers (0-based line → status), drawn as a colored bar in the
    /// gutter. Set by the editor pane from `GitService.diffLineStatus`.
    var gitDiff: [Int: GitLineStatus] = [:] {
        didSet { needsDisplay = true }
    }

    var document: Document? {
        didSet {
            caret = 0; anchor = 0
            updateFrameSize()
            needsDisplay = true
            notifyCursor()
        }
    }

    // MARK: Caret / selection (global byte offsets)
    private var caret = 0
    private var anchor = 0
    private var selStart: Int { min(caret, anchor) }
    private var selEnd: Int { max(caret, anchor) }
    private var hasSelection: Bool { caret != anchor }

    // MARK: Metrics
    private let font = Theme.editorFont
    private lazy var lineHeight: CGFloat = ceil(NSLayoutManager().defaultLineHeight(for: font)) + 4
    private let gutterGap: CGFloat = 16
    private let textLeftPad: CGFloat = 6
    private var gutterWidth: CGFloat = 48
    private var textOriginX: CGFloat { gutterWidth + textLeftPad }

    private lazy var textAttrs: [NSAttributedString.Key: Any] =
        [.font: font, .foregroundColor: Theme.editorForeground]
    private lazy var gutterAttrs: [NSAttributedString.Key: Any] =
        [.font: font, .foregroundColor: Theme.lineNumber]
    private lazy var gutterActiveAttrs: [NSAttributedString.Key: Any] =
        [.font: font, .foregroundColor: Theme.lineNumberActive]

    // MARK: Caret blink
    private var caretOn = true
    private var blinkTimer: Timer?

    // MARK: Lifecycle
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        startBlink()
        return super.becomeFirstResponder()
    }
    override func resignFirstResponder() -> Bool {
        stopBlink()
        return super.resignFirstResponder()
    }

    private var buffer: TextBuffer? { document?.buffer }

    // MARK: - Sizing

    func updateFrameSize() {
        let lines = buffer?.lineCount ?? 1
        recomputeGutterWidth(lineCount: lines)
        let height = max(CGFloat(lines) * lineHeight + lineHeight,
                         enclosingScrollView?.contentView.bounds.height ?? 0)
        let width = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        setFrameSize(NSSize(width: width, height: height))
    }

    private func recomputeGutterWidth(lineCount: Int) {
        let digits = max(2, String(lineCount).count)
        let sample = String(repeating: "8", count: digits)
        let w = (sample as NSString).size(withAttributes: gutterAttrs).width
        gutterWidth = ceil(w) + gutterGap + 8
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let buffer else { return }

        Theme.editorBackground.setFill()
        dirtyRect.fill()

        let totalLines = buffer.lineCount
        let firstLine = max(0, Int(floor(dirtyRect.minY / lineHeight)))
        let lastLine = min(totalLines - 1, Int(ceil(dirtyRect.maxY / lineHeight)))
        guard firstLine <= lastLine else { return }

        let caretLineIdx = buffer.byteToLine(caret)

        // Current-line highlight (only when there's no active selection).
        if !hasSelection, caretLineIdx >= firstLine, caretLineIdx <= lastLine {
            Theme.currentLine.setFill()
            NSRect(x: gutterWidth, y: CGFloat(caretLineIdx) * lineHeight,
                   width: bounds.width - gutterWidth, height: lineHeight).fill()
        }

        // Gutter background strip.
        Theme.gutterBackground.setFill()
        NSRect(x: 0, y: dirtyRect.minY, width: gutterWidth, height: dirtyRect.height).fill()

        // Git change bars at the right edge of the gutter.
        if !gitDiff.isEmpty {
            let barX = gutterWidth - 4
            for line in firstLine...lastLine {
                guard let status = gitDiff[line] else { continue }
                let y = CGFloat(line) * lineHeight
                switch status {
                case .added:    Theme.gitAdded.setFill()
                case .modified: Theme.gitModified.setFill()
                case .deleted:  Theme.gitDeleted.setFill()
                }
                if status == .deleted {
                    // A small downward wedge at the top of the line marks deleted text.
                    let tri = NSBezierPath()
                    tri.move(to: NSPoint(x: barX + 3, y: y))
                    tri.line(to: NSPoint(x: barX + 3, y: y + 8))
                    tri.line(to: NSPoint(x: barX - 4, y: y))
                    tri.close()
                    tri.fill()
                } else {
                    NSRect(x: barX, y: y, width: 3, height: lineHeight).fill()
                }
            }
        }

        // Selection.
        if hasSelection {
            drawSelection(firstLine: firstLine, lastLine: lastLine, buffer: buffer)
        }

        // Lines + line numbers.
        for line in firstLine...lastLine {
            let y = CGFloat(line) * lineHeight
            let content = buffer.line(line)

            // Line number, right-aligned in the gutter.
            let numStr = "\(line + 1)"
            let attrs = (line == caretLineIdx) ? gutterActiveAttrs : gutterAttrs
            let numWidth = (numStr as NSString).size(withAttributes: attrs).width
            (numStr as NSString).draw(at: NSPoint(x: gutterWidth - gutterGap - numWidth + 8, y: y),
                                      withAttributes: attrs)

            // Line text.
            if !content.isEmpty {
                (content as NSString).draw(at: NSPoint(x: textOriginX, y: y), withAttributes: textAttrs)
            }
        }

        // Caret.
        if caretOn, !hasSelection, window?.firstResponder === self {
            let p = point(forOffset: caret, buffer: buffer)
            Theme.caret.setFill()
            NSRect(x: p.x, y: p.y, width: 2, height: lineHeight).fill()
        }
    }

    private func drawSelection(firstLine: Int, lastLine: Int, buffer: TextBuffer) {
        let startLine = buffer.byteToLine(selStart)
        let endLine = buffer.byteToLine(selEnd)
        Theme.selection.setFill()
        for line in max(firstLine, startLine)...min(lastLine, endLine) where line >= startLine && line <= endLine {
            let lineStart = buffer.lineToByte(line)
            let content = buffer.line(line)
            let lineByteLen = content.utf8.count

            let segStartByte = (line == startLine) ? (selStart - lineStart) : 0
            let segEndByte = (line == endLine) ? (selEnd - lineStart) : lineByteLen

            let x0 = xForColumn(in: content, byteCol: max(0, min(segStartByte, lineByteLen)))
            var x1 = xForColumn(in: content, byteCol: max(0, min(segEndByte, lineByteLen)))
            if line != endLine { x1 += 6 } // hint that the newline is selected
            NSRect(x: x0, y: CGFloat(line) * lineHeight, width: max(2, x1 - x0), height: lineHeight).fill()
        }
    }

    // MARK: - Geometry helpers

    /// X coordinate (view space) for a byte column within a given line's content.
    private func xForColumn(in content: String, byteCol: Int) -> CGFloat {
        guard byteCol > 0 else { return textOriginX }
        let prefixBytes = Array(content.utf8.prefix(byteCol))
        let prefix = String(decoding: prefixBytes, as: UTF8.self)
        let w = (prefix as NSString).size(withAttributes: textAttrs).width
        return textOriginX + w
    }

    private func point(forOffset offset: Int, buffer: TextBuffer) -> NSPoint {
        let line = buffer.byteToLine(offset)
        let lineStart = buffer.lineToByte(line)
        let content = buffer.line(line)
        let byteCol = max(0, min(offset - lineStart, content.utf8.count))
        return NSPoint(x: xForColumn(in: content, byteCol: byteCol), y: CGFloat(line) * lineHeight)
    }

    /// Byte offset nearest a point (used for click / drag).
    private func offset(at p: NSPoint, buffer: TextBuffer) -> Int {
        let totalLines = buffer.lineCount
        let line = max(0, min(totalLines - 1, Int(floor(p.y / lineHeight))))
        let content = buffer.line(line)
        let lineStart = buffer.lineToByte(line)
        let relX = p.x - textOriginX
        if relX <= 0 { return lineStart }

        let attr = NSAttributedString(string: content, attributes: textAttrs)
        let ctLine = CTLineCreateWithAttributedString(attr)
        let u16 = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: relX, y: 0))
        let ns = content as NSString
        let clamped = max(0, min(u16, ns.length))
        let byteCol = ns.substring(to: clamped).lengthOfBytes(using: .utf8)
        return lineStart + byteCol
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let buffer else { return }
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        let off = offset(at: p, buffer: buffer)
        caret = off
        if !event.modifierFlags.contains(.shift) { anchor = off }
        caretOn = true
        needsDisplay = true
        notifyCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let buffer else { return }
        let p = convert(event.locationInWindow, from: nil)
        caret = offset(at: p, buffer: buffer)
        needsDisplay = true
        notifyCursor()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    // MARK: - Editing primitives

    private func replaceSelection(with text: String) {
        guard let buffer else { return }
        let start = selStart
        let len = selEnd - selStart
        buffer.edit(byteStart: start, oldLen: len, newText: text)
        caret = start + text.utf8.count
        anchor = caret
        document?.isDirty = true
        afterEdit()
    }

    private func afterEdit() {
        updateFrameSize()
        needsDisplay = true
        scrollCaretToVisible()
        notifyCursor()
        onEdit?()
    }

    /// UTF-8 length of the scalar immediately before `offset` within the buffer.
    private func scalarLengthBefore(_ offset: Int, buffer: TextBuffer) -> Int {
        guard offset > 0 else { return 0 }
        let line = buffer.byteToLine(offset)
        let lineStart = buffer.lineToByte(line)
        if offset == lineStart { return offset - buffer.lineToByte(max(0, line - 1)) - buffer.line(max(0, line - 1)).utf8.count }
        let content = Array(buffer.line(line).utf8)
        var i = (offset - lineStart) - 1
        while i > 0 && (content[i] & 0xC0) == 0x80 { i -= 1 }
        return (offset - lineStart) - i
    }

    private func scalarLengthAfter(_ offset: Int, buffer: TextBuffer) -> Int {
        let total = buffer.byteCount
        guard offset < total else { return 0 }
        let line = buffer.byteToLine(offset)
        let lineStart = buffer.lineToByte(line)
        let content = Array(buffer.line(line).utf8)
        let col = offset - lineStart
        if col >= content.count { return 1 } // the newline
        var i = col + 1
        while i < content.count && (content[i] & 0xC0) == 0x80 { i += 1 }
        return i - col
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        replaceSelection(with: text)
    }

    override func doCommand(by selector: Selector) {
        guard let buffer else { return }
        let name = NSStringFromSelector(selector)
        switch name {
        case "insertNewline:":
            replaceSelection(with: "\n")
        case "insertTab:":
            replaceSelection(with: "    ")
        case "deleteBackward:":
            if hasSelection { replaceSelection(with: "") }
            else if caret > 0 {
                let n = scalarLengthBefore(caret, buffer: buffer)
                buffer.edit(byteStart: caret - n, oldLen: n, newText: "")
                caret -= n; anchor = caret
                document?.isDirty = true; afterEdit()
            }
        case "deleteForward:":
            if hasSelection { replaceSelection(with: "") }
            else {
                let n = scalarLengthAfter(caret, buffer: buffer)
                if n > 0 { buffer.edit(byteStart: caret, oldLen: n, newText: ""); document?.isDirty = true; afterEdit() }
            }
        case "moveLeft:":
            collapseOrMove(to: hasSelection ? selStart : caret - scalarLengthBefore(caret, buffer: buffer), extend: false)
        case "moveRight:":
            collapseOrMove(to: hasSelection ? selEnd : caret + scalarLengthAfter(caret, buffer: buffer), extend: false)
        case "moveLeftAndModifySelection:":
            collapseOrMove(to: caret - scalarLengthBefore(caret, buffer: buffer), extend: true)
        case "moveRightAndModifySelection:":
            collapseOrMove(to: caret + scalarLengthAfter(caret, buffer: buffer), extend: true)
        case "moveUp:":
            collapseOrMove(to: verticalOffset(from: caret, delta: -1, buffer: buffer), extend: false)
        case "moveDown:":
            collapseOrMove(to: verticalOffset(from: caret, delta: 1, buffer: buffer), extend: false)
        case "moveUpAndModifySelection:":
            collapseOrMove(to: verticalOffset(from: caret, delta: -1, buffer: buffer), extend: true)
        case "moveDownAndModifySelection:":
            collapseOrMove(to: verticalOffset(from: caret, delta: 1, buffer: buffer), extend: true)
        case "moveToBeginningOfLine:", "moveToLeftEndOfLine:":
            collapseOrMove(to: buffer.lineToByte(buffer.byteToLine(caret)), extend: false)
        case "moveToEndOfLine:", "moveToRightEndOfLine:":
            let l = buffer.byteToLine(caret)
            collapseOrMove(to: buffer.lineToByte(l) + buffer.line(l).utf8.count, extend: false)
        default:
            break
        }
    }

    private func collapseOrMove(to offset: Int, extend: Bool) {
        guard let buffer else { return }
        caret = max(0, min(offset, buffer.byteCount))
        if !extend { anchor = caret }
        caretOn = true
        needsDisplay = true
        scrollCaretToVisible()
        notifyCursor()
    }

    private func verticalOffset(from offset: Int, delta: Int, buffer: TextBuffer) -> Int {
        let line = buffer.byteToLine(offset)
        let target = max(0, min(buffer.lineCount - 1, line + delta))
        if target == line { return offset }
        let col = offset - buffer.lineToByte(line)
        let targetContent = buffer.line(target)
        let targetLen = targetContent.utf8.count
        return buffer.lineToByte(target) + min(col, targetLen)
    }

    // Marked text (IME) — minimal: we commit directly. Full composition is a
    // Phase 1 polish item (see README IME risk row).
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: selStart, length: selEnd - selStart) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { 0 }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let buffer, let window else { return .zero }
        let p = self.point(forOffset: caret, buffer: buffer)
        let rectInView = NSRect(x: p.x, y: p.y, width: 1, height: lineHeight)
        let inWindow = convert(rectInView, to: nil)
        return window.convertToScreen(inWindow)
    }

    // MARK: - Standard edit actions (responder chain → Edit menu)

    @objc override func selectAll(_ sender: Any?) {
        guard let buffer else { return }
        anchor = 0; caret = buffer.byteCount
        needsDisplay = true; notifyCursor()
    }

    @objc func copy(_ sender: Any?) {
        guard hasSelection, let text = selectedText() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc func cut(_ sender: Any?) {
        copy(sender)
        if hasSelection { replaceSelection(with: "") }
    }

    @objc func paste(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        replaceSelection(with: s)
    }

    private func selectedText() -> String? {
        guard let buffer, hasSelection else { return nil }
        let all = Array(buffer.text().utf8)
        let lo = max(0, min(selStart, all.count))
        let hi = max(lo, min(selEnd, all.count))
        return String(decoding: all[lo..<hi], as: UTF8.self)
    }

    // MARK: - Misc

    private func scrollCaretToVisible() {
        guard let buffer else { return }
        let p = point(forOffset: caret, buffer: buffer)
        scrollToVisible(NSRect(x: p.x, y: p.y, width: 2, height: lineHeight).insetBy(dx: -40, dy: -2 * lineHeight))
    }

    private func notifyCursor() {
        guard let buffer else { return }
        let line = buffer.byteToLine(caret)
        let lineStart = buffer.lineToByte(line)
        let prefixBytes = Array(buffer.line(line).utf8.prefix(caret - lineStart))
        let col = String(decoding: prefixBytes, as: UTF8.self).count
        onCursorChange?(line + 1, col + 1)
    }

    private func startBlink() {
        stopBlink()
        caretOn = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.caretOn.toggle()
            self.needsDisplay = true
        }
    }

    private func stopBlink() {
        blinkTimer?.invalidate(); blinkTimer = nil
        caretOn = false
        needsDisplay = true
    }
}
