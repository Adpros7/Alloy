//! alloy-text — the rope text buffer engine, exposed over a flat C ABI.
//!
//! Design rules (see README "Rust Engine FFI Boundary"):
//!   * Opaque integer handle IDs, never raw pointers to internal state.
//!   * Edits are batched — one FFI call per keystroke.
//!   * Offsets are UTF-8 *byte* offsets at the boundary; ropey works in chars
//!     internally, so we convert at the edge.
//!   * Returned strings are heap slices the caller must free via `alloy_slice_free`.
//!
//! Everything here is `#[no_mangle] extern "C"` and panic-guarded: the crate is
//! built with `panic = "abort"`, so we defensively bounds-check rather than risk
//! unwinding across the FFI boundary.

use ropey::Rope;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::sync::OnceLock;

/// A heap-allocated byte slice handed back to Swift. The caller owns it and must
/// return it via [`alloy_slice_free`]. `cap` is carried so we can reconstruct the
/// original `Vec` for deallocation.
#[repr(C)]
pub struct AlloySlice {
    pub ptr: *mut u8,
    pub len: usize,
    pub cap: usize,
}

impl AlloySlice {
    fn empty() -> Self {
        AlloySlice { ptr: std::ptr::null_mut(), len: 0, cap: 0 }
    }

    fn from_vec(mut v: Vec<u8>) -> Self {
        v.shrink_to_fit();
        let ptr = v.as_mut_ptr();
        let len = v.len();
        let cap = v.capacity();
        std::mem::forget(v);
        AlloySlice { ptr, len, cap }
    }
}

/// Opaque buffer handle.
pub type AlloyBufferId = u64;

struct Registry {
    buffers: HashMap<AlloyBufferId, Rope>,
    next_id: AtomicU64,
}

fn registry() -> &'static Mutex<Registry> {
    static REG: OnceLock<Mutex<Registry>> = OnceLock::new();
    REG.get_or_init(|| {
        Mutex::new(Registry {
            buffers: HashMap::new(),
            next_id: AtomicU64::new(1),
        })
    })
}

/// Run `f` with the rope for `id`, or return `default` if the handle is unknown
/// or the mutex is poisoned.
fn with_buffer<T>(id: AlloyBufferId, default: T, f: impl FnOnce(&Rope) -> T) -> T {
    let guard = match registry().lock() {
        Ok(g) => g,
        Err(_) => return default,
    };
    match guard.buffers.get(&id) {
        Some(rope) => f(rope),
        None => default,
    }
}

fn with_buffer_mut<T>(id: AlloyBufferId, default: T, f: impl FnOnce(&mut Rope) -> T) -> T {
    let mut guard = match registry().lock() {
        Ok(g) => g,
        Err(_) => return default,
    };
    match guard.buffers.get_mut(&id) {
        Some(rope) => f(rope),
        None => default,
    }
}

/// Create a buffer from initial UTF-8 bytes. Pass `null`/`0` for an empty buffer.
/// Returns 0 on failure.
#[no_mangle]
pub extern "C" fn alloy_buffer_create(bytes: *const u8, len: usize) -> AlloyBufferId {
    let text: String = if bytes.is_null() || len == 0 {
        String::new()
    } else {
        let slice = unsafe { std::slice::from_raw_parts(bytes, len) };
        String::from_utf8_lossy(slice).into_owned()
    };

    let rope = Rope::from_str(&text);

    let mut guard = match registry().lock() {
        Ok(g) => g,
        Err(_) => return 0,
    };
    let id = guard.next_id.fetch_add(1, Ordering::Relaxed);
    guard.buffers.insert(id, rope);
    id
}

/// Destroy a buffer and free its memory.
#[no_mangle]
pub extern "C" fn alloy_buffer_destroy(id: AlloyBufferId) {
    if let Ok(mut guard) = registry().lock() {
        guard.buffers.remove(&id);
    }
}

/// Replace the bytes in `[byte_start, byte_start + old_byte_len)` with `new_bytes`.
/// This is the single hot-path mutation: one call per keystroke / paste / delete.
#[no_mangle]
pub extern "C" fn alloy_buffer_edit(
    id: AlloyBufferId,
    byte_start: usize,
    old_byte_len: usize,
    new_bytes: *const u8,
    new_len: usize,
) {
    let insert: String = if new_bytes.is_null() || new_len == 0 {
        String::new()
    } else {
        let slice = unsafe { std::slice::from_raw_parts(new_bytes, new_len) };
        String::from_utf8_lossy(slice).into_owned()
    };

    with_buffer_mut(id, (), |rope| {
        let total_bytes = rope.len_bytes();
        let start = byte_start.min(total_bytes);
        let end = (byte_start + old_byte_len).min(total_bytes);
        // ropey edits by char index; convert from byte offsets.
        let char_start = rope.byte_to_char(start);
        let char_end = rope.byte_to_char(end);
        if char_end > char_start {
            rope.remove(char_start..char_end);
        }
        if !insert.is_empty() {
            rope.insert(char_start, &insert);
        }
    });
}

/// Total length in UTF-8 bytes.
#[no_mangle]
pub extern "C" fn alloy_buffer_len_bytes(id: AlloyBufferId) -> usize {
    with_buffer(id, 0, |rope| rope.len_bytes())
}

/// Number of lines. A trailing newline yields a final empty line (ropey semantics),
/// matching how editors present a file that ends in `\n`.
#[no_mangle]
pub extern "C" fn alloy_buffer_line_count(id: AlloyBufferId) -> usize {
    with_buffer(id, 0, |rope| rope.len_lines())
}

/// The content of `line_index` *excluding* its trailing line break.
/// Returns an empty slice for out-of-range indices. Caller frees with `alloy_slice_free`.
#[no_mangle]
pub extern "C" fn alloy_buffer_line(id: AlloyBufferId, line_index: usize) -> AlloySlice {
    with_buffer(id, AlloySlice::empty(), |rope| {
        if line_index >= rope.len_lines() {
            return AlloySlice::empty();
        }
        let line = rope.line(line_index);
        let mut s = line.to_string();
        // Strip a single trailing EOL.
        if s.ends_with('\n') {
            s.pop();
            if s.ends_with('\r') {
                s.pop();
            }
        }
        AlloySlice::from_vec(s.into_bytes())
    })
}

/// The byte length of `line_index` excluding its trailing line break.
#[no_mangle]
pub extern "C" fn alloy_buffer_line_len_bytes(id: AlloyBufferId, line_index: usize) -> usize {
    with_buffer(id, 0, |rope| {
        if line_index >= rope.len_lines() {
            return 0;
        }
        let line = rope.line(line_index);
        let s = line.to_string();
        let trimmed = s.trim_end_matches(['\n', '\r']);
        trimmed.len()
    })
}

/// The entire buffer as UTF-8 bytes. Caller frees with `alloy_slice_free`.
#[no_mangle]
pub extern "C" fn alloy_buffer_text(id: AlloyBufferId) -> AlloySlice {
    with_buffer(id, AlloySlice::empty(), |rope| {
        AlloySlice::from_vec(rope.to_string().into_bytes())
    })
}

/// Byte offset of the first character of `line_index`.
#[no_mangle]
pub extern "C" fn alloy_buffer_line_to_byte(id: AlloyBufferId, line_index: usize) -> usize {
    with_buffer(id, 0, |rope| {
        let li = line_index.min(rope.len_lines());
        rope.line_to_byte(li)
    })
}

/// Line index containing `byte_offset`.
#[no_mangle]
pub extern "C" fn alloy_buffer_byte_to_line(id: AlloyBufferId, byte_offset: usize) -> usize {
    with_buffer(id, 0, |rope| {
        let off = byte_offset.min(rope.len_bytes());
        rope.byte_to_line(off)
    })
}

/// Free a slice previously returned by this library.
#[no_mangle]
pub extern "C" fn alloy_slice_free(slice: AlloySlice) {
    if slice.ptr.is_null() || slice.cap == 0 {
        return;
    }
    unsafe {
        // Reconstruct and drop.
        let _ = Vec::from_raw_parts(slice.ptr, slice.len, slice.cap);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(b: &str) -> (*const u8, usize) {
        (b.as_ptr(), b.len())
    }

    #[test]
    fn create_edit_readback() {
        let (p, l) = s("hello\nworld");
        let id = alloy_buffer_create(p, l);
        assert!(id != 0);
        assert_eq!(alloy_buffer_line_count(id), 2);
        assert_eq!(alloy_buffer_len_bytes(id), 11);

        // Insert " brave" after "hello" (byte 5).
        let ins = " brave";
        alloy_buffer_edit(id, 5, 0, ins.as_ptr(), ins.len());

        let line0 = alloy_buffer_line(id, 0);
        let got = unsafe { std::slice::from_raw_parts(line0.ptr, line0.len) };
        assert_eq!(std::str::from_utf8(got).unwrap(), "hello brave");
        alloy_slice_free(line0);

        // Delete " brave" back out (byte 5, length 6).
        alloy_buffer_edit(id, 5, 6, std::ptr::null(), 0);
        let line0 = alloy_buffer_line(id, 0);
        let got = unsafe { std::slice::from_raw_parts(line0.ptr, line0.len) };
        assert_eq!(std::str::from_utf8(got).unwrap(), "hello");
        alloy_slice_free(line0);

        alloy_buffer_destroy(id);
        assert_eq!(alloy_buffer_line_count(id), 0); // gone
    }

    #[test]
    fn unicode_offsets() {
        let (p, l) = s("café\nπ");
        let id = alloy_buffer_create(p, l);
        // "café" is 5 bytes (é = 2 bytes). Line 1 starts after "café\n" = byte 6.
        assert_eq!(alloy_buffer_line_to_byte(id, 1), 6);
        assert_eq!(alloy_buffer_byte_to_line(id, 6), 1);
        alloy_buffer_destroy(id);
    }
}
