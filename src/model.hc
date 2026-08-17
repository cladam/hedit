// model.hc — core editor state (pure data + constructors).
//
// This is a deliberately reduced slice of section 3 of docs/hedit-design.md:
// single buffer, single cursor, no panes, no undo stack, no buffer map. We'll
// grow these back in later steps once the minimum shell type-checks and runs.

import "keys"

// A caret position inside a `TextBuffer`.
pub struct Position {
  line: int,
  col: int
}

// One cursor. `cid` is the cursor identifier (avoids clashing with the
// `TextBuffer.id` accessor that Koka generates).
pub struct Cursor {
  cid: int,
  pos: Position
}

// A buffer of text lines plus its cursors and dirty flag.
// `bid` is the buffer identifier (same reason we don't reuse `id`).
// `lines` is a `list<string>` for now; a piece table / rope can slot in later
// without changing this file's public surface.
pub struct TextBuffer {
  bid: int,
  path: maybe<string>,
  lines: list<string>,
  cursors: list<Cursor>,
  is_dirty: bool
}

// ---------------------------------------------------------------------------
// Actions & key bindings (scaffolding for M4 HiLisp remap)
// ---------------------------------------------------------------------------
//
// Every editor operation ultimately reduces to one of these named `Action`s,
// mirroring micro's action model (see
// https://github.com/micro-editor/micro/blob/master/runtime/help/keybindings.md).
// `handle_action` / `event_loop` dispatch *only* on `Action`, never on raw
// keystrokes. That means users can rebind any key to any action via
//
//     (bind "Ctrl-x" 'save)   ; landing in M4
//
// without touching hedit's hica sources.
//
// The `Insert(c)` variant is a small special case: text entry doesn't have
// a fixed name, so `resolve_action` maps every `KChar(c)` to `Insert(c)`
// automatically. `Ignore` is what an unbound chord resolves to — a no-op
// that keeps the editor responsive.
pub type Action {
  Quit,
  Save,
  Insert(c: char),
  Resize(w: int, h: int),
  Copy,
  Paste,
  Ignore
}

// A key chord = a modifier + a printable char. Non-shortcut keys (bare
// KChar) route straight to `Insert`, so bindings only need to cover
// `KShortcut`s (Ctrl-x, Alt-w, …). Special keys (Enter, Backspace, …)
// will grow their own `KeyChord` payload once we need to bind them.
pub struct KeyChord {
  m: Modifier,
  c: char
}

// The user-configurable action map. Keyed by KeyChord so that lookup is
// pure and modifier-aware. Represented as an alist (`list<(KeyChord,
// Action)>`) to match hica's `map_get` / `map_set`; a HAMT can slot in
// later if this ever gets big enough to matter.
//
// hica doesn't (yet) support `pub type Alias = …` aliases, so we spell
// the alist type out at every use site. Small cost, no ambiguity.

// Default keybindings — sourced from micro's defaults (Ctrl-q → quit,
// Ctrl-s → save) but *not* hard-coded into the dispatcher. Every
// binding here is overridable via HiLisp `(bind …)` in M4.
pub fun default_bindings() : list<(KeyChord, Action)> =>
  [
    (KeyChord { m: Ctrl, c: 'q' }, Quit),
    (KeyChord { m: Ctrl, c: 's' }, Save),
    (KeyChord { m: Ctrl, c: 'c' }, Copy),
    (KeyChord { m: Ctrl, c: 'v' }, Paste)
  ]

// Resolve a `KeyChord` against a bindings map. Unbound chords resolve to
// `Ignore`, keeping the loop tail-recursive and side-effect-free for
// unknown input.
pub fun lookup_binding(kb: list<(KeyChord, Action)>, chord: KeyChord) : Action =>
  match map_get(kb, chord) {
    Some(a) => a,
    None    => Ignore
  }

// Config bundle carried through the editor. For now it's just the key
// bindings; M4 grows this with (set …) values like tabsize/theme.
pub struct Config {
  bindings: list<(KeyChord, Action)>
}

pub fun default_config() : Config =>
  Config { bindings: default_bindings() }

// ---------------------------------------------------------------------------
// Editor state
// ---------------------------------------------------------------------------

// Full editor state.  Single-buffer for step 1.
pub struct EditorState {
  buffer: TextBuffer,
  status_message: maybe<string>,
  screen_size: (int, int),
  should_quit: bool,
  config: Config
}

// The pixel-free "screen buffer" the Terminal handler flushes.
// Minimal M1/M2 shape: one string per row. M3+ can upgrade to ScreenCell.
pub struct ScreenBuffer {
  width: int,
  height: int,
  lines: list<string>
}

// Cursor-shape hint forwarded to the Terminal handler.
pub type CursorStyle {
  Block,
  Bar,
  Underscore
}

// --- constructors ---------------------------------------------------------

// A fresh buffer with one empty line and one cursor at (0, 0).
pub fun new_buffer(bid: int, path: maybe<string>) : TextBuffer =>
  TextBuffer {
    bid: bid,
    path: path,
    lines: [""],
    cursors: [Cursor { cid: 0, pos: Position { line: 0, col: 0 } }],
    is_dirty: false
  }

// Initial editor state. `path` is optional — `None` means an unnamed scratch
// buffer. A real file-open step will come with the `fs` effect later.
pub fun init_editor(path: maybe<string>) : EditorState =>
  EditorState {
    buffer: new_buffer(0, path),
    status_message: None,
    screen_size: (80, 24),
    should_quit: false,
    config: default_config()
  }

// --- small pure helpers ---------------------------------------------------

pub fun set_status_message(s: EditorState, msg: string) : EditorState =>
  EditorState { ...s, status_message: Some(msg) }

pub fun clear_status_message(s: EditorState) : EditorState =>
  EditorState { ...s, status_message: None }
