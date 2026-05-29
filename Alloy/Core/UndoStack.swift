import Foundation

struct UndoOp {
    let byteStart: Int
    let deleteCount: Int
    let insertText: String
}

/// A simple linear undo/redo stack. Phase 1 does not coalesce adjacent
/// character insertions; that's a Phase 5 polish item.
final class UndoStack {

    private struct Entry {
        let undo: UndoOp
        let redo: UndoOp
    }

    private var stack: [Entry] = []
    private var head: Int = 0  // index of the next redo entry (i.e. stack[head..] = future)

    func record(undo: UndoOp, redo: UndoOp) {
        // Discard any redo history beyond current position.
        stack.removeSubrange(head...)
        stack.append(Entry(undo: undo, redo: redo))
        head = stack.count
    }

    func undo() -> UndoOp? {
        guard head > 0 else { return nil }
        head -= 1
        return stack[head].undo
    }

    func redo() -> UndoOp? {
        guard head < stack.count else { return nil }
        let op = stack[head].redo
        head += 1
        return op
    }

    var canUndo: Bool { head > 0 }
    var canRedo: Bool { head < stack.count }
}
