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
pub fun head_cursor(buf: TextBuffer) : Cursor =>
  match buf.cursors {
    []       => Cursor { cid: 0, pos: Position { line: 0, col: 0 }, anchor: None, anchor_sticky: false },
    [x, .._] => x
  }

// ------------------- multi-cursor sorting & shift helpers -----------------

fun pos_compare(p1:Position, p2:Position) : int {
  if p1.line < p2.line { -1 }
  else if p1.line > p2.line { 1 }
  else if p1.col < p2.col { -1 }
  else if p1.col > p2.col { 1 }
  else { 0 }
}

fun cursor_pos_gt(c1:Cursor, c2:Cursor) : bool =>
  pos_compare(c1.pos, c2.pos) > 0

fun cursor_pos_lt(c1:Cursor, c2:Cursor) : bool =>
  pos_compare(c1.pos, c2.pos) < 0

fun insert_cursor_desc(c: Cursor, cs: list<Cursor>) : list<Cursor> =>
  match cs {
    []          => [c],
    [x, ..rest] =>
      if cursor_pos_gt(c, x) { [c, x] + rest }
      else { [x] + insert_cursor_desc(c, rest) }
  }

fun sort_cursors_desc(cs: list<Cursor>) : list<Cursor> =>
  match cs {
    []          => [],
    [c, ..rest] => insert_cursor_desc(c, sort_cursors_desc(rest))
  }

fun insert_cursor_asc(c: Cursor, cs: list<Cursor>) : list<Cursor> =>
  match cs {
    []          => [c],
    [x, ..rest] =>
      if cursor_pos_lt(c, x) { [c, x] + rest }
      else { [x] + insert_cursor_asc(c, rest) }
  }

fun sort_cursors_asc(cs: list<Cursor>) : list<Cursor> =>
  match cs {
    []          => [],
    [c, ..rest] => insert_cursor_asc(c, sort_cursors_asc(rest))
  }

fun deduplicate_cursors(cs: list<Cursor>) : list<Cursor> =>
  match cs {
    []  => [],
    [c] => [c],
    [c1, c2, ..rest] =>
      if c1.pos.line == c2.pos.line && c1.pos.col == c2.pos.col {
        deduplicate_cursors([c1] + rest)
      } else {
        [c1] + deduplicate_cursors([c2] + rest)
      }
  }

fun finalize_cursors(cs: list<Cursor>) : list<Cursor> {
  let sorted_cs = sort_cursors_asc(cs)
  deduplicate_cursors(sorted_cs)
}

fun max_cid(cs: list<Cursor>) : int =>
  match cs {
    []          => 0,
    [c, ..rest] => max(c.cid, max_cid(rest))
  }

fun next_cid(buf: TextBuffer) : int =>
  max_cid(buf.cursors) + 1

fun last_cursor(cs: list<Cursor>) : Cursor =>
  match cs {
    []          => Cursor { cid: 0, pos: Position { line: 0, col: 0 }, anchor: None, anchor_sticky: false },
    [c]         => c,
    [_, ..rest] => last_cursor(rest)
  }

fun drop_head_cursor(cs: list<Cursor>) : list<Cursor> =>
  match cs {
    []          => [],
    [_, ..rest] => rest
  }

fun shift_pos_after_insert(p: Position, line_idx: int, col_idx: int, k: int) : Position {
  if p.line == line_idx && p.col >= col_idx {
    Position { line: line_idx, col: p.col + k }
  } else {
    p
  }
}

fun shift_cursor_after_insert(c: Cursor, line_idx: int, col_idx: int, k: int) : Cursor {
  let new_p = shift_pos_after_insert(c.pos, line_idx, col_idx, k)
  let new_a = match c.anchor {
    None    => None,
    Some(a) => Some(shift_pos_after_insert(a, line_idx, col_idx, k))
  }
  Cursor { ...c, pos: new_p, anchor: new_a }
}

fun shift_cursors_after_insert(cs: list<Cursor>, line_idx: int, col_idx: int, k: int) : list<Cursor> =>
  map(cs, (c) => shift_cursor_after_insert(c, line_idx, col_idx, k))

fun shift_pos_after_newline(p: Position, line_idx: int, col_idx: int) : Position {
  if p.line == line_idx && p.col >= col_idx {
    Position { line: line_idx + 1, col: p.col - col_idx }
  } else if p.line > line_idx {
    Position { line: p.line + 1, col: p.col }
  } else {
    p
  }
}

fun shift_cursor_after_newline(c: Cursor, line_idx: int, col_idx: int) : Cursor {
  let new_p = shift_pos_after_newline(c.pos, line_idx, col_idx)
  let new_a = match c.anchor {
    None    => None,
    Some(a) => Some(shift_pos_after_newline(a, line_idx, col_idx))
  }
  Cursor { ...c, pos: new_p, anchor: new_a }
}

fun shift_cursors_after_newline(cs: list<Cursor>, line_idx: int, col_idx: int) : list<Cursor> =>
  map(cs, (c) => shift_cursor_after_newline(c, line_idx, col_idx))

fun shift_pos_after_backspace_char(p: Position, line_idx: int, col_idx: int) : Position {
  if p.line == line_idx && p.col >= col_idx {
    Position { line: line_idx, col: max(p.col - 1, 0) }
  } else {
    p
  }
}

fun shift_cursor_after_backspace_char(c: Cursor, line_idx: int, col_idx: int) : Cursor {
  let new_p = shift_pos_after_backspace_char(c.pos, line_idx, col_idx)
  let new_a = match c.anchor {
    None    => None,
    Some(a) => Some(shift_pos_after_backspace_char(a, line_idx, col_idx))
  }
  Cursor { ...c, pos: new_p, anchor: new_a }
}

fun shift_cursors_after_backspace_char(cs: list<Cursor>, line_idx: int, col_idx: int) : list<Cursor> =>
  map(cs, (c) => shift_cursor_after_backspace_char(c, line_idx, col_idx))

fun shift_pos_after_backspace_merge(p: Position, line_idx: int, prev_len: int) : Position {
  if p.line == line_idx {
    Position { line: line_idx - 1, col: prev_len + p.col }
  } else if p.line > line_idx {
    Position { line: p.line - 1, col: p.col }
  } else {
    p
  }
}

fun shift_cursor_after_backspace_merge(c: Cursor, line_idx: int, prev_len: int) : Cursor {
  let new_p = shift_pos_after_backspace_merge(c.pos, line_idx, prev_len)
  let new_a = match c.anchor {
    None    => None,
    Some(a) => Some(shift_pos_after_backspace_merge(a, line_idx, prev_len))
  }
  Cursor { ...c, pos: new_p, anchor: new_a }
}

fun shift_cursors_after_backspace_merge(cs: list<Cursor>, line_idx: int, prev_len: int) : list<Cursor> =>
  map(cs, (c) => shift_cursor_after_backspace_merge(c, line_idx, prev_len))

fun shift_pos_after_delete_forward_char(p: Position, line_idx: int, col_idx: int) : Position {
  if p.line == line_idx && p.col > col_idx {
    Position { line: line_idx, col: p.col - 1 }
  } else {
    p
  }
}

fun shift_cursor_after_delete_forward_char(c: Cursor, line_idx: int, col_idx: int) : Cursor {
  let new_p = shift_pos_after_delete_forward_char(c.pos, line_idx, col_idx)
  let new_a = match c.anchor {
    None    => None,
    Some(a) => Some(shift_pos_after_delete_forward_char(a, line_idx, col_idx))
  }
  Cursor { ...c, pos: new_p, anchor: new_a }
}

fun shift_cursors_after_delete_forward_char(cs: list<Cursor>, line_idx: int, col_idx: int) : list<Cursor> =>
  map(cs, (c) => shift_cursor_after_delete_forward_char(c, line_idx, col_idx))

fun shift_pos_after_delete_forward_merge(p: Position, line_idx: int, col_idx: int) : Position {
  if p.line == line_idx + 1 {
    Position { line: line_idx, col: col_idx + p.col }
  } else if p.line > line_idx + 1 {
    Position { line: p.line - 1, col: p.col }
  } else {
    p
  }
}

fun shift_cursor_after_delete_forward_merge(c: Cursor, line_idx: int, col_idx: int) : Cursor {
  let new_p = shift_pos_after_delete_forward_merge(c.pos, line_idx, col_idx)
  let new_a = match c.anchor {
    None    => None,
    Some(a) => Some(shift_pos_after_delete_forward_merge(a, line_idx, col_idx))
  }
  Cursor { ...c, pos: new_p, anchor: new_a }
}

fun shift_cursors_after_delete_forward_merge(cs: list<Cursor>, line_idx: int, col_idx: int) : list<Cursor> =>
  map(cs, (c) => shift_cursor_after_delete_forward_merge(c, line_idx, col_idx))

fun shift_pos_after_delete_span(p: Position, sl: int, sc: int, el: int, ec: int) : Position {
  if sl == el {
    if p.line == sl {
      if p.col >= ec { Position { line: sl, col: p.col - (ec - sc) } }
      else if p.col > sc { Position { line: sl, col: sc } }
      else { p }
    } else { p }
  } else {
    if p.line == sl {
      if p.col >= sc { Position { line: sl, col: sc } } else { p }
    } else if p.line > sl && p.line < el {
      Position { line: sl, col: sc }
    } else if p.line == el {
      if p.col >= ec { Position { line: sl, col: sc + (p.col - ec) } }
      else { Position { line: sl, col: sc } }
    } else if p.line > el {
      Position { line: p.line - (el - sl), col: p.col }
    } else {
      p
    }
  }
}

fun shift_cursor_after_delete_span(c: Cursor, sl: int, sc: int, el: int, ec: int) : Cursor {
  let new_p = shift_pos_after_delete_span(c.pos, sl, sc, el, ec)
  let new_a = match c.anchor {
    None    => None,
    Some(a) => Some(shift_pos_after_delete_span(a, sl, sc, el, ec))
  }
  Cursor { ...c, pos: new_p, anchor: new_a }
}

fun shift_cursors_after_delete_span(cs: list<Cursor>, sl: int, sc: int, el: int, ec: int) : list<Cursor> =>
  map(cs, (c) => shift_cursor_after_delete_span(c, sl, sc, el, ec))

/// Clamp `col` to a valid column within the line at `line_idx`.
fun clamp_col(lines: list<string>, line_idx: int, col: int) : int {
  let line_len = length(list_get(lines, line_idx, ""))
  max(min(col, line_len), 0)
}

fun fold_insert_char(lines: list<string>, remaining_cs: list<Cursor>, processed_cs: list<Cursor>, c: char) : (list<string>, list<Cursor>) =>
  match remaining_cs {
    [] => (lines, processed_cs),
    [cur, ..rest] => {
      let line_idx = cur.pos.line
      let col_idx  = cur.pos.col
      let current  = list_get(lines, line_idx, "")
      let before   = current[0:col_idx]
      let after    = current[col_idx: ]
      let updated  = before + char_to_string(c) + after
      let next_lines = list_set(lines, line_idx, updated)
      let cur_new  = Cursor { ...cur, pos: Position { line: line_idx, col: col_idx + 1 }, anchor: None, anchor_sticky: false }
      let shifted_processed = shift_cursors_after_insert(processed_cs, line_idx, col_idx, 1)
      fold_insert_char(next_lines, rest, [cur_new] + shifted_processed, c)
    }
  }

/// Insert `c` at each cursor's column and advance each cursor by one.
pub fun insert_char(state: EditorState, c: char) : EditorState {
  let s_base = if has_any_selection(state) { delete_selection(state) } else { state }
  let buf = s_base.buffer
  let sorted_cs = sort_cursors_desc(buf.cursors)
  let (new_lines, new_cs) = fold_insert_char(buf.lines, sorted_cs, [], c)
  let final_cs = finalize_cursors(new_cs)
  let new_buf = TextBuffer {
    ...buf,
    lines: new_lines,
    cursors: final_cs,
    is_dirty: true
  }
  EditorState { ...s_base, buffer: new_buf }
}

fun fold_insert_newline(lines: list<string>, remaining_cs: list<Cursor>, processed_cs: list<Cursor>) : (list<string>, list<Cursor>) =>
  match remaining_cs {
    [] => (lines, processed_cs),
    [cur, ..rest] => {
      let line_idx    = cur.pos.line
      let col_idx     = cur.pos.col
      let current     = list_get(lines, line_idx, "")
      let first_part  = current[0:col_idx]
      let second_part = current[col_idx: ]
      let next_lines  = list_split_at(lines, line_idx, first_part, second_part)
      let cur_new     = Cursor { ...cur, pos: Position { line: line_idx + 1, col: 0 }, anchor: None, anchor_sticky: false }
      let shifted_processed = shift_cursors_after_newline(processed_cs, line_idx, col_idx)
      fold_insert_newline(next_lines, rest, [cur_new] + shifted_processed)
    }
  }

/// Split the line at each cursor into two lines, each cursor moving
/// to column 0 of the new line.
pub fun insert_newline(state: EditorState) : EditorState {
  let s_base = if has_any_selection(state) { delete_selection(state) } else { state }
  let buf = s_base.buffer
  let sorted_cs = sort_cursors_desc(buf.cursors)
  let (new_lines, new_cs) = fold_insert_newline(buf.lines, sorted_cs, [])
  let final_cs = finalize_cursors(new_cs)
  let new_buf = TextBuffer {
    ...buf,
    lines: new_lines,
    cursors: final_cs,
    is_dirty: true
  }
  EditorState { ...s_base, buffer: new_buf }
}

fun move_line_start_pos(p: Position) : Position =>
  Position { line: p.line, col: 0 }

/// Move each cursor to column 0 of its current line.
pub fun move_line_start(state: EditorState) : EditorState {
  let buf = state.buffer
  let moved_cs = map(buf.cursors, (cc) => Cursor { ...cc, pos: move_line_start_pos(cc.pos) })
  let new_cursors = finalize_cursors(moved_cs)
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

fun move_line_end_pos(lines: list<string>, p: Position) : Position =>
  Position { line: p.line, col: length(list_get(lines, p.line, "")) }

/// Move each cursor to the end of its current line.
pub fun move_line_end(state: EditorState) : EditorState {
  let buf = state.buffer
  let moved_cs = map(buf.cursors, (cc) => Cursor { ...cc, pos: move_line_end_pos(buf.lines, cc.pos) })
  let new_cursors = finalize_cursors(moved_cs)
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

fun fold_delete_backward(lines: list<string>, remaining_cs: list<Cursor>, processed_cs: list<Cursor>) : (list<string>, list<Cursor>) =>
  match remaining_cs {
    [] => (lines, processed_cs),
    [cur, ..rest] => {
      let line_idx = cur.pos.line
      let col_idx  = cur.pos.col
      if col_idx > 0 {
        let current    = list_get(lines, line_idx, "")
        let updated    = current[0:col_idx - 1] + current[col_idx: ]
        let next_lines = list_set(lines, line_idx, updated)
        let cur_new    = Cursor { ...cur, pos: Position { line: line_idx, col: col_idx - 1 }, anchor: None, anchor_sticky: false }
        let shifted_processed = shift_cursors_after_backspace_char(processed_cs, line_idx, col_idx)
        fold_delete_backward(next_lines, rest, [cur_new] + shifted_processed)
      } else if line_idx > 0 {
        let prev_idx   = line_idx - 1
        let prev_line  = list_get(lines, prev_idx, "")
        let curr_line  = list_get(lines, line_idx, "")
        let prev_len   = length(prev_line)
        let merged     = prev_line + curr_line
        let joined     = list_set(lines, prev_idx, merged)
        let next_lines = list_remove_at(joined, line_idx)
        let cur_new    = Cursor { ...cur, pos: Position { line: prev_idx, col: prev_len }, anchor: None, anchor_sticky: false }
        let shifted_processed = shift_cursors_after_backspace_merge(processed_cs, line_idx, prev_len)
        fold_delete_backward(next_lines, rest, [cur_new] + shifted_processed)
      } else {
        fold_delete_backward(lines, rest, [cur] + processed_cs)
      }
    }
  }

/// Delete the char before each cursor, merging with the previous line
/// at column 0.
pub fun delete_backward(state: EditorState) : EditorState {
  if has_any_selection(state) {
    delete_selection(state)
  } else {
    let buf = state.buffer
    let sorted_cs = sort_cursors_desc(buf.cursors)
    let (new_lines, new_cs) = fold_delete_backward(buf.lines, sorted_cs, [])
    let final_cs = finalize_cursors(new_cs)
    let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: final_cs, is_dirty: true }
    EditorState { ...state, buffer: new_buf }
  }
}

fun fold_delete_forward(lines: list<string>, remaining_cs: list<Cursor>, processed_cs: list<Cursor>) : (list<string>, list<Cursor>) =>
  match remaining_cs {
    [] => (lines, processed_cs),
    [cur, ..rest] => {
      let line_idx = cur.pos.line
      let col_idx  = cur.pos.col
      let current  = list_get(lines, line_idx, "")
      let line_len = length(current)
      if col_idx < line_len {
        let updated    = current[0:col_idx] + current[col_idx + 1:]
        let next_lines = list_set(lines, line_idx, updated)
        let cur_new    = Cursor { ...cur, pos: Position { line: line_idx, col: col_idx }, anchor: None, anchor_sticky: false }
        let shifted_processed = shift_cursors_after_delete_forward_char(processed_cs, line_idx, col_idx)
        fold_delete_forward(next_lines, rest, [cur_new] + shifted_processed)
      } else if line_idx < length(lines) - 1 {
        let next_idx   = line_idx + 1
        let next_line  = list_get(lines, next_idx, "")
        let merged     = current + next_line
        let joined     = list_set(lines, line_idx, merged)
        let next_lines = list_remove_at(joined, next_idx)
        let cur_new    = Cursor { ...cur, pos: Position { line: line_idx, col: col_idx }, anchor: None, anchor_sticky: false }
        let shifted_processed = shift_cursors_after_delete_forward_merge(processed_cs, line_idx, col_idx)
        fold_delete_forward(next_lines, rest, [cur_new] + shifted_processed)
      } else {
        fold_delete_forward(lines, rest, [cur] + processed_cs)
      }
    }
  }

/// Delete the char under each cursor, merging the next line up into
/// this one at the end of a non-last line.
pub fun delete_forward(state: EditorState) : EditorState {
  if has_any_selection(state) {
    delete_selection(state)
  } else {
    let buf = state.buffer
    let sorted_cs = sort_cursors_desc(buf.cursors)
    let (new_lines, new_cs) = fold_delete_forward(buf.lines, sorted_cs, [])
    let final_cs = finalize_cursors(new_cs)
    let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: final_cs, is_dirty: true }
    EditorState { ...state, buffer: new_buf }
  }
}

fun move_left_pos(lines: list<string>, p: Position) : Position {
  if p.col > 0 { Position { line: p.line, col: p.col - 1 } }
  else if p.line > 0 {
    let prev_idx = p.line - 1
    Position { line: prev_idx, col: length(list_get(lines, prev_idx, "")) }
  } else {
    p
  }
}

/// Move each cursor left one column, wrapping onto the end of the
/// previous line at a line boundary.
pub fun move_left(state: EditorState) : EditorState {
  let buf = state.buffer
  let moved_cs = map(buf.cursors, (cc) => Cursor { ...cc, pos: move_left_pos(buf.lines, cc.pos) })
  let new_cursors = finalize_cursors(moved_cs)
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

fun move_right_pos(lines: list<string>, p: Position) : Position {
  let line_len = length(list_get(lines, p.line, ""))
  let n_lines  = length(lines)
  if p.col < line_len { Position { line: p.line, col: p.col + 1 } }
  else if p.line < n_lines - 1 { Position { line: p.line + 1, col: 0 } }
  else { p }
}

/// Move each cursor right one column, wrapping onto the start of the
/// next line at a line boundary.
pub fun move_right(state: EditorState) : EditorState {
  let buf         = state.buffer
  let moved_cs    = map(buf.cursors, (cc) => Cursor { ...cc, pos: move_right_pos(buf.lines, cc.pos) })
  let new_cursors = finalize_cursors(moved_cs)
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

fun move_up_pos(lines: list<string>, p: Position) : Position {
  let new_line = max(p.line - 1, 0)
  Position { line: new_line, col: clamp_col(lines, new_line, p.col) }
}

/// Move each cursor up one line, clamping the column to the target
/// line's length rather than tracking a "sticky" column.
pub fun move_up(state: EditorState) : EditorState {
  let buf         = state.buffer
  let moved_cs    = map(buf.cursors, (cc) => Cursor { ...cc, pos: move_up_pos(buf.lines, cc.pos) })
  let new_cursors = finalize_cursors(moved_cs)
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

fun move_down_pos(lines: list<string>, p: Position) : Position {
  let n_lines  = length(lines)
  let new_line = min(p.line + 1, n_lines - 1)
  Position { line: new_line, col: clamp_col(lines, new_line, p.col) }
}

/// Move each cursor down one line, clamping the column to the target
/// line's length rather than tracking a "sticky" column.
pub fun move_down(state: EditorState) : EditorState {
  let buf         = state.buffer
  let moved_cs    = map(buf.cursors, (cc) => Cursor { ...cc, pos: move_down_pos(buf.lines, cc.pos) })
  let new_cursors = finalize_cursors(moved_cs)
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

/// Return the text of the cursor's current line, or "" if the buffer
/// has no cursors or no lines.
pub fun current_line(state: EditorState) : string {
  let buf = state.buffer
  list_get(buf.lines, head_cursor(buf).pos.line, "")
}

fun fold_paste_text(lines: list<string>, remaining_cs: list<Cursor>, processed_cs: list<Cursor>, text: string) : (list<string>, list<Cursor>) =>
  match remaining_cs {
    [] => (lines, processed_cs),
    [cur, ..rest] => {
      let line_idx = cur.pos.line
      let col_idx  = cur.pos.col
      let current  = list_get(lines, line_idx, "")
      let updated  = current[0:col_idx] + text + current[col_idx: ]
      let next_lines = list_set(lines, line_idx, updated)
      let bump     = length(text)
      let cur_new  = Cursor { ...cur, pos: Position { line: line_idx, col: col_idx + bump }, anchor: None, anchor_sticky: false }
      let shifted_processed = shift_cursors_after_insert(processed_cs, line_idx, col_idx, bump)
      fold_paste_text(next_lines, rest, [cur_new] + shifted_processed, text)
    }
  }

/// Insert `text` at each cursor's column and advance each cursor by `length(text)`.
pub fun paste_text(state: EditorState, text: string) : EditorState {
  let buf = state.buffer
  let sorted_cs = sort_cursors_desc(buf.cursors)
  let (new_lines, new_cs) = fold_paste_text(buf.lines, sorted_cs, [], text)
  let final_cs = finalize_cursors(new_cs)
  let new_buf = TextBuffer {
    ...buf,
    lines: new_lines,
    cursors: final_cs,
    is_dirty: true
  }
  EditorState { ...state, buffer: new_buf }
}

// ------------------- Selection ranges (M17) -------------------------------
// `Cursor.anchor` is `None` outside a selection; `SetMark` (Ctrl-Space)
// sets it to the cursor's current position, and toggles it back off if a
// selection is already active. Movement actions need no changes at all to
// extend a selection: every motion helper above rebuilds `Cursor` via
// `{ ...cc, pos: ... }`, which already carries `anchor` along for free.

pub fun normalize_span(p1:Position, p2:Position) : (int, int, int, int) {
  if p1.line < p2.line { (p1.line, p1.col, p2.line, p2.col) }
  else if p1.line > p2.line { (p2.line, p2.col, p1.line, p1.col) }
  else if p1.col <= p2.col { (p1.line, p1.col, p2.line, p2.col) }
  else { (p2.line, p2.col, p1.line, p1.col) }
}

fun find_first_selection_span(cs: list<Cursor>) : maybe<(int, int, int, int)> =>
  match cs {
    [] => None,
    [c, ..rest] =>
      match c.anchor {
        Some(a) => Some(normalize_span(c.pos, a)),
        None    => find_first_selection_span(rest)
      }
  }

/// Normalised `(start_line, start_col, end_line, end_col)` span between
/// an active selection's anchor and cursor position. `None` if no cursor
/// has an active selection.
pub fun selection_span(state: EditorState) : maybe<(int, int, int, int)> =>
  find_first_selection_span(state.buffer.cursors)

fun any_has_anchor(cs: list<Cursor>) : bool =>
  match cs {
    []          => false,
    [c, ..rest] => match c.anchor { Some(_) => true, None => any_has_anchor(rest) }
  }

/// True if any cursor in the active buffer has a selection anchor.
pub fun has_any_selection(state: EditorState) : bool =>
  any_has_anchor(state.buffer.cursors)

/// Toggle marks for every cursor: sets `anchor` to the current position
/// if no selection is active, or clears it (cancelling selections)
/// if one already is. The resulting anchor is `sticky` (see
/// `Cursor.anchor_sticky`).
pub fun set_mark(state: EditorState) : EditorState {
  let buf = state.buffer
  let active = has_any_selection(state)
  let new_cursors = map(buf.cursors, (cc) =>
    if active { Cursor { ...cc, anchor: None, anchor_sticky: false } }
    else { Cursor { ...cc, anchor: Some(cc.pos), anchor_sticky: true } })
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

/// Select the whole buffer: anchor at the very start, cursor at the
/// very end of the last line. Non-sticky.
pub fun select_all(state: EditorState) : EditorState {
  let buf       = state.buffer
  let last_line = max(length(buf.lines) - 1, 0)
  let last_col  = length(list_get(buf.lines, last_line, ""))
  let end_pos   = Position { line: last_line, col: last_col }
  let new_cursors = [Cursor { cid: 0, pos: end_pos, anchor: Some(Position { line: 0, col: 0 }), anchor_sticky: false }]
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

/// The lines strictly between `lo` and `hi` (inclusive), or `[]` if
/// `lo > hi`.
fun middle_lines(lines: list<string>, lo: int, hi: int) : list<string> =>
  if lo > hi { [] } else { [list_get(lines, lo, "")] + middle_lines(lines, lo + 1, hi) }

/// Remove `hi - lo + 1` lines starting at `lo` (inclusive).
fun remove_lines_between(lines: list<string>, lo: int, hi: int) : list<string> =>
  match lines {
    []          => [],
    [x, ..rest] =>
      if lo <= 0 && hi >= 0 { remove_lines_between(rest, lo - 1, hi - 1) }
      else { [x] + remove_lines_between(rest, lo - 1, hi - 1) }
  }

fun span_text_from_lines(lines: list<string>, sl: int, sc: int, el: int, ec: int) : string {
  if sl == el {
    list_get(lines, sl, "")[sc: ec]
  } else {
    let first_line = list_get(lines, sl, "")[sc: ]
    let last_line  = list_get(lines, el, "")[0:ec]
    let mid_lines  = middle_lines(lines, sl + 1, el - 1)
    join([first_line] + mid_lines + [last_line], "\n")
  }
}

fun collect_selection_texts(lines: list<string>, cs: list<Cursor>) : list<string> =>
  match cs {
    [] => [],
    [c, ..rest] =>
      match c.anchor {
        None => collect_selection_texts(lines, rest),
        Some(a) => {
          let (sl, sc, el, ec) = normalize_span(c.pos, a)
          let txt = span_text_from_lines(lines, sl, sc, el, ec)
          [txt] + collect_selection_texts(lines, rest)
        }
      }
  }

/// The text spanned by active selections across all cursors (joined with newlines),
/// or `None` outside an active selection.
pub fun selection_text(state: EditorState) : maybe<string> {
  let texts = collect_selection_texts(state.buffer.lines, state.buffer.cursors)
  match texts {
    [] => None,
    _  => Some(join(texts, "\n"))
  }
}

fun delete_one_selection(lines: list<string>, sl: int, sc: int, el: int, ec: int) : list<string> {
  let start_line  = list_get(lines, sl, "")
  let end_line    = list_get(lines, el, "")
  let merged      = start_line[0:sc] + end_line[ec: ]
  let after_merge = list_set(lines, sl, merged)
  remove_lines_between(after_merge, sl + 1, el)
}

fun fold_delete_selection(lines: list<string>, remaining_cs: list<Cursor>, processed_cs: list<Cursor>) : (list<string>, list<Cursor>) =>
  match remaining_cs {
    [] => (lines, processed_cs),
    [cur, ..rest] =>
      match cur.anchor {
        None => fold_delete_selection(lines, rest, [cur] + processed_cs),
        Some(a) => {
          let (sl, sc, el, ec) = normalize_span(cur.pos, a)
          let next_lines = delete_one_selection(lines, sl, sc, el, ec)
          let cur_new    = Cursor { ...cur, pos: Position { line: sl, col: sc }, anchor: None, anchor_sticky: false }
          let shifted_processed = shift_cursors_after_delete_span(processed_cs, sl, sc, el, ec)
          fold_delete_selection(next_lines, rest, [cur_new] + shifted_processed)
        }
      }
  }

/// Remove all active selections across all cursors, moving each cursor to
/// its selection's start and clearing the anchor.
pub fun delete_selection(state: EditorState) : EditorState {
  if !has_any_selection(state) {
    state
  } else {
    let buf = state.buffer
    let sorted_cs = sort_cursors_desc(buf.cursors)
    let (new_lines, new_cs) = fold_delete_selection(buf.lines, sorted_cs, [])
    let final_cs = finalize_cursors(new_cs)
    let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: final_cs, is_dirty: true }
    EditorState { ...state, buffer: new_buf }
  }
}

// ------------------- kill / yank (Ctrl-k, Ctrl-w) -------------------------
// Reuses the same Clipboard sink as Copy/Paste (Ctrl-y/yank is Paste bound
// to a second chord, see default_bindings — there's no separate kill-ring).
// Each kill is split into a text getter (what would be killed) and a state
// mutator, so event_loop can hand the text to set_selection before applying
// the truncation.

/// Return the text from each cursor to the end of its line (joined with newlines).
pub fun kill_line_text(state: EditorState) : string {
  let buf   = state.buffer
  let texts = map(buf.cursors, (c) => {
    let line_str = list_get(buf.lines, c.pos.line, "")
    line_str[c.pos.col: ]
  })
  join(texts, "\n")
}

fun fold_kill_line(lines: list<string>, remaining_cs: list<Cursor>, processed_cs: list<Cursor>) : (list<string>, list<Cursor>) =>
  match remaining_cs {
    [] => (lines, processed_cs),
    [cur, ..rest] => {
      let line_idx = cur.pos.line
      let col_idx  = cur.pos.col
      let current  = list_get(lines, line_idx, "")
      let updated  = current[0:col_idx]
      let next_lines = list_set(lines, line_idx, updated)
      let cur_new  = Cursor { ...cur, anchor: None, anchor_sticky: false }
      let shifted_processed = map(processed_cs, (pc) =>
        if pc.pos.line == line_idx && pc.pos.col > col_idx {
          Cursor { ...pc, pos: Position { line: line_idx, col: col_idx } }
        } else { pc })
      fold_kill_line(next_lines, rest, [cur_new] + shifted_processed)
    }
  }

/// Truncate the line at each cursor.
pub fun kill_line(state: EditorState) : EditorState {
  let buf = state.buffer
  let sorted_cs = sort_cursors_desc(buf.cursors)
  let (new_lines, new_cs) = fold_kill_line(buf.lines, sorted_cs, [])
  let final_cs = finalize_cursors(new_cs)
  let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: final_cs, is_dirty: true }
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

// ------------------- buffer stats (M13, `(buffer-stats)`) ---------------
//
// Read-only line/word/char counts, exposed to HiLisp hooks via
// `hilisp_host.hc::env_with_buffer_stats`/`host_buffer_stats`. Word
// counting reuses the same whitespace-run-skipping idiom as
// `word_back_col`/`word_forward_col` above, just applied to a whole
// line instead of stopping at a cursor column.

/// Count whitespace-delimited words in a single line.
fun count_words_in_line(line: string) : int => count_words_go(chars(line))

/// Recursive worker: skip a whitespace run, then a non-whitespace run,
/// counting each non-whitespace run as one word.
fun count_words_go(cs: list<char>) : int {
  let no_space = drop_while(cs, is_space_char)
  match no_space {
    [] => 0,
    _  => {
      let no_word = drop_while(no_space, (c) => !is_space_char(c))
      1 + count_words_go(no_word)
    }
  }
}

/// Total line count of `buf` — the `(buffer-stats)` `"lines"` field.
pub fun line_count(buf: TextBuffer) : int => length(buf.lines)

/// Total whitespace-delimited word count across every line of `buf` —
/// the `(buffer-stats)` `"words"` field.
pub fun word_count(buf: TextBuffer) : int => sum_words(buf.lines)

fun sum_words(lines: list<string>) : int =>
  match lines {
    []          => 0,
    [l, ..rest] => count_words_in_line(l) + sum_words(rest)
  }

/// Total character count across every line of `buf`, not counting the
/// implicit newlines between lines — the `(buffer-stats)` `"chars"`
/// field.
pub fun char_count(buf: TextBuffer) : int => sum_chars(buf.lines)

fun sum_chars(lines: list<string>) : int =>
  match lines {
    []          => 0,
    [l, ..rest] => length(l) + sum_chars(rest)
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

/// Return the whitespace-delimited word before each cursor (joined with newlines).
pub fun kill_word_back_text(state: EditorState) : string {
  let buf   = state.buffer
  let texts = map(buf.cursors, (c) => {
    let ln      = list_get(buf.lines, c.pos.line, "")
    let new_col = word_back_col(ln, c.pos.col)
    ln[new_col: c.pos.col]
  })
  join(texts, "\n")
}

fun fold_delete_word_back(lines: list<string>, remaining_cs: list<Cursor>, processed_cs: list<Cursor>) : (list<string>, list<Cursor>) =>
  match remaining_cs {
    [] => (lines, processed_cs),
    [cur, ..rest] => {
      let line_idx = cur.pos.line
      let col_idx  = cur.pos.col
      let ln       = list_get(lines, line_idx, "")
      let new_col  = word_back_col(ln, col_idx)
      let k        = col_idx - new_col
      let updated  = ln[0:new_col] + ln[col_idx: ]
      let next_lines = list_set(lines, line_idx, updated)
      let cur_new  = Cursor { ...cur, pos: Position { line: line_idx, col: new_col }, anchor: None, anchor_sticky: false }
      let shifted_processed = map(processed_cs, (pc) =>
        if pc.pos.line == line_idx && pc.pos.col >= col_idx {
          Cursor { ...pc, pos: Position { line: line_idx, col: max(pc.pos.col - k, new_col) } }
        } else { pc })
      fold_delete_word_back(next_lines, rest, [cur_new] + shifted_processed)
    }
  }

/// Delete the whitespace-delimited word before each cursor.
pub fun delete_word_back(state: EditorState) : EditorState {
  let buf = state.buffer
  let sorted_cs = sort_cursors_desc(buf.cursors)
  let (new_lines, new_cs) = fold_delete_word_back(buf.lines, sorted_cs, [])
  let final_cs = finalize_cursors(new_cs)
  let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: final_cs, is_dirty: true }
  EditorState { ...state, buffer: new_buf }
}

fun move_word_back_pos(lines: list<string>, p: Position) : Position {
  let ln = list_get(lines, p.line, "")
  Position { line: p.line, col: word_back_col(ln, p.col) }
}

/// Move each cursor one whitespace-delimited word back.
pub fun move_word_back(state: EditorState) : EditorState {
  let buf         = state.buffer
  let moved_cs    = map(buf.cursors, (cc) => Cursor { ...cc, pos: move_word_back_pos(buf.lines, cc.pos) })
  let new_cursors = finalize_cursors(moved_cs)
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

fun move_word_forward_pos(lines: list<string>, p: Position) : Position {
  let ln = list_get(lines, p.line, "")
  Position { line: p.line, col: word_forward_col(ln, p.col) }
}

/// Move each cursor one whitespace-delimited word forward.
pub fun move_word_forward(state: EditorState) : EditorState {
  let buf         = state.buffer
  let moved_cs    = map(buf.cursors, (cc) => Cursor { ...cc, pos: move_word_forward_pos(buf.lines, cc.pos) })
  let new_cursors = finalize_cursors(moved_cs)
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
}

/// Return the whitespace-delimited word after each cursor (joined with newlines).
pub fun kill_word_forward_text(state: EditorState) : string {
  let buf   = state.buffer
  let texts = map(buf.cursors, (c) => {
    let ln      = list_get(buf.lines, c.pos.line, "")
    let new_col = word_forward_col(ln, c.pos.col)
    ln[c.pos.col: new_col]
  })
  join(texts, "\n")
}

fun fold_delete_word_forward(lines: list<string>, remaining_cs: list<Cursor>, processed_cs: list<Cursor>) : (list<string>, list<Cursor>) =>
  match remaining_cs {
    [] => (lines, processed_cs),
    [cur, ..rest] => {
      let line_idx = cur.pos.line
      let col_idx  = cur.pos.col
      let ln       = list_get(lines, line_idx, "")
      let new_col  = word_forward_col(ln, col_idx)
      let k        = new_col - col_idx
      let updated  = ln[0:col_idx] + ln[new_col: ]
      let next_lines = list_set(lines, line_idx, updated)
      let cur_new  = Cursor { ...cur, pos: Position { line: line_idx, col: col_idx }, anchor: None, anchor_sticky: false }
      let shifted_processed = map(processed_cs, (pc) =>
        if pc.pos.line == line_idx && pc.pos.col >= new_col {
          Cursor { ...pc, pos: Position { line: line_idx, col: pc.pos.col - k } }
        } else if pc.pos.line == line_idx && pc.pos.col > col_idx {
          Cursor { ...pc, pos: Position { line: line_idx, col: col_idx } }
        } else { pc })
      fold_delete_word_forward(next_lines, rest, [cur_new] + shifted_processed)
    }
  }

/// Delete the whitespace-delimited word after each cursor.
pub fun delete_word_forward(state: EditorState) : EditorState {
  let buf = state.buffer
  let sorted_cs = sort_cursors_desc(buf.cursors)
  let (new_lines, new_cs) = fold_delete_word_forward(buf.lines, sorted_cs, [])
  let final_cs = finalize_cursors(new_cs)
  let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: final_cs, is_dirty: true }
  EditorState { ...state, buffer: new_buf }
}

/// Return the full text of each cursor's line (joined with newlines).
pub fun kill_whole_line_text(state: EditorState) : string {
  let buf   = state.buffer
  let texts = map(buf.cursors, (c) => list_get(buf.lines, c.pos.line, ""))
  join(texts, "\n")
}

fun fold_kill_whole_line(lines: list<string>, remaining_cs: list<Cursor>, processed_cs: list<Cursor>) : (list<string>, list<Cursor>) =>
  match remaining_cs {
    [] => (lines, processed_cs),
    [cur, ..rest] => {
      let line_idx = cur.pos.line
      let next_lines = list_set(lines, line_idx, "")
      let cur_new  = Cursor { ...cur, pos: Position { line: line_idx, col: 0 }, anchor: None, anchor_sticky: false }
      let shifted_processed = map(processed_cs, (pc) =>
        if pc.pos.line == line_idx {
          Cursor { ...pc, pos: Position { line: line_idx, col: 0 } }
        } else { pc })
      fold_kill_whole_line(next_lines, rest, [cur_new] + shifted_processed)
    }
  }

/// Clear each cursor's line content; cursor moves to column 0.
pub fun kill_whole_line(state: EditorState) : EditorState {
  let buf = state.buffer
  let sorted_cs = sort_cursors_desc(buf.cursors)
  let (new_lines, new_cs) = fold_kill_whole_line(buf.lines, sorted_cs, [])
  let final_cs = finalize_cursors(new_cs)
  let new_buf = TextBuffer { ...buf, lines: new_lines, cursors: final_cs, is_dirty: true }
  EditorState { ...state, buffer: new_buf }
}

// ------------------- multi-buffer navigation (M5.5) ----------------------
// `state.buffer` is always active; `background_buffers` is the rest of
// the open buffers as a rotation ring, with no separate active index to
// keep in sync (see model.hc's EditorState doc comment).

/// Push the active buffer onto the background ring and make a fresh,
/// empty scratch buffer active.
// Pure: opening a file from disk needs a path-prompt input widget (M9).
// `panes` must track which bid the focused leaf shows — see the
// `pane_leaf_current` note on `cycle_next_buffer` below.
pub fun new_buffer_action(state: EditorState) : EditorState {
  let new_bid = state.next_bid
  EditorState {
    ...state,
    buffer: new_buffer(new_bid, None),
    background_buffers: state.background_buffers + [state.buffer],
    next_bid: new_bid + 1,
    panes: replace_leaf(state.panes, state.buffer.bid, Leaf(new_bid))
  }
}

/// Rotate to the next open buffer. A no-op with 0 or 1 open buffers.
// `panes`' leaf for the currently focused pane must be updated to the
// newly active bid (not just `state.buffer`) — otherwise a mouse click
// or a later VSplit/HSplit resolves against the stale bid still on the
// tree (`screen_to_buffer_pos`/`run_split` both key off `PaneNode`
// leaves, not `state.buffer.bid`), which looks like a click "jumping"
// back to whatever buffer the tree still remembers and silently no-ops
// a split (`replace_leaf` can't find the target bid to replace).
pub fun cycle_next_buffer(state: EditorState) : EditorState =>
  match state.background_buffers {
    []          => state,
    [x, ..rest] => EditorState { ...state, buffer: x, background_buffers: rest + [state.buffer], panes: replace_leaf(state.panes, state.buffer.bid, Leaf(x.bid)) }
  }

/// Rotate to the previous open buffer. A no-op with 0 or 1 open buffers.
pub fun cycle_prev_buffer(state: EditorState) : EditorState =>
  match reverse(state.background_buffers) {
    []          => state,
    [x, ..rest] => EditorState { ...state, buffer: x, background_buffers: [state.buffer] + reverse(rest), panes: replace_leaf(state.panes, state.buffer.bid, Leaf(x.bid)) }
  }

/// Close the active buffer and activate the next background buffer.
// hedit always keeps at least one open buffer, so closing the last one
// is a status-message no-op instead.
pub fun close_buffer_action(state: EditorState) : EditorState =>
  match state.background_buffers {
    []          => set_status_message(state, "Can't close the last buffer"),
    [x, ..rest] => EditorState { ...state, buffer: x, background_buffers: rest, panes: replace_leaf(state.panes, state.buffer.bid, Leaf(x.bid)) }
  }

// ------------------- Close pane (M15 follow-up, Ctrl-q) -------------------
// With 2+ panes open, Ctrl-q closes the active pane AND its buffer (not
// just unfocusing it, like `PaneLeft`/etc. do) instead of quitting hedit
// outright — see `apply_action`'s `Quit` arm below, which only sets
// `should_quit` once `state.panes` is back down to a single `Leaf`. Same
// "the editor must always be escapable" invariant as before: repeated
// Ctrl-q always terminates eventually, it just closes one pane at a time.

/// Close the active pane: collapse it out of `panes` (`model.hc`'s
/// `remove_leaf`) and hand focus to whichever pane comes first in the
/// remaining tree's document order. A no-op if `panes` is already a
/// single `Leaf` (nothing to collapse into) — callers check `is_leaf`
/// first, same precondition `remove_leaf` documents.
pub fun close_pane(state: EditorState) : EditorState {
  let closed_bid = state.buffer.bid
  let new_panes  = remove_leaf(state.panes, closed_bid)
  let focus_bid  = first_or(pane_order(new_panes), closed_bid)
  match extract_buffer(state.background_buffers, focus_bid) {
    None                => state,
    Some((next_buf, rest)) =>
      EditorState { ...state, buffer: next_buf, background_buffers: rest, panes: new_panes }
  }
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
    FindPrompt(t, _)   => t,
    VSplitPrompt(t, _) => t,
    HSplitPrompt(t, _) => t
  }

/// Return the cursor column within `p`'s typed text.
fun prompt_cursor(p: Prompt) : int =>
  match p {
    NoPrompt           => 0,
    SaveAsPrompt(_, c) => c,
    OpenPrompt(_, c)   => c,
    FindPrompt(_, c)   => c,
    VSplitPrompt(_, c) => c,
    HSplitPrompt(_, c) => c
  }

/// Return a copy of `p` with updated text and cursor column,
/// preserving its variant.
fun with_prompt(p: Prompt, t: string, c: int) : Prompt =>
  match p {
    NoPrompt           => NoPrompt,
    SaveAsPrompt(_, _) => SaveAsPrompt(t, c),
    OpenPrompt(_, _)   => OpenPrompt(t, c),
    FindPrompt(_, _)   => FindPrompt(t, c),
    VSplitPrompt(_, _) => VSplitPrompt(t, c),
    HSplitPrompt(_, _) => HSplitPrompt(t, c)
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

// ------------------- Split panes (M15) ------------------------------------
// Meta-v/Meta-h open `VSplitPrompt`/`HSplitPrompt` ("VSplit: "/"HSplit: ");
// submitting with a typed path opens that file in the new pane, a bare
// Enter duplicates the current buffer. The actual pane-tree/layout wiring
// (needs `<fsys>` for the typed-path case) lands in `runtime.hc`'s
// `run_prompt_submit`. Pane-focus movement (`PaneLeft`/`Right`/`Up`/
// `Down`/`NextPane`, bound to `Meta-Arrows`/`Meta-Tab`) lives further
// down this file, once `model.hc`'s pane geometry is in scope.

/// Open the vertical-split prompt with empty text.
pub fun open_vsplit_prompt(state: EditorState) : EditorState =>
  EditorState { ...state, prompt: VSplitPrompt("", 0) }

/// Open the horizontal-split prompt with empty text.
pub fun open_hsplit_prompt(state: EditorState) : EditorState =>
  EditorState { ...state, prompt: HSplitPrompt("", 0) }

/// A fresh, unnamed copy of `source`'s content under a new `bid` — the
/// bare-Enter ("duplicate the current buffer") half of a split submit.
/// Single cursor reset to (0, 0); not dirty (matches opening a fresh
/// view, same as `new_buffer`).
pub fun duplicate_buffer(new_bid: int, source: TextBuffer) : TextBuffer =>
  TextBuffer { ...new_buffer(new_bid, None), lines: source.lines }

// ------------------- Pane focus movement (M15 follow-up) ------------------
// `PaneLeft`/`Right`/`Up`/`Down` (`Meta-Arrows`) compare every leaf's
// rectangle center (`model.hc`'s `split_rect`/`rect_center`, computed
// fresh from the CURRENT `screen_size` — no persisted layout state to
// keep in sync) to find the nearest neighbour strictly in the requested
// direction, tie-broken by the smallest perpendicular distance (so
// e.g. moving down from a wide pane lands in whichever of several
// stacked panes below is most directly underneath). `NextPane`
// (`Meta-Tab`) instead walks the tree's leaves in document order
// (`pane_order`) for a stable linear cycle. Both are no-ops (state
// unchanged) when unsplit or already at an edge — `activate_buffer`
// itself is a no-op if the target `bid` isn't open, and `nearest_*`
// returning `None` short-circuits before ever calling it.

fun iabs(n: int) : int => if n < 0 { -n } else { n }

/// `(bid, center_x, center_y)` for every leaf in `rects`.
fun pane_centers(rects: list<(int, (int, int, int, int))>) : list<(int, int, int)> =>
  match rects {
    []                    => [],
    [(bid, rect), ..rest] => {
      let (cx, cy) = rect_center(rect)
      [(bid, cx, cy)] + pane_centers(rest)
    }
  }

/// The element of `cands` for which `better(candidate, current_best)`
/// holds most often — a plain "keep the best so far" reduction.
fun best_of(cands: list<(int, int, int)>, better: ((int, int, int), (int, int, int)) -> bool) : maybe<(int, int, int)> =>
  match cands {
    []          => None,
    [c, ..rest] =>
      match best_of(rest, better) {
        None      => Some(c),
        Some(cur) => if better(c, cur) { Some(c) } else { Some(cur) }
      }
  }

/// The nearest leaf strictly left of `(fx, fy)`, or `None` if there
/// isn't one.
fun nearest_left(cands: list<(int, int, int)>, fx: int, fy: int) : maybe<int> =>
  match best_of(filter(cands, (c) => c.1 < fx), (a, b) => a.1 > b.1 || (a.1 == b.1 && iabs(a.2 - fy) < iabs(b.2 - fy))) {
    None    => None,
    Some(c) => Some(c.0)
  }

/// The nearest leaf strictly right of `(fx, fy)`, or `None`.
fun nearest_right(cands: list<(int, int, int)>, fx: int, fy: int) : maybe<int> =>
  match best_of(filter(cands, (c) => c.1 > fx), (a, b) => a.1 < b.1 || (a.1 == b.1 && iabs(a.2 - fy) < iabs(b.2 - fy))) {
    None    => None,
    Some(c) => Some(c.0)
  }

/// The nearest leaf strictly above `(fx, fy)`, or `None`.
fun nearest_up(cands: list<(int, int, int)>, fx: int, fy: int) : maybe<int> =>
  match best_of(filter(cands, (c) => c.2 < fy), (a, b) => a.2 > b.2 || (a.2 == b.2 && iabs(a.1 - fx) < iabs(b.1 - fx))) {
    None    => None,
    Some(c) => Some(c.0)
  }

/// The nearest leaf strictly below `(fx, fy)`, or `None`.
fun nearest_down(cands: list<(int, int, int)>, fx: int, fy: int) : maybe<int> =>
  match best_of(filter(cands, (c) => c.2 > fy), (a, b) => a.2 < b.2 || (a.2 == b.2 && iabs(a.1 - fx) < iabs(b.1 - fx))) {
    None    => None,
    Some(c) => Some(c.0)
  }

/// Apply a `nearest_*` result: activate that pane's buffer, or leave
/// `state` untouched if there wasn't one.
fun move_focus(state: EditorState, target: maybe<int>) : EditorState =>
  match target {
    None      => state,
    Some(bid) => activate_buffer(state, bid)
  }

/// The active leaf's rectangle within the current content area.
fun active_rect(state: EditorState, rects: list<(int, (int, int, int, int))>, full_rect: (int, int, int, int)) : (int, int, int, int) =>
  find_rect(rects, state.buffer.bid, full_rect)

// ------------------- Mouse (M18) -------------------------------------------
// Screen (x, y) -> buffer Position is the inverse of render.hc's layout:
// row 1 is the tabline, rows 2..h-1 are content (split into per-pane
// rectangles via `split_rect`, same as the split-pane renderer), row h is
// the status line. Must stay in sync with both `render_normal_buffer` and
// `render_split_buffer` if that layout ever changes.

/// The `(bid, rect)` pair whose rectangle contains content-space point
/// `(x, y)`, or `None` if it falls in a divider gap or outside every pane.
fun rect_at(rects: list<(int, (int, int, int, int))>, x: int, y: int) : maybe<(int, (int, int, int, int))> =>
  match rects {
    []                    => None,
    [(pane_bid, rect), ..rest] =>
      if x >= rect.0 && x < rect.0 + rect.2 && y >= rect.1 && y < rect.1 + rect.3 { Some((pane_bid, rect)) }
      else { rect_at(rest, x, y) }
  }

/// The `(bid, rect)` pair a 1-indexed screen coordinate falls on, or
/// `None` for the tabline/status row, a divider gap, or outside every
/// pane. Shared by `screen_to_buffer_pos` (click/drag) and `scroll_view`
/// (wheel) so both agree on exactly the same content-area geometry.
fun locate_pane(state: EditorState, x: int, y: int) : maybe<(int, (int, int, int, int))> {
  let (w, h)    = state.screen_size
  let n_content = h - 2
  let cx        = x - 1
  let cy        = y - 2
  if cx < 0 || cx >= w || cy < 0 || cy >= n_content { None }
  else { rect_at(split_rect((0, 0, w, n_content), state.panes), cx, cy) }
}

/// Map a 1-indexed screen coordinate (`x` = column, `y` = row) to the pane
/// `bid` and the buffer-local `Position` it falls on. `None` for a click on
/// the tabline/status row, a divider gap, or outside every pane.
pub fun screen_to_buffer_pos(state: EditorState, x: int, y: int) : maybe<(int, Position)> {
  let cx = x - 1
  let cy = y - 2
  match locate_pane(state, x, y) {
    None => None,
    Some((pane_bid, rect)) => {
      let buf        = buffer_for(state, pane_bid)
      let local_col  = cx - rect.0
      let local_line = (cy - rect.1) + buf.scroll_line
      Some((pane_bid, clamp_position(buf.lines, Position { line: local_line, col: local_col })))
    }
  }
}

/// The divider index (`split_dividers`'s pre-order traversal) whose
/// rectangle contains content-space point `(x, y)`, or `None`.
fun divider_hit(dividers: list<(int, int, int, int)>, x: int, y: int, idx: int) : maybe<int> =>
  match dividers {
    []                    => None,
    [(dx, dy, dw, dh), ..rest] =>
      if x >= dx && x < dx + dw && y >= dy && y < dy + dh { Some(idx) }
      else { divider_hit(rest, x, y, idx + 1) }
  }

/// `xs[idx]`, or `None` past the end — `split_divider_specs`
/// specialised, since it's the only list this file indexes by a
/// divider index rather than searching by key.
fun spec_at(xs: list<(Axis, (int, int, int, int))>, idx: int) : maybe<(Axis, (int, int, int, int))> =>
  match xs {
    []          => None,
    [x, ..rest] => if idx <= 0 { Some(x) } else { spec_at(rest, idx - 1) }
  }

/// A drag's raw content-space column (`Vertical`) or row (`Horizontal`)
/// turned into a 0.0-1.0 ratio relative to the divider's enclosing
/// rect, clamped so neither side of the split can shrink to nothing —
/// `vsplit_extents`/`hsplit_extents` clamp the actual pane widths/
/// heights again at render time regardless, this just keeps the stored
/// ratio itself sane.
fun ratio_from_drag(axis: Axis, rect: (int, int, int, int), cx: int, cy: int) : float {
  let (x, y, w, h) = rect
  let raw = match axis {
    Vertical   => to_float(cx - x) / to_float(max(w, 1)),
    Horizontal => to_float(cy - y) / to_float(max(h, 1))
  }
  if raw < 0.05 { 0.05 } else if raw > 0.95 { 0.95 } else { raw }
}

/// Recompute divider `idx`'s ratio from the drag's current screen
/// coordinate `(x, y)` — a no-op if the content area's geometry can't
/// locate that divider anymore (shouldn't happen mid-drag).
fun resize_divider(state: EditorState, idx: int, x: int, y: int) : EditorState {
  let (w, h)    = state.screen_size
  let n_content = h - 2
  let cx        = x - 1
  let cy        = y - 2
  let specs     = split_divider_specs((0, 0, w, n_content), state.panes)
  match spec_at(specs, idx) {
    None => state,
    Some((axis, rect)) => EditorState { ...state, panes: resize_split(state.panes, idx, ratio_from_drag(axis, rect, cx, cy)) }
  }
}

/// The click/place-cursor behaviour `mouse_click` falls through to once
/// a click is known not to have landed on a divider.
fun mouse_click_pane(state: EditorState, x: int, y: int) : EditorState =>
  match screen_to_buffer_pos(state, x, y) {
    None => EditorState { ...state, resizing_divider: None },
    Some((pane_bid, click_pos)) => {
      let focused     = activate_buffer(state, pane_bid)
      let buf         = focused.buffer
      let new_cursors = [Cursor { cid: 0, pos: click_pos, anchor: None, anchor_sticky: false }]
      EditorState { ...focused, buffer: TextBuffer { ...buf, cursors: new_cursors }, resizing_divider: None }
    }
  }

/// `MetaMouseClick` (SGR press with Meta/Alt held): adds an extra
/// independent cursor at the clicked position without removing existing cursors.
pub fun meta_mouse_click(state: EditorState, x: int, y: int) : EditorState =>
  match screen_to_buffer_pos(state, x, y) {
    None => EditorState { ...state, resizing_divider: None },
    Some((pane_bid, click_pos)) => {
      let focused = activate_buffer(state, pane_bid)
      let buf     = focused.buffer
      let new_cur = Cursor { cid: next_cid(buf), pos: click_pos, anchor: None, anchor_sticky: false }
      let appended_cs = buf.cursors + [new_cur]
      let new_cs      = finalize_cursors(appended_cs)
      EditorState { ...focused, buffer: TextBuffer { ...buf, cursors: new_cs }, resizing_divider: None }
    }
  }

/// `MouseClick` (SGR press): a click on a divider strip starts a resize
/// gesture (`resizing_divider`, ended by the matching `MouseRelease`)
/// instead of moving the cursor. Otherwise focuses whichever pane the
/// click landed in and places the cursor there, clearing any active
/// selection. A click on the tabline/status row is a no-op. Every
/// branch resets `resizing_divider` to `None` except the one that
/// starts a new gesture, so a stray leftover from an interrupted drag
/// can never make a later plain drag misbehave.
pub fun mouse_click(state: EditorState, x: int, y: int) : EditorState {
  let (w, h)    = state.screen_size
  let n_content = h - 2
  let cx        = x - 1
  let cy        = y - 2
  if cx < 0 || cx >= w || cy < 0 || cy >= n_content { EditorState { ...state, resizing_divider: None } }
  else {
    match divider_hit(split_dividers((0, 0, w, n_content), state.panes), cx, cy, 0) {
      Some(idx) => EditorState { ...state, resizing_divider: Some(idx) },
      None      => mouse_click_pane(state, x, y)
    }
  }
}

/// The text-selection behaviour `mouse_drag` falls through to when no
/// divider resize is in progress.
fun mouse_drag_select(state: EditorState, x: int, y: int) : EditorState =>
  match screen_to_buffer_pos(state, x, y) {
    None => state,
    Some((pane_bid, drag_pos)) =>
      if pane_bid != state.buffer.bid { state }
      else {
        let buf         = state.buffer
        let cur         = head_cursor(buf)
        let new_anchor  = match cur.anchor { None => Some(cur.pos), Some(_) => cur.anchor }
        let new_cursors = map(buf.cursors, (cc) => Cursor { ...cc, pos: drag_pos, anchor: new_anchor, anchor_sticky: false })
        EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
      }
  }

/// `MouseDrag` (SGR motion with a button held): while `resizing_divider`
/// is active, recompute that divider's ratio instead of touching any
/// selection. Otherwise extends a selection from wherever the drag
/// started (the anchor is set on the first drag tick after a press,
/// same as `SetMark` + movement) to the current drag position. Ignored
/// once the drag has left the pane the gesture started in — a mouse
/// gesture shouldn't silently refocus mid-drag. Non-sticky: unlike
/// `SetMark`, a plain arrow press after the drag ends collapses the
/// selection instead of extending it (see `Cursor.anchor_sticky`).
pub fun mouse_drag(state: EditorState, x: int, y: int) : EditorState =>
  match state.resizing_divider {
    Some(idx) => resize_divider(state, idx, x, y),
    None      => mouse_drag_select(state, x, y)
  }

/// Adjust `target_bid`'s `scroll_line` by `delta` lines (positive = down),
/// clamped to `[0, max(0, total_lines - rh)]` so the wheel can't scroll
/// past the end into a screenful of "~" fill. Updates whichever buffer
/// (active or backgrounded) owns `target_bid`, without changing focus —
/// scrolling a pane you're hovering shouldn't activate it.
fun scroll_buffer(state: EditorState, target_bid: int, rh: int, delta: int) : EditorState {
  let buf        = buffer_for(state, target_bid)
  let max_scroll = max(length(buf.lines) - rh, 0)
  let new_scroll = max(0, min(buf.scroll_line + delta, max_scroll))
  let updated    = TextBuffer { ...buf, scroll_line: new_scroll }
  if target_bid == state.buffer.bid { EditorState { ...state, buffer: updated } }
  else {
    let new_bg = map(state.background_buffers, (b) => if b.bid == target_bid { updated } else { b })
    EditorState { ...state, background_buffers: new_bg }
  }
}

/// `ScrollViewUp`/`ScrollViewDown` (mouse wheel): scroll whichever pane's
/// rectangle `(x, y)` falls on, three lines per tick — the cursor doesn't
/// move, so it can end up outside the newly visible window until the next
/// cursor-moving action scrolls it back into view (standard wheel-scroll
/// behaviour). A wheel tick outside every pane is a no-op.
pub fun scroll_view(state: EditorState, x: int, y: int, dir: int) : EditorState =>
  match locate_pane(state, x, y) {
    None => state,
    Some((pane_bid, rect)) => scroll_buffer(state, pane_bid, rect.3, dir * 3)
  }

/// Clamp the active buffer's persisted `scroll_line` to keep its cursor
/// visible, moving it the minimum amount needed (see `clamp_scroll`).
/// Called after every cursor-moving action so `TextBuffer.scroll_line`
/// stays correct for `render.hc` to read directly.
pub fun sync_scroll(state: EditorState) : EditorState {
  let (w, h)    = state.screen_size
  let n_content = h - 2
  let rects     = split_rect((0, 0, w, n_content), state.panes)
  let (_, _, _, rh) = find_rect(rects, state.buffer.bid, (0, 0, w, n_content))
  let buf        = state.buffer
  let cur        = head_cursor(buf)
  let new_scroll = clamp_scroll(buf.scroll_line, rh, cur.pos.line)
  EditorState { ...state, buffer: TextBuffer { ...buf, scroll_line: new_scroll } }
}

/// `true` if anything that could affect which lines should stay visible
/// changed between `before` and `after` — active pane, cursor line, or
/// viewport size. `sync_scroll` should only run when this is true:
/// skipping it otherwise is what lets a deliberate `ScrollViewUp`/
/// `ScrollViewDown` (or a no-op `Tick`/`Ignore` right after one) leave
/// the viewport alone instead of snapping back to the cursor on the very
/// next idle poll — `sync_scroll` itself has no memory of "this scroll
/// was deliberate", it just re-clamps to wherever the cursor currently
/// is, so calling it unconditionally after every action undid wheel
/// scrolling within one ~200ms poll tick.
pub fun view_relevant_change(before: EditorState, after: EditorState) : bool =>
  before.buffer.bid != after.buffer.bid ||
  head_cursor(before.buffer).pos.line != head_cursor(after.buffer).pos.line ||
  before.screen_size != after.screen_size

pub fun pane_left(state: EditorState) : EditorState {
  let (w, h)   = state.screen_size
  let full     = (0, 0, w, h - 2)
  let rects    = split_rect(full, state.panes)
  let (fx, fy) = rect_center(active_rect(state, rects, full))
  move_focus(state, nearest_left(pane_centers(rects), fx, fy))
}

pub fun pane_right(state: EditorState) : EditorState {
  let (w, h)   = state.screen_size
  let full     = (0, 0, w, h - 2)
  let rects    = split_rect(full, state.panes)
  let (fx, fy) = rect_center(active_rect(state, rects, full))
  move_focus(state, nearest_right(pane_centers(rects), fx, fy))
}

pub fun pane_up(state: EditorState) : EditorState {
  let (w, h)   = state.screen_size
  let full     = (0, 0, w, h - 2)
  let rects    = split_rect(full, state.panes)
  let (fx, fy) = rect_center(active_rect(state, rects, full))
  move_focus(state, nearest_up(pane_centers(rects), fx, fy))
}

pub fun pane_down(state: EditorState) : EditorState {
  let (w, h)   = state.screen_size
  let full     = (0, 0, w, h - 2)
  let rects    = split_rect(full, state.panes)
  let (fx, fy) = rect_center(active_rect(state, rects, full))
  move_focus(state, nearest_down(pane_centers(rects), fx, fy))
}

/// Cycle focus to the next pane in document order, wrapping around.
pub fun next_pane(state: EditorState) : EditorState =>
  activate_buffer(state, next_in_order(pane_order(state.panes), state.buffer.bid))

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

// ------------------- Multi-cursor (M20) ------------------------------------

fun is_word_char_str(s: string) : bool =>
  (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || (s >= "0" && s <= "9") || s == "_"

fun is_word_char_at(line_str: string, col_idx: int) : bool {
  if col_idx < 0 || col_idx >= length(line_str) { false }
  else { is_word_char_str(line_str[col_idx: col_idx + 1]) }
}

fun find_word_start(line_str: string, col_idx: int) : int {
  if col_idx <= 0 { 0 }
  else if is_word_char_at(line_str, col_idx - 1) { find_word_start(line_str, col_idx - 1) }
  else { col_idx }
}

fun find_word_end(line_str: string, col_idx: int) : int {
  let n = length(line_str)
  if col_idx >= n { n }
  else if is_word_char_at(line_str, col_idx) { find_word_end(line_str, col_idx + 1) }
  else { col_idx }
}

fun match_is_selected(m: SearchMatch, q_len: int, cs: list<Cursor>) : bool =>
  match cs {
    [] => false,
    [c, ..rest] =>
      match c.anchor {
        None => match_is_selected(m, q_len, rest),
        Some(a) => {
          let (sl, sc, el, ec) = normalize_span(c.pos, a)
          if sl == m.line && sc == m.col && el == m.line && ec == m.col + q_len {
            true
          } else {
            match_is_selected(m, q_len, rest)
          }
        }
      }
  }

fun filter_unselected_matches(matches: list<SearchMatch>, q_len: int, cs: list<Cursor>) : list<SearchMatch> =>
  match matches {
    [] => [],
    [m, ..rest] =>
      if match_is_selected(m, q_len, cs) {
        filter_unselected_matches(rest, q_len, cs)
      } else {
        [m] + filter_unselected_matches(rest, q_len, cs)
      }
  }

fun first_match_after(matches: list<SearchMatch>, p: Position) : maybe<SearchMatch> =>
  match matches {
    [] => None,
    [m, ..rest] =>
      if m.line > p.line || (m.line == p.line && m.col >= p.col) {
        Some(m)
      } else {
        first_match_after(rest, p)
      }
  }

fun head_selection_text(state: EditorState) : maybe<string> {
  let cur = head_cursor(state.buffer)
  match cur.anchor {
    None => None,
    Some(a) => {
      let (sl, sc, el, ec) = normalize_span(cur.pos, a)
      Some(span_text_from_lines(state.buffer.lines, sl, sc, el, ec))
    }
  }
}

/// Add cursor at next match (Ctrl-d): with no selection, selects the word
/// under the head cursor; pressed again with selection active, finds the
/// next occurrence and adds a new cursor with that match selected.
pub fun add_cursor_next_match(state: EditorState) : EditorState {
  let buf = state.buffer
  if !has_any_selection(state) {
    let cur = head_cursor(buf)
    let line_str = list_get(buf.lines, cur.pos.line, "")
    let line_len = length(line_str)
    let col_check =
      if cur.pos.col >= line_len && cur.pos.col > 0 { cur.pos.col - 1 }
      else if cur.pos.col < line_len && !is_word_char_at(line_str, cur.pos.col) && cur.pos.col > 0 && is_word_char_at(line_str, cur.pos.col - 1) { cur.pos.col - 1 }
      else { cur.pos.col }
    if is_word_char_at(line_str, col_check) {
      let w_start = find_word_start(line_str, col_check)
      let w_end   = find_word_end(line_str, col_check)
      let new_cur = Cursor {
        ...cur,
        pos: Position { line: cur.pos.line, col: w_end },
        anchor: Some(Position { line: cur.pos.line, col: w_start }),
        anchor_sticky: false
      }
      let new_cursors = [new_cur] + drop_head_cursor(buf.cursors)
      EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
    } else {
      state
    }
  } else {
    match head_selection_text(state) {
      None => state,
      Some(q) => {
        let all_matches = find_all_matches(buf.lines, q)
        let unselected  = filter_unselected_matches(all_matches, length(q), buf.cursors)
        match unselected {
          [] => state,
          _  => {
            let last_c = last_cursor(buf.cursors)
            let chosen = match first_match_after(unselected, last_c.pos) {
              Some(m) => m,
              None    => match unselected { [m, .._] => m, [] => SearchMatch { line: 0, col: 0 } }
            }
            let new_cur = Cursor {
              cid: next_cid(buf),
              pos: Position { line: chosen.line, col: chosen.col + length(q) },
              anchor: Some(Position { line: chosen.line, col: chosen.col }),
              anchor_sticky: false
            }
            let appended_cs = buf.cursors + [new_cur]
            let new_cursors = finalize_cursors(appended_cs)
            EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
          }
        }
      }
    }
  }
}

/// Collapse all cursors back to the primary cursor and clear selections (Escape).
pub fun collapse_cursors(state: EditorState) : EditorState {
  let buf = state.buffer
  let cur = head_cursor(buf)
  let new_cur = Cursor { ...cur, anchor: None, anchor_sticky: false }
  EditorState { ...state, buffer: TextBuffer { ...buf, cursors: [new_cur] } }
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
    KeyEvent(KMetaSpecial(ArrowLeft))  => PaneLeft,
    KeyEvent(KMetaSpecial(ArrowRight)) => PaneRight,
    KeyEvent(KMetaSpecial(ArrowUp))    => PaneUp,
    KeyEvent(KMetaSpecial(ArrowDown))  => PaneDown,
    KeyEvent(KMetaSpecial(Tab))        => NextPane,
    KeyEvent(KSpecial(Esc))            => CollapseCursors,
    KeyEvent(KShortcut(m, c)) =>
      lookup_binding(state.config.bindings, KeyChord { m: m, c: c }),
    MouseEvent(Press, x, y)      => MouseClick(x, y),
    MouseEvent(MetaPress, x, y)  => MetaMouseClick(x, y),
    MouseEvent(Drag, x, y)       => MouseDrag(x, y),
    MouseEvent(Release, _, _)    => MouseRelease,
    MouseEvent(ScrollUp, x, y)   => ScrollViewUp(x, y),
    MouseEvent(ScrollDown, x, y) => ScrollViewDown(x, y),
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

fun has_nonsticky_anchor(cs: list<Cursor>) : bool =>
  match cs {
    [] => false,
    [c, ..rest] =>
      match c.anchor {
        Some(_) => !c.anchor_sticky || has_nonsticky_anchor(rest),
        None    => has_nonsticky_anchor(rest)
      }
  }

/// Clear non-sticky selections across all cursors (wraps every plain movement action).
fun collapse_unless_sticky(state: EditorState) : EditorState {
  let buf = state.buffer
  if has_nonsticky_anchor(buf.cursors) {
    let new_cursors = map(buf.cursors, (cc) =>
      if cc.anchor_sticky { cc } else { Cursor { ...cc, anchor: None } })
    EditorState { ...state, buffer: TextBuffer { ...buf, cursors: new_cursors } }
  } else {
    state
  }
}

/// Apply an Action to state, producing the next EditorState.
// Save/Copy/Paste/Undo/Redo/Kill*/PromptSubmit no-op here — they carry
// <fsys>/<Clipboard>/<Buffer> effects handled by event_loop, keeping this
// function total for tests and the HiLisp bridge. `Quit` only actually
// quits once `panes` is a single `Leaf` — with 2+ panes open it closes
// the active pane instead (see `close_pane`'s doc comment).
pub fun apply_action(state: EditorState, action: Action) : EditorState =>
  match action {
    Quit         => if is_leaf(state.panes) { EditorState { ...state, should_quit: true } } else { close_pane(state) },
    Insert(c)    => insert_char(state, c),
    NewLine        => insert_newline(state),
    DeleteBackward => delete_backward(state),
    DeleteForward  => delete_forward(state),
    MoveUp         => collapse_unless_sticky(move_up(state)),
    MoveDown     => collapse_unless_sticky(move_down(state)),
    MoveLeft     => collapse_unless_sticky(move_left(state)),
    MoveRight    => collapse_unless_sticky(move_right(state)),
    MoveLineStart => collapse_unless_sticky(move_line_start(state)),
    MoveLineEnd   => collapse_unless_sticky(move_line_end(state)),
    MoveWordForward => collapse_unless_sticky(move_word_forward(state)),
    MoveWordBack    => collapse_unless_sticky(move_word_back(state)),
    Resize(w, h) => EditorState { ...state, screen_size: (w, h) },
    Save         => state, // event_loop: <fsys>
    ReloadConfig => state, // event_loop: <fsys>
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
    VSplit       => open_vsplit_prompt(state),
    HSplit       => open_hsplit_prompt(state),
    PaneLeft     => pane_left(state),
    PaneRight    => pane_right(state),
    PaneUp       => pane_up(state),
    PaneDown     => pane_down(state),
    NextPane     => next_pane(state),
    SetMark      => set_mark(state),
    SelectAll    => select_all(state),
    AddCursorNextMatch => add_cursor_next_match(state),
    CollapseCursors    => collapse_cursors(state),
    MetaMouseClick(x, y) => meta_mouse_click(state, x, y),
    MouseClick(x, y) => mouse_click(state, x, y),
    MouseDrag(x, y)  => mouse_drag(state, x, y),
    MouseRelease     => EditorState { ...state, resizing_divider: None },
    ScrollViewUp(x, y)   => scroll_view(state, x, y, -1),
    ScrollViewDown(x, y) => scroll_view(state, x, y, 1),
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

/// Resolve and apply an event against state in one step, then re-clamp
/// the active buffer's scroll if the action actually moved the cursor,
/// switched panes, or resized the viewport (see `view_relevant_change`)
/// — mirrors `runtime.hc`'s real `event_loop_step`, which does the same
/// around its effectful `dispatch_action`.
pub fun handle_action(state: EditorState, evt: Event) : EditorState => {
  let action = resolve_action(state, evt)
  let next   = apply_action(state, action)
  if view_relevant_change(state, next) { sync_scroll(next) } else { next }
}
