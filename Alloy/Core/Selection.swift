import Foundation

/// A single cursor or selection range in the document, expressed as UTF-8 byte offsets.
struct CursorRange: Equatable {
    /// The anchor end of the selection (where it started).
    var anchor: Int
    /// The active end (where the cursor currently sits).
    var active: Int

    init(at position: Int) {
        anchor = position
        active = position
    }

    init(anchor: Int, active: Int) {
        self.anchor = anchor
        self.active = active
    }

    var isEmpty: Bool { anchor == active }

    /// The lower byte offset of the selection.
    var start: Int { min(anchor, active) }
    /// The upper byte offset (exclusive).
    var end: Int   { max(anchor, active) }

    var range: Range<Int> { start..<end }
}

/// The full selection state for a document — supports multiple cursors.
///
/// Invariants:
///  * Always at least one cursor.
///  * Cursors are sorted by `active` position ascending.
///  * No two cursors overlap.
struct Selection: Equatable {

    private(set) var cursors: [CursorRange]

    static let zero = Selection(cursors: [CursorRange(at: 0)])

    init(cursors: [CursorRange]) {
        precondition(!cursors.isEmpty)
        self.cursors = cursors.sorted { $0.active < $1.active }
    }

    init(at byteOffset: Int) {
        cursors = [CursorRange(at: byteOffset)]
    }

    /// The primary (first) cursor.
    var primary: CursorRange { cursors[0] }

    // MARK: - Mutation helpers

    mutating func moveTo(_ byteOffset: Int) {
        cursors = [CursorRange(at: byteOffset)]
    }

    mutating func extendTo(_ byteOffset: Int) {
        cursors[0].active = byteOffset
    }

    /// Adjust all cursor/anchor positions after an edit at `editStart` that
    /// replaced `deleteCount` bytes with `insertCount` bytes.
    mutating func adjustForEdit(atByte editStart: Int, deleting deleteCount: Int, inserting insertCount: Int) {
        let delta = insertCount - deleteCount
        let editEnd = editStart + deleteCount
        cursors = cursors.map { c in
            var cur = c
            cur.anchor = adjust(cur.anchor, editStart: editStart, editEnd: editEnd, delta: delta)
            cur.active = adjust(cur.active, editStart: editStart, editEnd: editEnd, delta: delta)
            return cur
        }
    }

    private func adjust(_ pos: Int, editStart: Int, editEnd: Int, delta: Int) -> Int {
        if pos <= editStart { return pos }
        if pos < editEnd    { return editStart }
        return pos + delta
    }
}
