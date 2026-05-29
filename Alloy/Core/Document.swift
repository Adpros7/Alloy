import Foundation
import AppKit

/// The unique identifier for an open document.
typealias DocumentID = UUID

/// `Document` owns a `TextBuffer` and tracks all document-level state: file URL,
/// encoding, EOL style, dirty flag, and the undo stack.
///
/// Marked `@MainActor` because all mutations go through the editor UI — there is
/// no concurrent write path in Phase 1. Background threads (syntax, git) only read.
@MainActor
final class Document: ObservableObject {

    let id: DocumentID = UUID()

    @Published private(set) var fileURL: URL?
    @Published private(set) var isDirty: Bool = false
    @Published private(set) var displayName: String

    let buffer: TextBuffer
    private(set) var encoding: String.Encoding = .utf8
    private(set) var eolStyle: EOLStyle = .lf

    private let undoStack: UndoStack

    // MARK: - Init

    init(fileURL: URL? = nil, contents: String = "", encoding: String.Encoding = .utf8) {
        self.fileURL = fileURL
        self.displayName = fileURL?.lastPathComponent ?? "Untitled"
        self.buffer = TextBuffer(string: contents)
        self.encoding = encoding
        self.eolStyle = EOLStyle.detect(in: contents)
        self.undoStack = UndoStack()
    }

    // MARK: - Reading from disk

    static func open(url: URL) throws -> Document {
        let data = try Data(contentsOf: url)
        // Detect encoding — try UTF-8 first, fall back to macOS Latin-1.
        let (string, encoding): (String, String.Encoding) = {
            if let s = String(data: data, encoding: .utf8) { return (s, .utf8) }
            if let s = String(data: data, encoding: .utf16) { return (s, .utf16) }
            return (String(data: data, encoding: .isoLatin1) ?? "", .isoLatin1)
        }()
        return Document(fileURL: url, contents: string, encoding: encoding)
    }

    // MARK: - Saving to disk

    func save() throws {
        guard let url = fileURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let text = buffer.fullText()
        let data = text.data(using: encoding) ?? text.data(using: .utf8)!
        try data.write(to: url, options: .atomic)
        isDirty = false
    }

    func saveAs(url: URL) throws {
        fileURL = url
        displayName = url.lastPathComponent
        try save()
    }

    // MARK: - Editing (called by EditorView)

    /// Apply a single edit. Records the inverse operation on the undo stack.
    func applyEdit(atByte byteStart: Int, deleting deleteCount: Int, inserting insertText: String) {
        // Capture what we're about to overwrite for the undo record.
        let oldText: String
        if deleteCount > 0 {
            let full = buffer.fullText()
            let startIdx = full.utf8.index(full.utf8.startIndex, offsetBy: byteStart, limitedBy: full.utf8.endIndex) ?? full.utf8.endIndex
            let endIdx   = full.utf8.index(startIdx, offsetBy: deleteCount, limitedBy: full.utf8.endIndex) ?? full.utf8.endIndex
            oldText = String(full.utf8[startIdx..<endIdx]) ?? ""
        } else {
            oldText = ""
        }

        buffer.edit(atByte: byteStart, deleting: deleteCount, inserting: insertText)
        isDirty = true

        undoStack.record(
            undo: UndoOp(byteStart: byteStart, deleteCount: insertText.utf8.count, insertText: oldText),
            redo: UndoOp(byteStart: byteStart, deleteCount: deleteCount, insertText: insertText)
        )
    }

    func undo() {
        guard let op = undoStack.undo() else { return }
        buffer.edit(atByte: op.byteStart, deleting: op.deleteCount, inserting: op.insertText)
        isDirty = true
    }

    func redo() {
        guard let op = undoStack.redo() else { return }
        buffer.edit(atByte: op.byteStart, deleting: op.deleteCount, inserting: op.insertText)
        isDirty = true
    }
}

// MARK: - EOL Style

enum EOLStyle {
    case lf, crlf, cr

    static func detect(in string: String) -> EOLStyle {
        if string.contains("\r\n") { return .crlf }
        if string.contains("\r")   { return .cr }
        return .lf
    }

    var string: String {
        switch self {
        case .lf:   return "\n"
        case .crlf: return "\r\n"
        case .cr:   return "\r"
        }
    }
}
