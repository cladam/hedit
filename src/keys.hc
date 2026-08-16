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
