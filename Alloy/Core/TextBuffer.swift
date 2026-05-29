import Foundation
import CAlloyEngine

/// Swift wrapper around the Rust rope engine exposed via the C ABI in alloy_text.h.
///
/// `TextBuffer` is the single source of truth for a document's text. All
/// mutations go through `edit(at:deleting:inserting:)` which maps to a single
/// `alloy_buffer_edit` FFI call — O(log n) for any position in the document.
///
/// Indices are always **UTF-8 byte offsets** at the FFI boundary. Swift code
/// that works with `String.Index` or `NSRange` must convert through the helpers
/// provided here.
final class TextBuffer {

    private let id: AlloyBufferId

    /// Create a buffer from a Swift String (UTF-8 encoded).
    init(string: String = "") {
        let bytes = Array(string.utf8)
        id = bytes.withUnsafeBytes { ptr in
            alloy_buffer_create(ptr.baseAddress?.assumingMemoryBound(to: UInt8.self), UInt(ptr.count))
        }
    }

    deinit {
        alloy_buffer_destroy(id)
    }

    // MARK: - Metrics

    var byteCount: Int {
        Int(alloy_buffer_len_bytes(id))
    }

    var lineCount: Int {
        Int(alloy_buffer_line_count(id))
    }

    // MARK: - Line access

    /// Returns the UTF-8 content of `lineIndex` (0-based) without the trailing newline,
    /// or `nil` if out of range.
    func lineString(_ lineIndex: Int) -> String? {
        guard lineIndex >= 0 && lineIndex < lineCount else { return nil }
        let slice = alloy_buffer_line(id, UInt(lineIndex))
        defer { alloy_slice_free(slice) }
        if slice.len == 0 { return "" }
        guard let ptr = slice.ptr else { return "" }
        return String(bytes: UnsafeBufferPointer(start: ptr, count: Int(slice.len)), encoding: .utf8) ?? ""
    }

    /// Byte length of a line, excluding its trailing newline.
    func lineByteLength(_ lineIndex: Int) -> Int {
        Int(alloy_buffer_line_len_bytes(id, UInt(lineIndex)))
    }

    // MARK: - Byte ↔ line conversion

    func byteOffset(forLine lineIndex: Int) -> Int {
        Int(alloy_buffer_line_to_byte(id, UInt(lineIndex)))
    }

    func lineIndex(forByteOffset byteOffset: Int) -> Int {
        Int(alloy_buffer_byte_to_line(id, UInt(byteOffset)))
    }

    // MARK: - Mutation

    /// Core edit primitive. Replaces bytes `[byteStart, byteStart+deleteCount)` with `insertText`.
    /// One FFI call per invocation — safe to call on every keystroke.
    func edit(atByte byteStart: Int, deleting deleteCount: Int, inserting insertText: String) {
        let newBytes = Array(insertText.utf8)
        newBytes.withUnsafeBytes { newPtr in
            alloy_buffer_edit(
                id,
                UInt(byteStart),
                UInt(deleteCount),
                newPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                UInt(newPtr.count)
            )
        }
    }

    // MARK: - Full text access

    /// Returns the entire document as a Swift String. Use sparingly (copies all bytes).
    func fullText() -> String {
        let slice = alloy_buffer_text(id)
        defer { alloy_slice_free(slice) }
        if slice.len == 0 { return "" }
        guard let ptr = slice.ptr else { return "" }
        return String(bytes: UnsafeBufferPointer(start: ptr, count: Int(slice.len)), encoding: .utf8) ?? ""
    }

    // MARK: - NSRange / String.Index helpers

    /// Converts an NSRange (UTF-16 based, from NSString) to a byte range.
    /// Falls back to clamped values on out-of-range input.
    func byteRange(from nsRange: NSRange) -> Range<Int> {
        let fullText = self.fullText()
        guard let range = Range(nsRange, in: fullText) else {
            return 0..<0
        }
        let startByte = fullText.utf8.distance(from: fullText.utf8.startIndex, to: range.lowerBound)
        let endByte   = fullText.utf8.distance(from: fullText.utf8.startIndex, to: range.upperBound)
        return startByte..<endByte
    }
}
