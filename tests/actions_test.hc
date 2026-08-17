// actions_test.hc — pure tests for the event → Action → state pipeline.
//
// No I/O, no effect handlers — just feed events through the pipeline and
// assert on the resulting `Action` / `EditorState`. Each `test` block has
// its own inference scope (SKILL §14) so generic helpers stay unconstrained.

import "../src/keys"
import "../src/model"
import "../src/actions"

// ------------------- handle_action (Event → EditorState) ---------------

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

// ------------------- Modifier / Key equality ---------------------------

test "enum equality distinguishes modifier variants" {
  assert((Ctrl == Ctrl) == true)
  assert((Ctrl == Alt) == false)
  assert((Alt == Alt) == true)
}

test "enum equality distinguishes key payloads" {
  assert((KShortcut(Ctrl, 'q') == KShortcut(Ctrl, 'q')) == true)
  assert((KShortcut(Ctrl, 'q') == KShortcut(Alt, 'q')) == false)
  assert((KShortcut(Ctrl, 'q') == KShortcut(Ctrl, 'x')) == false)
  assert((KChar('x') == KShortcut(Ctrl, 'q')) == false)
}

// ------------------- resolve_action: config-driven bindings -----------

test "resolve_action maps Ctrl-q to Quit via default_bindings" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'q')))
  assert(a == Quit)
}

test "resolve_action maps Ctrl-s to Save via default_bindings" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 's')))
  assert(a == Save)
}

test "resolve_action returns Ignore for an unbound Ctrl-x" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'x')))
  assert(a == Ignore)
}

test "resolve_action maps every KChar to Insert" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KChar('a'))) == Insert('a'))
  assert(resolve_action(s0, KeyEvent(KChar('Z'))) == Insert('Z'))
}

// ------------------- Copy/Paste resolution (Clipboard land in M3) ------

test "resolve_action maps Ctrl-c to Copy via default_bindings" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'c')))
  assert(a == Copy)
}

test "resolve_action maps Ctrl-v to Paste via default_bindings" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'v')))
  assert(a == Paste)
}

// Pure `apply_action` no-ops Copy/Paste; the actual clipboard round-trip
// lives in event_loop with the Clipboard handler installed (see
// runtime_test.hc). Guarding here that the pure surface stays pure.
test "apply_action leaves state untouched for Copy" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, Copy)
  assert(s1.buffer.lines == [""])
  assert(s1.buffer.is_dirty == false)
}

test "apply_action leaves state untouched for Paste" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, Paste)
  assert(s1.buffer.lines == [""])
  assert(s1.buffer.is_dirty == false)
}

// paste_text is the pure helper event_loop feeds `get_selection()` into.
test "paste_text appends clipboard content to head cursor line" {
  let s0 = init_editor(None)
  let s1 = paste_text(s0, "hello")
  assert(s1.buffer.lines == ["hello"])
  assert(s1.buffer.is_dirty == true)
}

// current_line reads what event_loop hands to `set_selection()` on Copy.
test "current_line returns the head cursor line" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  assert(current_line(s2) == "hi")
}

test "custom bindings override defaults — Ctrl-x becomes Quit" {
  // Simulate a HiLisp init.hl that did `(bind "Ctrl-x" 'quit)`.
  let custom: list<(KeyChord, Action)> =
    [(KeyChord { m: Ctrl, c: 'x' }, Quit)]
  let s0 = init_editor(None)
  let s1 = EditorState { ...s0, config: Config { bindings: custom } }
  // Ctrl-x now resolves to Quit …
  assert(resolve_action(s1, KeyEvent(KShortcut(Ctrl, 'x'))) == Quit)
  // … and Ctrl-q, which was default, is now Ignore (custom map replaces).
  assert(resolve_action(s1, KeyEvent(KShortcut(Ctrl, 'q'))) == Ignore)
}
