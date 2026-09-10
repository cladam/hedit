// actions_test.hc — pure tests for the event → Action → state pipeline.
//
// No I/O, no effect handlers — just feed events through the pipeline and
// assert on the resulting `Action` / `EditorState`. Each `test` block has
// its own inference scope so generic helpers stay unconstrained.

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

// ------------------- Enter / Backspace / arrow movement  --------------

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

// ------------------- Stage 1 readline chords (docs/new-keybindings.txt) --

test "Ctrl-a/Ctrl-e move to the start/end of the line via default_bindings" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  let s3 = handle_action(s2, KeyEvent(KShortcut(Ctrl, 'a')))
  assert(head_cursor_pos(s3) == Position { line: 0, col: 0 })
  let s4 = handle_action(s3, KeyEvent(KShortcut(Ctrl, 'e')))
  assert(head_cursor_pos(s4) == Position { line: 0, col: 2 })
}

test "Ctrl-b is unbound (M12: readline Ctrl-b/Ctrl-f retired in favour of arrows + find)" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  let s3 = handle_action(s2, KeyEvent(KShortcut(Ctrl, 'b')))
  assert(head_cursor_pos(s3) == Position { line: 0, col: 2 })
}

test "Ctrl-d deletes the char under the cursor (forward-delete)" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  let s3 = handle_action(s2, KeyEvent(KShortcut(Ctrl, 'a')))
  let s4 = handle_action(s3, KeyEvent(KShortcut(Ctrl, 'd')))
  assert(s4.buffer.lines == ["i"])
}

test "delete_forward at the end of a non-last line merges the next line up" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('a')))
  let s2 = handle_action(s1, KeyEvent(KSpecial(Enter)))
  let s3 = handle_action(s2, KeyEvent(KChar('b')))
  let s4 = handle_action(s3, KeyEvent(KSpecial(ArrowUp))) // back to line 0, end of "a"
  let s5 = apply_action(s4, DeleteForward)
  assert(s5.buffer.lines == ["ab"])
}

test "kill_line_text/kill_line kill from the cursor to the end of the line" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  let s3 = handle_action(s2, KeyEvent(KChar('!')))
  let s4 = handle_action(s3, KeyEvent(KShortcut(Ctrl, 'a')))
  let s5 = handle_action(s4, KeyEvent(KSpecial(ArrowRight)))
  assert(kill_line_text(s5) == "i!")
  let s6 = kill_line(s5)
  assert(s6.buffer.lines == ["h"])
}

test "resolve_action maps Ctrl-k to KillLine via default_bindings" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'k'))) == KillLine)
}

test "kill_word_back_text/delete_word_back kill the whitespace-delimited word before the cursor" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('a')))
  let s2 = handle_action(s1, KeyEvent(KChar(' ')))
  let s3 = handle_action(s2, KeyEvent(KChar('b')))
  let s4 = handle_action(s3, KeyEvent(KChar('c')))
  assert(kill_word_back_text(s4) == "bc")
  let s5 = delete_word_back(s4)
  assert(s5.buffer.lines == ["a "])
  assert(head_cursor_pos(s5) == Position { line: 0, col: 2 })
}

test "resolve_action maps Ctrl-w to KillWordBack via default_bindings" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'w'))) == KillWordBack)
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

// ------------------- Copy/Paste resolution ---------------------

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

// ------------------- Undo/Redo resolution  ---------------------

test "resolve_action maps Ctrl-z to Undo via default_bindings" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'z')))
  assert(a == Undo)
}

test "resolve_action maps Ctrl-r to Redo via default_bindings" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'r')))
  assert(a == Redo)
}

test "resolve_action maps Ctrl-y to Paste (yank) via default_bindings" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'y')))
  assert(a == Paste)
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

// ------------------- Multi-buffer navigation  --------------------------
//
// `EditorState.buffer` is always the active buffer; `open_buffers`
// returns the full ring (active first). `NewBuffer` only ever creates an
// in-memory scratch buffer — opening a file from disk needs a
// path-prompt input widget that's deferred (see
// docs/effects-journal.md M5.5 non-goals).

// Stage 1 remap (docs/new-keybindings.txt): NewBuffer/NextBuffer/
// PrevBuffer/CloseBuffer move to Meta-o/Meta-n/Meta-p/Meta-w — dormant
// until Stage 2's FFI decoder emits real Meta chords, but already
// resolvable here since resolve_action only cares about the KeyChord.
test "resolve_action maps the multi-buffer chords via default_bindings" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KShortcut(Meta, 'o'))) == NewBuffer)
  assert(resolve_action(s0, KeyEvent(KShortcut(Meta, 'n'))) == NextBuffer)
  assert(resolve_action(s0, KeyEvent(KShortcut(Meta, 'p'))) == PrevBuffer)
  assert(resolve_action(s0, KeyEvent(KShortcut(Meta, 'w'))) == CloseBuffer)
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

// ------------------- Save-As / Open prompt --------------------------

test "resolve_action maps Ctrl-o to OpenFile via default_bindings" {
  let s0 = init_editor(None)
  let a  = resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'o')))
  assert(a == OpenFile)
}

test "OpenFile opens an Open prompt with empty text" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  assert(s1.prompt == OpenPrompt("", 0))
}

test "while a prompt is active, typing resolves to PromptChar not Insert" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  assert(resolve_action(s1, KeyEvent(KChar('a'))) == PromptChar('a'))
}

test "while a prompt is active, Enter/Backspace/Esc resolve to prompt actions" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  assert(resolve_action(s1, KeyEvent(KSpecial(Enter))) == PromptSubmit)
  assert(resolve_action(s1, KeyEvent(KSpecial(Backspace))) == PromptBackspace)
  assert(resolve_action(s1, KeyEvent(KSpecial(Esc))) == PromptCancel)
}

test "a resize event still resolves to Resize while a prompt is active" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  assert(resolve_action(s1, ResizeEvent(100, 40)) == Resize(100, 40))
}

// A closed/EOF'd stdin decodes to the same synthetic Ctrl-q event as a
// real keypress (see keys.hc::decode_key) — without this, a prompt left
// open when input ends would spin `event_loop` forever instead of exiting.
test "Ctrl-q still resolves to Quit even while a prompt is active" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  assert(resolve_action(s1, KeyEvent(KShortcut(Ctrl, 'q'))) == Quit)
}

test "PromptChar/PromptBackspace edit the prompt text without touching the buffer" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  let s2 = apply_action(s1, PromptChar('a'))
  let s3 = apply_action(s2, PromptChar('b'))
  assert(s3.prompt == OpenPrompt("ab", 2))
  let s4 = apply_action(s3, PromptBackspace)
  assert(s4.prompt == OpenPrompt("a", 1))
  assert(s4.buffer.lines == [""])
}

test "PromptBackspace on empty prompt text is a no-op" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  let s2 = apply_action(s1, PromptBackspace)
  assert(s2.prompt == OpenPrompt("", 0))
}

test "PromptCancel clears the prompt back to NoPrompt, discarding typed text" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  let s2 = apply_action(s1, PromptChar('x'))
  let s3 = apply_action(s2, PromptCancel)
  assert(s3.prompt == NoPrompt)
}

test "apply_action leaves state untouched for PromptSubmit (handled in event_loop)" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  let s2 = apply_action(s1, PromptChar('x'))
  let s3 = apply_action(s2, PromptSubmit)
  assert(s3.prompt == OpenPrompt("x", 1))
}

// ------------------- Prompt cursor movement -----------------------

test "PromptMoveStart/PromptMoveLeft/PromptMoveRight/PromptMoveEnd move the cursor" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  let s2 = apply_action(s1, PromptChar('a'))
  let s3 = apply_action(s2, PromptChar('b'))
  let s4 = apply_action(s3, PromptChar('c'))
  assert(s4.prompt == OpenPrompt("abc", 3))
  let s5 = apply_action(s4, PromptMoveStart)
  assert(s5.prompt == OpenPrompt("abc", 0))
  let s6 = apply_action(s5, PromptMoveRight)
  assert(s6.prompt == OpenPrompt("abc", 1))
  let s7 = apply_action(s6, PromptMoveEnd)
  assert(s7.prompt == OpenPrompt("abc", 3))
  let s8 = apply_action(s7, PromptMoveLeft)
  assert(s8.prompt == OpenPrompt("abc", 2))
}

test "PromptChar inserts at the cursor, not just at the end" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  let s2 = apply_action(s1, PromptChar('a'))
  let s3 = apply_action(s2, PromptChar('c'))
  let s4 = apply_action(s3, PromptMoveLeft)
  let s5 = apply_action(s4, PromptChar('b'))
  assert(s5.prompt == OpenPrompt("abc", 2))
}

test "PromptDeleteForward removes the char under the prompt cursor" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  let s2 = apply_action(s1, PromptChar('a'))
  let s3 = apply_action(s2, PromptChar('b'))
  let s4 = apply_action(s3, PromptMoveStart)
  let s5 = apply_action(s4, PromptDeleteForward)
  assert(s5.prompt == OpenPrompt("b", 0))
}

test "prompt_kill_text/prompt_truncate kill from the cursor to the end" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, OpenFile)
  let s2 = apply_action(s1, PromptChar('a'))
  let s3 = apply_action(s2, PromptChar('b'))
  let s4 = apply_action(s3, PromptChar('c'))
  let s5 = apply_action(s4, PromptMoveStart)
  let s6 = apply_action(s5, PromptMoveRight)
  assert(prompt_kill_text(s6) == "bc")
  let s7 = prompt_truncate(s6)
  assert(s7.prompt == OpenPrompt("a", 1))
}

// ------------------- Help overlay -----------------------------------

test "resolve_action maps Ctrl-g to ToggleHelp via default_bindings" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'g'))) == ToggleHelp)
}

test "ToggleHelp flips show_help on and back off" {
  let s0 = init_editor(None)
  assert(s0.show_help == false)
  let s1 = apply_action(s0, ToggleHelp)
  assert(s1.show_help == true)
  let s2 = apply_action(s1, ToggleHelp)
  assert(s2.show_help == false)
}

test "while help is showing, any keypress resolves to ToggleHelp (closes it)" {
  let s0 = apply_action(init_editor(None), ToggleHelp)
  assert(resolve_action(s0, KeyEvent(KChar('x'))) == ToggleHelp)
  assert(resolve_action(s0, KeyEvent(KSpecial(Enter))) == ToggleHelp)
}

// Regression: the periodic idle-poll `Tick` (see keys.hc) must NOT close
// the help overlay — it isn't a keypress. Without this, the overlay
// closed itself ~200ms after opening, before a user could read it.
test "while help is showing, a Tick event does not close it" {
  let s0 = apply_action(init_editor(None), ToggleHelp)
  assert(resolve_action(s0, Tick) == Ignore)
}

test "Ctrl-q still resolves to Quit even while help is showing" {
  let s0 = apply_action(init_editor(None), ToggleHelp)
  assert(resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'q'))) == Quit)
}

test "a resize event still resolves to Resize while help is showing" {
  let s0 = apply_action(init_editor(None), ToggleHelp)
  assert(resolve_action(s0, ResizeEvent(100, 40)) == Resize(100, 40))
}

// ------------------- Find (M12) --------------------------------------

fun with_lines(lines: list<string>) : EditorState {
  let s0  = init_editor(None)
  let buf = TextBuffer { ...s0.buffer, lines: lines }
  EditorState { ...s0, buffer: buf }
}

/// `n` placeholder lines — used to build a buffer taller than one
/// screen's worth of content rows, for scroll-related tests.
fun many_lines(n: int) : list<string> =>
  if n <= 0 { [] } else { many_lines(n - 1) + ["line " + show(n)] }

test "resolve_action maps Ctrl-f to StartFind via default_bindings" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KShortcut(Ctrl, 'f'))) == StartFind)
}

test "StartFind opens FindPrompt with an empty query and a fresh search" {
  let s0 = apply_action(init_editor(None), StartFind)
  assert(s0.prompt == FindPrompt("", 0))
  assert(s0.search == ActiveSearch("", [], -1))
}

test "typing into FindPrompt re-scans the buffer for matches" {
  let s0 = with_lines(["one cat", "two cats", "no match here"])
  let s1 = apply_action(s0, StartFind)
  let s2 = apply_action(s1, PromptChar('c'))
  let s3 = apply_action(s2, PromptChar('a'))
  let s4 = apply_action(s3, PromptChar('t'))
  let s5 = s4.search
  assert(s5 == ActiveSearch("cat", [SearchMatch { line: 0, col: 4 }, SearchMatch { line: 1, col: 4 }], -1))
}

test "PromptBackspace/PromptDeleteForward in FindPrompt also refresh matches" {
  let s0 = with_lines(["cats and cats"])
  let s1 = apply_action(s0, StartFind)
  let s2 = apply_action(s1, PromptChar('c'))
  let s3 = apply_action(s2, PromptChar('a'))
  let s4 = apply_action(s3, PromptChar('t'))
  let s5 = apply_action(s4, PromptChar('s'))
  let s6 = apply_action(s5, PromptBackspace)
  assert(s6.search == ActiveSearch("cat", [SearchMatch { line: 0, col: 0 }, SearchMatch { line: 0, col: 9 }], -1))
}

test "find_all_matches finds every non-overlapping occurrence, case-sensitive" {
  assert(find_all_matches(["ababab"], "ab") == [SearchMatch { line: 0, col: 0 }, SearchMatch { line: 0, col: 2 }, SearchMatch { line: 0, col: 4 }])
  assert(find_all_matches(["Cat cat"], "cat") == [SearchMatch { line: 0, col: 4 }])
  assert(find_all_matches(["no query"], "") == [])
}

test "FindNext jumps to the next match, wrapping past the last one" {
  let s0 = with_lines(["cat dog cat"])
  let s1 = apply_action(s0, StartFind)
  let s2 = apply_action(s1, PromptChar('c'))
  let s3 = apply_action(s2, PromptChar('a'))
  let s4 = apply_action(s3, PromptChar('t'))
  let s5 = apply_action(s4, FindNext) // cursor at col 0 -> first match strictly after is col 8
  assert(head_cursor_pos(s5) == Position { line: 0, col: 8 })
  let s6 = apply_action(s5, FindNext) // wraps back to col 0
  assert(head_cursor_pos(s6) == Position { line: 0, col: 0 })
}

test "FindPrev jumps to the previous match, wrapping before the first one" {
  let s0 = with_lines(["cat dog cat"])
  let s1 = apply_action(s0, StartFind)
  let s2 = apply_action(s1, PromptChar('c'))
  let s3 = apply_action(s2, PromptChar('a'))
  let s4 = apply_action(s3, PromptChar('t'))
  let s5 = apply_action(s4, FindPrev) // cursor at col 0 -> wraps to the last match, col 8
  assert(head_cursor_pos(s5) == Position { line: 0, col: 8 })
  let s6 = apply_action(s5, FindPrev) // steps back to col 0
  assert(head_cursor_pos(s6) == Position { line: 0, col: 0 })
}

test "FindNext/FindPrev are a no-op with no active search" {
  let s0 = with_lines(["cat dog cat"])
  let s1 = apply_action(s0, FindNext)
  assert(head_cursor_pos(s1) == Position { line: 0, col: 0 })
  assert(s1.status_message == Some("No active search"))
}

test "submit_find (Enter) closes the prompt and jumps to the next match" {
  let s0 = with_lines(["cat dog cat"])
  let s1 = apply_action(s0, StartFind)
  let s2 = apply_action(s1, PromptChar('c'))
  let s3 = apply_action(s2, PromptChar('a'))
  let s4 = apply_action(s3, PromptChar('t'))
  let s5 = submit_find(s4)
  assert(s5.prompt == NoPrompt)
  assert(head_cursor_pos(s5) == Position { line: 0, col: 8 })
  // search stays active after Enter so Ctrl-Right/Ctrl-Left keep working
  let s6 = apply_action(s5, FindNext)
  assert(head_cursor_pos(s6) == Position { line: 0, col: 0 })
}

test "PromptCancel (Esc) on FindPrompt clears the search entirely" {
  let s0 = with_lines(["cat dog cat"])
  let s1 = apply_action(s0, StartFind)
  let s2 = apply_action(s1, PromptChar('c'))
  let s3 = apply_action(s2, PromptChar('a'))
  let s4 = apply_action(s3, PromptChar('t'))
  let s5 = apply_action(s4, PromptCancel)
  assert(s5.prompt == NoPrompt)
  assert(s5.search == NoSearch)
}

test "Ctrl-Right/Ctrl-Left resolve to FindNext/FindPrev in normal editing" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KCtrlSpecial(ArrowRight))) == FindNext)
  assert(resolve_action(s0, KeyEvent(KCtrlSpecial(ArrowLeft))) == FindPrev)
}

test "Ctrl-Right/Ctrl-Left also resolve to FindNext/FindPrev while FindPrompt is open" {
  let s0 = apply_action(init_editor(None), StartFind)
  assert(resolve_action(s0, KeyEvent(KCtrlSpecial(ArrowRight))) == FindNext)
  assert(resolve_action(s0, KeyEvent(KCtrlSpecial(ArrowLeft))) == FindPrev)
}

// ------------------- buffer stats (M13) --------------------------------

test "line_count counts every line, including a single empty scratch line" {
  assert(line_count(init_editor(None).buffer) == 1)
  assert(line_count(with_lines(["a", "b", "c"]).buffer) == 3)
  assert(line_count(with_lines([]).buffer) == 0)
}

test "word_count counts whitespace-delimited words across every line" {
  assert(word_count(with_lines(["one two", "three"]).buffer) == 3)
  assert(word_count(with_lines(["  leading  spaces  "]).buffer) == 2)
  assert(word_count(with_lines([""]).buffer) == 0)
}

test "char_count sums line lengths, not counting newlines" {
  assert(char_count(with_lines(["abc", "de"]).buffer) == 5)
  assert(char_count(with_lines([""]).buffer) == 0)
}

// ------------------- Pane focus movement (M15 follow-up) ---------------

fun with_two_panes(node: PaneNode) : EditorState {
  let s0   = init_editor(None)
  let bufa = TextBuffer { ...s0.buffer, bid: 0, lines: ["a"] }
  let bufb = TextBuffer { ...new_buffer(1, None), lines: ["b"] }
  EditorState { ...s0, buffer: bufa, background_buffers: [bufb], panes: node, screen_size: (80, 24) }
}

test "PaneRight/PaneLeft move focus between two vertically split panes" {
  let node = Split(Vertical, 0.5, Leaf(0), Leaf(1))
  let s0 = with_two_panes(node)
  let s1 = apply_action(s0, PaneRight)
  assert(s1.buffer.bid == 1)
  assert(s1.buffer.lines == ["b"])
  let s2 = apply_action(s1, PaneLeft)
  assert(s2.buffer.bid == 0)
  assert(s2.buffer.lines == ["a"])
}

test "PaneDown/PaneUp move focus between two horizontally split panes" {
  let node = Split(Horizontal, 0.5, Leaf(0), Leaf(1))
  let s0 = with_two_panes(node)
  let s1 = apply_action(s0, PaneDown)
  assert(s1.buffer.bid == 1)
  let s2 = apply_action(s1, PaneUp)
  assert(s2.buffer.bid == 0)
}

test "NextPane cycles through panes in document order, wrapping" {
  let node = Split(Vertical, 0.5, Leaf(0), Leaf(1))
  let s0 = with_two_panes(node)
  let s1 = apply_action(s0, NextPane)
  assert(s1.buffer.bid == 1)
  let s2 = apply_action(s1, NextPane)
  assert(s2.buffer.bid == 0)
}

test "pane-focus actions are a no-op with only one pane" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, PaneRight)
  assert(s1.buffer.bid == s0.buffer.bid)
  let s2 = apply_action(s0, NextPane)
  assert(s2.buffer.bid == s0.buffer.bid)
}

test "resolve_action maps Meta-Arrows/Meta-Tab to pane-focus actions" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KMetaSpecial(ArrowLeft))) == PaneLeft)
  assert(resolve_action(s0, KeyEvent(KMetaSpecial(ArrowRight))) == PaneRight)
  assert(resolve_action(s0, KeyEvent(KMetaSpecial(ArrowUp))) == PaneUp)
  assert(resolve_action(s0, KeyEvent(KMetaSpecial(ArrowDown))) == PaneDown)
  assert(resolve_action(s0, KeyEvent(KMetaSpecial(Tab))) == NextPane)
}

// ------------------- Ctrl-q closes the active pane, not hedit (M15) -----

test "Quit closes the active pane instead of quitting when 2+ panes are open" {
  let node = Split(Vertical, 0.5, Leaf(0), Leaf(1))
  let s0   = with_two_panes(node)
  let s1   = apply_action(s0, Quit)
  assert(s1.should_quit == false)
  assert(s1.buffer.bid == 1)
  assert(s1.buffer.lines == ["b"])
  assert(s1.panes == Leaf(1))
  assert(s1.background_buffers == [])
}

test "Quit actually quits once panes has collapsed back to a single Leaf" {
  let s0 = init_editor(None)
  let s1 = apply_action(s0, Quit)
  assert(s1.should_quit == true)
}

// ------------------- Selection ranges (M17) -----------------------------

test "resolve_action maps Ctrl-Space to SetMark via default_bindings" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KShortcut(Ctrl, ' '))) == SetMark)
}

test "resolve_action maps Meta-a to SelectAll via default_bindings" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, KeyEvent(KShortcut(Meta, 'a'))) == SelectAll)
}

test "set_mark starts a selection at the cursor, then clears it on a second press" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  assert(selection_span(s2) == None)
  let s3 = apply_action(s2, SetMark)
  assert(selection_span(s3) == Some((0, 2, 0, 2)))
  let s4 = apply_action(s3, SetMark)
  assert(selection_span(s4) == None)
}

test "moving the cursor after SetMark extends the selection" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('a')))
  let s2 = handle_action(s1, KeyEvent(KChar('b')))
  let s3 = handle_action(s2, KeyEvent(KChar('c')))
  let s4 = apply_action(s3, SetMark) // mark at col 3
  let s5 = handle_action(s4, KeyEvent(KShortcut(Ctrl, 'a'))) // move to col 0
  assert(selection_span(s5) == Some((0, 0, 0, 3)))
  assert(selection_text(s5) == Some("abc"))
}

test "select_all selects the whole buffer" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('a')))
  let s2 = handle_action(s1, KeyEvent(KSpecial(Enter)))
  let s3 = handle_action(s2, KeyEvent(KChar('b')))
  let s4 = apply_action(s3, SelectAll)
  assert(selection_span(s4) == Some((0, 0, 1, 1)))
  assert(selection_text(s4) == Some("a\nb"))
}

test "selection_text spans multiple lines, joined with newlines" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('a')))
  let s2 = handle_action(s1, KeyEvent(KSpecial(Enter)))
  let s3 = handle_action(s2, KeyEvent(KChar('b')))
  let s4 = handle_action(s3, KeyEvent(KShortcut(Ctrl, 'a'))) // col 0 of "b"
  let s5 = apply_action(s4, SetMark)                          // mark at (1, 0)
  let s6 = handle_action(s5, KeyEvent(KSpecial(ArrowUp)))     // cursor -> (0, 0)
  assert(selection_span(s6) == Some((0, 0, 1, 0)))
  assert(selection_text(s6) == Some("a\n"))
}

test "selection_text is None outside an active selection" {
  let s0 = init_editor(None)
  assert(selection_text(s0) == None)
}

test "delete_selection removes a single-line span and clears the anchor" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('a')))
  let s2 = handle_action(s1, KeyEvent(KChar('b')))
  let s3 = handle_action(s2, KeyEvent(KChar('c')))
  let s4 = handle_action(s3, KeyEvent(KShortcut(Ctrl, 'a')))
  let s5 = apply_action(s4, SetMark)
  let s6 = handle_action(s5, KeyEvent(KShortcut(Ctrl, 'e')))
  let s7 = delete_selection(s6)
  assert(s7.buffer.lines == [""])
  assert(selection_span(s7) == None)
}

test "delete_selection joins a multi-line span into one line" {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('a')))
  let s2 = handle_action(s1, KeyEvent(KSpecial(Enter)))
  let s3 = handle_action(s2, KeyEvent(KChar('b')))
  let s4 = handle_action(s3, KeyEvent(KShortcut(Ctrl, 'a')))
  let s5 = apply_action(s4, SetMark)
  let s6 = handle_action(s5, KeyEvent(KSpecial(ArrowUp)))
  let s7 = handle_action(s6, KeyEvent(KShortcut(Ctrl, 'a')))
  let s8 = delete_selection(s7)
  assert(s8.buffer.lines == ["b"])
}

// ------------------- SGR mouse support (M18) ------------------------------
// Screen coordinates are 1-indexed (row 1 = tabline, rows 2..h-1 = content,
// row h = status), matching render.hc's layout — see screen_to_buffer_pos.

test "resolve_action maps a mouse Press/Drag to MouseClick/MouseDrag" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, MouseEvent(Press, 5, 3)) == MouseClick(5, 3))
  assert(resolve_action(s0, MouseEvent(Drag, 5, 3)) == MouseDrag(5, 3))
}

test "resolve_action maps mouse wheel events to ScrollViewUp/ScrollViewDown" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, MouseEvent(ScrollUp, 5, 3)) == ScrollViewUp(5, 3))
  assert(resolve_action(s0, MouseEvent(ScrollDown, 5, 3)) == ScrollViewDown(5, 3))
}

test "resolve_action maps a mouse Release to MouseRelease" {
  let s0 = init_editor(None)
  assert(resolve_action(s0, MouseEvent(Release, 5, 3)) == MouseRelease)
}

test "mouse events are ignored while a prompt or the help overlay is active" {
  let sp = apply_action(init_editor(None), StartFind)
  assert(resolve_action(sp, MouseEvent(Press, 5, 3)) == Ignore)
  let sh = apply_action(init_editor(None), ToggleHelp)
  assert(resolve_action(sh, MouseEvent(Press, 5, 3)) == Ignore)
}

test "screen_to_buffer_pos maps a content-row click to the right buffer position" {
  let s0 = with_lines(["hello", "world"])
  assert(screen_to_buffer_pos(s0, 3, 2) == Some((s0.buffer.bid, Position { line: 0, col: 2 })))
  assert(screen_to_buffer_pos(s0, 1, 3) == Some((s0.buffer.bid, Position { line: 1, col: 0 })))
}

test "screen_to_buffer_pos is None on the tabline/status row" {
  let s0 = with_lines(["hello"])
  assert(screen_to_buffer_pos(s0, 3, 1) == None)  // tabline
  assert(screen_to_buffer_pos(s0, 3, 24) == None) // status row
}

test "MouseClick places the cursor at the clicked position" {
  let s0 = with_lines(["hello world"])
  let s1 = apply_action(s0, MouseClick(6, 2))
  assert(head_cursor_pos(s1) == Position { line: 0, col: 5 })
}

test "MouseClick clears any active selection" {
  let s0 = with_lines(["hello world"])
  let s1 = apply_action(s0, SetMark)
  let s2 = handle_action(s1, KeyEvent(KSpecial(ArrowRight)))
  assert(selection_span(s2) != None)
  let s3 = apply_action(s2, MouseClick(6, 2))
  assert(selection_span(s3) == None)
  assert(head_cursor_pos(s3) == Position { line: 0, col: 5 })
}

test "MouseClick on the tabline/status row is a no-op" {
  let s0 = with_lines(["hello"])
  let before = head_cursor_pos(s0)
  let s1 = apply_action(s0, MouseClick(1, 1))
  assert(head_cursor_pos(s1) == before)
}

test "MouseDrag after MouseClick extends a selection from the click" {
  let s0 = with_lines(["hello world"])
  let s1 = apply_action(s0, MouseClick(1, 2))  // col 0
  let s2 = apply_action(s1, MouseDrag(6, 2))   // col 5 — first drag sets the anchor
  assert(selection_span(s2) == Some((0, 0, 0, 5)))
  let s3 = apply_action(s2, MouseDrag(9, 2))   // col 8 — anchor stays put
  assert(selection_span(s3) == Some((0, 0, 0, 8)))
}

// A drag-created selection is non-sticky: unlike SetMark, plain arrow
// movement afterward collapses it instead of extending it (matches a
// mouse click) — otherwise navigating away with arrows then Paste
// silently replaced the stale selection instead of inserting (M18
// follow-up: real-terminal testing found this exact surprise).
test "a plain arrow move after MouseDrag collapses the selection instead of extending it" {
  let s0 = with_lines(["hello world", "second line"])
  let s1 = apply_action(s0, MouseClick(1, 2))
  let s2 = apply_action(s1, MouseDrag(6, 2))
  assert(selection_span(s2) != None)
  let s3 = handle_action(s2, KeyEvent(KSpecial(ArrowDown)))
  assert(selection_span(s3) == None)
}

test "a plain arrow move after SelectAll collapses the selection instead of extending it" {
  let s0 = with_lines(["hello world", "second line"])
  let s1 = apply_action(s0, SelectAll)
  assert(selection_span(s1) != None)
  let s2 = handle_action(s1, KeyEvent(KSpecial(ArrowLeft)))
  assert(selection_span(s2) == None)
}

test "a plain arrow move after SetMark still extends the selection (sticky)" {
  let s0 = with_lines(["hello world"])
  let s1 = apply_action(s0, SetMark)
  let s2 = handle_action(s1, KeyEvent(KSpecial(ArrowRight)))
  assert(selection_span(s2) != None)
}

test "MouseClick focuses whichever split pane the click landed in" {
  let node = Split(Vertical, 0.5, Leaf(0), Leaf(1))
  let s0 = with_two_panes(node)
  let s1 = apply_action(s0, MouseClick(42, 2)) // right pane (bid 1)
  assert(s1.buffer.bid == 1)
  assert(head_cursor_pos(s1) == Position { line: 0, col: 0 })
  let s2 = apply_action(s1, MouseClick(1, 2))  // left pane (bid 0)
  assert(s2.buffer.bid == 0)
}

// ------------------- Divider drag-resize (M18 follow-up) ------------------
// Screen (80, 24) -> n_content 22, w 80; a vertical split at ratio 0.5
// reserves its divider at content column 40 (screen x 41).

test "MouseClick on a divider starts a resize gesture instead of moving the cursor" {
  let node = Split(Vertical, 0.5, Leaf(0), Leaf(1))
  let s0 = with_two_panes(node)
  let s1 = apply_action(s0, MouseClick(41, 2))
  assert(s1.resizing_divider == Some(0))
  assert(s1.buffer.bid == 0) // focus untouched
}

test "MouseDrag while resizing a divider recomputes its ratio, not a selection" {
  let node = Split(Vertical, 0.5, Leaf(0), Leaf(1))
  let s0 = with_two_panes(node)
  let s1 = apply_action(s0, MouseClick(41, 2))
  let s2 = apply_action(s1, MouseDrag(61, 2)) // content col 60 -> ratio 60/80 = 0.75
  match s2.panes {
    Split(Vertical, r, Leaf(0), Leaf(1)) => assert(r > 0.74 && r < 0.76),
    _                                    => assert(false)
  }
  assert(selection_span(s2) == None)
}

test "MouseRelease ends a divider resize gesture" {
  let node = Split(Vertical, 0.5, Leaf(0), Leaf(1))
  let s0 = with_two_panes(node)
  let s1 = apply_action(s0, MouseClick(41, 2))
  let s2 = apply_action(s1, MouseRelease)
  assert(s2.resizing_divider == None)
}

test "a drag after MouseRelease is a normal selection, not a leftover resize" {
  let s0 = with_lines(["hello world"])
  let s1 = apply_action(s0, MouseRelease) // no-op: resizing_divider was already None
  let s2 = apply_action(s1, MouseClick(1, 2))
  let s3 = apply_action(s2, MouseDrag(6, 2))
  assert(selection_span(s3) == Some((0, 0, 0, 5)))
}

test "resize_split replaces only the target divider's ratio in a nested tree" {
  let inner   = Split(Horizontal, 0.5, Leaf(0), Leaf(1))
  let node    = Split(Vertical, 0.5, inner, Leaf(2))
  let resized = resize_split(node, 1, 0.25) // index 1 = the nested horizontal divider
  match resized {
    Split(Vertical, outer_r, Split(Horizontal, inner_r, Leaf(0), Leaf(1)), Leaf(2)) => {
      assert(outer_r == 0.5)
      assert(inner_r == 0.25)
    },
    _ => assert(false)
  }
}

// ------------------- Persisted scroll / click-jump fix (M18 follow-up) ----
// Real-terminal testing found clicking an already-visible row snapped the
// viewport so that row became the LAST visible one (`scroll_offset` always
// re-derived the offset from the cursor's line alone, with no memory of
// what was already on screen). `clamp_scroll`/`sync_scroll` fix this by
// persisting `TextBuffer.scroll_line` and only nudging it the minimum
// amount needed to keep the cursor visible.

test "clamp_scroll leaves an already-visible line's scroll untouched" {
  assert(clamp_scroll(10, 20, 15) == 10)
}

test "clamp_scroll snaps down to the minimum scroll that reveals a line below the window" {
  assert(clamp_scroll(0, 20, 25) == 6)
}

test "clamp_scroll snaps up to the minimum scroll that reveals a line above the window" {
  assert(clamp_scroll(10, 20, 3) == 3)
}

test "clamp_scroll never goes negative" {
  assert(clamp_scroll(-5, 20, 0) == 0)
}

test "sync_scroll leaves the viewport alone when the cursor is already visible" {
  let s0 = with_lines(many_lines(60))
  let scrolled = TextBuffer { ...s0.buffer, scroll_line: 20, cursors: [Cursor { cid: 0, pos: Position { line: 25, col: 0 }, anchor: None, anchor_sticky: false }] }
  let s1 = EditorState { ...s0, buffer: scrolled }
  let s2 = sync_scroll(s1)
  assert(s2.buffer.scroll_line == 20) // old design would've snapped this to 4
}

test "MouseClick on an already-visible row doesn't move the viewport (bug fix)" {
  let s0 = with_lines(many_lines(60))
  let scrolled = TextBuffer { ...s0.buffer, scroll_line: 20, cursors: [Cursor { cid: 0, pos: Position { line: 25, col: 0 }, anchor: None, anchor_sticky: false }] }
  let s1 = EditorState { ...s0, buffer: scrolled }
  let s2 = handle_action(s1, MouseEvent(Press, 1, 5)) // content row 3 -> buffer line 23, already visible
  assert(s2.buffer.scroll_line == 20)
  assert(head_cursor_pos(s2) == Position { line: 23, col: 0 })
}

test "ScrollViewDown moves the viewport without moving the cursor" {
  let s0 = with_lines(many_lines(60))
  let s1 = handle_action(s0, MouseEvent(ScrollDown, 1, 5))
  assert(s1.buffer.scroll_line == 3)
  assert(head_cursor_pos(s1) == Position { line: 0, col: 0 })
}

test "ScrollViewUp/ScrollViewDown clamp to the buffer's scroll bounds" {
  let s0 = with_lines(many_lines(60))
  let s1 = handle_action(s0, MouseEvent(ScrollUp, 1, 5)) // already at the top
  assert(s1.buffer.scroll_line == 0)
  let far = TextBuffer { ...s0.buffer, scroll_line: 100 }
  let s2 = handle_action(EditorState { ...s0, buffer: far }, MouseEvent(ScrollDown, 1, 5))
  assert(s2.buffer.scroll_line == 38) // max(60 - 22, 0)
}

test "an unrelated no-op action after a wheel scroll doesn't snap the viewport back (bug fix)" {
  let s0 = with_lines(many_lines(60))
  let s1 = handle_action(s0, MouseEvent(ScrollDown, 1, 5))
  assert(s1.buffer.scroll_line == 3)
  // Ctrl-x is unbound (Ignore) and Tick is a no-op — neither moves the
  // cursor, so the deliberate scroll must survive both untouched.
  let s2 = handle_action(s1, KeyEvent(KShortcut(Ctrl, 'x')))
  assert(s2.buffer.scroll_line == 3)
  let s3 = handle_action(s2, Tick)
  assert(s3.buffer.scroll_line == 3)
}
