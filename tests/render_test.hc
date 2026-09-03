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
  assert(first_content == "hi")
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
  assert(buf.highlights == [(2, 0, 3), (2, 8, 11)])
}

test "the find prompt label shows the typed query in the status row" {
  let s0 = EditorState { ...init_editor(None), screen_size: (40, 10) }
  let s1 = apply_action(s0, StartFind)
  let s2 = apply_action(s1, PromptChar('c'))
  let buf = render_editor_to_buffer(s2)
  let status = last_or(buf.lines, "MISSING")
  assert(status == "Find: c")
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
  assert(nth_or(buf.lines, 1, "MISSING") == "left │righ")
}

test "a horizontal split stacks the left buffer's pane above a divider row above the right one" {
  let node = Split(Horizontal, 0.5, Leaf(1), Leaf(2))
  let s0   = with_split_state(["top"], ["bottom"], node, (10, 6))
  let buf  = render_editor_to_buffer(s0)
  // height 6 → n_content 4 → 2 rows top, 1 divider row, 1 row bottom
  assert(nth_or(buf.lines, 1, "MISSING") == "top       ")
  assert(nth_or(buf.lines, 3, "MISSING") == "──────────")
  assert(nth_or(buf.lines, 4, "MISSING") == "bottom    ")
}
