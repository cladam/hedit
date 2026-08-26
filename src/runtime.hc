/// The impure shell around `apply_action`: the Terminal/Clipboard/Buffer
/// effects, the save/open/save-as filesystem paths, and the
/// tail-recursive `event_loop` that ties them to the pure dispatch in
/// actions.hc.
// Handlers live at the call site (src/main.hc for native,
// tests/runtime_test.hc for headless) — this module has no
// `handle Terminal { ... } in { ... }` of its own.

import "keys"
import "model"
import "actions"
import "render"

// ------------------- Terminal effect -----------------------------------

/// Screen I/O: render a frame, query dimensions/cursor style, and poll
/// for the next input event. Arm bodies auto-resume (hica 0.49 syntax).
pub effect Terminal {
  fun poll_event() : Event
  fun render_frame(buf: ScreenBuffer)
  fun get_dimensions() : (int, int)
  fun set_cursor_style(style: CursorStyle)
}

// ------------------- Clipboard effect ----------------------------------

/// Cross-platform clipboard abstraction.
// The in-memory handler in tests + main.hc uses a `with var buf = ""`
// slot; a native handler (pbcopy / wl-copy / xclip) can land later
// without touching event_loop or the Copy/Paste dispatch here.
pub effect Clipboard {
  fun get_selection() : string
  fun set_selection(text: string)
}

// ------------------- Buffer effect (M5, named/spawned) ------------------

/// Per-buffer undo/redo history, spawned once per `event_loop` call.
// Ops take the *current* `TextBuffer` as an explicit argument rather
// than mirroring it in handler-local state, so there's no separate
// "current" var that can drift out of sync with `EditorState.buffer` —
// the handler only ever owns the two stacks. `snapshot(b)` pushes `b`
// onto the undo stack and clears the redo stack (the standard "new edit
// invalidates redo history" rule). `undo`/`redo` pop their stack, push
// `current` onto the other stack, and return `Some(restored)` — or
// `None` on an empty stack (a no-op, not an error).
pub effect Buffer {
  fun snapshot(b: TextBuffer)
  fun undo(current: TextBuffer) : maybe<TextBuffer>
  fun redo(current: TextBuffer) : maybe<TextBuffer>
}

// ------------------- save (fsys) ---------------------------------------

/// Apply a `write_file` result to state: clear dirty + status on
/// success, error status on failure.
fun apply_write_result(state: EditorState, result: result<(), string>) {
  match result {
    Ok(_) => {
      let saved_buf = TextBuffer { ...state.buffer, is_dirty: false }
      set_status_message(EditorState { ...state, buffer: saved_buf }, "Saved")
    },
    Err(msg) => set_status_message(state, "Save failed: " + msg)
  }
}

/// Write buffer content to disk for the `Save` action.
// Files are joined with "\n" and get a trailing newline (POSIX
// convention). `--readonly` gates this before touching the
// filesystem at all. A pathless ("scratch") buffer opens the Save-As
// prompt instead.
// Return-type annotation omitted: carries <fsys> (Koka rejects pure annotation).
fun save_buffer(state: EditorState) {
  if state.config.readonly {
    set_status_message(state, "Read-only — not saved")
  }
  else {
    match state.buffer.path {
      None    => EditorState { ...state, prompt: SaveAsPrompt("", 0) },
      Some(p) => {
        let body = join(state.buffer.lines, "\n") + "\n"
        apply_write_result(state, write_file(p, body))
      }
    }
  }
}

/// Write the buffer to a freshly-entered path (Save-As prompt submit,
/// M9), naming the buffer on success so subsequent Ctrl-s saves go
/// straight to disk without re-prompting.
fun submit_save_as(state: EditorState, path: string) {
  let body = join(state.buffer.lines, "\n") + "\n"
  match write_file(path, body) {
    Ok(_) => {
      let saved_buf = TextBuffer { ...state.buffer, path: Some(path), is_dirty: false }
      set_status_message(EditorState { ...state, buffer: saved_buf, prompt: NoPrompt }, "Saved")
    },
    Err(msg) => set_status_message(EditorState { ...state, prompt: NoPrompt }, "Save failed: " + msg)
  }
}

/// Load a path entered in the Open prompt into a new buffer,
/// backgrounding the current one (same shape as `NewBuffer`).
fun submit_open_file(state: EditorState, path: string) {
  let new_bid = state.next_bid
  let (new_buf, load_status) = load_buffer(new_bid, Some(path))
  let opened = EditorState {
    ...state,
    buffer: new_buf,
    background_buffers: state.background_buffers + [state.buffer],
    next_bid: new_bid + 1,
    prompt: NoPrompt
  }
  match load_status {
    None      => opened,
    Some(msg) => set_status_message(opened, msg)
  }
}

/// Dispatch `PromptSubmit` (Enter while a prompt is active) to the
/// right effectful handler.
// `NoPrompt` can't happen in practice (resolve_action only emits
// PromptSubmit while a prompt is active) but falls back to a no-op
// rather than crashing.
fun submit_prompt(state: EditorState) {
  match state.prompt {
    NoPrompt              => state,
    SaveAsPrompt(text, _) => submit_save_as(state, text),
    OpenPrompt(text, _)   => submit_open_file(state, text)
  }
}

// ------------------- the loop ------------------------------------------

/// Apply an undo/redo result to state: restore the buffer on `Some`,
/// leave state untouched (with a status note) on `None` (empty stack).
fun apply_history(state: EditorState, result: maybe<TextBuffer>, verb: string) : EditorState =>
  match result {
    Some(b) => set_status_message(EditorState { ...state, buffer: b }, verb),
    None    => set_status_message(state, "Nothing to " + verb)
  }

/// One tick of the event loop: query dimensions, render (if the frame
/// changed), poll for the next event, resolve + dispatch it, and
/// recurse. Returns the final `EditorState` once `should_quit` flips true.
// `resolve_action` turns the raw Event into a semantic `Action` using
// `state.config.bindings`; event_loop only pattern-matches on the action
// variants that need effects, everything else falls through to the pure
// `apply_action`. `Insert`/`Paste`/etc. snapshot the buffer *before*
// mutating so Undo always has a valid history entry to restore.
// `last_frame` (the previously-drawn ScreenBuffer) lets a Tick with
// nothing to redraw skip `render_frame` when the freshly-built buffer
// structurally equals the last one drawn — avoids a visible flicker on
// the styled rows every ~200ms poll timeout otherwise.
fun event_loop_step(state: EditorState, buf_ref: ref<Buffer>, last_frame: maybe<ScreenBuffer>) {
  if state.should_quit {
    state
  } else {
    let dims  = get_dimensions()
    let sized = EditorState { ...state, screen_size: dims }
    let frame = render_editor_to_buffer(sized)
    let changed = match last_frame { Some(prev) => !(prev == frame), None => true }
    if changed { render_frame(frame) }
    let next_frame = if changed { Some(frame) } else { last_frame }
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
      NewLine        => {
        buf_ref.snapshot(sized.buffer)
        apply_action(sized, action)
      },
      DeleteBackward => {
        buf_ref.snapshot(sized.buffer)
        apply_action(sized, action)
      },
      DeleteForward => {
        buf_ref.snapshot(sized.buffer)
        apply_action(sized, action)
      },
      KillLine  => {
        buf_ref.snapshot(sized.buffer)
        set_selection(kill_line_text(sized))
        kill_line(sized)
      },
      KillWordBack => {
        buf_ref.snapshot(sized.buffer)
        set_selection(kill_word_back_text(sized))
        delete_word_back(sized)
      },
      KillWordForward => {
        buf_ref.snapshot(sized.buffer)
        set_selection(kill_word_forward_text(sized))
        delete_word_forward(sized)
      },
      KillWholeLine => {
        buf_ref.snapshot(sized.buffer)
        set_selection(kill_whole_line_text(sized))
        kill_whole_line(sized)
      },
      Undo      => apply_history(sized, buf_ref.undo(sized.buffer), "undo"),
      Redo      => apply_history(sized, buf_ref.redo(sized.buffer), "redo"),
      PromptSubmit => submit_prompt(sized),
      PromptKillLine => {
        set_selection(prompt_kill_text(sized))
        prompt_truncate(sized)
      },
      _         => apply_action(sized, action)
    }
    event_loop_step(next, buf_ref, next_frame)
  }
}

/// Entry point: spawns one `Buffer` instance (fresh undo/redo stacks)
/// and hands off to the tail-recursive `event_loop_step`.
// Return-type annotation omitted: the full effect row (<Terminal,
// Clipboard, Buffer, fsys, div>) is inferred by Koka — explicit
// annotation would be rejected as too narrow.
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
  event_loop_step(state, buf_ref, None)
}

