// runtime.hc — the impure shell around `handle_action`.
//
// M1 (see docs/effects-journal.md) carves the effectful surface out of
// `src/main.hc` and puts it here. `handle_action` in `src/actions.hc`
// stays 100% pure; this module owns:
//
//   * the `Terminal` effect declaration (poll_event / render_frame /
//     get_dimensions / set_cursor_style),
//   * the `ScreenBuffer` shape the handler flushes,
//   * `build_screen` (trivial in M1: dump the buffer lines; M2 will
//     bring a real `render_editor_to_buffer`),
//   * `event_loop`, the tail-recursive driver that ticks
//     `poll_event -> handle_action -> render_frame` until
//     `state.should_quit` flips to true.
//
// Handlers live at the *call site* (see `src/main.hc` for the native
// stub, `tests/runtime_test.hc` for the headless scripted-events
// handler). This module has no `handle Terminal { … } in { … }` of
// its own — that's the whole point of the split.

import "types"
import "model"
import "actions"

// ------------------- Terminal effect + surface types --------------------

// The pixel-free "screen buffer" the handler flushes. Minimal M1 shape:
// width/height plus one string per row. M2 will upgrade this to
// `list<ScreenCell>` with fg/bg + style flags — the `Terminal` effect
// signature does not need to change when that happens because
// `render_frame` already takes an abstract `ScreenBuffer`.
pub struct ScreenBuffer {
  width: int,
  height: int,
  lines: list<string>
}

// Cursor-shape hint for the handler. Not consumed in M1 (the stub arm
// is `() => ()`); wired up when the native ANSI handler lands.
pub type CursorStyle {
  Block,
  Bar,
  Underscore
}

// User-facing effect (hica 0.49 syntax). Arm bodies auto-resume; no
// explicit `resume(...)` anywhere in user code.
effect Terminal {
  fun poll_event() : Event
  fun render_frame(buf: ScreenBuffer)
  fun get_dimensions() : (int, int)
  fun set_cursor_style(style: CursorStyle)
}

// ------------------- helpers around EditorState -------------------------

// Trivial M1 renderer: mirror the current buffer's lines into a
// `ScreenBuffer` sized to the caller-supplied `(w, h)`. A real render
// (cursor overlay, status line, viewport scrolling) arrives in M2.
pub fun build_screen(state: EditorState, dims: (int, int)) : ScreenBuffer {
  let (w, h) = dims
  ScreenBuffer { width: w, height: h, lines: state.buffer.lines }
}

// ------------------- the loop -------------------------------------------

// Tail-recursive event loop, parameterised over the installed `Terminal`
// handler. Each tick queries `get_dimensions` (so M2 can react to
// resizes), sinks a rendered frame via `render_frame`, then blocks on
// `poll_event` for the next input. The pure `handle_action` drives the
// state transition; when `should_quit` flips to true we return the
// final `EditorState` so callers (tests, main) can assert on it.
pub fun event_loop(state: EditorState) : <Terminal> EditorState {
  if state.should_quit {
    state
  } else {
    let dims = get_dimensions()
    let sized = EditorState { ...state, screen_size: dims }
    render_frame(build_screen(sized, dims))
    let evt = poll_event()
    let next = handle_action(sized, evt)
    event_loop(next)
  }
}
