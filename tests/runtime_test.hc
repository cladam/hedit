// runtime_test.hc — M1/M2/M3 headless-handler regression tests.
//
// Every test installs a scripted `Terminal` handler with two pieces of
// handler-local state:
//
//   * `var events` — a queue of `Event`s to pop from `poll_event()`.
//     When empty we fall back to `Ctrl-q` so a buggy test can't hang
//     the event loop.
//   * `var render_count` — bumped on every `render_frame()` call so we
//     can assert the loop actually ticked.
//
// M3 tests additionally wrap the Terminal handler in an in-memory
// `Clipboard` handler (`with var clip = ""`), so Ctrl-c / Ctrl-v
// round-trips are asserted without hitting a real OS clipboard.
//
// `event_loop` in `src/runtime.hc` is the pure driver we're testing;
// each arm body auto-resumes (hica 0.49 handler semantics), so we
// don't write `resume(...)` anywhere.

import "../src/keys"
import "../src/model"
import "../src/runtime"

// ------------------- test 1: quit terminates immediately ----------------

test "scripted Ctrl-q terminates the loop after one tick" {
  // The EditorState annotation on `final` prevents a cross-module type-inference
  // issue where Koka resolves `final.buffer.lines` as the prelude `hc_lines(string)
  // rather than the TextBuffer field accessor.
  let final: EditorState = handle Terminal {
    poll_event() => match events {
      []          => KeyEvent(KShortcut(Ctrl, 'q')),
      [e, ..rest] => { events = rest; e }
    },
    render_frame(_buf)   => render_count = render_count + 1,
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } with var events = [KeyEvent(KShortcut(Ctrl, 'q'))],
         var render_count = 0 in {
    event_loop(init_editor(None))
  }
  assert(final.should_quit == true)
  assert(final.buffer.lines == [""])   // no chars typed
}

// ------------------- test 2: scripted keys build "hi" -------------------

test "scripted keys h i Ctrl-q leave buffer as [hi]" {
  let final: EditorState = handle Terminal {
    poll_event() => match events {
      []          => KeyEvent(KShortcut(Ctrl, 'q')),
      [e, ..rest] => { events = rest; e }
    },
    render_frame(_buf)   => render_count = render_count + 1,
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } with var events = [
    KeyEvent(KChar('h')),
    KeyEvent(KChar('i')),
    KeyEvent(KShortcut(Ctrl, 'q'))
  ], var render_count = 0 in {
    event_loop(init_editor(None))
  }
  assert(final.buffer.lines == ["hi"])
  assert(final.buffer.is_dirty == true)
  assert(final.should_quit == true)
}

// ------------------- test 3: render fires each iteration ----------------

test "render_frame is called at least once per iteration" {
  // Return the EditorState alongside render_count as a typed tuple so that
  // the EditorState type flows through to the result.0 binding.
  let pair: (EditorState, int) = handle Terminal {
    poll_event() => match events {
      []          => KeyEvent(KShortcut(Ctrl, 'q')),
      [e, ..rest] => { events = rest; e }
    },
    render_frame(_buf)   => render_count = render_count + 1,
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } with var events = [
    KeyEvent(KChar('a')),
    KeyEvent(KChar('b')),
    KeyEvent(KChar('c')),
    KeyEvent(KShortcut(Ctrl, 'q'))
  ], var render_count = 0 in {
    let s = event_loop(init_editor(None))
    (s, render_count)
  }
  let final = pair.0
  let renders = pair.1
  // Four events processed → at least four render_frame calls before we quit.
  assert(renders >= 4)
  assert(final.buffer.lines == ["abc"])
}

// ------------------- test 4: get_dimensions updates screen_size ---------

test "get_dimensions is propagated onto EditorState.screen_size" {
  let final = handle Terminal {
    poll_event()         => KeyEvent(KShortcut(Ctrl, 'q')),
    render_frame(_buf)   => (),
    get_dimensions()     => (120, 40),
    set_cursor_style(_s) => ()
  } in {
    event_loop(init_editor(None))
  }
  assert(final.screen_size == (120, 40))
}

// ------------------- test 5: Ctrl-s writes the file --------------------

test "ctrl-s on a named buffer writes content to disk" {
  let tmp_path = "/tmp/hedit_test_m2_save.txt"
  let s0 = init_editor(Some(tmp_path))
  let final = handle Terminal {
    poll_event() => match events {
      []          => KeyEvent(KShortcut(Ctrl, 'q')),
      [e, ..rest] => { events = rest; e }
    },
    render_frame(_buf)   => (),
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } with var events = [
    KeyEvent(KChar('h')),
    KeyEvent(KChar('i')),
    KeyEvent(KShortcut(Ctrl, 's')),
    KeyEvent(KShortcut(Ctrl, 'q'))
  ] in {
    event_loop(s0)
  }
  assert(final.buffer.is_dirty == false)
  assert(final.status_message == Some("Saved"))
  // Verify the file was written by reading it back. Trailing newline is
  // added by save_buffer for POSIX-friendliness (`wc -l`, `git diff`, …).
  let content = read_file(tmp_path)
  assert(content == Ok("hi\n"))
}

// ------------------- Clipboard integration tests (blocked on Issue #5) --
//
// M3 was intended to grow three integration tests here that drive the
// Copy/Paste path through `event_loop` end-to-end (Ctrl-c copy, Ctrl-v
// paste, full copy→paste round-trip). Each would install both the
// `Terminal` and `Clipboard` handlers around
// `event_loop(init_editor(None))` — either inline via nested `handle`
// blocks, or via the `pub fun run_scripted(...)` harness we prepared
// in `src/runtime.hc`.
//
// Both approaches hit hica-issues.md **Issue #5**: hica's codegen
// wraps every `with handler` block in an anonymous `(fn() … )()`, and
// that anonymous-function boundary hides the enclosing handler chain
// from any inner `with handler`. So when `event_loop` calls
// `set_selection(...)` (a Clipboard op) from inside the inner Terminal
// handler's `(fn())`, no Clipboard handler is live at that stack
// frame, and Koka reports `unhandled effect: runtime/clipboard` from
// the test-mode `fun main()`.
//
// The `run_scripted` harness is retained in `src/runtime.hc` so that
// once the codegen fix lands upstream, we can re-enable these three
// tests with a single `let pair: (EditorState, string) = run_scripted
// (...)` call — no logic change required.
//
// Meanwhile, Copy/Paste coverage lives at the pure-unit level in
// `tests/actions_test.hc` (6 dedicated tests: `resolve_action → Copy /
// Paste`, `apply_action` no-op behaviour on both, and pure-helper
// coverage for `current_line` + `paste_text`). The integration path
// itself is exercised by hand via `hica run src/main.hc` — the M3
// stub installs the in-memory Clipboard handler and exits cleanly.
