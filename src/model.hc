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
  Undo,
  Redo,
  NewBuffer,
  NextBuffer,
  PrevBuffer,
  CloseBuffer,
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
    (KeyChord { m: Ctrl, c: 'v' }, Paste),
    (KeyChord { m: Ctrl, c: 'z' }, Undo),
    (KeyChord { m: Ctrl, c: 'y' }, Redo),
    (KeyChord { m: Ctrl, c: 'o' }, NewBuffer),
    (KeyChord { m: Ctrl, c: 'n' }, NextBuffer),
    (KeyChord { m: Ctrl, c: 'p' }, PrevBuffer),
    (KeyChord { m: Ctrl, c: 'w' }, CloseBuffer)
  ]

// Resolve a `KeyChord` against a bindings map. Unbound chords resolve to
// `Ignore`, keeping the loop tail-recursive and side-effect-free for
// unknown input.
pub fun lookup_binding(kb: list<(KeyChord, Action)>, chord: KeyChord) : Action =>
  match map_get(kb, chord) {
    Some(a) => a,
    None    => Ignore
  }

// Config bundle carried through the editor. M4 grows this with `(set …)`
// values sourced from HiLisp — kept as `list<(string, string)>` so keys
// and values round-trip through the HiLisp bridge without an extra ADT.
// Booleans/ints are stringified at the boundary; helpers below decode
// them back on the hedit side.
pub struct Config {
  bindings: list<(KeyChord, Action)>,
  values: list<(string, string)>
}

pub fun default_config() : Config =>
  Config { bindings: default_bindings(), values: [] }

// Look up a `(set key value)` value from the config, or `default` if
// absent. Config values are stringly typed at the HiLisp boundary;
// callers use `get_config_int` for numeric settings like `tabsize`.
pub fun get_config(cfg: Config, key: string, default: string) : string =>
  match map_get(cfg.values, key) {
    Some(v) => v,
    None    => default
  }

// Numeric convenience: reads the value under `key`, parses as int, and
// falls back to `default` on missing key or non-numeric content.
// We route through an explicit `parse_or` helper so hica codegen
// doesn't build a `.default(default)` chain (Koka's `default` method
// on maybe conflicts with our `default` parameter name in that call
// position). Named parameter `fallback` sidesteps the clash entirely.
fun parse_or(v: string, fallback: int) : int =>
  match parse_int(v) {
    Some(n) => n,
    None    => fallback
  }

pub fun get_config_int(cfg: Config, key: string, default: int) : int =>
  match map_get(cfg.values, key) {
    Some(v) => parse_or(v, default),
    None    => default
  }

// ---------------------------------------------------------------------------
// Editor state
// ---------------------------------------------------------------------------

// Full editor state. `buffer` is always the *active* buffer — every pure
// helper written before M5.5 (actions.hc, render.hc) keeps working
// unchanged. `background_buffers` holds the other open buffers as a
// rotation ring (see `cycle_next_buffer` / `cycle_prev_buffer` below):
// the active buffer is conceptually always "at the front", so switching
// buffers never needs a separate active-index to stay in sync.
// `next_bid` hands out fresh `TextBuffer.bid`s for `NewBuffer`.
pub struct EditorState {
  buffer: TextBuffer,
  background_buffers: list<TextBuffer>,
  next_bid: int,
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
  init_editor_with_config(path, default_config())

// Same as init_editor but takes a caller-supplied `Config` (typically
// the merger of `default_config()` + the user's HiLisp init.hl, built
// by `src/hilisp_host.hc::load_config`). Kept as a separate constructor
// so `init_editor(None)` stays a one-liner for callers that don't touch
// scripting (all pure tests).
pub fun init_editor_with_config(path: maybe<string>, cfg: Config) : EditorState =>
  EditorState {
    buffer: new_buffer(0, path),
    background_buffers: [],
    next_bid: 1,
    status_message: None,
    screen_size: (80, 24),
    should_quit: false,
    config: cfg
  }

// All currently-open buffers, active buffer first — the order a tabline
// should render them in. Pure, read-only convenience over the ring shape.
pub fun open_buffers(s: EditorState) : list<TextBuffer> =>
  [s.buffer] + s.background_buffers

// --- small pure helpers ---------------------------------------------------

pub fun set_status_message(s: EditorState, msg: string) : EditorState =>
  EditorState { ...s, status_message: Some(msg) }

pub fun clear_status_message(s: EditorState) : EditorState =>
  EditorState { ...s, status_message: None }
