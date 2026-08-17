// runtime.hc — the impure shell around `handle_action`.
//
// M1: extracted Terminal effect + event_loop here.
// M2: ScreenBuffer/CursorStyle moved to model.hc; build_screen replaced by
//     render_editor_to_buffer from render.hc; event_loop gains <fsys> from
//     handle_action's Ctrl-s save path.
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

// Write buffer content to disk. Called from event_loop for Ctrl-s.
// Return-type annotation omitted: carries <fsys> (Koka rejects pure annotation).
fun save_buffer(state: EditorState) {
  match state.buffer.path {
    None    => set_status_message(state, "No file — save not possible"),
    Some(p) => apply_write_result(state, write_file(p, join(state.buffer.lines, "\n")))
  }
}

// ------------------- the loop ------------------------------------------

// Tail-recursive event loop parameterised over the installed Terminal handler.
// Each tick: query dimensions → render → poll → dispatch → recurse.
// Ctrl-s is intercepted here (before handle_action) so handle_action stays pure.
// Returns final EditorState when should_quit flips true.
// Return-type annotation omitted: the full effect row (<Terminal, fsys, div>)
// is inferred by Koka — explicit annotation would be rejected as too narrow.
pub fun event_loop(state: EditorState) {
  if state.should_quit {
    state
  } else {
    let dims = get_dimensions()
    let sized = EditorState { ...state, screen_size: dims }
    render_frame(render_editor_to_buffer(sized))
    let evt = poll_event()
    let next = match evt {
      KeyEvent(KShortcut(m, c)) =>
        if (m == Ctrl) && c == 's' { save_buffer(sized) }
        else { handle_action(sized, evt) },
      _ => handle_action(sized, evt)
    }
    event_loop(next)
  }
}
