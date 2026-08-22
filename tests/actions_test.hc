// actions_test.hc — pure tests for the event → Action → state pipeline.
//
// No I/O, no effect handlers — just feed events through the pipeline and
// assert on the resulting `Action` / `EditorState`. Each `test` block has
// its own inference scope (SKILL §14) so generic helpers stay unconstrained.

import "../src/keys"
import "../src/model"
import "../src/actions"

// Small named helper (instead of an inline lambda) so the `TextBuffer`
// receiver type is pinned — avoids the cross-module `hc_lines` collision
// with the prelude's string `lines` function (see repo memory notes).
fun buf_lines(b: TextBuffer) : list<string> => b.lines

// ------------------- handle_action (Event → EditorState) ---------------

test "typing appends chars to the active line" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  assert(s2.buffer.lines == ["hi"])
  assert(s2.buffer.is_dirty == true)
}

// ------------------- Enter / Backspace / arrow movement (M7 revisit) ----

test "typing inserts at the cursor column, not always at end of line" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))    // "hi", cursor at col 2
  let s3 = handle_action(s2, KeyEvent(KSpecial(ArrowLeft)))
  let s4 = handle_action(s3, KeyEvent(KChar('X')))    // insert between h and i
  assert(s4.buffer.lines == ["hXi"])
}

test "enter splits the line at the cursor and moves to column 0 of the next" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  let s3 = handle_action(s2, KeyEvent(KSpecial(Enter)))
  let s4 = handle_action(s3, KeyEvent(KChar('!')))
  assert(s4.buffer.lines == ["hi", "!"])
}

test "backspace deletes the char before the cursor" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  let s3 = handle_action(s2, KeyEvent(KSpecial(Backspace)))
  assert(s3.buffer.lines == ["h"])
}

test "backspace at column 0 merges the line into the previous one" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KSpecial(Enter)))
  let s3 = handle_action(s2, KeyEvent(KChar('i')))
  let s4 = handle_action(s3, KeyEvent(KSpecial(ArrowLeft)))  // col 0 of "i" line
  let s5 = handle_action(s4, KeyEvent(KSpecial(Backspace)))
  assert(s5.buffer.lines == ["hi"])
}

test "backspace at the very start of the buffer is a no-op" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KSpecial(Backspace)))
  assert(s1.buffer.lines == [""])
}

test "arrow keys move the cursor and wrap at line boundaries" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('a')))
  let s2 = handle_action(s1, KeyEvent(KSpecial(Enter)))
  let s3 = handle_action(s2, KeyEvent(KChar('b')))
  // Cursor at end of "b" (line 1, col 1). Up moves to line 0, clamped col.
  let s4 = handle_action(s3, KeyEvent(KSpecial(ArrowUp)))
  let cur4 = head_cursor_pos(s4)
  assert(cur4 == Position { line: 0, col: 1 })
  // Left at col 0 of line 0 is a no-op (nothing before the start).
  let s5 = handle_action(s4, KeyEvent(KSpecial(ArrowLeft)))
  let s6 = handle_action(s5, KeyEvent(KSpecial(ArrowLeft)))
  let cur6 = head_cursor_pos(s6)
  assert(cur6 == Position { line: 0, col: 0 })
}

fun head_cursor_pos(s: EditorState) : Position =>
  match s.buffer.cursors { [] => Position { line: 0, col: 0 }, [x, .._] => x.pos }

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

// ------------------- Undo/Redo resolution (Buffer effect lands in M5) --

test "resolve_action maps Ctrl-z to Undo via default_bindings" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'z')))
  assert(a == Undo)
}

test "resolve_action maps Ctrl-y to Redo via default_bindings" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'y')))
  assert(a == Redo)
}

// Pure `apply_action` no-ops Undo/Redo; the actual history swap lives in
// event_loop with the spawned Buffer handler installed (see spawn_test.hc).
test "apply_action leaves state untouched for Undo" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, Undo)
  assert(s1.buffer.lines == [""])
  assert(s1.buffer.is_dirty == false)
}

test "apply_action leaves state untouched for Redo" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, Redo)
  assert(s1.buffer.lines == [""])
  assert(s1.buffer.is_dirty == false)
}

test "custom bindings override defaults — Ctrl-x becomes Quit" {
  // Simulate a HiLisp init.hl that did `(bind "Ctrl-x" 'quit)`.
  let custom: list<(KeyChord, Action)> =
    [(KeyChord { m: Ctrl, c: 'x' }, Quit)]
  let s0 = init_editor(None)
  let s1 = EditorState { ...s0, config: Config { bindings: custom, values: [], readonly: false } }
  // Ctrl-x now resolves to Quit …
  assert(resolve_action(s1, KeyEvent(KShortcut(Ctrl, 'x'))) == Quit)
  // … and Ctrl-q, which was default, is now Ignore (custom map replaces).
  assert(resolve_action(s1, KeyEvent(KShortcut(Ctrl, 'q'))) == Ignore)
}

// ------------------- Multi-buffer navigation (M5.5) ---------------------
//
// `EditorState.buffer` is always the active buffer; `open_buffers`
// returns the full ring (active first). `NewBuffer` only ever creates an
// in-memory scratch buffer — opening a file from disk needs a
// path-prompt input widget that's deferred (see
// docs/effects-journal.md M5.5 non-goals).

test "resolve_action maps the multi-buffer chords via default_bindings" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'o'))) == NewBuffer)
  assert(resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'n'))) == NextBuffer)
  assert(resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'p'))) == PrevBuffer)
  assert(resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'w'))) == CloseBuffer)
}

test "NewBuffer opens a fresh scratch buffer and keeps the old one open" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = apply_action(s1, NewBuffer)
  // The new buffer is active and empty …
  assert(s2.buffer.lines == [""])
  // … and the "h" buffer is still open in the background.
  let names = map(s2.background_buffers, buf_lines)
  assert(names == [["h"]])
}

test "NextBuffer/PrevBuffer cycle through all open buffers and wrap" {
  let s0 = init_editor(None)                    // buffer A: [""]
  let s1 = handle_action(s0, KeyEvent(KChar('a')))
  let s2 = apply_action(s1, NewBuffer)           // buffer B: [""], A backgrounded
  let s3 = handle_action(s2, KeyEvent(KChar('b')))
  // Open buffers, active first: [B:"b", A:"a"]
  assert(s3.buffer.lines == ["b"])
  let s4 = apply_action(s3, NextBuffer)          // wraps back to A
  assert(s4.buffer.lines == ["a"])
  let s5 = apply_action(s4, NextBuffer)          // wraps forward to B again
  assert(s5.buffer.lines == ["b"])
  let s6 = apply_action(s5, PrevBuffer)          // back to A
  assert(s6.buffer.lines == ["a"])
}

test "NextBuffer/PrevBuffer are no-ops with a single open buffer" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, NextBuffer)
  let s2 = apply_action(s1, PrevBuffer)
  assert(s2.buffer.lines == [""])
  assert(length(s2.background_buffers) == 0)
}

test "CloseBuffer drops the active buffer and promotes the next one" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('a')))
  let s2 = apply_action(s1, NewBuffer)
  let s3 = handle_action(s2, KeyEvent(KChar('b')))
  let s4 = apply_action(s3, CloseBuffer)         // closes "b", "a" becomes active
  assert(s4.buffer.lines == ["a"])
  assert(length(s4.background_buffers) == 0)
}

test "CloseBuffer on the last remaining buffer is a no-op with a status message" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, CloseBuffer)
  assert(s1.buffer.lines == [""])
  assert(s1.status_message == Some("Can't close the last buffer"))
}
