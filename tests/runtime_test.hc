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
import "../src/hilisp_host"

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

// ------------------- Clipboard integration tests (M3) ------------------
//
// Nested Terminal+Clipboard handlers around `event_loop`. Previously
// blocked on hica-issues.md Issue #5 (test-mode `fun main()` didn't
// discharge user-defined effects from `try({ hctest_() })`); resolved
// in hica 0.49.3 with the auto-installed panic-handler fix.

// ------------------- test 6: Ctrl-c copies current line ----------------

test "ctrl-c copies the head cursor line into the Clipboard" {
  // Type "abc", Ctrl-c, then Ctrl-q. After the loop returns, `clip`
  // should hold "abc" and the buffer itself should still be "abc".
  let pair: (EditorState, string) = handle Clipboard {
    get_selection()  => clip,
    set_selection(t) => clip = t
  } with var clip = "" in {
    let final: EditorState = handle Terminal {
      poll_event() => match events {
        []          => KeyEvent(KShortcut(Ctrl, 'q')),
        [e, ..rest] => { events = rest; e }
      },
      render_frame(_buf)   => (),
      get_dimensions()     => (80, 24),
      set_cursor_style(_s) => ()
    } with var events = [
      KeyEvent(KChar('a')),
      KeyEvent(KChar('b')),
      KeyEvent(KChar('c')),
      KeyEvent(KShortcut(Ctrl, 'c')),
      KeyEvent(KShortcut(Ctrl, 'q'))
    ] in {
      event_loop(init_editor(None))
    }
    (final, clip)
  }
  let final = pair.0
  let clipped = pair.1
  assert(clipped == "abc")
  assert(final.buffer.lines == ["abc"])
  assert(final.status_message == Some("Copied line"))
}

// ------------------- test 7: Ctrl-v pastes from Clipboard --------------

test "ctrl-v appends Clipboard contents to head cursor line" {
  // Pre-seed the clipboard with "xyz". After Ctrl-v, the buffer's first
  // line should read "xyz" (empty + paste), is_dirty should flip true.
  let pair: (EditorState, string) = handle Clipboard {
    get_selection()  => clip,
    set_selection(t) => clip = t
  } with var clip = "xyz" in {
    let inner: EditorState = handle Terminal {
      poll_event() => match events {
        []          => KeyEvent(KShortcut(Ctrl, 'q')),
        [e, ..rest] => { events = rest; e }
      },
      render_frame(_buf)   => (),
      get_dimensions()     => (80, 24),
      set_cursor_style(_s) => ()
    } with var events = [
      KeyEvent(KShortcut(Ctrl, 'v')),
      KeyEvent(KShortcut(Ctrl, 'q'))
    ] in {
      event_loop(init_editor(None))
    }
    (inner, clip)
  }
  let final = pair.0
  assert(final.buffer.lines == ["xyz"])
  assert(final.buffer.is_dirty == true)
}

// ------------------- test 8: full Copy → Paste round-trip --------------

test "copy then paste duplicates the line content" {
  // Type "hi", Copy, Paste, Ctrl-q. Final line should be "hihi",
  // clipboard should hold the pre-paste "hi".
  let pair: (EditorState, string) = handle Clipboard {
    get_selection()  => clip,
    set_selection(t) => clip = t
  } with var clip = "" in {
    let inner: EditorState = handle Terminal {
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
      KeyEvent(KShortcut(Ctrl, 'c')),
      KeyEvent(KShortcut(Ctrl, 'v')),
      KeyEvent(KShortcut(Ctrl, 'q'))
    ] in {
      event_loop(init_editor(None))
    }
    (inner, clip)
  }
  let final = pair.0
  let clipped = pair.1
  assert(final.buffer.lines == ["hihi"])
  assert(final.buffer.is_dirty == true)
  assert(clipped == "hi")
}

// ------------------- M4b integration: HiLisp-rebound chord fires action -

// End-to-end proof that a HiLisp `(bind …)` form materialised through
// `load_config` reaches the event loop's action dispatch. We rebind
// `Ctrl-x` → 'quit and `Ctrl-q` → 'ignore, seed the editor with the
// resulting Config, script a single Ctrl-x event, and assert
// `should_quit` flipped true. Any regression in the M4 chain
// (`load_config` → `Config.bindings` → `resolve_action` → `event_loop`)
// surfaces here without touching the filesystem.
test "HiLisp (bind Ctrl-x 'quit) rewires the quit chord end-to-end" {
  let src = "(bind \"Ctrl-x\" 'quit) (bind \"Ctrl-q\" 'ignore)"
  let (cfg, err) = load_config(src, default_config())
  assert(err == None)
  let s0 = init_editor_with_config(None, cfg)
  let final: EditorState = handle Terminal {
    poll_event() => match events {
      []          => KeyEvent(KShortcut(Ctrl, 'x')),
      [e, ..rest] => { events = rest; e }
    },
    render_frame(_buf)   => (),
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } with var events = [
    KeyEvent(KShortcut(Ctrl, 'x'))
  ] in {
    event_loop(s0)
  }
  assert(final.should_quit == true)
}
