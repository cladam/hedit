// runtime.hc — the impure shell around `apply_action`.
//
// M1: extracted Terminal effect + event_loop here.
// M2: ScreenBuffer/CursorStyle moved to model.hc; build_screen replaced by
//     render_editor_to_buffer from render.hc; event_loop gains <fsys> from
//     the Ctrl-s save path.
// M2 pre-M3 cleanup: dispatch flows through the resolve_action / Action
//     pipeline so keybindings become config-driven — event_loop only
//     special-cases effectful actions (Save), everything else is
//     delegated to the pure apply_action.
//
// Handlers live at the call site (src/main.hc for native,
// tests/runtime_test.hc for headless). This module has no
// `handle Terminal { … } in { … }` of its own.

import "keys"
import "model"
import "actions"
import "render"

// ------------------- Terminal effect -----------------------------------

// User-facing effect (hica 0.49 syntax). Arm bodies auto-resume.
pub effect Terminal {
  fun poll_event() : Event
  fun render_frame(buf: ScreenBuffer)
  fun get_dimensions() : (int, int)
  fun set_cursor_style(style: CursorStyle)
}

// ------------------- Clipboard effect ----------------------------------

// Cross-platform clipboard abstraction (M3). The in-memory handler in
// tests + `src/main.hc` uses a `with var buf = ""` slot; a native
// handler (pbcopy / wl-copy / xclip) can land later without touching
// event_loop or the Copy/Paste dispatch here.
pub effect Clipboard {
  fun get_selection() : string
  fun set_selection(text: string)
}

// ------------------- save (fsys) ---------------------------------------

// Apply the write_file result to state: clear dirty + status on success,
// error status on failure.
fun apply_write_result(state: EditorState, result: result<(), string>) {
  match result {
    Ok(_) => {
      let saved_buf = TextBuffer { ...state.buffer, is_dirty: false }
      set_status_message(EditorState { ...state, buffer: saved_buf }, "Saved")
    },
    Err(msg) => set_status_message(state, "Save failed: " + msg)
  }
}

// Write buffer content to disk. Called from event_loop for the `Save`
// action. Files are joined with "\n" and get a trailing newline (POSIX
// convention — `wc -l`, `git diff`, etc. all expect it).
// Return-type annotation omitted: carries <fsys> (Koka rejects pure annotation).
fun save_buffer(state: EditorState) {
  match state.buffer.path {
    None    => set_status_message(state, "No file — save not possible"),
    Some(p) => {
      let body = join(state.buffer.lines, "\n") + "\n"
      apply_write_result(state, write_file(p, body))
    }
  }
}

// ------------------- the loop ------------------------------------------

// Tail-recursive event loop parameterised over the installed Terminal +
// Clipboard handlers. Each tick: query dimensions → render → poll →
// resolve → dispatch → recurse.
//
// The dispatch is deliberately thin: `resolve_action` turns the raw Event
// into a semantic `Action` using `state.config.bindings`, and event_loop
// only pattern-matches on the *action variants that need effects*. Every
// pure action falls through to `apply_action`, which stays effect-free.
//
// Returns final EditorState when should_quit flips true.
// Return-type annotation omitted: the full effect row
// (<Terminal, Clipboard, fsys, div>) is inferred by Koka — explicit
// annotation would be rejected as too narrow.
pub fun event_loop(state: EditorState) {
  if state.should_quit {
    state
  } else {
    let dims  = get_dimensions()
    let sized = EditorState { ...state, screen_size: dims }
    render_frame(render_editor_to_buffer(sized))
    let evt    = poll_event()
    let action = resolve_action(sized, evt)
    let next   = match action {
      // Effectful actions handled inline; pure ones fall through.
      Save  => save_buffer(sized),
      Copy  => {
        set_selection(current_line(sized))
        set_status_message(sized, "Copied line")
      },
      Paste => paste_text(sized, get_selection()),
      _     => apply_action(sized, action)
    }
    event_loop(next)
  }
}

// ------------------- scripted harness (removed pending Issue #5) --------
//
// A `pub fun run_scripted(initial, events, clip0) : (EditorState, string)`
// that installed both `Clipboard` and `Terminal` handlers around
// `event_loop` was drafted here as an M3 test harness. It hit hica-
// issues.md **Issue #5**: the emitted `with handler` blocks inside
// hica's per-handler `(fn())` wrapper hide the outer Clipboard handler
// from the inner Terminal handler's scope, so `event_loop`'s
// `set_selection(...)` call from a Copy/Paste dispatch escapes as an
// unhandled effect all the way out to the test-file `fun main()`.
//
// Notably, *the mere presence* of such a `pub fun` in this module is
// enough to make Koka treat `runtime/clipboard` as an inferred effect
// of the module's `main` expression — so even omitting the call site
// in `tests/runtime_test.hc` doesn't dodge the failure. Until the
// codegen fix lands upstream (see `docs/hica-issues.md` Issue #5), the
// harness is removed entirely and Copy/Paste coverage lives at the
// pure-unit level in `tests/actions_test.hc`. Once fixed, restore
// `run_scripted` here and re-enable the three Ctrl-c/Ctrl-v tests
// sketched at the bottom of `tests/runtime_test.hc`.
