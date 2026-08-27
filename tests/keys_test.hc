// keys_test.hc — pure tests for `decode_key` (native Terminal handler).
//
// No tty, no FFI — `decode_key` only sees the int codes `term_ffi.read_key`
// contracts to produce (see src/term_ffi.kk / src/term_ffi_inline.c).

import "../src/keys"

test "printable ascii decodes to KChar" {
  assert(decode_key(97) == KeyEvent(KChar('a')))
  assert(decode_key(65) == KeyEvent(KChar('A')))
  assert(decode_key(32) == KeyEvent(KChar(' ')))
}

test "control codes decode to the special keys" {
  assert(decode_key(10) == KeyEvent(KSpecial(Enter)))
  assert(decode_key(127) == KeyEvent(KSpecial(Backspace)))
  assert(decode_key(9) == KeyEvent(KSpecial(Tab)))
  assert(decode_key(27) == KeyEvent(KSpecial(Esc)))
}

test "synthetic arrow codes decode to arrow keys" {
  assert(decode_key(1001) == KeyEvent(KSpecial(ArrowUp)))
  assert(decode_key(1002) == KeyEvent(KSpecial(ArrowDown)))
  assert(decode_key(1003) == KeyEvent(KSpecial(ArrowRight)))
  assert(decode_key(1004) == KeyEvent(KSpecial(ArrowLeft)))
}

test "ctrl range decodes to KShortcut(Ctrl, letter)" {
  assert(decode_key(17) == KeyEvent(KShortcut(Ctrl, 'q')))
  assert(decode_key(1) == KeyEvent(KShortcut(Ctrl, 'a')))
  assert(decode_key(26) == KeyEvent(KShortcut(Ctrl, 'z')))
}

test "eof/error code quits gracefully" {
  assert(decode_key(-1) == KeyEvent(KShortcut(Ctrl, 'q')))
}

test "read timeout produces a Tick, not a key event" {
  assert(decode_key(-2) == Tick)
}

test "decoded multi-byte UTF-8 codepoints decode to KChar (åäö)" {
  assert(decode_key(229) == KeyEvent(KChar('å')))
  assert(decode_key(228) == KeyEvent(KChar('ä')))
  assert(decode_key(246) == KeyEvent(KChar('ö')))
}

test "unrecognised low control code falls back to Esc" {
  assert(decode_key(0) == KeyEvent(KSpecial(Esc)))
}
