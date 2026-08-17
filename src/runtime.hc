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

// Tail-recursive event loop parameterised over the installed Terminal handler.
// Each tick: query dimensions → render → poll → resolve → dispatch → recurse.
//
// The dispatch is deliberately thin: `resolve_action` turns the raw Event
// into a semantic `Action` using `state.config.bindings`, and event_loop
// only pattern-matches on the *action variants that need effects*. Every
// pure action falls through to `apply_action`, which stays effect-free.
//
// Returns final EditorState when should_quit flips true.
// Return-type annotation omitted: the full effect row (<Terminal, fsys, div>)
// is inferred by Koka — explicit annotation would be rejected as too narrow.
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
      Save => save_buffer(sized),
      _    => apply_action(sized, action)
    }
    event_loop(next)
  }
}
