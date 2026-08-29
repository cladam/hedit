/// User input & event types for hedit (mirrors section 2.1 of
/// docs/hedit-design.md). These are the plain payload types carried by
/// the `Terminal` effect declared in runtime.hc; kept effect-free here
/// so `decode_key` stays pure and unit-testable without a real tty.

/// A modifier key that can be combined with a base char (Ctrl-s, Alt-x, ...).
pub type Modifier {
  Ctrl,
  Alt,
  Meta,
  Shift
}

/// A non-printable key that doesn't map to a single `char`.
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

/// A single keypress the terminal handler delivers to us.
pub type Key {
  KChar(c: char),
  KSpecial(k: SpecialKey),
  KShortcut(m: Modifier, c: char),
  KCtrlSpecial(k: SpecialKey)
}

/// A mouse button / wheel action.
pub type MouseAction {
  Press,
  Release,
  Drag,
  ScrollUp,
  ScrollDown
}

/// Anything the outside world can deliver into the editor's event loop.
pub type Event {
  KeyEvent(k: Key),
  MouseEvent(a: MouseAction, x: int, y: int),
  ResizeEvent(w: int, h: int),
  Tick
}

/// Decode a raw key code from the native `Terminal` handler
/// (`term_ffi.hedit_read_key`'s contract, see src/term_ffi.kk) into an
/// `Event`.
// The C FFI already assembles escape sequences into synthetic 1001-1004
// arrow codes, decodes multi-byte UTF-8 (åäö etc.) into a single Unicode
// codepoint, and returns -2 on a read timeout (no key pressed — lets
// event_loop re-poll dimensions and redraw periodically without waiting
// on the next keystroke). 1010/1011 are Ctrl-Right/Ctrl-Left (M12 find
// navigation) — the only modifier-parameterised arrows decoded so far.
pub fun decode_key(code: int) : Event {
  if code == 10 { KeyEvent(KSpecial(Enter)) }
  else if code == 127 { KeyEvent(KSpecial(Backspace)) }
  else if code == 9 { KeyEvent(KSpecial(Tab)) }
  else if code == 27 { KeyEvent(KSpecial(Esc)) }
  else if code == 1001 { KeyEvent(KSpecial(ArrowUp)) }
  else if code == 1002 { KeyEvent(KSpecial(ArrowDown)) }
  else if code == 1003 { KeyEvent(KSpecial(ArrowRight)) }
  else if code == 1004 { KeyEvent(KSpecial(ArrowLeft)) }
  else if code == 1010 { KeyEvent(KCtrlSpecial(ArrowRight)) }
  else if code == 1011 { KeyEvent(KCtrlSpecial(ArrowLeft)) }
  else if code == -2 { Tick } // read timeout — no key, just a redraw tick
  else if code == -1 { KeyEvent(KShortcut(Ctrl, 'q')) } // stdin closed — quit gracefully
  else if code >= 1 && code <= 26 { KeyEvent(KShortcut(Ctrl, chr(code + 96))) }
  else if code >= 2032 && code <= 2126 { KeyEvent(KShortcut(Meta, chr(code - 2000))) } // bare ESC + char (Alt/Meta)
  else if code >= 32 && code <= 126 { KeyEvent(KChar(chr(code))) }
  else if code >= 128 { KeyEvent(KChar(chr(code))) } // decoded multi-byte UTF-8 codepoint
  else { KeyEvent(KSpecial(Esc)) }
}
