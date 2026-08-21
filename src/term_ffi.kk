// term_ffi.kk — Koka wrapper for raw terminal I/O C FFI.
// Hand-written (not hica-generated) — used by src/main.hc via:
//   extern import "term_ffi"
//
// Pattern + key-code contract copied from hica-ecosystem's
// programs/myeon/term_raw.kk (same author's prior art for this exact
// problem — raw-mode single-key reads + terminal size query from a
// hica program). Function names match hica's own `effectful-prims`
// list (src/emit/codegen.kk) so effect-annotation inference treats
// calls to them the same way it treats the built-in rawterm ops.
module term_ffi

extern import
  c file "term_ffi_inline.c"

// Read a single key from stdin (raw mode).
// Key codes:
//   printable: ASCII 32-126
//   Enter: 10, Backspace: 127, Tab: 9, Esc: 27
//   Arrow Up: 1001, Down: 1002, Right: 1003, Left: 1004
//   decoded multi-byte UTF-8 input (åäö, etc.): the Unicode codepoint (>=128)
//   read timeout (~200ms, no key pressed): -2
//   error/EOF: -1
pub extern read_key() : io int
  c "hedit_read_key"

// Terminal column count (falls back to 80).
pub extern term_cols() : io int
  c "hedit_term_cols"

// Terminal row count (falls back to 24).
pub extern term_rows() : io int
  c "hedit_term_rows"

// Flush stdout (raw-mode render writes aren't line-buffered).
pub extern flush_stdout() : io ()
  c "hedit_flush_stdout"
