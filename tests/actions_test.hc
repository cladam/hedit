// actions_test.hc — pure tests for the step-1 event dispatcher.
//
// No I/O, no effect handlers — just feed events into `handle_action` and
// assert on the resulting `EditorState`. Each `test` block has its own
// inference scope (SKILL §14) so generic helpers stay unconstrained.

import "../src/keys"
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

test "non-ctrl shortcut does not quit" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KShortcut(Alt, 'q')))
  assert(s1.should_quit == false)
}

test "ctrl + non-q does not quit" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KShortcut(Ctrl, 'x')))
  assert(s1.should_quit == false)
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

test "enum equality distinguishes modifier variants" {
  assert((Ctrl == Ctrl) == true)
  assert((Ctrl == Alt)  == false)
  assert((Alt  == Alt)  == true)
}

test "enum equality distinguishes key payloads" {
  assert((KShortcut(Ctrl, 'q') == KShortcut(Ctrl, 'q')) == true)
  assert((KShortcut(Ctrl, 'q') == KShortcut(Alt, 'q')) == false)
  assert((KShortcut(Ctrl, 'q') == KShortcut(Ctrl, 'x')) == false)
  assert((KChar('x') == KShortcut(Ctrl, 'q')) == false)
}
