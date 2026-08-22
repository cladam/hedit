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
  NewLine,
  DeleteBackward,
  MoveUp,
  MoveDown,
  MoveLeft,
  MoveRight,
  Resize(w: int, h: int),
  Copy,
  Paste,
  Undo,
  Redo,
  NewBuffer,
  NextBuffer,
  PrevBuffer,
  CloseBuffer,
  OpenFile,
  PromptChar(c: char),
  PromptBackspace,
  PromptSubmit,
  PromptCancel,
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
    (KeyChord { m: Ctrl, c: 'w' }, CloseBuffer),
    (KeyChord { m: Ctrl, c: 'e' }, OpenFile)
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
// `readonly` (M8) gates the `Save` action in `runtime.hc::save_buffer`
// — it's a plain struct field rather than a `values` entry because
// it's only ever set from `--readonly` on the CLI, never from HiLisp.
pub struct Config {
  bindings: list<(KeyChord, Action)>,
  values: list<(string, string)>,
  readonly: bool
}

pub fun default_config() : Config =>
  Config { bindings: default_bindings(), values: [], readonly: false }

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

// Set (or override) a single `(key, value)` entry — used by `--tabsize`
// (main.hc, M8) to apply a CLI override after `init.hl` has already run,
// matching micro's session-override precedence (CLI wins over config).
pub fun set_config_value(cfg: Config, key: string, value: string) : Config =>
  Config { ...cfg, values: map_set(cfg.values, key, value) }

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
  config: Config,
  prompt: Prompt
}

// The pixel-free "screen buffer" the Terminal handler flushes.
// Minimal M1/M2 shape: one string per row. M3+ can upgrade to ScreenCell.
// `cursor_row`/`cursor_col` (1-indexed, M7 revisit) are where the native
// handler positions the terminal's real cursor after a redraw — clamped
// to the visible viewport by `render_editor_to_buffer` (no scroll-offset
// tracking yet, so a cursor below the fold renders at the last visible
// row rather than scrolling the view).
pub struct ScreenBuffer {
  width: int,
  height: int,
  lines: list<string>,
  cursor_row: int,
  cursor_col: int
}

// Cursor-shape hint forwarded to the Terminal handler.
pub type CursorStyle {
  Block,
  Bar,
  Underscore
}

// A minimal single-line input widget (M9). `NoPrompt` is the normal-editing
// state; `SaveAsPrompt`/`OpenPrompt` carry the text typed so far. Only one
// prompt can be active at a time — `resolve_action` checks `state.prompt`
// before falling back to the normal Insert/Enter/Backspace dispatch, so
// prompt text entry and buffer editing never race.
pub type Prompt {
  NoPrompt,
  SaveAsPrompt(text: string),
  OpenPrompt(text: string)
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

// `line`-th element of `lines`, or `""` past the end. Small recursive
// helper local to this file (actions.hc has its own `list_get` — not
// exported, so we don't share it).
fun nth_line(lines: list<string>, idx: int) : string =>
  match lines {
    []          => "",
    [x, ..rest] => if idx <= 0 { x } else { nth_line(rest, idx - 1) }
  }

// Clamp a `+LINE:COL`-derived `Position` into a buffer's actual bounds
// so an out-of-range startup position (negative, or past EOF) can
// never crash — it just lands on the nearest valid line/column.
pub fun clamp_position(lines: list<string>, pos: Position) : Position {
  let line     = max(min(pos.line, max(length(lines) - 1, 0)), 0)
  let line_len = length(nth_line(lines, line))
  let col      = max(min(pos.col, line_len), 0)
  Position { line: line, col: col }
}

// Apply an optional `+LINE:COL` startup position (already clamped) to
// every cursor on a freshly loaded buffer. `None` (no `+…` argument
// given) leaves the buffer untouched.
pub fun set_initial_position(buf: TextBuffer, pos: maybe<Position>) : TextBuffer =>
  match pos {
    None => buf,
    Some(p) => {
      let clamped     = clamp_position(buf.lines, p)
      let new_cursors = map(buf.cursors, (c) => Cursor { ...c, pos: clamped })
      TextBuffer { ...buf, cursors: new_cursors }
    }
  }

// Initial editor state. `path` is optional — `None` means an unnamed scratch
// buffer. A real file-open step will come with the `fs` effect later.
pub fun init_editor(path: maybe<string>) : EditorState =>
  init_editor_with_config(path, default_config())

// Same as init_editor but takes a caller-supplied `Config` (typically
// the merger of `default_config()` + the user's HiLisp init.hl, built
// by `src/hilisp_host.hc::load_config`). Kept as a separate constructor
// so `init_editor(None)` stays a one-liner for callers that don't touch
// scripting (all pure tests). Builds a content-free buffer — callers
// that want real file content loaded should go through
// `init_editor_with_buffer` + `load_buffer` instead (see main.hc, M6).
pub fun init_editor_with_config(path: maybe<string>, cfg: Config) : EditorState =>
  init_editor_with_buffer(new_buffer(0, path), cfg)

// Same as init_editor_with_config, but takes an already-built `TextBuffer`
// (typically the result of `load_buffer`) instead of constructing an
// empty one from a path. Lets main.hc load real file content before the
// rest of `EditorState` is assembled, without touching the pure
// `init_editor` / `init_editor_with_config` surface every test relies on.
pub fun init_editor_with_buffer(buf: TextBuffer, cfg: Config) : EditorState =>
  EditorState {
    buffer: buf,
    background_buffers: [],
    next_bid: 1,
    status_message: None,
    screen_size: (80, 24),
    should_quit: false,
    config: cfg,
    prompt: NoPrompt
  }

// Split file content into lines, dropping one trailing newline artifact
// (if present) so this round-trips exactly with `runtime.hc::save_buffer`,
// which joins lines with "\n" and appends a single trailing "\n".
fun split_lines(content: string) : list<string> =>
  if ends_with(content, "\n") { split(content[0:length(content) - 1], "\n") }
  else { split(content, "\n") }

// Read `p` from disk into a fresh buffer, or fall back to an empty one
// with an error status. Split out of `load_buffer` so each function
// only matches once (avoids nested match on maybe/result).
// Return-type annotation omitted: carries <fsys> (Koka rejects a pure
// annotation here once the read is behind a helper call).
fun load_existing_buffer(new_bid: int, p: string) =>
  match read_file(p) {
    Ok(content) => (TextBuffer { ...new_buffer(new_bid, Some(p)), lines: split_lines(content) }, None),
    Err(msg)    => (new_buffer(new_bid, Some(p)), Some("Could not open " + p + ": " + msg))
  }

// Load a buffer's content from disk. `None` (no file given) and a failed
// read both fall back to `new_buffer`'s empty-scratch shape — this never
// crashes. On failure the second element carries a status message the
// caller can hand to `set_status_message`, mirroring
// `config_loader.hc::load_user_config`'s error-surfacing pattern. The
// path is kept on the buffer even after a failed read, so a subsequent
// Save still knows where to write (mirrors opening a new file in vim).
// Return-type annotation omitted: carries <fsys>, and Koka misinfers a
// `total` requirement here when a pub arrow-body function's return type
// is pinned while it delegates to an effectful helper. Callers that need
// the buffer's `lines` field pinned against the `hc_lines` prelude
// collision should annotate their own `let` binding instead (see
// `tests/model_test.hc`).
pub fun load_buffer(new_bid: int, path: maybe<string>) =>
  match path {
    None    => (new_buffer(new_bid, None), None),
    Some(p) => load_existing_buffer(new_bid, p)
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
