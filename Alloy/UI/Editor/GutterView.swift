import AppKit

/// A fixed-width NSView that draws line numbers. It sits to the left of the
/// NSScrollView and mirrors the scroll offset through `scrollOffset`.
final class GutterView: NSView {

    weak var document: Document?
    var theme: EditorTheme = .current { didSet { needsDisplay = true } }
    var scrollOffset: CGFloat = 0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let doc = document else {
            theme.gutterBackground.setFill()
            bounds.fill()
            return
        }

        theme.gutterBackground.setFill()
        bounds.fill()

        // Right-edge separator.
        NSColor(white: 0.5, alpha: 0.15).setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()

        let lh = theme.lineHeight
        let firstVisible = max(0, Int(floor((scrollOffset + dirtyRect.minY) / lh)))
        let lastVisible  = min(doc.buffer.lineCount - 1,
                               Int(ceil((scrollOffset + dirtyRect.maxY) / lh)))

        guard firstVisible <= lastVisible else { return }

        for lineIdx in firstVisible...lastVisible {
            let y = CGFloat(lineIdx) * lh - scrollOffset
            let number = lineIdx + 1
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: theme.font.pointSize - 1, weight: .regular),
                .foregroundColor: theme.gutterForeground
            ]
            let str = "\(number)" as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: bounds.width - size.width - 8, y: y + (lh - size.height) / 2),
                     withAttributes: attrs)
        }
    }
}
