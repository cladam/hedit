// actions_test.hc — pure tests for the step-1 event dispatcher.
//
// No I/O, no effect handlers — just feed events into `handle_action` and
// assert on the resulting `EditorState`. Each `test` block has its own
// inference scope (SKILL §14) so generic helpers stay unconstrained.

import "../src/types"
import "../src/model"
import "../src/actions"

test "typing appends chars to the active line" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  assert(s2.buffer.lines == ["hi"])
  assert(s2.buffer.is_dirty == true)
}

test "ctrl-q sets should_quit" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KShortcut(Ctrl, 'q')))
  assert(s1.should_quit == true)
}

test "resize updates screen size" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, ResizeEvent(120, 40))
  assert(s1.screen_size == (120, 40))
}

test "unhandled event leaves state unchanged" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, Tick)
  assert(s1.buffer.lines == [""])
  assert(s1.should_quit == false)
}

test "is_ctrl / is_alt distinguish modifiers" {
  assert(is_ctrl(Ctrl) == true)
  assert(is_ctrl(Alt)  == false)
  assert(is_alt(Alt)   == true)
  assert(is_alt(Shift) == false)
}
