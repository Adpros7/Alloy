import Foundation
import CAlloyEngine

/// Swift-side handle to a Rust rope buffer. All heavy text storage lives in Rust;
/// this is a thin, safe wrapper over the C ABI in `alloy_engine.h`.
///
/// Offsets at this boundary are UTF-8 *byte* offsets, matching the Rust engine.
final class TextBuffer {
    private let id: AlloyBufferId

    init(text: String = "") {
        let bytes = Array(text.utf8)
        self.id = bytes.withUnsafeBufferPointer { buf in
            alloy_buffer_create(buf.baseAddress, UInt(buf.count))
        }
    }

    deinit {
        alloy_buffer_destroy(id)
    }

    // The C ABI uses `uintptr_t` (→ Swift `UInt`) for all sizes/offsets; the rest of
    // the editor works in `Int` (caret offsets, line indices). Convert at this
    // boundary only. All values here are non-negative by construction.
    var lineCount: Int { Int(alloy_buffer_line_count(id)) }
    var byteCount: Int { Int(alloy_buffer_len_bytes(id)) }

    /// Content of `index` excluding its trailing EOL. Empty string if out of range.
    func line(_ index: Int) -> String {
        let slice = alloy_buffer_line(id, UInt(index))
        defer { alloy_slice_free(slice) }
        return Self.string(from: slice)
    }

    /// Byte length of `index` excluding its EOL.
    func lineLengthBytes(_ index: Int) -> Int {
        Int(alloy_buffer_line_len_bytes(id, UInt(index)))
    }

    /// Whole buffer as a String.
    func text() -> String {
        let slice = alloy_buffer_text(id)
        defer { alloy_slice_free(slice) }
        return Self.string(from: slice)
    }

    func lineToByte(_ line: Int) -> Int { Int(alloy_buffer_line_to_byte(id, UInt(line))) }
    func byteToLine(_ byte: Int) -> Int { Int(alloy_buffer_byte_to_line(id, UInt(byte))) }

    /// Replace `[byteStart, byteStart+oldLen)` with `newText`. The single hot path.
    func edit(byteStart: Int, oldLen: Int, newText: String) {
        let bytes = Array(newText.utf8)
        bytes.withUnsafeBufferPointer { buf in
            alloy_buffer_edit(id, UInt(byteStart), UInt(oldLen), buf.baseAddress, UInt(buf.count))
        }
    }

    // MARK: - Helpers

    private static func string(from slice: AlloySlice) -> String {
        guard let ptr = slice.ptr, slice.len > 0 else { return "" }
        let data = Data(bytes: ptr, count: Int(slice.len))
        return String(decoding: data, as: UTF8.self)
    }
}
