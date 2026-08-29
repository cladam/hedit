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
import "hilisp_host"
import "../lib/hilisp/src/lisp"

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

/// Apply the `pre-save`/`pre-action` cancel convention's status: a
/// hook's own `LStr` return wins, else a generic "blocked" message.
fun blocked_state(state: EditorState, verb: string, results: list<LVal>) : EditorState =>
  match hook_status(results) {
    Some(msg) => set_status_message(state, msg),
    None      => set_status_message(state, "Blocked by plugin (" + verb + ")")
  }

/// Apply the status-bar convention: a hook's `LStr` return (if any)
/// becomes the next status message; otherwise `state` is untouched.
fun apply_hook_status(state: EditorState, results: list<LVal>) : EditorState =>
  match hook_status(results) {
    Some(msg) => set_status_message(state, msg),
    None      => state
  }

/// Fire the `buffer-open` hook for a buffer that just finished
/// loading (`path` is `""` for a scratch buffer), threading `Env` and
/// applying the status-bar convention to `next_state`.
fun run_buffer_open(next_state: EditorState, path: string, hl_env: Env) : (EditorState, Env) {
  let stats_env = env_with_buffer_stats(hl_env, next_state.buffer)
  let (results, hl_env1) = fire_hook(stats_env, "buffer-open", [LStr(path)])
  (apply_hook_status(next_state, results), hl_env1)
}

/// `Save` (Ctrl-s): read-only and pathless (Save-As prompt) buffers
/// never touch a real path, so they skip the save hooks entirely; a
/// buffer with a known path runs `save_buffer` through the
/// `pre-save`/`post-save` hooks, honoring the cancel convention.
fun run_save(sized: EditorState, hl_env: Env) : (EditorState, Env) =>
  if sized.config.readonly {
    (save_buffer(sized), hl_env)
  } else {
    match sized.buffer.path {
      None    => (save_buffer(sized), hl_env),
      Some(p) => {
        let stats_env = env_with_buffer_stats(hl_env, sized.buffer)
        let (pre_results, hl_env1) = fire_hook(stats_env, "pre-save", [LStr(p)])
        if hook_cancels(pre_results) {
          (blocked_state(sized, "save", pre_results), hl_env1)
        } else {
          let saved = save_buffer(sized)
          let (post_results, hl_env2) = fire_hook(hl_env1, "post-save", [LStr(p)])
          (apply_hook_status(saved, post_results), hl_env2)
        }
      }
    }
  }

/// Save-As prompt submit: same `pre-save`/`post-save` wrapping as
/// `run_save`, around `submit_save_as`. The prompt always closes on
/// submit (success, failure, or a `pre-save` cancel) — matching
/// `submit_save_as`'s own behavior.
fun run_save_as(sized: EditorState, path: string, hl_env: Env) : (EditorState, Env) {
  let stats_env = env_with_buffer_stats(hl_env, sized.buffer)
  let (pre_results, hl_env1) = fire_hook(stats_env, "pre-save", [LStr(path)])
  if hook_cancels(pre_results) {
    (blocked_state(EditorState { ...sized, prompt: NoPrompt }, "save", pre_results), hl_env1)
  } else {
    let saved = submit_save_as(sized, path)
    let (post_results, hl_env2) = fire_hook(hl_env1, "post-save", [LStr(path)])
    (apply_hook_status(saved, post_results), hl_env2)
  }
}

/// Open prompt submit: load the file, then fire `buffer-open` on the
/// freshly loaded buffer.
// Return-type annotation omitted: carries <fsys> (Koka rejects pure
// annotation once the read is behind `submit_open_file`/`load_buffer`).
fun run_open_file(sized: EditorState, path: string, hl_env: Env) =>
  run_buffer_open(submit_open_file(sized, path), path, hl_env)

/// Dispatch `PromptSubmit` (Enter while a prompt is active) to the
/// right hook-aware effectful handler.
// `NoPrompt` can't happen in practice (resolve_action only emits
// PromptSubmit while a prompt is active) but falls back to a no-op
// rather than crashing. Return-type annotation omitted: carries
// <fsys> transitively via `run_open_file`/`run_save_as`.
fun run_prompt_submit(sized: EditorState, hl_env: Env) =>
  match sized.prompt {
    NoPrompt              => (sized, hl_env),
    SaveAsPrompt(text, _) => run_save_as(sized, text, hl_env),
    OpenPrompt(text, _)   => run_open_file(sized, text, hl_env),
    FindPrompt(_, _)      => (submit_find(sized), hl_env)
  }

// ------------------- the loop ------------------------------------------

/// Apply an undo/redo result to state: restore the buffer on `Some`,
/// leave state untouched (with a status note) on `None` (empty stack).
fun apply_history(state: EditorState, result: maybe<TextBuffer>, verb: string) : EditorState =>
  match result {
    Some(b) => set_status_message(EditorState { ...state, buffer: b }, verb),
    None    => set_status_message(state, "Nothing to " + verb)
  }

/// Dispatch a resolved `Action` (the `pre-action` hook has already
/// run and not cancelled it) to its effectful handler, threading
/// `Env` alongside `EditorState` for actions that fire their own
/// `buffer-open`/`pre-save`/`post-save` hooks.
// Return-type annotation omitted: carries <fsys>/<Clipboard> transitively
// via `run_save`/`run_prompt_submit`/etc.
fun dispatch_action(sized: EditorState, action: Action, buf_ref: ref<Buffer>, hl_env: Env) =>
  match action {
    // Effectful actions handled inline; pure ones fall through.
    Save      => run_save(sized, hl_env),
    Copy      => {
      set_selection(current_line(sized))
      (set_status_message(sized, "Copied line"), hl_env)
    },
    Paste     => {
      buf_ref.snapshot(sized.buffer)
      (paste_text(sized, get_selection()), hl_env)
    },
    Insert(_) => {
      buf_ref.snapshot(sized.buffer)
      (apply_action(sized, action), hl_env)
    },
    NewLine        => {
      buf_ref.snapshot(sized.buffer)
      (apply_action(sized, action), hl_env)
    },
    DeleteBackward => {
      buf_ref.snapshot(sized.buffer)
      (apply_action(sized, action), hl_env)
    },
    DeleteForward => {
      buf_ref.snapshot(sized.buffer)
      (apply_action(sized, action), hl_env)
    },
    KillLine  => {
      buf_ref.snapshot(sized.buffer)
      set_selection(kill_line_text(sized))
      (kill_line(sized), hl_env)
    },
    KillWordBack => {
      buf_ref.snapshot(sized.buffer)
      set_selection(kill_word_back_text(sized))
      (delete_word_back(sized), hl_env)
    },
    KillWordForward => {
      buf_ref.snapshot(sized.buffer)
      set_selection(kill_word_forward_text(sized))
      (delete_word_forward(sized), hl_env)
    },
    KillWholeLine => {
      buf_ref.snapshot(sized.buffer)
      set_selection(kill_whole_line_text(sized))
      (kill_whole_line(sized), hl_env)
    },
    Undo      => (apply_history(sized, buf_ref.undo(sized.buffer), "undo"), hl_env),
    Redo      => (apply_history(sized, buf_ref.redo(sized.buffer), "redo"), hl_env),
    PromptSubmit => run_prompt_submit(sized, hl_env),
    PromptKillLine => {
      set_selection(prompt_kill_text(sized))
      (prompt_truncate(sized), hl_env)
    },
    NewBuffer => run_buffer_open(apply_action(sized, action), "", hl_env),
    _         => (apply_action(sized, action), hl_env)
  }

/// `true` for `Quit` only — used to keep `Quit` un-cancellable by a
/// `pre-action` hook (see `event_loop_step`): a plugin can still
/// observe/message the quit attempt, but can never permanently trap
/// the editor open, matching the existing invariant that `Ctrl-q`
/// always resolves to `Quit` even from a keystroke-eating mode.
fun is_quit(action: Action) : bool =>
  match action {
    Quit => true,
    _    => false
  }

/// One tick of the event loop: query dimensions, render (if the frame
/// changed), poll for the next event, resolve + dispatch it, and
/// recurse. Returns the final `EditorState` once `should_quit` flips true.
// `resolve_action` turns the raw Event into a semantic `Action` using
// `state.config.bindings`; `pre-action` fires for every resolved action
// (see `hilisp_host.hc`'s cancel convention) before `dispatch_action`
// pattern-matches on the variants that need effects, everything else
// falling through to the pure `apply_action`. `Insert`/`Paste`/etc.
// snapshot the buffer *before* mutating so Undo always has a valid
// history entry to restore. `last_frame` (the previously-drawn
// ScreenBuffer) lets a Tick with nothing to redraw skip `render_frame`
// when the freshly-built buffer structurally equals the last one drawn
// — avoids a visible flicker on the styled rows every ~200ms poll
// timeout otherwise. `hl_env` is the HiLisp `Env` threaded through
// every hook firing (`init.hl` + any loaded plugins' `(on ...)`
// registrations live on it).
fun event_loop_step(state: EditorState, buf_ref: ref<Buffer>, last_frame: maybe<ScreenBuffer>, hl_env: Env) {
  if state.should_quit {
    let (_, _) = fire_hook(env_with_buffer_stats(hl_env, state.buffer), "quit", [])
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
    let stats_env = env_with_buffer_stats(hl_env, sized.buffer)
    let (pre_results, hl_env1) = fire_hook(stats_env, "pre-action", [LStr(action_to_string(action))])
    let (next, hl_env2) =
      if hook_cancels(pre_results) && !is_quit(action) { (blocked_state(sized, action_to_string(action), pre_results), hl_env1) }
      else { dispatch_action(sized, action, buf_ref, hl_env1) }
    event_loop_step(next, buf_ref, next_frame, hl_env2)
  }
}

/// Same as `event_loop`, but threads a caller-supplied HiLisp `Env`
/// (typically `config_loader.hc`'s output, carrying `init.hl` +
/// plugin `(on ...)` registrations) through every hook firing instead
/// of a bare, hook-free one.
// Return-type annotation omitted: the full effect row (<Terminal,
// Clipboard, Buffer, fsys, div>) is inferred by Koka — explicit
// annotation would be rejected as too narrow.
pub fun event_loop_with_env(state: EditorState, hl_env0:Env) {
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
  event_loop_step(state, buf_ref, None, hl_env0)
}

/// Entry point for callers with no HiLisp env of their own (most
/// existing tests): spawns one `Buffer` instance and hands off to
/// `event_loop_with_env` with a bare, hook-free `Env`.
pub fun event_loop(state: EditorState) {
  event_loop_with_env(state, make_env())
}
