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

// Replace the element at `idx` with two elements `a`, `b` (used to split a
// line in two on Enter). Out-of-range `idx` is a no-op, matching `list_set`.
fun list_split_at(xs: list<string>, idx: int, a: string, b: string) : list<string> =>
  match xs {
    []          => [],
    [x, ..rest] =>
      if idx == 0 { [a, b] + rest }
      else { [x] + list_split_at(rest, idx - 1, a, b) }
  }

// Drop the element at `idx` entirely (used to merge a line into the
// previous one on Backspace-at-column-0).
fun list_remove_at(xs: list<string>, idx: int) : list<string> =>
  match xs {
    []          => [],
    [x, ..rest] =>
      if idx == 0 { rest }
      else { [x] + list_remove_at(rest, idx - 1) }
  }

// ------------------- cursor + edit helpers -------------------------------

// The single cursor hedit currently supports (multi-cursor is future work),
// or a fresh one at (0, 0) if the buffer somehow has none.
fun head_cursor(buf: TextBuffer) : Cursor =>
  match buf.cursors {
    []       => Cursor { cid: 0, pos: Position { line: 0, col: 0 } },
    [x, .._] => x
  }

// Clamp `col` into `[0, length(line at line_idx)]`.
fun clamp_col(lines: list<string>, line_idx: int, col: int) : int {
  let line_len = length(list_get(lines, line_idx, ""))
  max(min(col, line_len), 0)
}

// Insert `c` at the head cursor's column (not just end-of-line — M7
// revisit). Step-1 simplification: still only one cursor; multi-cursor
// insertion needs per-cursor line/column bookkeeping that doesn't exist yet.
pub fun insert_char(state: EditorState, c: char) : EditorState {
  let buf         = state.buffer
  let cur         = head_cursor(buf)
  let line_idx    = cur.pos.line
  let col         = cur.pos.col
  let current     = list_get(buf.lines, line_idx, "")
  let before      = current[0:col]
  let after       = current[col: ]
  let updated     = before + char_to_string(c) + after
  let new_lines   = list_set(buf.lines, line_idx, updated)
  let new_cursors = map(buf.cursors, (cc) =>
    Cursor { ...cc, pos: Position { line: line_idx, col: col + 1 } })
  let new_buf = TextBuffer {
    ...buf,
    lines: new_lines,
    cursors: new_cursors,
    is_dirty: true
  }
  EditorState { ...state, buffer: new_buf }
}

// Enter: split the current line at the cursor column into two lines,
// cursor moves to column 0 of the new (second) line.
pub fun insert_newline(state: EditorState) : EditorState {
  let buf         = state.buffer
  let cur         = head_cursor(buf)
  let line_idx    = cur.pos.line
  let col         = cur.pos.col
  let current     = list_get(buf.lines, line_idx, "")
  let before      = current[0:col]
  let after       = current[col: ]
  let new_lines   = list_split_at(buf.lines, line_idx, before, after)
  let new_cursors = map(buf.cursors, (cc) =>
    Cursor { ...cc, pos: Position { line: line_idx + 1, col: 0 } })
  let new_buf = TextBuffer {
    ...buf,
    lines: new_lines,
    cursors: new_cursors,
    is_dirty: true
  }
  EditorState { ...state, buffer: new_buf }
}

// Ctrl-a: move the head cursor to column 0 of its current line.
pub fun move_line_start(state: EditorState) : EditorState {
  let buf = state.buffer
  let cur = head_cursor(buf)
  let new_pos = Position { line: cur.pos.line, col: 0 }
  let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: new_pos })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

// Ctrl-e: move the head cursor to the end of its current line.
pub fun move_line_end(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let line_len = length(list_get(buf.lines, cur.pos.line, ""))
  let new_pos  = Position { line: cur.pos.line, col: line_len }
  let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: new_pos })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

// Backspace: delete the char before the cursor on the same line, or — at
// column 0 — merge the current line into the end of the previous one. A
// no-op at the very start of the buffer (line 0, col 0).
pub fun delete_backward(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let line_idx = cur.pos.line
  let col      = cur.pos.col
  if col > 0 {
    let current     = list_get(buf.lines, line_idx, "")
    let updated     = current[0:col - 1] + current[col: ]
    let new_lines   = list_set(buf.lines, line_idx, updated)
    let new_cursors = map(buf.cursors, (cc) =>
      Cursor { ...cc, pos: Position { line: line_idx, col: col - 1 } })
    let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: new_cursors, is_dirty: true }
    EditorState { ...state, buffer: new_buf }
  } else if line_idx > 0 {
    let prev_idx    = line_idx - 1
    let prev        = list_get(buf.lines, prev_idx, "")
    let current     = list_get(buf.lines, line_idx, "")
    let merged      = prev + current
    let merged_col  = length(prev)
    let joined      = list_set(buf.lines, prev_idx, merged)
    let new_lines   = list_remove_at(joined, line_idx)
    let new_cursors = map(buf.cursors, (cc) =>
      Cursor { ...cc, pos: Position { line: prev_idx, col: merged_col } })
    let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: new_cursors, is_dirty: true }
    EditorState { ...state, buffer: new_buf }
  } else {
    state
  }
}

// Ctrl-d: delete the char under the cursor (forward-delete), or — at the
// end of a non-last line — merge the next line up into this one. Mirrors
// `delete_backward`'s line-merge but in the opposite direction. A no-op
// at the very end of the buffer.
pub fun delete_forward(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let line_idx = cur.pos.line
  let col      = cur.pos.col
  let current  = list_get(buf.lines, line_idx, "")
  let line_len = length(current)
  if col < line_len {
    let updated   = current[0:col] + current[col + 1:]
    let new_lines = list_set(buf.lines, line_idx, updated)
    let new_buf   = TextBuffer { ...buf, lines: new_lines, is_dirty: true }
    EditorState { ...state, buffer: new_buf }
  } else if line_idx < length(buf.lines) - 1 {
    let next_idx  = line_idx + 1
    let next      = list_get(buf.lines, next_idx, "")
    let merged    = current + next
    let joined    = list_set(buf.lines, line_idx, merged)
    let new_lines = list_remove_at(joined, next_idx)
    let new_buf   = TextBuffer { ...buf, lines: new_lines, is_dirty: true }
    EditorState { ...state, buffer: new_buf }
  } else {
    state
  }
}

// Arrow-key cursor movement. Left/Right wrap onto the previous/next line at
// a line boundary (standard editor feel); Up/Down keep the column clamped
// to the target line's length rather than tracking a "sticky" column.
pub fun move_left(state: EditorState) : EditorState {
  let buf = state.buffer
  let cur = head_cursor(buf)
  let new_pos =
    if cur.pos.col > 0 { Position { line: cur.pos.line, col: cur.pos.col - 1 } }
    else if cur.pos.line > 0 {
      let prev_idx = cur.pos.line - 1
      Position { line: prev_idx, col: length(list_get(buf.lines, prev_idx, "")) }
    }
    else { cur.pos }
  let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: new_pos })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

pub fun move_right(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let line_len = length(list_get(buf.lines, cur.pos.line, ""))
  let n_lines  = length(buf.lines)
  let new_pos =
    if cur.pos.col < line_len { Position { line: cur.pos.line, col: cur.pos.col + 1 } }
    else if cur.pos.line < n_lines - 1 { Position { line: cur.pos.line + 1, col: 0 } }
    else { cur.pos }
  let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: new_pos })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

pub fun move_up(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let new_line = max(cur.pos.line - 1, 0)
  let new_pos  = Position { line: new_line, col: clamp_col(buf.lines, new_line, cur.pos.col) }
  let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: new_pos })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

pub fun move_down(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let n_lines  = length(buf.lines)
  let new_line = min(cur.pos.line + 1, n_lines - 1)
  let new_pos  = Position { line: new_line, col: clamp_col(buf.lines, new_line, cur.pos.col) }
  let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: new_pos })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

// Return the content of the head cursor's current line, or "" if the buffer
// has no cursors / no lines. Pure: used by event_loop's `Copy` arm to compute
// the string handed to `Clipboard.set_selection`.
pub fun current_line(state: EditorState) : string {
  let buf = state.buffer
  list_get(buf.lines, head_cursor(buf).pos.line, "")
}

// Append `text` verbatim to the end of the head cursor's line, advancing
// the cursor by `length(text)`. Simplification consistent with `insert_char`:
// no multi-line splitting on '\n' yet (a '\n' in the clipboard is inserted
// as a literal two-char sequence). Pure: `event_loop` calls this after
// `Clipboard.get_selection()` produces the text.
pub fun paste_text(state: EditorState, text: string) : EditorState {
  let buf = state.buffer
  let cur = head_cursor(buf)
  let line_idx  = cur.pos.line
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

// ------------------- kill / yank (Ctrl-k, Ctrl-w) -------------------------
//
// Both kill actions reuse the same `Clipboard` sink as `Copy`/`Paste`
// (event_loop calls `set_selection` with the killed text) — hedit only
// has one clipboard slot for now, so `Ctrl-y` (yank) is just `Paste`
// bound to a second chord (see `default_bindings`), not a separate
// kill-ring. Split into a pure "what gets killed" + "what state looks
// like after" pair so `event_loop` can hand the text to `set_selection`
// before applying the truncation, mirroring the `Copy` dispatch.

// Ctrl-k: the text from the cursor to the end of the current line —
// what gets killed (added to the clipboard) without yet applying it.
pub fun kill_line_text(state: EditorState) : string {
  let buf  = state.buffer
  let cur  = head_cursor(buf)
  let line = list_get(buf.lines, cur.pos.line, "")
  line[cur.pos.col:]
}

// Ctrl-k: truncate the current line at the cursor. Cursor position is
// already valid at the truncation point, so it doesn't need updating.
pub fun kill_line(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let line_idx = cur.pos.line
  let current  = list_get(buf.lines, line_idx, "")
  let updated  = current[0:cur.pos.col]
  let new_lines = list_set(buf.lines, line_idx, updated)
  let new_buf   = TextBuffer { ...buf, lines: new_lines, is_dirty: true }
  EditorState { ...state, buffer: new_buf }
}

fun is_space_char(c: char) : bool => c == ' ' || char_to_string(c) == "\t"

// Drop chars off the front of a char list while `pred` holds. Used on
// both a reversed prefix (word-back) and a plain suffix (word-forward)
// slice — "drop leading matches" doesn't care which direction the
// caller's list represents.
fun drop_while(chs: list<char>, pred: (char) -> bool) : list<char> =>
  match chs {
    []          => [],
    [x, ..rest] => if pred(x) { drop_while(rest, pred) } else { chs }
  }

// readline/bash-style Ctrl-w (`unix-word-rubout`): the column one
// whitespace-delimited word back from `col` — skip trailing whitespace,
// then skip the trailing run of non-whitespace chars.
fun word_back_col(line: string, col: int) : int {
  let prefix   = reverse(chars(line[0:col]))
  let no_space = drop_while(prefix, is_space_char)
  let no_word  = drop_while(no_space, (c) => !is_space_char(c))
  length(no_word)
}

// Meta-f/Meta-d word-forward boundary: the column one whitespace-
// delimited word forward from `col` — skip leading whitespace, then
// skip the following run of non-whitespace chars. Single-line only,
// same simplification as `word_back_col` (a no-op at end of line).
fun word_forward_col(line: string, col: int) : int {
  let suffix     = chars(line[col:])
  let no_space   = drop_while(suffix, is_space_char)
  let no_word    = drop_while(no_space, (c) => !is_space_char(c))
  col + (length(suffix) - length(no_word))
}

// Ctrl-w: the word-back text that gets killed, without yet applying it.
pub fun kill_word_back_text(state: EditorState) : string {
  let buf     = state.buffer
  let cur     = head_cursor(buf)
  let line    = list_get(buf.lines, cur.pos.line, "")
  let new_col = word_back_col(line, cur.pos.col)
  line[new_col:cur.pos.col]
}

// Ctrl-w: remove the whitespace-delimited word before the cursor,
// moving the cursor to the start of the removed span.
pub fun delete_word_back(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let line_idx = cur.pos.line
  let col      = cur.pos.col
  let line     = list_get(buf.lines, line_idx, "")
  let new_col  = word_back_col(line, col)
  let updated  = line[0:new_col] + line[col:]
  let new_lines   = list_set(buf.lines, line_idx, updated)
  let new_cursors = map(buf.cursors, (cc) =>
    Cursor { ...cc, pos: Position { line: line_idx, col: new_col } })
  let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: new_cursors, is_dirty: true }
  EditorState { ...state, buffer: new_buf }
}

// Meta-b: move the cursor one whitespace-delimited word back.
pub fun move_word_back(state: EditorState) : EditorState {
  let buf     = state.buffer
  let cur     = head_cursor(buf)
  let ln      = list_get(buf.lines, cur.pos.line, "")
  let new_col = word_back_col(ln, cur.pos.col)
  let new_cursors = map(buf.cursors, (cc) =>
    Cursor { ...cc, pos: Position { line: cur.pos.line, col: new_col } })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

// Meta-f: move the cursor one whitespace-delimited word forward.
pub fun move_word_forward(state: EditorState) : EditorState {
  let buf     = state.buffer
  let cur     = head_cursor(buf)
  let ln      = list_get(buf.lines, cur.pos.line, "")
  let new_col = word_forward_col(ln, cur.pos.col)
  let new_cursors = map(buf.cursors, (cc) =>
    Cursor { ...cc, pos: Position { line: cur.pos.line, col: new_col } })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

// Meta-d: the word-forward text that gets killed, without yet applying it.
pub fun kill_word_forward_text(state: EditorState) : string {
  let buf     = state.buffer
  let cur     = head_cursor(buf)
  let ln      = list_get(buf.lines, cur.pos.line, "")
  let new_col = word_forward_col(ln, cur.pos.col)
  ln[cur.pos.col:new_col]
}

// Meta-d: remove the whitespace-delimited word after the cursor. The
// cursor column is unchanged (still valid at the truncation point).
pub fun delete_word_forward(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let line_idx = cur.pos.line
  let col      = cur.pos.col
  let ln       = list_get(buf.lines, line_idx, "")
  let new_col  = word_forward_col(ln, col)
  let updated  = ln[0:col] + ln[new_col:]
  let new_lines = list_set(buf.lines, line_idx, updated)
  let new_buf   = TextBuffer { ...buf, lines: new_lines, is_dirty: true }
  EditorState { ...state, buffer: new_buf }
}

// Meta-l: the entire current line's text, without yet applying the kill.
pub fun kill_whole_line_text(state: EditorState) : string {
  let buf = state.buffer
  list_get(buf.lines, head_cursor(buf).pos.line, "")
}

// Meta-l: clear the current line's content, cursor moves to column 0.
// Unlike `kill_line` (Ctrl-k, cursor to end-of-line) this always wipes
// the whole line regardless of cursor position; the line itself stays
// (an empty line), it isn't removed from the buffer.
pub fun kill_whole_line(state: EditorState) : EditorState {
  let buf      = state.buffer
  let line_idx = head_cursor(buf).pos.line
  let new_lines   = list_set(buf.lines, line_idx, "")
  let new_cursors = map(buf.cursors, (cc) =>
    Cursor { ...cc, pos: Position { line: line_idx, col: 0 } })
  let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: new_cursors, is_dirty: true }
  EditorState { ...state, buffer: new_buf }
}

// ------------------- multi-buffer navigation (M5.5) ----------------------
//
// `EditorState.buffer` is always the active buffer; `background_buffers`
// is the rest of the open buffers, held as a rotation ring. Cycling
// forward/backward just rotates the ring — there is no separate active
// index to keep in sync (see model.hc's EditorState doc comment).

// Push the current active buffer to a fresh, empty scratch buffer,
// which becomes the new active buffer. Pure — this only ever creates an
// in-memory buffer; opening a file from disk needs a path-prompt input
// widget that doesn't exist yet (see docs/effects-journal.md M5.5
// non-goals).
pub fun new_buffer_action(state: EditorState) : EditorState {
  let bid = state.next_bid
  EditorState {
    ...state,
    buffer: new_buffer(bid, None),
    background_buffers: state.background_buffers + [state.buffer],
    next_bid: bid + 1
  }
}

// Rotate the ring forward: the first background buffer becomes active,
// the old active buffer moves to the back. No-op with 0 or 1 open buffers.
pub fun cycle_next_buffer(state: EditorState) : EditorState =>
  match state.background_buffers {
    []          => state,
    [x, ..rest] => EditorState { ...state, buffer: x, background_buffers: rest + [state.buffer] }
  }

// Rotate the ring backward: the *last* background buffer becomes active,
// the old active buffer moves to the front. No-op with 0 or 1 open buffers.
pub fun cycle_prev_buffer(state: EditorState) : EditorState =>
  match reverse(state.background_buffers) {
    []          => state,
    [x, ..rest] => EditorState { ...state, buffer: x, background_buffers: [state.buffer] + reverse(rest) }
  }

// Drop the active buffer and promote the first background buffer in its
// place. Never closes the last remaining buffer — hedit always keeps at
// least one open buffer, so this is a status-message no-op instead.
pub fun close_buffer_action(state: EditorState) : EditorState =>
  match state.background_buffers {
    []          => set_status_message(state, "Can't close the last buffer"),
    [x, ..rest] => EditorState { ...state, buffer: x, background_buffers: rest }
  }

// ------------------- Save-As / Open prompt (M9 + Stage 1 readline) -------
//
// A minimal single-line input widget. Only one prompt is ever active at a
// time (`EditorState.prompt`); `resolve_action` routes every `KeyEvent` to
// the Prompt* actions below while a prompt is active, instead of the
// normal Insert/Enter/Backspace dispatch. Submitting (`PromptSubmit`) needs
// `<fsys>`, so it stays a no-op here and is handled in `runtime.hc`.
//
// `Prompt`'s `cursor` field (Stage 1) is the column within `text` where
// typing/deletion happens — it lets the readline-style Ctrl-a/e/b/f/d/k
// chords work inside the prompt the same way they do in the main buffer,
// instead of only ever appending at the end of the typed text.

// The text typed so far, regardless of which prompt variant is active.
fun prompt_text(p: Prompt) : string =>
  match p {
    NoPrompt           => "",
    SaveAsPrompt(t, _) => t,
    OpenPrompt(t, _)   => t
  }

// The cursor column within the prompt's typed text.
fun prompt_cursor(p: Prompt) : int =>
  match p {
    NoPrompt           => 0,
    SaveAsPrompt(_, c) => c,
    OpenPrompt(_, c)   => c
  }

// Rebuild `p` with new text + cursor, preserving its variant. A
// `NoPrompt` stays `NoPrompt` — there's nothing to type into.
fun with_prompt(p: Prompt, t: string, c: int) : Prompt =>
  match p {
    NoPrompt           => NoPrompt,
    SaveAsPrompt(_, _) => SaveAsPrompt(t, c),
    OpenPrompt(_, _)   => OpenPrompt(t, c)
  }

// Insert `c` at the prompt's cursor column, advancing the cursor by one.
pub fun prompt_insert_char(state: EditorState, c: char) : EditorState {
  let p   = state.prompt
  let t   = prompt_text(p)
  let col = prompt_cursor(p)
  let new_t = t[0:col] + char_to_string(c) + t[col:]
  EditorState { ...state, prompt: with_prompt(p, new_t, col + 1) }
}

// Delete the char before the prompt's cursor. No-op at column 0.
pub fun prompt_backspace(state: EditorState) : EditorState {
  let p   = state.prompt
  let t   = prompt_text(p)
  let col = prompt_cursor(p)
  if col > 0 {
    let new_t = t[0:col - 1] + t[col:]
    EditorState { ...state, prompt: with_prompt(p, new_t, col - 1) }
  } else {
    state
  }
}

pub fun prompt_cancel(state: EditorState) : EditorState =>
  EditorState { ...state, prompt: NoPrompt }

// Ctrl-a inside a prompt: move the cursor to column 0.
pub fun prompt_move_start(state: EditorState) : EditorState {
  let p = state.prompt
  EditorState { ...state, prompt: with_prompt(p, prompt_text(p), 0) }
}

// Ctrl-e inside a prompt: move the cursor to the end of the typed text.
pub fun prompt_move_end(state: EditorState) : EditorState {
  let p = state.prompt
  let t = prompt_text(p)
  EditorState { ...state, prompt: with_prompt(p, t, length(t)) }
}

// Ctrl-b inside a prompt: move the cursor left one column.
pub fun prompt_move_left(state: EditorState) : EditorState {
  let p   = state.prompt
  let col = prompt_cursor(p)
  EditorState { ...state, prompt: with_prompt(p, prompt_text(p), max(col - 1, 0)) }
}

// Ctrl-f inside a prompt: move the cursor right one column.
pub fun prompt_move_right(state: EditorState) : EditorState {
  let p   = state.prompt
  let t   = prompt_text(p)
  let col = prompt_cursor(p)
  EditorState { ...state, prompt: with_prompt(p, t, min(col + 1, length(t))) }
}

// Ctrl-d inside a prompt: delete the char under the cursor. No-op at
// the end of the typed text.
pub fun prompt_delete_forward(state: EditorState) : EditorState {
  let p   = state.prompt
  let t   = prompt_text(p)
  let col = prompt_cursor(p)
  if col < length(t) {
    let new_t = t[0:col] + t[col + 1:]
    EditorState { ...state, prompt: with_prompt(p, new_t, col) }
  } else {
    state
  }
}

// Ctrl-k inside a prompt: the text from the cursor to the end — what
// gets killed (added to the clipboard) without yet applying it.
pub fun prompt_kill_text(state: EditorState) : string {
  let p = state.prompt
  prompt_text(p)[prompt_cursor(p):]
}

// Ctrl-k inside a prompt: truncate the typed text at the cursor.
pub fun prompt_truncate(state: EditorState) : EditorState {
  let p   = state.prompt
  let t   = prompt_text(p)
  let col = prompt_cursor(p)
  EditorState { ...state, prompt: with_prompt(p, t[0:col], col) }
}

// `Ctrl-o` (default binding): open the "open file" prompt with empty text.
pub fun open_file_prompt(state: EditorState) : EditorState =>
  EditorState { ...state, prompt: OpenPrompt("", 0) }

// ------------------- Event → Action resolution ---------------------------

// Turn a raw `Event` into a semantic `Action` using the bindings currently
// installed on `state.config`. Pure: no I/O, no hardcoded chord names.
//
// While a prompt is active every `KeyEvent` routes to one of the four
// Prompt* actions instead of the normal Insert/Enter/Backspace dispatch —
// `Esc` cancels, `Enter` submits, everything else edits the prompt text.
// `Ctrl-q` still quits even mid-prompt: it's the same synthetic event a
// closed/EOF'd stdin decodes to (see `keys.hc::decode_key`), so treating
// it as an ordinary ignored shortcut would spin `event_loop` forever
// re-reading EOF instead of exiting. `ResizeEvent` still resizes so a
// terminal resize while typing a filename doesn't get swallowed.
//
// Stage 1 (docs/new-keybindings.txt): the same readline cursor/kill
// chords bound in the main buffer (Ctrl-a/e/b/f/d/k) also work while a
// prompt is active, routed to their Prompt* counterparts instead of the
// TextBuffer ones.
fun resolve_prompt_action(evt: Event) : Action =>
  match evt {
    KeyEvent(KChar(c))            => PromptChar(c),
    KeyEvent(KSpecial(Enter))     => PromptSubmit,
    KeyEvent(KSpecial(Backspace)) => PromptBackspace,
    KeyEvent(KSpecial(Esc))       => PromptCancel,
    KeyEvent(KShortcut(Ctrl, 'q')) => Quit,
    KeyEvent(KShortcut(Ctrl, 'a')) => PromptMoveStart,
    KeyEvent(KShortcut(Ctrl, 'e')) => PromptMoveEnd,
    KeyEvent(KShortcut(Ctrl, 'b')) => PromptMoveLeft,
    KeyEvent(KShortcut(Ctrl, 'f')) => PromptMoveRight,
    KeyEvent(KShortcut(Ctrl, 'd')) => PromptDeleteForward,
    KeyEvent(KShortcut(Ctrl, 'k')) => PromptKillLine,
    ResizeEvent(w, h)             => Resize(w, h),
    _                             => Ignore
  }

// While the help overlay (M10, `ToggleHelp`) is showing, every key closes
// it again — same defensive carve-outs as `resolve_prompt_action`:
// `Ctrl-q` still quits (synthetic EOF-quit event) and resize still resizes.
// The catch-all only matches `KeyEvent` — the periodic `Tick` (idle-poll
// timeout, see keys.hc) must resolve to `Ignore`, or the help overlay
// closes itself on the very next tick, before the user can read it.
fun resolve_help_action(evt: Event) : Action =>
  match evt {
    KeyEvent(KShortcut(Ctrl, 'q')) => Quit,
    ResizeEvent(w, h)              => Resize(w, h),
    KeyEvent(_)                    => ToggleHelp,
    _                              => Ignore
  }

// Priority: KChar always inserts, ResizeEvent always resizes; Enter/
// Backspace/arrows are fixed (not user-remappable — they have no `char`
// payload to key a binding on); only KShortcuts pass through the
// user-configurable binding table. Unbound shortcuts resolve to `Ignore`
// — event_loop then no-ops.
fun resolve_normal_action(state: EditorState, evt: Event) : Action =>
  match evt {
    KeyEvent(KChar(c))              => Insert(c),
    KeyEvent(KSpecial(Enter))       => NewLine,
    KeyEvent(KSpecial(Backspace))   => DeleteBackward,
    KeyEvent(KSpecial(ArrowUp))     => MoveUp,
    KeyEvent(KSpecial(ArrowDown))   => MoveDown,
    KeyEvent(KSpecial(ArrowLeft))   => MoveLeft,
    KeyEvent(KSpecial(ArrowRight))  => MoveRight,
    KeyEvent(KShortcut(m, c)) =>
      lookup_binding(state.config.bindings, KeyChord { m: m, c: c }),
    ResizeEvent(w, h)         => Resize(w, h),
    _                         => Ignore
  }

// Turn a raw `Event` into a semantic `Action`. Checks `state.prompt` first
// (M9) — a `SaveAsPrompt`/`OpenPrompt` in progress takes over every
// keystroke until it's submitted or cancelled.
pub fun resolve_action(state: EditorState, evt: Event) : Action {
  if state.show_help {
    resolve_help_action(evt)
  } else {
    match state.prompt {
      NoPrompt => resolve_normal_action(state, evt),
      _        => resolve_prompt_action(evt)
    }
  }
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
    NewLine        => insert_newline(state),
    DeleteBackward => delete_backward(state),
    DeleteForward  => delete_forward(state),
    MoveUp         => move_up(state),
    MoveDown     => move_down(state),
    MoveLeft     => move_left(state),
    MoveRight    => move_right(state),
    MoveLineStart => move_line_start(state),
    MoveLineEnd   => move_line_end(state),
    MoveWordForward => move_word_forward(state),
    MoveWordBack    => move_word_back(state),
    Resize(w, h) => EditorState { ...state, screen_size: (w, h) },
    Save         => state, // handled in event_loop; no-op here for purity
    Copy         => state, // handled in event_loop; needs <Clipboard>
    Paste        => state, // handled in event_loop; needs <Clipboard>
    Undo         => state, // handled in event_loop; needs <Buffer>
    Redo         => state, // handled in event_loop; needs <Buffer>
    KillLine       => state, // handled in event_loop; needs <Clipboard>
    KillWordBack   => state, // handled in event_loop; needs <Clipboard>
    KillWordForward => state, // handled in event_loop; needs <Clipboard>
    KillWholeLine   => state, // handled in event_loop; needs <Clipboard>
    NewBuffer    => new_buffer_action(state),
    NextBuffer   => cycle_next_buffer(state),
    PrevBuffer   => cycle_prev_buffer(state),
    CloseBuffer  => close_buffer_action(state),
    OpenFile     => open_file_prompt(state),
    PromptChar(c)   => prompt_insert_char(state, c),
    PromptBackspace => prompt_backspace(state),
    PromptCancel    => prompt_cancel(state),
    PromptSubmit    => state, // handled in event_loop; needs <fsys>
    PromptMoveStart     => prompt_move_start(state),
    PromptMoveEnd       => prompt_move_end(state),
    PromptMoveLeft      => prompt_move_left(state),
    PromptMoveRight     => prompt_move_right(state),
    PromptDeleteForward => prompt_delete_forward(state),
    PromptKillLine      => state, // handled in event_loop; needs <Clipboard>
    ToggleHelp      => EditorState { ...state, show_help: !state.show_help },
    Ignore       => state
  }

// ------------------- pure event dispatcher ------------------------------

// Convenience combinator: resolve + apply in one call. Used by callers
// that don't need to inspect the intermediate `Action` (all pure paths).
pub fun handle_action(state: EditorState, evt: Event) : EditorState =>
  apply_action(state, resolve_action(state, evt))
