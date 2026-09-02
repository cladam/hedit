/// Core editor state.

import "keys"

/// A caret position inside a `TextBuffer`.
pub struct Position {
  line: int,
  col: int
}

/// One cursor. `cid` avoids clashing with the `TextBuffer.id` accessor
/// Koka generates.
pub struct Cursor {
  cid: int,
  pos: Position
}

/// A buffer of text lines plus its cursors and dirty flag.
// `bid` avoids clashing with Koka's generated `id` accessor. `lines` is a
// `list<string>` for now; a piece table / rope can slot in later without
// changing this file's public surface.
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
// Every editor operation reduces to one of these named `Action`s, mirroring
// micro's action model. `handle_action`/`event_loop` dispatch *only* on
// `Action`, never on raw keystrokes, so users can rebind any key to any
// action via `(bind "Ctrl-x" 'save)` (M4) without touching hica sources.
//
// `Insert(c)` is a special case: `resolve_action` maps every `KChar(c)` to
// it automatically, since text entry has no fixed name. `Ignore` is what
// an unbound chord resolves to.

/// A semantic editor operation that `resolve_action`/`apply_action`
/// dispatch on, decoupled from the raw keystroke that triggered it.
pub type Action {
  Quit,
  Save,
  Insert(c: char),
  NewLine,
  DeleteBackward,
  DeleteForward,
  MoveUp,
  MoveDown,
  MoveLeft,
  MoveRight,
  MoveLineStart,
  MoveLineEnd,
  MoveWordForward,
  MoveWordBack,
  Resize(w: int, h: int),
  Copy,
  Paste,
  Undo,
  Redo,
  KillLine,
  KillWordBack,
  KillWordForward,
  KillWholeLine,
  NewBuffer,
  NextBuffer,
  PrevBuffer,
  CloseBuffer,
  OpenFile,
  PromptChar(c: char),
  PromptBackspace,
  PromptSubmit,
  PromptCancel,
  PromptMoveStart,
  PromptMoveEnd,
  PromptMoveLeft,
  PromptMoveRight,
  PromptDeleteForward,
  PromptKillLine,
  ToggleHelp,
  StartFind,
  FindNext,
  FindPrev,
  VSplit,
  HSplit,
  PaneLeft,
  PaneRight,
  PaneUp,
  PaneDown,
  NextPane,
  Ignore
}

/// A key chord: a modifier + a printable char. Bare `KChar`s route
/// straight to `Insert`, so bindings only need to cover `KShortcut`s.
pub struct KeyChord {
  m: Modifier,
  c: char
}

// The user-configurable action map. Represented as an alist (`list<(KeyChord,
// Action)>`) to match hica's `map_get`/`map_set` — hica doesn't (yet)
// support `pub type Alias = ...`, so we spell the alist type out at every
// use site. A HAMT can slot in later if this ever gets big enough to matter.

/// Default keybindings, every binding is overridable via
/// HiLisp `(bind ...)`.
pub fun default_bindings() : list<(KeyChord, Action)> =>
  [
    (KeyChord { m: Ctrl, c: 'q' }, Quit),
    (KeyChord { m: Ctrl, c: 's' }, Save),
    (KeyChord { m: Ctrl, c: 'c' }, Copy),
    (KeyChord { m: Ctrl, c: 'v' }, Paste),
    (KeyChord { m: Ctrl, c: 'z' }, Undo),
    (KeyChord { m: Ctrl, c: 'r' }, Redo),
    (KeyChord { m: Ctrl, c: 'o' }, OpenFile),
    (KeyChord { m: Ctrl, c: 'g' }, ToggleHelp),
    (KeyChord { m: Ctrl, c: 'a' }, MoveLineStart),
    (KeyChord { m: Ctrl, c: 'e' }, MoveLineEnd),
    (KeyChord { m: Ctrl, c: 'f' }, StartFind),
    (KeyChord { m: Ctrl, c: 'd' }, DeleteForward),
    (KeyChord { m: Ctrl, c: 'k' }, KillLine),
    (KeyChord { m: Ctrl, c: 'w' }, KillWordBack),
    (KeyChord { m: Ctrl, c: 'y' }, Paste),
    (KeyChord { m: Meta, c: 'o' }, NewBuffer),
    (KeyChord { m: Meta, c: 'n' }, NextBuffer),
    (KeyChord { m: Meta, c: 'p' }, PrevBuffer),
    (KeyChord { m: Meta, c: 'w' }, CloseBuffer),
    (KeyChord { m: Meta, c: 'v' }, VSplit),
    (KeyChord { m: Meta, c: 'h' }, HSplit),
    (KeyChord { m: Meta, c: 'f' }, MoveWordForward),
    (KeyChord { m: Meta, c: 'b' }, MoveWordBack),
    (KeyChord { m: Meta, c: 'd' }, KillWordForward),
    (KeyChord { m: Meta, c: 'l' }, KillWholeLine)
  ]

/// Resolve a `KeyChord` against a bindings map. Unbound chords resolve
/// to `Ignore`.
pub fun lookup_binding(kb: list<(KeyChord, Action)>, chord: KeyChord) : Action =>
  match map_get(kb, chord) {
    Some(a) => a,
    None    => Ignore
  }

/// Config bundle carried through the editor.
// M4 grows this with `(set ...)` values sourced from HiLisp, kept as
// `list<(string, string)>` so keys/values round-trip through the HiLisp
// bridge without an extra ADT (stringified at the boundary; helpers below
// decode them back). `readonly` (M8) gates `Save` in
// `runtime.hc::save_buffer` — a plain field since it's only ever set from
// `--readonly` on the CLI, never from HiLisp.
pub struct Config {
  bindings: list<(KeyChord, Action)>,
  values: list<(string, string)>,
  readonly: bool
}

/// The default `Config`: default bindings, no HiLisp values, not readonly.
pub fun default_config() : Config =>
  Config { bindings: default_bindings(), values: [], readonly: false }

/// Look up a `(set key value)` value from the config, or `default` if
/// absent.
pub fun get_config(cfg: Config, key: string, default: string) : string =>
  match map_get(cfg.values, key) {
    Some(v) => v,
    None    => default
  }

/// Parse `v` as an int, falling back to `fallback` if it isn't numeric.
// Routed through an explicit helper so hica codegen doesn't build a
// `.default(default)` chain (Koka's `default` method on maybe conflicts
// with our `default` parameter name in that call position).
fun parse_or(v: string, fallback: int) : int =>
  match parse_int(v) {
    Some(n) => n,
    None    => fallback
  }

/// Numeric convenience over `get_config`: reads `key`, parses as int,
/// falling back to `default` on a missing key or non-numeric content.
pub fun get_config_int(cfg: Config, key: string, default: int) : int =>
  match map_get(cfg.values, key) {
    Some(v) => parse_or(v, default),
    None    => default
  }

/// Set (or override) a single `(key, value)` config entry.
// Used by `--tabsize` (main.hc, M8) to apply a CLI override after
// `init.hl` has already run, matching micro's session-override
// precedence (CLI wins over config).
pub fun set_config_value(cfg: Config, key: string, value: string) : Config =>
  Config { ...cfg, values: map_set(cfg.values, key, value) }

// ---------------------------------------------------------------------------
// Theming (M10) — hedit's own chrome colors (tabline/status line/cursor
// line), NOT syntax highlighting. Every color is a true-color (r, g, b)
// triple applied via std/term's ANSI helpers in main.hc's render_native.
// Configurable from HiLisp with well-known `(set ...)` keys read straight
// out of the existing `Config.values` alist: `(set "theme" "ilseon")` picks
// a built-in preset, `(set "theme.status-fg" "R,G,B")`-style keys override
// individual slots on top of whichever preset is active.
// ---------------------------------------------------------------------------

/// hedit's chrome color palette (tabline, status line, cursor line).
pub struct Theme {
  tabline_fg: (int, int, int),
  tabline_bg: (int, int, int),
  status_fg: (int, int, int),
  status_bg: (int, int, int),
  active_tab_fg: (int, int, int),
  active_tab_bg: (int, int, int),
  cursor_line_bg: (int, int, int),
  search_match_bg: (int, int, int)
}

/// hedit's built-in default theme.
pub fun default_theme() : Theme =>
  Theme {
    tabline_fg: (255, 255, 255),
    tabline_bg: (33, 33, 33),
    status_fg: (0, 0, 0),
    status_bg: (200, 200, 200),
    active_tab_fg: (255, 215, 0),
    active_tab_bg: (60, 60, 60),
    cursor_line_bg: (45, 45, 45),
    search_match_bg: (90, 90, 0)
  }

/// A dark, low-sensory preset (`(set "theme" "ilseon")`), using the
/// same RGB values as std/term's ilseon palette
/// (github.com/cladam/ilseon).
pub fun ilseon_theme() : Theme =>
  Theme {
    tabline_fg: (163, 169, 145),
    tabline_bg: (20, 20, 20),
    status_fg: (0, 191, 165),
    status_bg: (20, 20, 20),
    active_tab_fg: (226, 176, 94),
    active_tab_bg: (40, 40, 40),
    cursor_line_bg: (30, 30, 30),
    search_match_bg: (80, 70, 20)
  }

/// Look up a built-in theme preset by name.
fun theme_preset(name: string) : maybe<Theme> =>
  match name {
    "default" => Some(default_theme()),
    "ilseon"  => Some(ilseon_theme()),
    _         => None
  }

/// Parse a "R,G,B" override string into a color triple, falling back
/// to `fallback` on any malformed or missing component.
fun parse_rgb(s: string, fallback: (int, int, int)) : (int, int, int) =>
  match split(s, ",") {
    [r_str, g_str, b_str] =>
      (parse_or(r_str, fallback.0), parse_or(g_str, fallback.1), parse_or(b_str, fallback.2)),
    _ => fallback
  }

/// Look up a single `theme.<slot>` RGB override from config.
fun get_rgb_override(cfg: Config, key: string, fallback: (int, int, int)) : (int, int, int) =>
  match map_get(cfg.values, key) {
    Some(v) => parse_rgb(v, fallback),
    None    => fallback
  }

/// Apply every `theme.<slot>` override on top of a resolved preset.
// One sequential struct-update per slot — kept flat (no nested match)
// so `hica analyse` stays clean.
fun apply_theme_overrides(cfg: Config, base: Theme) : Theme {
  let t1 = Theme { ...base, tabline_fg: get_rgb_override(cfg, "theme.tabline-fg", base.tabline_fg) }
  let t2 = Theme { ...t1, tabline_bg: get_rgb_override(cfg, "theme.tabline-bg", t1.tabline_bg) }
  let t3 = Theme { ...t2, status_fg: get_rgb_override(cfg, "theme.status-fg", t2.status_fg) }
  let t4 = Theme { ...t3, status_bg: get_rgb_override(cfg, "theme.status-bg", t3.status_bg) }
  let t5 = Theme { ...t4, active_tab_fg: get_rgb_override(cfg, "theme.active-tab-fg", t4.active_tab_fg) }
  let t6 = Theme { ...t5, active_tab_bg: get_rgb_override(cfg, "theme.active-tab-bg", t5.active_tab_bg) }
  let t7 = Theme { ...t6, cursor_line_bg: get_rgb_override(cfg, "theme.cursor-line-bg", t6.cursor_line_bg) }
  Theme { ...t7, search_match_bg: get_rgb_override(cfg, "theme.search-match-bg", t7.search_match_bg) }
}

/// Resolve `Config.values` into a concrete `Theme` plus an optional
/// status message when an unrecognised `theme` preset name falls back
/// to `default_theme()`.
pub fun resolve_theme_with_status(cfg: Config) : (Theme, maybe<string>) {
  let preset_name = get_config(cfg, "theme", "default")
  let (base, warn) = match theme_preset(preset_name) {
    Some(t) => (t, None),
    None    => (default_theme(), Some("Unknown theme \"" + preset_name + "\", using default"))
  }
  (apply_theme_overrides(cfg, base), warn)
}

/// Resolve `Config.values` into a concrete `Theme`, discarding any
/// unknown-preset warning.
pub fun resolve_theme(cfg: Config) : Theme =>
  resolve_theme_with_status(cfg).0

// ---------------------------------------------------------------------------
// Editor state
// ---------------------------------------------------------------------------

/// Full editor state. `buffer` is always the active buffer;
/// `background_buffers` holds the rest of the open buffers as a
/// rotation ring with no separate active index to keep in sync.
// `next_bid` hands out fresh `TextBuffer.bid`s for `NewBuffer`. `panes`
// (M15) is the split-pane layout tree; the "active" leaf is always the
// one whose `bid` equals `buffer.bid` (every leaf gets a distinct bid
// at split time, so this stays unambiguous without a separate index).
pub struct EditorState {
  buffer: TextBuffer,
  background_buffers: list<TextBuffer>,
  next_bid: int,
  status_message: maybe<string>,
  screen_size: (int, int),
  should_quit: bool,
  config: Config,
  prompt: Prompt,
  show_help: bool,
  search: SearchState,
  panes: PaneNode
}

/// The pixel-free "screen buffer" the Terminal handler flushes.
// `cursor_row`/`cursor_col` (1-indexed) are where the native handler
// positions the terminal's real cursor after a redraw — clamped to the
// visible viewport by `render_editor_to_buffer`, which scrolls the buffer
// line by line so the cursor's line is always shown. `highlights` is
// `(row, start_col, end_col)` triples (1-indexed row, 0-indexed cols)
// for search-match spans (M12) the Terminal handler paints with
// `theme.search_match_bg` — empty outside an active search.
pub struct ScreenBuffer {
  width: int,
  height: int,
  lines: list<string>,
  cursor_row: int,
  cursor_col: int,
  highlights: list<(int, int, int)>
}

/// Cursor-shape hint forwarded to the Terminal handler.
pub type CursorStyle {
  Block,
  Bar,
  Underscore
}

/// A minimal single-line input widget (M9). `NoPrompt` is the normal-
/// editing state; `SaveAsPrompt`/`OpenPrompt`/`FindPrompt`/`VSplitPrompt`/
/// `HSplitPrompt` carry the text typed so far. Only one prompt can be
/// active at a time.
pub type Prompt {
  NoPrompt,
  SaveAsPrompt(text: string, cursor: int),
  OpenPrompt(text: string, cursor: int),
  FindPrompt(text: string, cursor: int),
  VSplitPrompt(text: string, cursor: int),
  HSplitPrompt(text: string, cursor: int)
}

/// The split-axis of a `Split` pane (M15).
pub type Axis {
  Horizontal,
  Vertical
}

/// A binary tree of split panes (M15). `Leaf(bid)` is a single visible
/// pane showing the `TextBuffer` with that `bid` — resolved against
/// `EditorState.buffer` + `background_buffers` at render/focus time,
/// same lookup either needs. `Split` divides its rectangle along
/// `axis` at `ratio` (0.0–1.0, the fraction given to `left`/`top`).
pub type PaneNode {
  Leaf(bid: int),
  Split(axis: Axis, ratio: float, left: PaneNode, right: PaneNode)
}

/// One match of an active search: the line/column where it starts —
/// its end column is `col + length(query)`.
pub struct SearchMatch {
  line: int,
  col: int
}

/// Find (M12) state: `NoSearch` outside an active search; `ActiveSearch`
/// carries the query, every match across the buffer (recomputed on each
/// keystroke while `FindPrompt` is open), and `current` — the index into
/// `matches` the cursor last jumped to via `FindNext`/`FindPrev`
/// (`-1` if no match has been visited yet).
pub type SearchState {
  NoSearch,
  ActiveSearch(query: string, matches: list<SearchMatch>, current: int)
}

// --- constructors ---------------------------------------------------------

/// A fresh buffer with one empty line and one cursor at (0, 0).
pub fun new_buffer(bid: int, path: maybe<string>) : TextBuffer =>
  TextBuffer {
    bid: bid,
    path: path,
    lines: [""],
    cursors: [Cursor { cid: 0, pos: Position { line: 0, col: 0 } }],
    is_dirty: false
  }

/// `line`-th element of `lines`, or "" past the end.
// Local to this file — actions.hc has its own `list_get`, not exported,
// so we don't share it.
fun nth_line(lines: list<string>, idx: int) : string =>
  match lines {
    []          => "",
    [x, ..rest] => if idx <= 0 { x } else { nth_line(rest, idx - 1) }
  }

/// Clamp a `+LINE:COL`-derived `Position` into a buffer's actual
/// bounds so an out-of-range startup position can never crash.
pub fun clamp_position(lines: list<string>, pos: Position) : Position {
  let line     = max(min(pos.line, max(length(lines) - 1, 0)), 0)
  let line_len = length(nth_line(lines, line))
  let col      = max(min(pos.col, line_len), 0)
  Position { line: line, col: col }
}

/// Apply an optional `+LINE:COL` startup position to every cursor on
/// a freshly loaded buffer. `None` leaves the buffer untouched.
pub fun set_initial_position(buf: TextBuffer, pos: maybe<Position>) : TextBuffer =>
  match pos {
    None => buf,
    Some(p) => {
      let clamped     = clamp_position(buf.lines, p)
      let new_cursors = map(buf.cursors, (c) => Cursor { ...c, pos: clamped })
      TextBuffer { ...buf, cursors: new_cursors }
    }
  }

/// Initial editor state with a default `Config`. `path` is `None` for
/// an unnamed scratch buffer.
pub fun init_editor(path: maybe<string>) : EditorState =>
  init_editor_with_config(path, default_config())

/// Same as `init_editor` but takes a caller-supplied `Config`
/// (typically `default_config()` merged with the user's HiLisp
/// `init.hl`, built by `hilisp_host.hc::load_config`).
// Builds a content-free buffer; callers that want real file content
// loaded should go through `init_editor_with_buffer` + `load_buffer`
// instead (see main.hc, M6).
pub fun init_editor_with_config(path: maybe<string>, cfg: Config) : EditorState =>
  init_editor_with_buffer(new_buffer(0, path), cfg)

/// Same as `init_editor_with_config`, but takes an already-built
/// `TextBuffer` (typically the result of `load_buffer`) instead of
/// constructing an empty one from a path.
pub fun init_editor_with_buffer(buf: TextBuffer, cfg: Config) : EditorState =>
  EditorState {
    buffer: buf,
    background_buffers: [],
    next_bid: 1,
    status_message: None,
    screen_size: (80, 24),
    should_quit: false,
    config: cfg,
    prompt: NoPrompt,
    show_help: false,
    search: NoSearch,
    panes: Leaf(buf.bid)
  }

/// Split file content into lines, dropping one trailing newline
/// artifact so this round-trips exactly with `runtime.hc::save_buffer`.
fun split_lines(content: string) : list<string> =>
  if ends_with(content, "\n") { split(content[0:length(content) - 1], "\n") }
  else { split(content, "\n") }

/// Read `p` from disk into a fresh buffer, or fall back to an empty
/// one with an error status.
// Split out of `load_buffer` so each function only matches once (avoids
// nested match on maybe/result). Return-type annotation omitted: carries
// <fsys> (Koka rejects a pure annotation here once the read is behind a
// helper call).
fun load_existing_buffer(new_bid: int, p: string) =>
  match read_file(p) {
    Ok(content) => (TextBuffer { ...new_buffer(new_bid, Some(p)), lines: split_lines(content) }, None),
    Err(msg)    => (new_buffer(new_bid, Some(p)), Some("Could not open " + p + ": " + msg))
  }

/// Load a buffer's content from disk. `None` (no file given) and a
/// failed read both fall back to `new_buffer`'s empty-scratch shape;
/// this never crashes. On failure the second element carries a status
/// message the caller can hand to `set_status_message`.
// The path is kept on the buffer even after a failed read, so a
// subsequent Save still knows where to write (mirrors opening a new
// file in vim). Return-type annotation omitted: carries <fsys>, and Koka
// misinfers a `total` requirement here when a pub arrow-body function's
// return type is pinned while it delegates to an effectful helper.
// Callers that need the buffer's `lines` field pinned against the
// `hc_lines` prelude collision should annotate their own `let` binding
// instead (see tests/model_test.hc).
pub fun load_buffer(new_bid: int, path: maybe<string>) =>
  match path {
    None    => (new_buffer(new_bid, None), None),
    Some(p) => load_existing_buffer(new_bid, p)
  }

/// All currently-open buffers, active buffer first — the order a
/// tabline should render them in.
pub fun open_buffers(s: EditorState) : list<TextBuffer> =>
  [s.buffer] + s.background_buffers

// ------------------- Split panes (M15) ------------------------------------

/// The `TextBuffer` shown in the leaf with the given `bid`, or `s.buffer`
/// as a safe fallback if `bid` isn't currently open (e.g. a stale pane
/// left behind by `CloseBuffer` — panes don't prune themselves yet, a
/// follow-up). Total: never crashes on a bid/state desync.
pub fun buffer_for(s: EditorState, bid: int) : TextBuffer =>
  buffer_for_go(open_buffers(s), bid, s.buffer)

fun buffer_for_go(bufs: list<TextBuffer>, target_bid: int, fallback: TextBuffer) : TextBuffer =>
  match bufs {
    []          => fallback,
    [b, ..rest] => if b.bid == target_bid { b } else { buffer_for_go(rest, target_bid, fallback) }
  }

/// Replace the leaf holding `target_bid` with `replacement`, walking the
/// tree — how `VSplit`/`HSplit` turn a `Leaf` into a `Split`. A no-op if
/// `target_bid` isn't found (defensive; every leaf's bid comes from an
/// actually-open buffer in practice).
pub fun replace_leaf(node: PaneNode, target_bid: int, replacement: PaneNode) : PaneNode =>
  match node {
    Leaf(bid) => if bid == target_bid { replacement } else { node },
    Split(axis, ratio, left, right) =>
      Split(axis, ratio, replace_leaf(left, target_bid, replacement), replace_leaf(right, target_bid, replacement))
  }

// --- small pure helpers ---------------------------------------------------

/// Set the status line message.
pub fun set_status_message(s: EditorState, msg: string) : EditorState =>
  EditorState { ...s, status_message: Some(msg) }

/// Clear the status line message.
pub fun clear_status_message(s: EditorState) : EditorState =>
  EditorState { ...s, status_message: None }
