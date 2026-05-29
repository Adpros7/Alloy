/*
 * alloy_engine.h — C ABI for the Alloy Rust engine.
 *
 * This header is the single FFI contract between the Swift app and the Rust
 * engine crates. It is hand-maintained to mirror the `#[no_mangle] extern "C"`
 * signatures in `alloy-engine/crates/*`. (cbindgen can regenerate it later; we
 * keep it by hand for now so the build is hermetic.)
 */

#ifndef ALLOY_ENGINE_H
#define ALLOY_ENGINE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque buffer handle. 0 means "invalid / not found". */
typedef uint64_t AlloyBufferId;

/*
 * A heap-allocated byte slice owned by the caller.
 * Free EVERY non-empty slice with alloy_slice_free(). `cap` is an implementation
 * detail used for deallocation; Swift code only reads `ptr`/`len`.
 */
typedef struct AlloySlice {
    uint8_t *ptr;
    size_t   len;
    size_t   cap;
} AlloySlice;

/* ---- alloy-text: rope buffer ------------------------------------------- */

/* Create a buffer from UTF-8 bytes (pass NULL/0 for empty). Returns 0 on failure. */
AlloyBufferId alloy_buffer_create(const uint8_t *bytes, size_t len);

/* Destroy a buffer and release its memory. */
void alloy_buffer_destroy(AlloyBufferId id);

/* Replace [byte_start, byte_start+old_byte_len) with new_bytes (the hot path). */
void alloy_buffer_edit(AlloyBufferId id,
                       size_t byte_start,
                       size_t old_byte_len,
                       const uint8_t *new_bytes,
                       size_t new_len);

/* Total length in UTF-8 bytes. */
size_t alloy_buffer_len_bytes(AlloyBufferId id);

/* Number of lines (trailing newline yields a final empty line). */
size_t alloy_buffer_line_count(AlloyBufferId id);

/* Content of one line WITHOUT its trailing EOL. Free with alloy_slice_free. */
AlloySlice alloy_buffer_line(AlloyBufferId id, size_t line_index);

/* Byte length of one line excluding its EOL. */
size_t alloy_buffer_line_len_bytes(AlloyBufferId id, size_t line_index);

/* Entire buffer as UTF-8. Free with alloy_slice_free. */
AlloySlice alloy_buffer_text(AlloyBufferId id);

/* Byte offset of the first character of a line. */
size_t alloy_buffer_line_to_byte(AlloyBufferId id, size_t line_index);

/* Line index containing a byte offset. */
size_t alloy_buffer_byte_to_line(AlloyBufferId id, size_t byte_offset);

/* Free a slice previously returned by this library. */
void alloy_slice_free(AlloySlice slice);

#ifdef __cplusplus
}
#endif

#endif /* ALLOY_ENGINE_H */
