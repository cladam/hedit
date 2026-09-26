// render_test.hc — pure tests for render_editor_to_buffer.
//
// All tests are headless: no Terminal handler, no file I/O.
// We build EditorState values directly and assert on the ScreenBuffer shape.

import "../src/keys"
import "../src/model"
import "../src/actions"
import "../src/render"

// Helper: get the last element of a list, or `default` if empty.
fun last_or(xs: list<string>, default: string) : string =>
  match xs {
    []          => default,
    [x]         => x,
    [_, ..rest] => last_or(rest, default)
  }

// ------------------- structural height --------------------------

test "render height equals screen_size height" {
  let state = EditorState { ...init_editor(None), screen_size: (80, 24) }
  let buf = render_editor_to_buffer(state)
  assert(buf.width == 80)
  assert(buf.height == 24)
  assert(length(buf.lines) == 24)
}

// ------------------- content row --------------------------------

test "typed content appears in the first content row after the tabline" {
  let s0 = EditorState { ...init_editor(None), screen_size: (40, 10) }
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  let buf = render_editor_to_buffer(s2)
  let first_content = match buf.lines { [_tabline, x, .._] => x, _ => "MISSING" }
  assert(first_content == "1 hi")
}

test "line numbers can be disabled through config" {
  let s0 = EditorState { ...init_editor(None), screen_size: (40, 10) }
  let cfg = set_config_value(s0.config, "line-numbers", "false")
  let s1 = EditorState { ...s0, config: cfg }
  let s2 = handle_action(s1, KeyEvent(KChar('h')))
  let buf = render_editor_to_buffer(s2)
  assert(nth_or(buf.lines, 1, "MISSING") == "h")
  assert(buf.cursor_col == 2)
}

test "long content wraps at the screen width and moves the cursor to its continuation row" {
  let s0 = with_lines_render(["Clipboard and history"], (10, 5))
  let wrapped = TextBuffer { ...s0.buffer, cursors: [Cursor { cid: 0, pos: Position { line: 0, col: 13 }, anchor: None, anchor_sticky: false }] }
  let s1 = EditorState { ...s0, buffer: wrapped }
  let buf = render_editor_to_buffer(s1)
  assert(nth_or(buf.lines, 1, "MISSING") == "1 Clipboar")
  assert(nth_or(buf.lines, 2, "MISSING") == "  d and hi")
  assert(nth_or(buf.lines, 3, "MISSING") == "  story")
  assert(buf.cursor_row == 3)
  assert(buf.cursor_col == 8)
}

// ------------------- tabline row --------------------------------

test "tabline shows a single bracketed scratch tab with one buffer open" {
  let s0 = EditorState { ...init_editor(None), screen_size: (40, 10) }
  let buf = render_editor_to_buffer(s0)
  let tabline = match buf.lines { [x, .._] => x, [] => "MISSING" }
  assert(tabline == "[scratch]")
}

test "tabline lists every open buffer, active one bracketed" {
  let s0 = EditorState { ...init_editor(None), screen_size: (40, 10) }
  let s1 = apply_action(s0, NewBuffer)
  let buf = render_editor_to_buffer(s1)
  let tabline = match buf.lines { [x, .._] => x, [] => "MISSING" }
  assert(tabline == "[scratch]|scratch")
}

// ------------------- status line --------------------------------

test "status line shows path and dirty flag when buffer is dirty" {
  let s0 = init_editor(Some("/tmp/test.txt"))
  let s1 = handle_action(s0, KeyEvent(KChar('x')))
  let s2 = EditorState { ...s1, screen_size: (80, 5) }
  let buf = render_editor_to_buffer(s2)
  let status = last_or(buf.lines, "MISSING")
  assert(status == "/tmp/test.txt [+]")
}

// ------------------- explicit status message --------------------

test "explicit status_message overrides the default path line" {
  let s0 = set_status_message(init_editor(None), "File saved")
  let s1 = EditorState { ...s0, screen_size: (80, 5) }
  let buf = render_editor_to_buffer(s1)
  let status = last_or(buf.lines, "MISSING")
  assert(status == "File saved")
}

// ------------------- Find match highlighting (M12) ----------------

fun with_lines_render(lines: list<string>, size: (int, int)) : EditorState {
  let s0  = init_editor(None)
  let buf = TextBuffer { ...s0.buffer, lines: lines }
  EditorState { ...s0, buffer: buf, screen_size: size }
}

test "no active search means no highlight spans" {
  let s0 = EditorState { ...init_editor(None), screen_size: (40, 10) }
  let buf = render_editor_to_buffer(s0)
  assert(buf.highlights == [])
}

test "an active search highlights every visible match" {
  let s0 = with_lines_render(["cat dog cat"], (40, 10))
  let s1 = apply_action(s0, StartFind)
  let s2 = apply_action(s1, PromptChar('c'))
  let s3 = apply_action(s2, PromptChar('a'))
  let s4 = apply_action(s3, PromptChar('t'))
  let buf = render_editor_to_buffer(s4)
  assert(buf.highlights == [(2, 2, 5), (2, 10, 13)])
}

test "the find prompt label shows the typed query in the status row" {
  let s0 = EditorState { ...init_editor(None), screen_size: (40, 10) }
  let s1 = apply_action(s0, StartFind)
  let s2 = apply_action(s1, PromptChar('c'))
  let buf = render_editor_to_buffer(s2)
  let status = last_or(buf.lines, "MISSING")
  assert(status == "Find: c")
}

// ------------------- Selection highlighting (M17) ------------------

test "no active selection means no selection spans" {
  let s0 = EditorState { ...init_editor(None), screen_size: (40, 10) }
  let buf = render_editor_to_buffer(s0)
  assert(buf.selection_spans == [])
}

test "an active single-line selection highlights just its span" {
  let s0 = with_lines_render(["cat dog cat"], (40, 10))
  let s1 = apply_action(s0, SetMark)
  let s2 = handle_action(s1, KeyEvent(KSpecial(ArrowRight)))
  let s3 = handle_action(s2, KeyEvent(KSpecial(ArrowRight)))
  let s4 = handle_action(s3, KeyEvent(KSpecial(ArrowRight)))
  let buf = render_editor_to_buffer(s4)
  assert(buf.selection_spans == [(2, 2, 5)])
}

test "a multi-line selection covers the middle line's full width" {
  let s0 = with_lines_render(["abc", "defg", "hi"], (40, 10))
  let s1 = apply_action(s0, SetMark)
  let s2 = handle_action(s1, KeyEvent(KSpecial(ArrowDown)))
  let s3 = handle_action(s2, KeyEvent(KSpecial(ArrowDown)))
  let s4 = handle_action(s3, KeyEvent(KSpecial(ArrowRight)))
  let buf = render_editor_to_buffer(s4)
  assert(buf.selection_spans == [(2, 2, 5), (3, 2, 6), (4, 2, 3)])
}

// ------------------- Split panes (M15) ----------------------------

fun nth_or(xs: list<string>, idx: int, default: string) : string =>
  match xs {
    []          => default,
    [x, ..rest] => if idx <= 0 { x } else { nth_or(rest, idx - 1, default) }
  }

test "split_rect on a single Leaf yields the whole rect unchanged" {
  let rects = split_rect((0, 0, 80, 24), Leaf(1))
  assert(rects == [(1, (0, 0, 80, 24))])
}

// One column/row is reserved between siblings for the divider (see
// `model.hc`'s `vsplit_extents`/`hsplit_extents`), so panes are 1
// column/row narrower/shorter than a naive `w * ratio` split.
test "split_rect on a vertical split at ratio 0.5 reserves a 1-column divider" {
  let node = Split(Vertical, 0.5, Leaf(1), Leaf(2))
  let rects = split_rect((0, 0, 80, 24), node)
  assert(rects == [(1, (0, 0, 40, 24)), (2, (41, 0, 39, 24))])
}

test "split_rect on a horizontal split at ratio 0.5 reserves a 1-row divider" {
  let node = Split(Horizontal, 0.5, Leaf(1), Leaf(2))
  let rects = split_rect((0, 0, 80, 24), node)
  assert(rects == [(1, (0, 0, 80, 12)), (2, (0, 13, 80, 11))])
}

test "split_dividers on a single Leaf yields no dividers" {
  assert(split_dividers((0, 0, 80, 24), Leaf(1)) == [])
}

test "split_dividers on a vertical split yields one column at the seam" {
  let node = Split(Vertical, 0.5, Leaf(1), Leaf(2))
  assert(split_dividers((0, 0, 80, 24), node) == [(40, 0, 1, 24)])
}

test "split_dividers on a horizontal split yields one row at the seam" {
  let node = Split(Horizontal, 0.5, Leaf(1), Leaf(2))
  assert(split_dividers((0, 0, 80, 24), node) == [(0, 12, 80, 1)])
}

fun with_split_state(lines_a: list<string>, lines_b: list<string>, node: PaneNode, size: (int, int)) : EditorState {
  let s0   = init_editor(None)
  let bufa = TextBuffer { ...s0.buffer, bid: 1, lines: lines_a }
  let bufb = TextBuffer { ...new_buffer(2, None), lines: lines_b }
  EditorState { ...s0, buffer: bufa, background_buffers: [bufb], panes: node, screen_size: size }
}

test "a vertical split renders both panes side by side with a divider between them" {
  let node = Split(Vertical, 0.5, Leaf(1), Leaf(2))
  let s0   = with_split_state(["left"], ["right"], node, (10, 5))
  let buf  = render_editor_to_buffer(s0)
  // width 10 → 5-wide left pane, 1-col divider, 4-wide right pane
  assert(nth_or(buf.lines, 1, "MISSING") == "1 lef│1 ri")
}

test "a long line wraps at its pane width in a vertical split" {
  let node = Split(Vertical, 0.5, Leaf(1), Leaf(2))
  let s0   = with_split_state(["left-hand"], ["right"], node, (10, 5))
  let buf  = render_editor_to_buffer(s0)
  assert(nth_or(buf.lines, 1, "MISSING") == "1 lef│1 ri")
  assert(nth_or(buf.lines, 2, "MISSING") == "  t-h│  gh")
  assert(nth_or(buf.lines, 3, "MISSING") == "  and│  t ")
}

test "a horizontal split stacks the left buffer's pane above a divider row above the right one" {
  let node = Split(Horizontal, 0.5, Leaf(1), Leaf(2))
  let s0   = with_split_state(["top"], ["bottom"], node, (10, 6))
  let buf  = render_editor_to_buffer(s0)
  // height 6 → n_content 4 → 2 rows top, 1 divider row, 1 row bottom
  assert(nth_or(buf.lines, 1, "MISSING") == "1 top     ")
  assert(nth_or(buf.lines, 3, "MISSING") == "──────────")
  assert(nth_or(buf.lines, 4, "MISSING") == "1 bottom  ")
}

// ------------------- Cursor visibility while scrolled (M18 wheel fix) -----
// A mouse wheel scroll moves `TextBuffer.scroll_line` without moving the
// cursor, so the cursor's line can end up outside the visible viewport —
// `cursor_row` is the sentinel `0` in that case (main.hc hides the real
// cursor and skips the cursor-line tint) instead of pinning to whichever
// edge row is nearest, which looked like the cursor was "following" the
// scroll (see effects-journal.md M18).

fun render_lines(n: int) : list<string> =>
  if n <= 0 { [] } else { render_lines(n - 1) + ["line " + show(n)] }

test "cursor_row is 0 (hidden) when the cursor's line is scrolled out of view" {
  let s0 = with_lines_render(render_lines(20), (40, 10)) // n_content = 8
  let scrolled = TextBuffer { ...s0.buffer, scroll_line: 0, cursors: [Cursor { cid: 0, pos: Position { line: 15, col: 0 }, anchor: None, anchor_sticky: false }] }
  let s1  = EditorState { ...s0, buffer: scrolled }
  let buf = render_editor_to_buffer(s1)
  assert(buf.cursor_row == 0)
}

test "cursor_row is a real row when the cursor is within the scrolled viewport" {
  let s0 = with_lines_render(render_lines(20), (40, 10))
  let scrolled = TextBuffer { ...s0.buffer, scroll_line: 10, cursors: [Cursor { cid: 0, pos: Position { line: 12, col: 0 }, anchor: None, anchor_sticky: false }] }
  let s1  = EditorState { ...s0, buffer: scrolled }
  let buf = render_editor_to_buffer(s1)
  assert(buf.cursor_row == 4) // (12 - 10) + 2
}

test "secondary cursor without anchor renders a 1-character selection marker" {
  let c1 = Cursor { cid: 0, pos: Position { line: 0, col: 2 }, anchor: None, anchor_sticky: false }
  let c2 = Cursor { cid: 1, pos: Position { line: 1, col: 3 }, anchor: None, anchor_sticky: false }
  let s0 = with_lines_render(["hello", "world"], (40, 10))
  let s1 = EditorState { ...s0, buffer: TextBuffer { ...s0.buffer, cursors: [c1, c2] } }
  let buf = render_editor_to_buffer(s1)
  // c1 is head cursor (gets hardware cursor_row/col, no fake span)
  // c2 is secondary cursor on line 1 (screen row 3), col 3 -> span (3, 3, 4)
  assert(buf.selection_spans == [(3, 5, 6)])
}

test "multiple cursors with selections render all their spans" {
  let c1 = Cursor { cid: 0, pos: Position { line: 0, col: 4 }, anchor: Some(Position { line: 0, col: 1 }), anchor_sticky: false }
  let c2 = Cursor { cid: 1, pos: Position { line: 1, col: 5 }, anchor: Some(Position { line: 1, col: 2 }), anchor_sticky: false }
  let s0 = with_lines_render(["hello", "world"], (40, 10))
  let s1 = EditorState { ...s0, buffer: TextBuffer { ...s0.buffer, cursors: [c1, c2] } }
  let buf = render_editor_to_buffer(s1)
  assert(buf.selection_spans == [(2, 3, 6), (3, 4, 7)])
}

// ------------------- Undo Tree rendering (M21) --------------------------

test "render_undo_tree_buffer renders title, tree branch lines, and footer" {
  let b0 = with_lines_render(["root"], (80, 24)).buffer
  let b1 = with_lines_render(["branch 1"], (80, 24)).buffer
  let b2 = with_lines_render(["branch 2"], (80, 24)).buffer
  let n1 = UndoNode { id: 1, snapshot: b0, parent: 0, children: [2, 3], last_child: Some(3) }
  let n2 = UndoNode { id: 2, snapshot: b1, parent: 1, children: [], last_child: None }
  let n3 = UndoNode { id: 3, snapshot: b2, parent: 1, children: [], last_child: None }
  let uts = UndoTreeState {
    tree: UndoTree { current_id: 3, nodes: [n1, n2, n3] },
    selected_id: 2,
    original_buffer: b2,
    original_id: 3
  }
  let s0 = init_editor(None)
  let s1 = EditorState { ...s0, screen_size: (80, 6), undo_tree: Some(uts) }
  let buf = render_editor_to_buffer(s1)
  assert(buf.width == 80)
  assert(buf.height == 6)
  assert(length(buf.lines) == 6)
  let l0 = match buf.lines { [x, .._] => x, [] => "" }
  let l1 = match buf.lines { [_, x, .._] => x, _ => "" }
  let l2 = match buf.lines { [_, _, x, .._] => x, _ => "" }
  let l3 = match buf.lines { [_, _, _, x, .._] => x, _ => "" }
  assert(starts_with(l0, "Undo Tree"))
  assert(l1 == "  ○ [1] 1L: \"root\"")
  assert(l2 == "> ├─○ [2] 1L: \"branch 1\"")
  assert(l3 == "  ╰─● [3] 1L: \"branch 2\"")
}

// ------------------- Command Palette rendering (M24) ---------------------

fun line_at(xs: list<string>, idx: int) : string =>
  match xs {
    [] => "",
    [x, ..rest] =>
      if idx <= 0 { x }
      else { line_at(rest, idx - 1) }
  }

test "CommandPrompt renders Command: label in status row and suggestions above it" {
  let s0 = with_lines_render(["some buffer content"], (40, 10))
  let s1 = EditorState { ...s0, prompt: CommandPrompt("sav", 3, 0) }
  let buf = render_editor_to_buffer(s1)
  assert(buf.height == 10)
  assert(length(buf.lines) == 10)

  // Status line is the last line (index 9)
  let status_line = line_at(buf.lines, 9)
  assert(starts_with(status_line, "Command: sav"))

  // Row right above status line should contain suggestion with selection marker
  let sug_line = line_at(buf.lines, 8)
  assert(starts_with(sug_line, "> save"))

  // Cursor is on the status line
  assert(buf.cursor_row == 10)
  assert(buf.cursor_col == length("Command: ") + 3 + 1)
}

test "ShellPrompt renders Shell: label in status row" {
  let s0 = with_lines_render(["content"], (40, 10))
  let s1 = EditorState { ...s0, prompt: ShellPrompt("ls -la", 6) }
  let buf = render_editor_to_buffer(s1)
  let status_line = line_at(buf.lines, 9)
  assert(starts_with(status_line, "Shell: ls -la"))
  assert(buf.cursor_row == 10)
  assert(buf.cursor_col == length("Shell: ") + 6 + 1)
}

// ------------------- Shell output rendering (M26) -----------------------

fun with_shell_output_render(output_rows: list<string>, succeeded: bool, size: (int, int)) : EditorState {
  let view = ShellOutputState { command: "ls", lines: output_rows, scroll_line: 0, succeeded: succeeded }
  EditorState { ...init_editor(None), screen_size: size, shell_output: Some(view) }
}

test "shell output overlay renders command result output and controls" {
  let buf = render_editor_to_buffer(with_shell_output_render(["one", "two"], true, (40, 6)))
  assert(starts_with(line_at(buf.lines, 0), "$ ls — success"))
  assert(line_at(buf.lines, 1) == "one")
  assert(line_at(buf.lines, 2) == "two")
  assert(starts_with(line_at(buf.lines, 5), "1-2/2 | Up/Down"))
  assert(buf.cursor_row == 0)
}

test "successful shell command with empty output renders an explicit marker" {
  let buf = render_editor_to_buffer(with_shell_output_render([""], true, (40, 5)))
  assert(line_at(buf.lines, 1) == "(no output)")
}

test "shell output overlay wraps long lines and slices by visual row" {
  let s0 = with_shell_output_render(["abcdefghijk"], false, (5, 4))
  let view = ShellOutputState { command: "ls", lines: ["abcdefghijk"], scroll_line: 1, succeeded: false }
  let s1 = EditorState { ...s0, shell_output: Some(view) }
  let buf = render_editor_to_buffer(s1)
  assert(starts_with(line_at(buf.lines, 0), "$ ls"))
  assert(line_at(buf.lines, 1) == "fghij")
  assert(line_at(buf.lines, 2) == "k")
  assert(starts_with(line_at(buf.lines, 3), "2-3/"))
}

test "shell output overlay takes precedence over other editor overlays" {
  let s0 = with_shell_output_render(["visible"], true, (40, 5))
  let s1 = EditorState { ...s0, show_help: true }
  let buf = render_editor_to_buffer(s1)
  assert(starts_with(line_at(buf.lines, 0), "$ ls — success"))
  assert(line_at(buf.lines, 1) == "visible")
}
