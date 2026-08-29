/// Pure event -> state transitions: `resolve_action` turns a raw Event
/// into a semantic Action (consulting `state.config.bindings` so users
/// can remap Ctrl-/Alt-shortcuts from a HiLisp `init.hl`, M4), and
/// `apply_action` turns an Action into the next EditorState. Only pure
/// actions live here; effectful ones (`Save`, which needs `<fsys>`) are
/// dispatched by `event_loop` in `runtime.hc`.

import "keys"
import "model"

// ------------------- list helpers (pure, index-safe) ---------------------

/// Return a copy of `xs` with the element at `idx` replaced by `new_val`.
fun list_set(xs: list<string>, idx: int, new_val: string) : list<string> =>
  match xs {
    []          => [],
    [x, ..rest] =>
      if idx == 0 { [new_val] + rest }
      else { [x] + list_set(rest, idx - 1, new_val) }
  }

/// Return the element of `xs` at `idx`, or `default` if out of range.
fun list_get(xs: list<string>, idx: int, default: string) : string =>
  match xs {
    []          => default,
    [x, ..rest] =>
      if idx == 0 { x }
      else { list_get(rest, idx - 1, default) }
  }

/// Return a copy of `xs` with the element at `idx` replaced by two
/// elements `a` and `b`.
fun list_split_at(xs: list<string>, idx: int, a: string, b: string) : list<string> =>
  match xs {
    []          => [],
    [x, ..rest] =>
      if idx == 0 { [a, b] + rest }
      else { [x] + list_split_at(rest, idx - 1, a, b) }
  }

/// Return a copy of `xs` with the element at `idx` removed.
fun list_remove_at(xs: list<string>, idx: int) : list<string> =>
  match xs {
    []          => [],
    [x, ..rest] =>
      if idx == 0 { rest }
      else { [x] + list_remove_at(rest, idx - 1) }
  }

// ------------------- cursor + edit helpers -------------------------------

/// Return the buffer's primary cursor (multi-cursor is future work),
/// defaulting to (0, 0) if the buffer has none.
fun head_cursor(buf: TextBuffer) : Cursor =>
  match buf.cursors {
    []       => Cursor { cid: 0, pos: Position { line: 0, col: 0 } },
    [x, .._] => x
  }

/// Clamp `col` to a valid column within the line at `line_idx`.
fun clamp_col(lines: list<string>, line_idx: int, col: int) : int {
  let line_len = length(list_get(lines, line_idx, ""))
  max(min(col, line_len), 0)
}

/// Insert `c` at the cursor's column and advance the cursor by one.
// Simplification: only the primary cursor is used; true multi-cursor
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

/// Split the current line at the cursor into two lines, cursor moves
/// to column 0 of the new (second) line.
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

/// Move the cursor to column 0 of its current line.
pub fun move_line_start(state: EditorState) : EditorState {
  let buf = state.buffer
  let cur = head_cursor(buf)
  let new_pos = Position { line: cur.pos.line, col: 0 }
  let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: new_pos })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

/// Move the cursor to the end of its current line.
pub fun move_line_end(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let line_len = length(list_get(buf.lines, cur.pos.line, ""))
  let new_pos  = Position { line: cur.pos.line, col: line_len }
  let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: new_pos })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

/// Delete the char before the cursor, merging with the previous line
/// at column 0. A no-op at the very start of the buffer.
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

/// Delete the char under the cursor, merging the next line up into
/// this one at the end of a non-last line. A no-op at the very end of
/// the buffer.
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

/// Move the cursor left one column, wrapping onto the end of the
/// previous line at a line boundary.
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

/// Move the cursor right one column, wrapping onto the start of the
/// next line at a line boundary.
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

/// Move the cursor up one line, clamping the column to the target
/// line's length rather than tracking a "sticky" column.
pub fun move_up(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let new_line = max(cur.pos.line - 1, 0)
  let new_pos  = Position { line: new_line, col: clamp_col(buf.lines, new_line, cur.pos.col) }
  let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: new_pos })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

/// Move the cursor down one line, clamping the column to the target
/// line's length rather than tracking a "sticky" column.
pub fun move_down(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let n_lines  = length(buf.lines)
  let new_line = min(cur.pos.line + 1, n_lines - 1)
  let new_pos  = Position { line: new_line, col: clamp_col(buf.lines, new_line, cur.pos.col) }
  let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: new_pos })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

/// Return the text of the cursor's current line, or "" if the buffer
/// has no cursors or no lines.
pub fun current_line(state: EditorState) : string {
  let buf = state.buffer
  list_get(buf.lines, head_cursor(buf).pos.line, "")
}

/// Append `text` to the end of the cursor's line and advance the
/// cursor by `length(text)`.
// No multi-line splitting: an embedded '\n' (e.g. from the clipboard)
// is inserted as a literal two-char sequence, not a new line.
pub fun paste_text(state: EditorState, text: string) : EditorState {
  let buf = state.buffer
  let cur = head_cursor(buf)
  let line_idx  = cur.pos.line
  let current   = list_get(buf.lines, line_idx, "")
  let updated   = current + text
  let new_lines = list_set(buf.lines, line_idx, updated)
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
// Reuses the same Clipboard sink as Copy/Paste (Ctrl-y/yank is Paste bound
// to a second chord, see default_bindings — there's no separate kill-ring).
// Each kill is split into a text getter (what would be killed) and a state
// mutator, so event_loop can hand the text to set_selection before applying
// the truncation.

/// Return the text from the cursor to the end of the current line.
pub fun kill_line_text(state: EditorState) : string {
  let buf  = state.buffer
  let cur  = head_cursor(buf)
  let line = list_get(buf.lines, cur.pos.line, "")
  line[cur.pos.col: ]
}

/// Truncate the current line at the cursor.
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

/// Return whether `c` is a space or tab character.
fun is_space_char(c: char) : bool => c == ' ' || char_to_string(c) == "\t"

/// Return the suffix of `chs` after dropping the leading run of
/// elements matching `pred`.
fun drop_while(chs: list<char>, pred: (char) -> bool) : list<char> =>
  match chs {
    []          => [],
    [x, ..rest] => if pred(x) { drop_while(rest, pred) } else { chs }
  }

/// Return the column one whitespace-delimited word back from `col`
/// (readline/bash-style `unix-word-rubout`).
fun word_back_col(line: string, col: int) : int {
  let prefix   = reverse(chars(line[0:col]))
  let no_space = drop_while(prefix, is_space_char)
  let no_word  = drop_while(no_space, (c) => !is_space_char(c))
  length(no_word)
}

/// Return the column one whitespace-delimited word forward from `col`.
// Single-line only: a no-op at the end of the line.
fun word_forward_col(line: string, col: int) : int {
  let suffix     = chars(line[col: ])
  let no_space   = drop_while(suffix, is_space_char)
  let no_word    = drop_while(no_space, (c) => !is_space_char(c))
  col + (length(suffix) - length(no_word))
}

/// Return the whitespace-delimited word before the cursor.
pub fun kill_word_back_text(state: EditorState) : string {
  let buf     = state.buffer
  let cur     = head_cursor(buf)
  let line    = list_get(buf.lines, cur.pos.line, "")
  let new_col = word_back_col(line, cur.pos.col)
  line[new_col: cur.pos.col]
}

/// Delete the whitespace-delimited word before the cursor, moving the
/// cursor to the start of the removed span.
pub fun delete_word_back(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let line_idx = cur.pos.line
  let col      = cur.pos.col
  let line     = list_get(buf.lines, line_idx, "")
  let new_col  = word_back_col(line, col)
  let updated  = line[0:new_col] + line[col: ]
  let new_lines   = list_set(buf.lines, line_idx, updated)
  let new_cursors = map(buf.cursors, (cc) =>
    Cursor { ...cc, pos: Position { line: line_idx, col: new_col } })
  let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: new_cursors, is_dirty: true }
  EditorState { ...state, buffer: new_buf }
}

/// Move the cursor one whitespace-delimited word back.
pub fun move_word_back(state: EditorState) : EditorState {
  let buf     = state.buffer
  let cur     = head_cursor(buf)
  let ln      = list_get(buf.lines, cur.pos.line, "")
  let new_col = word_back_col(ln, cur.pos.col)
  let new_cursors = map(buf.cursors, (cc) =>
    Cursor { ...cc, pos: Position { line: cur.pos.line, col: new_col } })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

/// Move the cursor one whitespace-delimited word forward.
pub fun move_word_forward(state: EditorState) : EditorState {
  let buf     = state.buffer
  let cur     = head_cursor(buf)
  let ln      = list_get(buf.lines, cur.pos.line, "")
  let new_col = word_forward_col(ln, cur.pos.col)
  let new_cursors = map(buf.cursors, (cc) =>
    Cursor { ...cc, pos: Position { line: cur.pos.line, col: new_col } })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

/// Return the whitespace-delimited word after the cursor.
pub fun kill_word_forward_text(state: EditorState) : string {
  let buf     = state.buffer
  let cur     = head_cursor(buf)
  let ln      = list_get(buf.lines, cur.pos.line, "")
  let new_col = word_forward_col(ln, cur.pos.col)
  ln[cur.pos.col: new_col]
}

/// Delete the whitespace-delimited word after the cursor. The cursor
/// column is unchanged (still valid at the truncation point).
pub fun delete_word_forward(state: EditorState) : EditorState {
  let buf      = state.buffer
  let cur      = head_cursor(buf)
  let line_idx = cur.pos.line
  let col      = cur.pos.col
  let ln       = list_get(buf.lines, line_idx, "")
  let new_col  = word_forward_col(ln, col)
  let updated  = ln[0:col] + ln[new_col: ]
  let new_lines = list_set(buf.lines, line_idx, updated)
  let new_buf   = TextBuffer { ...buf, lines: new_lines, is_dirty: true }
  EditorState { ...state, buffer: new_buf }
}

/// Return the full text of the cursor's current line.
pub fun kill_whole_line_text(state: EditorState) : string {
  let buf = state.buffer
  list_get(buf.lines, head_cursor(buf).pos.line, "")
}

/// Clear the current line's content; the line itself stays (an empty
/// line, not removed from the buffer). Cursor moves to column 0.
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
// `state.buffer` is always active; `background_buffers` is the rest of
// the open buffers as a rotation ring, with no separate active index to
// keep in sync (see model.hc's EditorState doc comment).

/// Push the active buffer onto the background ring and make a fresh,
/// empty scratch buffer active.
// Pure: opening a file from disk needs a path-prompt input widget (M9).
pub fun new_buffer_action(state: EditorState) : EditorState {
  let bid = state.next_bid
  EditorState {
    ...state,
    buffer: new_buffer(bid, None),
    background_buffers: state.background_buffers + [state.buffer],
    next_bid: bid + 1
  }
}

/// Rotate to the next open buffer. A no-op with 0 or 1 open buffers.
pub fun cycle_next_buffer(state: EditorState) : EditorState =>
  match state.background_buffers {
    []          => state,
    [x, ..rest] => EditorState { ...state, buffer: x, background_buffers: rest + [state.buffer] }
  }

/// Rotate to the previous open buffer. A no-op with 0 or 1 open buffers.
pub fun cycle_prev_buffer(state: EditorState) : EditorState =>
  match reverse(state.background_buffers) {
    []          => state,
    [x, ..rest] => EditorState { ...state, buffer: x, background_buffers: [state.buffer] + reverse(rest) }
  }

/// Close the active buffer and activate the next background buffer.
// hedit always keeps at least one open buffer, so closing the last one
// is a status-message no-op instead.
pub fun close_buffer_action(state: EditorState) : EditorState =>
  match state.background_buffers {
    []          => set_status_message(state, "Can't close the last buffer"),
    [x, ..rest] => EditorState { ...state, buffer: x, background_buffers: rest }
  }

// ------------------- Save-As / Open prompt (M9 + Stage 1 readline) -------
// A minimal single-line input widget. Only one prompt is ever active at a
// time (`EditorState.prompt`); `resolve_action` routes every `KeyEvent` to
// the Prompt* actions below while a prompt is active. `PromptSubmit` needs
// `<fsys>` so it's a no-op here, handled in `runtime.hc`. `Prompt`'s
// `cursor` field is the column within `text` where typing/deletion
// happens, letting readline-style Ctrl-a/e/b/f/d/k chords work inside the
// prompt the same way they do in the main buffer.

/// Return the text typed so far in `p`.
fun prompt_text(p: Prompt) : string =>
  match p {
    NoPrompt           => "",
    SaveAsPrompt(t, _) => t,
    OpenPrompt(t, _)   => t,
    FindPrompt(t, _)   => t
  }

/// Return the cursor column within `p`'s typed text.
fun prompt_cursor(p: Prompt) : int =>
  match p {
    NoPrompt           => 0,
    SaveAsPrompt(_, c) => c,
    OpenPrompt(_, c)   => c,
    FindPrompt(_, c)   => c
  }

/// Return a copy of `p` with updated text and cursor column,
/// preserving its variant.
fun with_prompt(p: Prompt, t: string, c: int) : Prompt =>
  match p {
    NoPrompt           => NoPrompt,
    SaveAsPrompt(_, _) => SaveAsPrompt(t, c),
    OpenPrompt(_, _)   => OpenPrompt(t, c),
    FindPrompt(_, _)   => FindPrompt(t, c)
  }

/// Insert `c` at the prompt's cursor column, advancing the cursor by one.
pub fun prompt_insert_char(state: EditorState, c: char) : EditorState {
  let p   = state.prompt
  let t   = prompt_text(p)
  let col = prompt_cursor(p)
  let new_t = t[0:col] + char_to_string(c) + t[col: ]
  EditorState { ...state, prompt: with_prompt(p, new_t, col + 1) }
}

/// Delete the char before the prompt's cursor. A no-op at column 0.
pub fun prompt_backspace(state: EditorState) : EditorState {
  let p   = state.prompt
  let t   = prompt_text(p)
  let col = prompt_cursor(p)
  if col > 0 {
    let new_t = t[0:col - 1] + t[col: ]
    EditorState { ...state, prompt: with_prompt(p, new_t, col - 1) }
  } else {
    state
  }
}

/// Dismiss the active prompt.
pub fun prompt_cancel(state: EditorState) : EditorState =>
  EditorState { ...state, prompt: NoPrompt }

/// Move the prompt's cursor to column 0.
pub fun prompt_move_start(state: EditorState) : EditorState {
  let p = state.prompt
  EditorState { ...state, prompt: with_prompt(p, prompt_text(p), 0) }
}

/// Move the prompt's cursor to the end of the typed text.
pub fun prompt_move_end(state: EditorState) : EditorState {
  let p = state.prompt
  let t = prompt_text(p)
  EditorState { ...state, prompt: with_prompt(p, t, length(t)) }
}

/// Move the prompt's cursor left one column.
pub fun prompt_move_left(state: EditorState) : EditorState {
  let p   = state.prompt
  let col = prompt_cursor(p)
  EditorState { ...state, prompt: with_prompt(p, prompt_text(p), max(col - 1, 0)) }
}

/// Move the prompt's cursor right one column.
pub fun prompt_move_right(state: EditorState) : EditorState {
  let p   = state.prompt
  let t   = prompt_text(p)
  let col = prompt_cursor(p)
  EditorState { ...state, prompt: with_prompt(p, t, min(col + 1, length(t))) }
}

/// Delete the char under the prompt's cursor. A no-op at the end of
/// the typed text.
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

/// Return the prompt's typed text from the cursor to the end.
pub fun prompt_kill_text(state: EditorState) : string {
  let p = state.prompt
  prompt_text(p)[prompt_cursor(p): ]
}

/// Truncate the prompt's typed text at the cursor.
pub fun prompt_truncate(state: EditorState) : EditorState {
  let p   = state.prompt
  let t   = prompt_text(p)
  let col = prompt_cursor(p)
  EditorState { ...state, prompt: with_prompt(p, t[0:col], col) }
}

/// Open the "open file" prompt with empty text.
pub fun open_file_prompt(state: EditorState) : EditorState =>
  EditorState { ...state, prompt: OpenPrompt("", 0) }

// ------------------- Find (M12) --------------------------------------------
// Ctrl-f opens `FindPrompt`; every keystroke re-scans the whole buffer for
// `query` (plain substring, case-sensitive) via `find_all_matches`, so the
// highlight set `render.hc` paints is always current. Ctrl-Right/Ctrl-Left
// (`FindNext`/`FindPrev`, decoded from synthetic codes 1010/1011 in
// `keys.hc`) walk `matches` in document order relative to the cursor,
// wrapping at either end, and work whether the prompt is still open or was
// already closed by Enter — only Esc (`PromptCancel`) drops the search
// entirely.

/// Return the element of `xs` at `idx`, or `default` if out of range —
/// same shape as `list_get`, specialised to `SearchMatch`.
fun match_get(xs: list<SearchMatch>, idx: int, default: SearchMatch) : SearchMatch =>
  match xs {
    []          => default,
    [x, ..rest] =>
      if idx == 0 { x }
      else { match_get(rest, idx - 1, default) }
  }

/// Every match of `query` within a single line, scanning forward from
/// `from_col` (non-overlapping — the next scan starts right after each
/// match ends). Assumes `query` is non-empty (checked by the caller).
fun find_in_line(line: string, query: string, line_idx: int, from_col: int) : list<SearchMatch> =>
  if from_col > length(line) { [] }
  else {
    match index_of(line[from_col: ], query) {
      None => [],
      Some(rel) => {
        let col = from_col + rel
        [SearchMatch { line: line_idx, col: col }] + find_in_line(line, query, line_idx, col + length(query))
      }
    }
  }

/// Every match of `query` across `lines`, in document order.
fun find_all_matches_go(lines: list<string>, query: string, line_idx: int) : list<SearchMatch> =>
  match lines {
    []          => [],
    [l, ..rest] => find_in_line(l, query, line_idx, 0) + find_all_matches_go(rest, query, line_idx + 1)
  }

/// Every match of `query` across `lines`, in document order. An empty
/// `query` yields no matches (nothing to highlight yet).
pub fun find_all_matches(lines: list<string>, query: string) : list<SearchMatch> =>
  if query == "" { [] } else { find_all_matches_go(lines, query, 0) }

/// Open the find prompt with an empty query and a fresh search state
/// (Ctrl-f) — discards whatever search was previously active.
pub fun start_find(state: EditorState) : EditorState =>
  EditorState { ...state, prompt: FindPrompt("", 0), search: ActiveSearch("", [], -1) }

/// Re-scan the buffer for the query currently typed into an active
/// `FindPrompt`, refreshing `state.search`'s matches. A no-op outside
/// `FindPrompt` (other prompts don't touch `search`).
fun refresh_find_matches(state: EditorState) : EditorState =>
  match state.prompt {
    FindPrompt(q, _) => EditorState { ...state, search: ActiveSearch(q, find_all_matches(state.buffer.lines, q), -1) },
    _                => state
  }

/// `true` if match `m` sits strictly before `pos` in document order.
fun pos_before(m: SearchMatch, pos: Position) : bool =>
  m.line < pos.line || (m.line == pos.line && m.col < pos.col)

/// `true` if match `m` sits strictly after `pos` in document order.
fun pos_after(m: SearchMatch, pos: Position) : bool =>
  m.line > pos.line || (m.line == pos.line && m.col > pos.col)

/// Index of the first match strictly after `pos`, or `None` if every
/// match is at or before it (caller wraps to the first match).
fun first_after(matches: list<SearchMatch>, pos: Position, idx: int) : maybe<int> =>
  match matches {
    []          => None,
    [m, ..rest] => if pos_after(m, pos) { Some(idx) } else { first_after(rest, pos, idx + 1) }
  }

/// Index of the last match strictly before `pos`, or `None` if every
/// match is at or after it (caller wraps to the last match).
fun last_before(matches: list<SearchMatch>, pos: Position, idx: int, acc: maybe<int>) : maybe<int> =>
  match matches {
    []          => acc,
    [m, ..rest] => if pos_before(m, pos) { last_before(rest, pos, idx + 1, Some(idx)) } else { last_before(rest, pos, idx + 1, acc) }
  }

/// The match index `find_next`/`find_prev` should jump to from `pos`:
/// `dir >= 0` walks forward (wrapping to index 0), `dir < 0` walks
/// backward (wrapping to the last index).
fun next_match_index(matches: list<SearchMatch>, pos: Position, dir: int) : int =>
  if dir >= 0 {
    match first_after(matches, pos, 0) {
      Some(i) => i,
      None    => 0
    }
  } else {
    match last_before(matches, pos, 0, None) {
      Some(i) => i,
      None    => max(length(matches) - 1, 0)
    }
  }

/// Move every cursor to `matches[idx]` and record it as `search.current`.
fun jump_to_match(state: EditorState, q: string, matches: list<SearchMatch>, idx: int) : EditorState {
  let m = match_get(matches, idx, SearchMatch { line: 0, col: 0 })
  let new_cursors = map(state.buffer.cursors, (cc) => Cursor { ...cc, pos: Position { line: m.line, col: m.col } })
  let new_buf = TextBuffer { ...state.buffer, cursors: new_cursors }
  EditorState { ...state, buffer: new_buf, search: ActiveSearch(q, matches, idx) }
}

/// `FindNext`/`FindPrev` (Ctrl-Right/Ctrl-Left): jump to the next/previous
/// match relative to the cursor, wrapping at either end. A no-op (with a
/// status message) when there's no active search or it has no matches.
fun jump_search(state: EditorState, dir: int) : EditorState =>
  match state.search {
    NoSearch => set_status_message(state, "No active search"),
    ActiveSearch(q, matches, _) =>
      match matches {
        [] => set_status_message(state, "No matches for \"" + q + "\""),
        _  => jump_to_match(state, q, matches, next_match_index(matches, head_cursor(state.buffer).pos, dir))
      }
  }

/// Jump to the next match after the cursor (wraps to the first match).
pub fun find_next(state: EditorState) : EditorState => jump_search(state, 1)

/// Jump to the previous match before the cursor (wraps to the last match).
pub fun find_prev(state: EditorState) : EditorState => jump_search(state, -1)

/// `FindPrompt` submit (Enter): close the prompt and jump to the next
/// match from the cursor, same as `FindNext` — leaves the search active
/// (and its highlights visible) so Ctrl-Right/Ctrl-Left keep working
/// after the bar closes.
pub fun submit_find(state: EditorState) : EditorState =>
  EditorState { ...find_next(state), prompt: NoPrompt }

/// Cancel the active prompt (Esc). Cancelling a `FindPrompt` also drops
/// the search entirely, clearing every highlight — other prompts are
/// unaffected (`search` stays whatever it already was, i.e. `NoSearch`).
pub fun cancel_prompt(state: EditorState) : EditorState =>
  match state.prompt {
    FindPrompt(_, _) => EditorState { ...prompt_cancel(state), search: NoSearch },
    _                => prompt_cancel(state)
  }

// ------------------- Event -> Action resolution ---------------------------

/// Resolve a raw event to an Action while a Save-As/Open prompt is active,
/// routing keystrokes to the Prompt* actions instead of the normal
/// Insert/Enter/Backspace dispatch.
// Ctrl-q still quits mid-prompt: it's the synthetic event decode_key emits
// for closed/EOF stdin (keys.hc), so ignoring it would spin event_loop
// forever re-reading EOF. Resize still resizes so it isn't swallowed while
// typing. Stage 1: readline cursor/kill chords (Ctrl-a/e/b/f/d/k) route to
// their Prompt* counterparts instead of the TextBuffer ones.
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
    KeyEvent(KCtrlSpecial(ArrowRight)) => FindNext,
    KeyEvent(KCtrlSpecial(ArrowLeft))  => FindPrev,
    ResizeEvent(w, h)             => Resize(w, h),
    _                             => Ignore
  }

/// Resolve a raw event to an Action while the help overlay (M10) is
/// showing: any key closes it again.
// Ctrl-q still quits and resize still resizes, same carve-outs as
// resolve_prompt_action. Tick (idle-poll timeout, keys.hc) must resolve to
// Ignore or the overlay closes itself on the next tick before it's read.
fun resolve_help_action(evt: Event) : Action =>
  match evt {
    KeyEvent(KShortcut(Ctrl, 'q')) => Quit,
    ResizeEvent(w, h)              => Resize(w, h),
    KeyEvent(_)                    => ToggleHelp,
    _                              => Ignore
  }

/// Resolve a raw event to an Action during normal editing, via
/// `state.config.bindings` for user-remappable shortcuts.
// Enter/Backspace/arrows are fixed (no `char` payload to key a binding
// on); only KShortcuts pass through the binding table. Unbound shortcuts
// resolve to Ignore.
fun resolve_normal_action(state: EditorState, evt: Event) : Action =>
  match evt {
    KeyEvent(KChar(c))              => Insert(c),
    KeyEvent(KSpecial(Enter))       => NewLine,
    KeyEvent(KSpecial(Backspace))   => DeleteBackward,
    KeyEvent(KSpecial(ArrowUp))     => MoveUp,
    KeyEvent(KSpecial(ArrowDown))   => MoveDown,
    KeyEvent(KSpecial(ArrowLeft))   => MoveLeft,
    KeyEvent(KSpecial(ArrowRight))  => MoveRight,
    KeyEvent(KCtrlSpecial(ArrowRight)) => FindNext,
    KeyEvent(KCtrlSpecial(ArrowLeft))  => FindPrev,
    KeyEvent(KShortcut(m, c)) =>
      lookup_binding(state.config.bindings, KeyChord { m: m, c: c }),
    ResizeEvent(w, h)         => Resize(w, h),
    _                         => Ignore
  }

/// Resolve a raw event to a semantic Action, dispatching by editor mode
/// (help overlay, active prompt, or normal editing).
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

// ------------------- Action -> EditorState apply -------------------------

/// Apply an Action to state, producing the next EditorState.
// Save/Copy/Paste/Undo/Redo/Kill*/PromptSubmit no-op here — they carry
// <fsys>/<Clipboard>/<Buffer> effects handled by event_loop, keeping this
// function total for tests and the HiLisp bridge.
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
    Save         => state, // event_loop: <fsys>
    Copy         => state, // event_loop: <Clipboard>
    Paste        => state, // event_loop: <Clipboard>
    Undo         => state, // event_loop: <Buffer>
    Redo         => state, // event_loop: <Buffer>
    KillLine       => state, // event_loop: <Clipboard>
    KillWordBack   => state, // event_loop: <Clipboard>
    KillWordForward => state, // event_loop: <Clipboard>
    KillWholeLine   => state, // event_loop: <Clipboard>
    NewBuffer    => new_buffer_action(state),
    NextBuffer   => cycle_next_buffer(state),
    PrevBuffer   => cycle_prev_buffer(state),
    CloseBuffer  => close_buffer_action(state),
    OpenFile     => open_file_prompt(state),
    PromptChar(c)   => refresh_find_matches(prompt_insert_char(state, c)),
    PromptBackspace => refresh_find_matches(prompt_backspace(state)),
    PromptCancel    => cancel_prompt(state),
    PromptSubmit    => match state.prompt { FindPrompt(_, _) => submit_find(state), _ => state }, // event_loop: <fsys> for Save/Open
    PromptMoveStart     => prompt_move_start(state),
    PromptMoveEnd       => prompt_move_end(state),
    PromptMoveLeft      => prompt_move_left(state),
    PromptMoveRight     => prompt_move_right(state),
    PromptDeleteForward => refresh_find_matches(prompt_delete_forward(state)),
    PromptKillLine      => state, // event_loop: <Clipboard>
    ToggleHelp      => EditorState { ...state, show_help: !state.show_help },
    StartFind    => start_find(state),
    FindNext     => find_next(state),
    FindPrev     => find_prev(state),
    Ignore       => state
  }

// ------------------- pure event dispatcher ------------------------------

/// Resolve and apply an event against state in one step.
pub fun handle_action(state: EditorState, evt: Event) : EditorState =>
  apply_action(state, resolve_action(state, evt))
