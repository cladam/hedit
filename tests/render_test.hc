// render_test.hc — pure tests for render_editor_to_buffer (M2).
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

// ------------------- test 1: structural height --------------------------

test "render height equals screen_size height" {
  let state = EditorState { ...init_editor(None), screen_size: (80, 24) }
  let buf = render_editor_to_buffer(state)
  assert(buf.width == 80)
  assert(buf.height == 24)
  assert(length(buf.lines) == 24)
}

// ------------------- test 2: content row --------------------------------

test "typed content appears in the first content row after the tabline" {
  let s0 = EditorState { ...init_editor(None), screen_size: (40, 10) }
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  let buf = render_editor_to_buffer(s2)
  let first_content = match buf.lines { [_tabline, x, .._] => x, _ => "MISSING" }
  assert(first_content == "hi")
}

// ------------------- test 2b: tabline row --------------------------------

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

// ------------------- test 3: status line --------------------------------

test "status line shows path and dirty flag when buffer is dirty" {
  let s0 = init_editor(Some("/tmp/test.txt"))
  let s1 = handle_action(s0, KeyEvent(KChar('x')))
  let s2 = EditorState { ...s1, screen_size: (80, 5) }
  let buf = render_editor_to_buffer(s2)
  let status = last_or(buf.lines, "MISSING")
  assert(status == "/tmp/test.txt [+]")
}

// ------------------- test 4: explicit status message --------------------

test "explicit status_message overrides the default path line" {
  let s0 = set_status_message(init_editor(None), "File saved")
  let s1 = EditorState { ...s0, screen_size: (80, 5) }
  let buf = render_editor_to_buffer(s1)
  let status = last_or(buf.lines, "MISSING")
  assert(status == "File saved")
}
