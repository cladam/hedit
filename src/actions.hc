// actions.hc — pure event → state transitions.
//
// This is the "handle_action" core from section 5 of docs/hedit-design.md,
// carved down to the minimum: a single active cursor, single-line append.
// No effects yet, so no file save / no rendering — those arrive with the
// `fs` and `terminal` effects.

import "types"
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

// ------------------- pure event dispatcher -------------------------------

// Matches the shape of `handle_action` in the design doc. hica now
// auto-derives `==` on enums, so we can destructure the payload and compare
// the modifier directly — no `is_ctrl` helper needed. The condition is
// parenthesised because `x == Ctrl { ... }` would otherwise be parsed as a
// struct literal (see hica language-reference §Enums).
pub fun handle_action(state: EditorState, evt: Event) : EditorState =>
  match evt {
    KeyEvent(KShortcut(m, c)) =>
      if (m == Ctrl) && c == 'q' {
        EditorState { ...state, should_quit: true }
      } else {
        state
      },
    KeyEvent(KChar(c))  => insert_char(state, c),
    ResizeEvent(w, h)   => EditorState { ...state, screen_size: (w, h) },
    _                   => state
  }
