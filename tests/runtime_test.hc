// runtime_test.hc — M1 headless-handler regression tests.
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
// `event_loop` in `src/runtime.hc` is the pure driver we're testing;
// each arm body auto-resumes (hica 0.49 handler semantics), so we
// don't write `resume(...)` anywhere.

import "../src/keys"
import "../src/model"
import "../src/runtime"

// ------------------- test 1: quit terminates immediately ----------------

test "scripted Ctrl-q terminates the loop after one tick" {
  let final = handle Terminal {
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
  let final = handle Terminal {
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
  // We can't smuggle handler-local state into an outer `var` (the
  // Koka handler scope pins it down), so instead of a spy variable we
  // wire `render_count` through the arm bodies and pass it back by
  // returning it from the `in { … }` block as part of a tuple. That
  // keeps every read/write inside the handler where the escape rule
  // is satisfied.
  let (final, renders) = handle Terminal {
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
  // Four events processed → at least four render_frame calls before
  // we quit.
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
