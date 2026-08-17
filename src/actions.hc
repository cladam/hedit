// actions.hc — pure event → state transitions.
//
// The dispatcher is a two-step pipeline:
//
//   raw Event  ──resolve_action──►  Action  ──apply_action──►  EditorState
//
// `resolve_action` consults `state.config.bindings`, so users can
// remap any Ctrl-/Alt-shortcut from a HiLisp `init.hl` (M4) without
// editing hica sources — mirroring micro's model
// (https://github.com/micro-editor/micro/blob/master/runtime/help/keybindings.md).
//
// Only pure actions live here. Effectful ones (`Save`, which needs
// `<fsys>`) are dispatched by `event_loop` in `runtime.hc`.

import "keys"
import "model"

// ------------------- list helpers (pure, index-safe) ---------------------

// Replace the list element at `idx` with `new_val`. Recursive & pure so we
// don't need index-based mutation (which would raise `exn` in hica).
fun list_set(xs: list<string>, idx: int, new_val: string) : list<string> =>
  match xs {
    []          => [],
    [x, ..rest] =>
      if idx == 0 { [new_val] + rest }
      else { [x] + list_set(rest, idx - 1, new_val) }
  }

// Get the list element at `idx`, or a default if out of range.
fun list_get(xs: list<string>, idx: int, default: string) : string =>
  match xs {
    []          => default,
    [x, ..rest] =>
      if idx == 0 { x }
      else { list_get(rest, idx - 1, default) }
  }

// ------------------- cursor + edit helpers -------------------------------

// Move a single cursor one column to the right.
fun advance_cursor(c: Cursor) : Cursor =>
  Cursor { ...c, pos: Position { line: c.pos.line, col: c.pos.col + 1 } }

// Append `c` at the end of the active cursor's line. Step-1 simplification:
// we only support one cursor and only insert at end-of-line. Real per-cursor
// column-aware insertion comes with the multi-cursor step.
pub fun insert_char(state: EditorState, c: char) : EditorState {
  let buf = state.buffer
  let head_cursor = match buf.cursors {
    []       => Cursor { cid: 0, pos: Position { line: 0, col: 0 } },
    [x, .._] => x
  }
  let line_idx    = head_cursor.pos.line
  let current     = list_get(buf.lines, line_idx, "")
  let updated     = current + char_to_string(c)
  let new_lines   = list_set(buf.lines, line_idx, updated)
  let new_cursors = map(buf.cursors, advance_cursor)
  let new_buf = TextBuffer {
    ...buf,
    lines: new_lines,
    cursors: new_cursors,
    is_dirty: true
  }
  EditorState { ...state, buffer: new_buf }
}

// Return the content of the head cursor's current line, or "" if the buffer
// has no cursors / no lines. Pure: used by event_loop's `Copy` arm to compute
// the string handed to `Clipboard.set_selection`.
pub fun current_line(state: EditorState) : string {
  let buf = state.buffer
  let head_cursor = match buf.cursors {
    []       => Cursor { cid: 0, pos: Position { line: 0, col: 0 } },
    [x, .._] => x
  }
  list_get(buf.lines, head_cursor.pos.line, "")
}

// Append `text` verbatim to the end of the head cursor's line, advancing
// the cursor by `length(text)`. Simplification consistent with `insert_char`:
// no multi-line splitting on '\n' yet (a '\n' in the clipboard is inserted
// as a literal two-char sequence). Pure: `event_loop` calls this after
// `Clipboard.get_selection()` produces the text.
pub fun paste_text(state: EditorState, text: string) : EditorState {
  let buf = state.buffer
  let head_cursor = match buf.cursors {
    []       => Cursor { cid: 0, pos: Position { line: 0, col: 0 } },
    [x, .._] => x
  }
  let line_idx  = head_cursor.pos.line
  let current   = list_get(buf.lines, line_idx, "")
  let updated   = current + text
  let new_lines = list_set(buf.lines, line_idx, updated)
  // Advance every cursor by length(text). Same simplification as
  // insert_char: only end-of-line insertion, so column bookkeeping is
  // trivially additive.
  let bump      = length(text)
  let new_cursors = map(buf.cursors, (c) =>
    Cursor { ...c, pos: Position { line: c.pos.line, col: c.pos.col + bump } })
  let new_buf = TextBuffer {
    ...buf,
    lines: new_lines,
    cursors: new_cursors,
    is_dirty: true
  }
  EditorState { ...state, buffer: new_buf }
}

// ------------------- Event → Action resolution ---------------------------

// Turn a raw `Event` into a semantic `Action` using the bindings currently
// installed on `state.config`. Pure: no I/O, no hardcoded chord names.
//
// Priority: KChar always inserts, ResizeEvent always resizes; only
// KShortcuts pass through the user-configurable binding table. Unbound
// shortcuts resolve to `Ignore` — event_loop then no-ops.
pub fun resolve_action(state: EditorState, evt: Event) : Action =>
  match evt {
    KeyEvent(KChar(c))        => Insert(c),
    KeyEvent(KShortcut(m, c)) =>
      lookup_binding(state.config.bindings, KeyChord { m: m, c: c }),
    ResizeEvent(w, h)         => Resize(w, h),
    _                         => Ignore
  }

// ------------------- Action → EditorState apply -------------------------

// Apply an `Action` to state, purely. `Save`, `Copy`, and `Paste` are
// intentionally NOT handled here — they carry `<fsys>` / `<Clipboard>`
// effects that must live in `event_loop`. They no-op here so the pure
// callers (tests, HiLisp bridge) still get a total function.
pub fun apply_action(state: EditorState, action: Action) : EditorState =>
  match action {
    Quit         => EditorState { ...state, should_quit: true },
    Insert(c)    => insert_char(state, c),
    Resize(w, h) => EditorState { ...state, screen_size: (w, h) },
    Save         => state, // handled in event_loop; no-op here for purity
    Copy         => state, // handled in event_loop; needs <Clipboard>
    Paste        => state, // handled in event_loop; needs <Clipboard>
    Ignore       => state
  }

// ------------------- pure event dispatcher ------------------------------

// Convenience combinator: resolve + apply in one call. Used by callers
// that don't need to inspect the intermediate `Action` (all pure paths).
pub fun handle_action(state: EditorState, evt: Event) : EditorState =>
  apply_action(state, resolve_action(state, evt))
