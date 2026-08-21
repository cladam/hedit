// types.hc — user input & event types for hedit.
//
// These mirror section 2.1 of docs/hedit-design.md but without the algebraic
// `effect` blocks (hica has no user-defined effects yet). Once the compiler
// ships effects we'll layer `effect terminal` on top of these types.
//
// Naming: hica requires user-defined types to be PascalCase.

// Modifier keys that can be combined with a base char (Ctrl-s, Alt-x, ...).
pub type Modifier {
  Ctrl,
  Alt,
  Meta,
  Shift
}

// Non-printable keys that don't map to a single `char`.
pub type SpecialKey {
  Enter,
  Backspace,
  Tab,
  Esc,
  ArrowUp,
  ArrowDown,
  ArrowLeft,
  ArrowRight
}

// A single keypress the terminal handler delivers to us.
pub type Key {
  KChar(c: char),
  KSpecial(k: SpecialKey),
  KShortcut(m: Modifier, c: char)
}

// Mouse button / wheel actions.
pub type MouseAction {
  Press,
  Release,
  Drag,
  ScrollUp,
  ScrollDown
}

// Anything the outside world can deliver into the editor's event loop.
pub type Event {
  KeyEvent(k: Key),
  MouseEvent(a: MouseAction, x: int, y: int),
  ResizeEvent(w: int, h: int),
  Tick
}

// M7: decode a raw key code from the native `Terminal` handler
// (`term_ffi.hedit_read_key`'s contract — see src/term_ffi.kk) into an
// `Event`. Kept pure and unit-tested (tests/keys_test.hc) without
// needing a real tty: the C FFI already assembles escape sequences into
// the synthetic 1001-1004 arrow codes, so this is the one seam that
// needs no I/O to test.
pub fun decode_key(code: int) : Event {
  if code == 10 { KeyEvent(KSpecial(Enter)) }
  else if code == 127 { KeyEvent(KSpecial(Backspace)) }
  else if code == 9 { KeyEvent(KSpecial(Tab)) }
  else if code == 27 { KeyEvent(KSpecial(Esc)) }
  else if code == 1001 { KeyEvent(KSpecial(ArrowUp)) }
  else if code == 1002 { KeyEvent(KSpecial(ArrowDown)) }
  else if code == 1003 { KeyEvent(KSpecial(ArrowRight)) }
  else if code == 1004 { KeyEvent(KSpecial(ArrowLeft)) }
  else if code == -1 { KeyEvent(KShortcut(Ctrl, 'q')) } // stdin closed — quit gracefully
  else if code >= 1 && code <= 26 { KeyEvent(KShortcut(Ctrl, chr(code + 96))) }
  else if code >= 32 && code <= 126 { KeyEvent(KChar(chr(code))) }
  else { KeyEvent(KSpecial(Esc)) }
}
