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

// Small named helper (instead of an inline lambda) so the `TextBuffer`
// receiver type is pinned — avoids the cross-module `hc_lines` collision
// with the prelude's string `lines` function (see repo memory notes).
fun buf_lines(b: TextBuffer) : list<string> => b.lines

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

// ------------------- M8: --readonly gates Save --------------------------

test "ctrl-s on a readonly buffer does not write and sets a status message" {
  let tmp_path = "/tmp/hedit_test_m8_readonly_save.txt"
  let ro_cfg = Config { ...default_config(), readonly: true }
  let s0 = init_editor_with_config(Some(tmp_path), ro_cfg)
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
    KeyEvent(KShortcut(Ctrl, 's')),
    KeyEvent(KShortcut(Ctrl, 'q'))
  ] in {
    event_loop(s0)
  }
  assert(final.status_message == Some("Read-only — not saved"))
  // The file must never have been created/written.
  let content = read_file(tmp_path)
  let was_written = match content {
    Ok(_)  => true,
    Err(_) => false
  }
  assert(!was_written)
}

// A pathless buffer under --readonly must not open the Save-As prompt
// either — the readonly gate is checked before the "no path" branch in
// `runtime.hc::save_buffer` (M9).
test "ctrl-s on a readonly scratch buffer does not open a Save-As prompt" {
  let ro_cfg = Config { ...default_config(), readonly: true }
  let s0 = init_editor_with_config(None, ro_cfg)
  let final: EditorState = handle Terminal {
    poll_event() => match events {
      []          => KeyEvent(KShortcut(Ctrl, 'q')),
      [e, ..rest] => { events = rest; e }
    },
    render_frame(_buf)   => (),
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } with var events = [
    KeyEvent(KChar('h')),
    KeyEvent(KShortcut(Ctrl, 's')),
    KeyEvent(KShortcut(Ctrl, 'q'))
  ] in {
    event_loop(s0)
  }
  assert(final.status_message == Some("Read-only — not saved"))
  assert(final.prompt == NoPrompt)
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

// ------------------- M5.5: multi-buffer navigation through event_loop --

// Meta-o (new), Meta-n / Meta-p (cycle), Meta-w (close) all reach
// `apply_action` through the same resolve_action/event_loop pipeline as
// every other default binding — no special-casing in event_loop, since
// these are all pure `Action`s (see src/actions.hc). Stage 1 remap
// (docs/new-keybindings.txt) moved these off Ctrl-o/n/p/w to make room
// for the new readline chords; the Meta chords are dormant until
// Stage 2's FFI decoder emits real `KShortcut(Meta, _)` events, but
// resolve_action doesn't care how the event was produced.
test "Meta-o opens a new buffer, Meta-n cycles back to the original" {
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
    KeyEvent(KShortcut(Meta, 'o')), // open a fresh scratch buffer
    KeyEvent(KChar('b')),
    KeyEvent(KShortcut(Meta, 'n')), // cycle forward — wraps to buffer "a"
    KeyEvent(KShortcut(Ctrl, 'q'))
  ] in {
    event_loop(init_editor(None))
  }
  assert(final.buffer.lines == ["a"])
  assert(length(final.background_buffers) == 1)
}

test "Meta-w closes the active buffer and promotes the other one" {
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
    KeyEvent(KShortcut(Meta, 'o')), // buffer "b" is now active, "a" backgrounded
    KeyEvent(KChar('b')),
    KeyEvent(KShortcut(Meta, 'w')), // close "b" — "a" is promoted
    KeyEvent(KShortcut(Ctrl, 'q'))
  ] in {
    event_loop(init_editor(None))
  }
  assert(final.buffer.lines == ["a"])
  assert(length(final.background_buffers) == 0)
}

// ------------------- M9: Save-As / Open prompt through event_loop -------

// Ctrl-s on a pathless ("scratch") buffer opens a Save-As prompt instead
// of the old "not possible" dead end; typing a path and pressing Enter
// writes the file and names the buffer.
test "ctrl-s on a scratch buffer opens Save-As prompt; typing a path + Enter saves it" {
  let tmp_path = "/tmp/hedit_test_m9_save_as.txt"
  let path_events = map(chars(tmp_path), (c) => KeyEvent(KChar(c)))
  let events = [
    KeyEvent(KChar('h')),
    KeyEvent(KChar('i')),
    KeyEvent(KShortcut(Ctrl, 's')) // opens SaveAsPrompt("")
  ] + path_events + [
    KeyEvent(KSpecial(Enter)), // submits — writes the file
    KeyEvent(KShortcut(Ctrl, 'q'))
  ]
  let final: EditorState = handle Terminal {
    poll_event() => match ev {
      []          => KeyEvent(KShortcut(Ctrl, 'q')),
      [e, ..rest] => { ev = rest; e }
    },
    render_frame(_buf)   => (),
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } with var ev = events in {
    event_loop(init_editor(None))
  }
  assert(final.prompt == NoPrompt)
  assert(final.buffer.path == Some(tmp_path))
  assert(final.buffer.is_dirty == false)
  assert(final.status_message == Some("Saved"))
  let content = read_file(tmp_path)
  assert(content == Ok("hi\n"))
}

// Esc cancels a Save-As prompt without ever touching the filesystem;
// the typed text is discarded.
test "Esc cancels a Save-As prompt without writing anything" {
  let tmp_path = "/tmp/hedit_test_m9_save_as_cancel.txt"
  let path_events = map(chars(tmp_path), (c) => KeyEvent(KChar(c)))
  let events = [
    KeyEvent(KShortcut(Ctrl, 's'))
  ] + path_events + [
    KeyEvent(KSpecial(Esc)),
    KeyEvent(KShortcut(Ctrl, 'q'))
  ]
  let final: EditorState = handle Terminal {
    poll_event() => match ev {
      []          => KeyEvent(KShortcut(Ctrl, 'q')),
      [e, ..rest] => { ev = rest; e }
    },
    render_frame(_buf)   => (),
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } with var ev = events in {
    event_loop(init_editor(None))
  }
  assert(final.prompt == NoPrompt)
  assert(final.buffer.path == None)
  let content = read_file(tmp_path)
  let was_written = match content { Ok(_) => true, Err(_) => false }
  assert(!was_written)
}

// Ctrl-o opens an Open prompt (Stage 1 remap, docs/new-keybindings.txt);
// typing an existing path and Enter loads its real content into a new
// buffer, backgrounding the current one — same shape as Meta-o's
// NewBuffer.
test "ctrl-o opens an Open prompt; typing a path + Enter loads a new buffer" {
  let src_path = "/tmp/hedit_test_m9_open_src.txt"
  let write_result = write_file(src_path, "line1\nline2\n")
  assert(write_result == Ok(()))
  let path_events = map(chars(src_path), (c) => KeyEvent(KChar(c)))
  let events = [
    KeyEvent(KChar('a')), // original scratch buffer has content
    KeyEvent(KShortcut(Ctrl, 'o'))       // opens OpenPrompt("")
  ] + path_events + [
    KeyEvent(KSpecial(Enter)), // submits — loads the file
    KeyEvent(KShortcut(Ctrl, 'q'))
  ]
  let final: EditorState = handle Terminal {
    poll_event() => match ev {
      []          => KeyEvent(KShortcut(Ctrl, 'q')),
      [e, ..rest] => { ev = rest; e }
    },
    render_frame(_buf)   => (),
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } with var ev = events in {
    event_loop(init_editor(None))
  }
  assert(final.prompt == NoPrompt)
  assert(final.buffer.path == Some(src_path))
  assert(final.buffer.lines == ["line1", "line2"])
  assert(length(final.background_buffers) == 1)
  let bg_lines = map(final.background_buffers, buf_lines)
  assert(bg_lines == [["a"]])
}
