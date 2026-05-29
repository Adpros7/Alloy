import AppKit

/// Quiet by default, with a restrained macOS-style hover/selection material.
final class HoverOutlineRowView: NSTableRowView {
    private var hovered = false
    private var trackingAreaRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard hovered || isSelected else { return }

        let rect = bounds.insetBy(dx: 5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)

        NSColor.white.withAlphaComponent(isSelected ? 0.075 : 0.045).setFill()
        path.fill()

        path.lineWidth = 0.8
        NSColor.white.withAlphaComponent(hovered ? 0.085 : 0.060).setStroke()
        path.stroke()
    }
}
