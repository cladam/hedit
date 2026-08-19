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
// M5: adds `pub effect Buffer` — a *named* effect (spawned via `spawn
//     Buffer { … } as ref`, not `handle … in { … }`) that owns the
//     undo/redo history for the active buffer. `EditorState.buffer`
//     stays a plain `TextBuffer` (pure surface unchanged); `event_loop`
//     spawns one `ref<Buffer>` per loop and threads it through the
//     tail-recursive step — see `tests/spawn_test.hc` for the isolation
//     proof and `docs/effects-journal.md` M5 Log for the design-fork
//     rationale (why `snapshot`/`undo`/`redo` pass the buffer as an
//     argument instead of mirroring it in handler-local state).
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

// ------------------- Buffer effect (M5, named/spawned) ------------------

// Per-buffer undo/redo history, spawned once per `event_loop` call
// (single active buffer for M5 — see the milestone's narrow-scope
// note). Ops take the *current* `TextBuffer` as an explicit argument
// rather than mirroring it in handler-local state, so there is no
// separate "current" var that can drift out of sync with
// `EditorState.buffer` — the handler only ever owns the two stacks.
// `snapshot(b)` pushes `b` onto the undo stack and clears the redo
// stack (the standard "new edit invalidates redo history" rule).
// `undo`/`redo` pop their stack, push `current` onto the other stack,
// and return `Some(restored)` — or `None` on an empty stack (a no-op,
// not an error). Stacks are prepend-ordered (`[x] + stack`) so
// push/pop are both a single pattern match.
pub effect Buffer {
  fun snapshot(b: TextBuffer)
  fun undo(current: TextBuffer) : maybe<TextBuffer>
  fun redo(current: TextBuffer) : maybe<TextBuffer>
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

// Apply an undo/redo result to state: restore the buffer on `Some`,
// leave state untouched (with a status note) on `None` (empty stack).
fun apply_history(state: EditorState, result: maybe<TextBuffer>, verb: string) : EditorState =>
  match result {
    Some(b) => set_status_message(EditorState { ...state, buffer: b }, verb),
    None    => set_status_message(state, "Nothing to " + verb)
  }

// Tail-recursive event loop step, parameterised over the installed
// Terminal + Clipboard handlers and a spawned `ref<Buffer>` (see
// `event_loop` below, which spawns it once and delegates here). Each
// tick: query dimensions → render → poll → resolve → dispatch →
// recurse.
//
// The dispatch is deliberately thin: `resolve_action` turns the raw Event
// into a semantic `Action` using `state.config.bindings`, and event_loop
// only pattern-matches on the *action variants that need effects*. Every
// pure action falls through to `apply_action`, which stays effect-free.
// `Insert`/`Paste` snapshot the buffer *before* mutating so Undo always
// has a valid history entry to restore.
//
// Returns final EditorState when should_quit flips true.
fun event_loop_step(state: EditorState, buf_ref: ref<Buffer>) {
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
      Save      => save_buffer(sized),
      Copy      => {
        set_selection(current_line(sized))
        set_status_message(sized, "Copied line")
      },
      Paste     => {
        buf_ref.snapshot(sized.buffer)
        paste_text(sized, get_selection())
      },
      Insert(_) => {
        buf_ref.snapshot(sized.buffer)
        apply_action(sized, action)
      },
      Undo      => apply_history(sized, buf_ref.undo(sized.buffer), "undo"),
      Redo      => apply_history(sized, buf_ref.redo(sized.buffer), "redo"),
      _         => apply_action(sized, action)
    }
    event_loop_step(next, buf_ref)
  }
}

// Entry point: spawns one `Buffer` instance (fresh undo/redo stacks)
// and hands off to the tail-recursive step. Return-type annotation
// omitted: the full effect row (<Terminal, Clipboard, Buffer, fsys,
// div>) is inferred by Koka — explicit annotation would be rejected
// as too narrow.
pub fun event_loop(state: EditorState) {
  spawn Buffer {
    snapshot(b) => {
      undo_stack = [b] + undo_stack
      redo_stack = []
    },
    undo(current) => match undo_stack {
      [] => None,
      [top, ..rest] => {
        redo_stack = [current] + redo_stack
        undo_stack = rest
        Some(top)
      }
    },
    redo(current) => match redo_stack {
      [] => None,
      [top, ..rest] => {
        undo_stack = [current] + undo_stack
        redo_stack = rest
        Some(top)
      }
    }
  } with var undo_stack = [], var redo_stack = [] as buf_ref
  event_loop_step(state, buf_ref)
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
