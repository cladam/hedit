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
import "config_loader"
import "session"
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

// ------------------- Buffer effect (M5/M21, named/spawned) --------------

/// Per-buffer branching undo history graph (M21), spawned per buffer.
// Ops take the *current* `TextBuffer` explicitly where needed. Edits
// create new child nodes rather than destroying redo chains, forming
// a tree of revisions. `next_branch` cycles siblings at a divergence.
// `snapshot_tree` exports the graph for visual rendering (Meta-t).
// `jump_to` restores any historical node by ID.
pub effect Buffer {
  fun snapshot(b: TextBuffer)
  fun undo(current: TextBuffer) : maybe<TextBuffer>
  fun redo(current: TextBuffer) : maybe<TextBuffer>
  fun next_branch(current: TextBuffer) : maybe<TextBuffer>
  fun snapshot_tree() : UndoTree
  fun jump_to(target_id: int) : maybe<TextBuffer>
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
/// backgrounding the current one (same shape as `NewBuffer`). Also
/// spawns the new buffer's own `Buffer` history instance and conses it
/// onto `pool` — every open `bid` must have a pool entry (M14).
fun submit_open_file(state: EditorState, path: string, pool: list<(int, ref<Buffer>)>) {
  let new_bid = state.next_bid
  let (new_buf, load_status) = load_buffer(new_bid, Some(path))
  let new_ref = spawn_buffer_handler().0
  let pool1 = [(new_bid, new_ref)] + pool
  let opened = EditorState {
    ...state,
    buffer: new_buf,
    background_buffers: state.background_buffers + [state.buffer],
    next_bid: new_bid + 1,
    prompt: NoPrompt,
    panes: replace_leaf(state.panes, state.buffer.bid, Leaf(new_bid))
  }
  let final = match load_status {
    None      => opened,
    Some(msg) => set_status_message(opened, msg)
  }
  (final, pool1)
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
/// freshly loaded buffer. Threads `pool` through unchanged except for
/// the new entry `submit_open_file` conses on.
// Return-type annotation omitted: carries <fsys> (Koka rejects pure
// annotation once the read is behind `submit_open_file`/`load_buffer`).
fun run_open_file(sized: EditorState, path: string, hl_env: Env, pool: list<(int, ref<Buffer>)>) {
  let (opened, pool1) = submit_open_file(sized, path, pool)
  let (next, hl_env1) = run_buffer_open(opened, path, hl_env)
  (next, hl_env1, pool1)
}

// ------------------- Split panes (M15) --------------------------------
// `VSplitPrompt`/`HSplitPrompt` submit: an empty typed path duplicates
// the current buffer's content into a fresh, unnamed buffer (pure); a
// non-empty path loads that file from disk (<fsys>, same as Open). Either
// way the new buffer gets its own `bid`, its own `Buffer` history pool
// entry (undo/redo never crosses panes, same invariant M14 established
// for background buffers), and `panes` grows a `Split` where the
// focused leaf used to be a `Leaf` — the new buffer becomes active/
// focused, the old one slides into `background_buffers` (same "push
// the old one, focus the new one" shape as `NewBuffer`/`OpenFile`).

/// Build the new pane's buffer: a disk load for a typed path, or a pure
/// in-memory duplicate of the current buffer for a bare Enter.
fun split_buffer(sized: EditorState, new_bid: int, text: string) =>
  if text == "" { (duplicate_buffer(new_bid, sized.buffer), None) }
  else { load_buffer(new_bid, Some(text)) }

/// Split submit shared by `VSplitPrompt`/`HSplitPrompt`, `axis` picking
/// which. Threads `pool`/`hl_env` the same shape as `run_open_file`, plus
/// growing `sized.panes` at the focused leaf.
fun run_split(sized: EditorState, axis: Axis, text: string, hl_env: Env, pool: list<(int, ref<Buffer>)>) {
  let new_bid = sized.next_bid
  let (new_buf, load_status) = split_buffer(sized, new_bid, text)
  let new_ref = spawn_buffer_handler().0
  let pool1 = [(new_bid, new_ref)] + pool
  let new_panes = replace_leaf(sized.panes, sized.buffer.bid, Split(axis, 0.5, Leaf(sized.buffer.bid), Leaf(new_bid)))
  let opened = EditorState {
    ...sized,
    buffer: new_buf,
    background_buffers: sized.background_buffers + [sized.buffer],
    next_bid: new_bid + 1,
    prompt: NoPrompt,
    panes: new_panes
  }
  let based = match load_status {
    None      => opened,
    Some(msg) => set_status_message(opened, msg)
  }
  let (next, hl_env1) = run_buffer_open(based, text, hl_env)
  (next, hl_env1, pool1)
}

fun shell_success_marker() : string =>
  "__HEDIT_SHELL_COMMAND_OK__"

fun run_shell_command(cmd_str: string) {
  let marker = shell_success_marker()
  match exec(cmd_str + " 2>&1 && printf '" + marker + "'") {
    Err(msg) => (
      ShellOutputState { command: cmd_str, lines: [msg], scroll_line: 0, succeeded: false },
      Some("Could not execute command: " + msg)
    ),
    Ok(out) => {
      let succeeded = ends_with(out, marker)
      let captured = if succeeded { out[0:length(out) - length(marker)] } else { out }
      (
        ShellOutputState { command: cmd_str, lines: split(captured, "\n"), scroll_line: 0, succeeded: succeeded },
        None
      )
    }
  }
}

fun run_palette_error(closed: EditorState, err_opt: maybe<string>, hl_env: Env, pool: list<(int, ref<Buffer>)>) =>
  match err_opt {
    Some(err_msg) => (set_status_message(closed, err_msg), hl_env, pool),
    None          => (closed, hl_env, pool)
  }

/// Dispatch `PromptSubmit` (Enter while a prompt is active) to the
/// right hook-aware effectful handler.
// `NoPrompt` can't happen in practice (resolve_action only emits
// PromptSubmit while a prompt is active) but falls back to a no-op
// rather than crashing. Return-type annotation omitted: carries
// <fsys> transitively via `run_open_file`/`run_save_as`/`run_split`.
fun run_prompt_submit(sized: EditorState, hl_env: Env, pool: list<(int, ref<Buffer>)>) =>
  match sized.prompt {
    NoPrompt              => (sized, hl_env, pool),
    SaveAsPrompt(text, _) => {
      let (s2, e2) = run_save_as(sized, text, hl_env)
      (s2, e2, pool)
    },
    OpenPrompt(text, _)   => run_open_file(sized, text, hl_env, pool),
    FindPrompt(_, _)      => (submit_find(sized), hl_env, pool),
    VSplitPrompt(text, _) => run_split(sized, Vertical, text, hl_env, pool),
    HSplitPrompt(text, _) => run_split(sized, Horizontal, text, hl_env, pool),
    CommandPrompt(p_text, _, sel_idx) => {
      let closed = EditorState { ...sized, prompt: NoPrompt }
      let (act_opt, err_opt) = resolve_command_palette_action(p_text, sel_idx)
      match act_opt {
        Some(act) => dispatch_action(closed, act, pool, hl_env),
        None      => run_palette_error(closed, err_opt, hl_env, pool)
      }
    },
    ShellPrompt(cmd_str, _) => {
      let closed = EditorState { ...sized, prompt: NoPrompt }
      dispatch_action(closed, RunShellCommand(cmd_str), pool, hl_env)
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

/// Look up the `Buffer` history instance for `bid` in the pool. Falls
/// back to spawning a fresh (empty-history) instance on a miss — should
/// not happen in practice (every open `bid` gets a pool entry when it's
/// created), but keeps Undo/Redo from ever crashing on a pool/state
/// desync instead of silently corrupting another buffer's history.
fun pool_get(pool: list<(int, ref<Buffer>)>, bid: int) =>
  match map_get(pool, bid) {
    Some(r) => r,
    None    => spawn_buffer_handler().0
  }

/// Drop the pool entry for a buffer that just closed (M14) — otherwise
/// closed buffers' handlers pile up for the rest of the session.
fun pool_drop(pool: list<(int, ref<Buffer>)>, bid: int) : list<(int, ref<Buffer>)> =>
  match pool {
    []                     => [],
    [(pbid, pref), ..rest] =>
      if pbid == bid { pool_drop(rest, bid) } else { [(pbid, pref)] + pool_drop(rest, bid) }
  }

/// Dispatch a resolved `Action` (the `pre-action` hook has already
/// run and not cancelled it) to its effectful handler, threading `Env`
/// alongside `EditorState` for actions that fire their own
/// `buffer-open`/`pre-save`/`post-save` hooks, and the per-buffer
/// `Buffer` pool (M14) for actions that touch undo/redo history or
/// change which buffers are open.
// Return-type annotation omitted: carries <fsys>/<Clipboard>/<Buffer>
// transitively via `run_save`/`run_prompt_submit`/etc.
fun dispatch_action(sized: EditorState, action: Action, buf_pool: list<(int, ref<Buffer>)>, hl_env: Env) =>
  match action {
    // Effectful actions handled inline; pure ones fall through.
    Save      => {
      let (s2, e2) = run_save(sized, hl_env)
      (s2, e2, buf_pool)
    },
    ReloadConfig => {
      let (s2, e2) = reload_config_with_env(sized, hl_env)
      (s2, e2, buf_pool)
    },
    Copy      => {
      let (text, msg) = match selection_text(sized) {
        Some(t) => (t, "Copied selection"),
        None    => (current_line(sized), "Copied line")
      }
      set_selection(text)
      (set_status_message(sized, msg), hl_env, buf_pool)
    },
    Paste     => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      buf_ref.snapshot(sized.buffer)
      let base = match selection_span(sized) { Some(_) => delete_selection(sized), None => sized }
      (paste_text(base, get_selection()), hl_env, buf_pool)
    },
    Insert(_) => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      buf_ref.snapshot(sized.buffer)
      (apply_action(sized, action), hl_env, buf_pool)
    },
    NewLine        => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      buf_ref.snapshot(sized.buffer)
      (apply_action(sized, action), hl_env, buf_pool)
    },
    DeleteBackward => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      buf_ref.snapshot(sized.buffer)
      (apply_action(sized, action), hl_env, buf_pool)
    },
    DeleteForward => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      buf_ref.snapshot(sized.buffer)
      (apply_action(sized, action), hl_env, buf_pool)
    },
    KillLine  => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      buf_ref.snapshot(sized.buffer)
      set_selection(kill_line_text(sized))
      (kill_line(sized), hl_env, buf_pool)
    },
    KillWordBack => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      buf_ref.snapshot(sized.buffer)
      set_selection(kill_word_back_text(sized))
      (delete_word_back(sized), hl_env, buf_pool)
    },
    KillWordForward => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      buf_ref.snapshot(sized.buffer)
      set_selection(kill_word_forward_text(sized))
      (delete_word_forward(sized), hl_env, buf_pool)
    },
    KillWholeLine => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      buf_ref.snapshot(sized.buffer)
      set_selection(kill_whole_line_text(sized))
      (kill_whole_line(sized), hl_env, buf_pool)
    },
    Undo      => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      (apply_history(sized, buf_ref.undo(sized.buffer), "undo"), hl_env, buf_pool)
    },
    Redo      => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      (apply_history(sized, buf_ref.redo(sized.buffer), "redo"), hl_env, buf_pool)
    },
    ToggleUndoTree =>
      match sized.undo_tree {
        Some(uts) => (EditorState { ...sized, undo_tree: None, buffer: uts.original_buffer }, hl_env, buf_pool),
        None => {
          let buf_ref = pool_get(buf_pool, sized.buffer.bid)
          buf_ref.snapshot(sized.buffer)
          let tree = buf_ref.snapshot_tree()
          if is_empty(tree.nodes) {
            (set_status_message(sized, "No undo history"), hl_env, buf_pool)
          } else {
            let uts = UndoTreeState {
              tree: tree,
              selected_id: tree.current_id,
              original_buffer: sized.buffer,
              original_id: tree.current_id
            }
            (EditorState { ...sized, undo_tree: Some(uts) }, hl_env, buf_pool)
          }
        }
      },
    NextBranch => {
      let buf_ref = pool_get(buf_pool, sized.buffer.bid)
      let res = buf_ref.next_branch(sized.buffer)
      let next_state = match res {
        Some(b) => set_status_message(EditorState { ...sized, buffer: b }, "Switched branch"),
        None    => set_status_message(sized, "No other branch")
      }
      (next_state, hl_env, buf_pool)
    },
    UndoTreeCommit =>
      match sized.undo_tree {
        Some(uts) => {
          let buf_ref = pool_get(buf_pool, sized.buffer.bid)
          let restored = buf_ref.jump_to(uts.selected_id)
          let next_buf = match restored {
            Some(b) => b,
            None    => sized.buffer
          }
          let committed = EditorState { ...sized, undo_tree: None, buffer: next_buf }
          let msg = "Restored snapshot [" + show(uts.selected_id) + "]"
          (set_status_message(committed, msg), hl_env, buf_pool)
        },
        None => (sized, hl_env, buf_pool)
      },
    PromptSubmit => run_prompt_submit(sized, hl_env, buf_pool),
    PromptKillLine => {
      set_selection(prompt_kill_text(sized))
      (prompt_truncate(sized), hl_env, buf_pool)
    },
    NewBuffer => {
      let new_ref = spawn_buffer_handler().0
      let pool1 = [(sized.next_bid, new_ref)] + buf_pool
      let (next, hl_env1) = run_buffer_open(apply_action(sized, action), "", hl_env)
      (next, hl_env1, pool1)
    },
    CloseBuffer => {
      let closed_bid = sized.buffer.bid
      let next = apply_action(sized, action)
      let pool1 = if next.buffer.bid == closed_bid { buf_pool } else { pool_drop(buf_pool, closed_bid) }
      (next, hl_env, pool1)
    },
    // With 2+ panes open, `Quit` closes the active pane's buffer (see
    // `actions.hc::close_pane`) instead of quitting — drop its history
    // pool entry the same way `CloseBuffer` does, keyed on whether the
    // active bid actually changed.
    Quit => {
      let closed_bid = sized.buffer.bid
      let next = apply_action(sized, action)
      let pool1 = if next.buffer.bid == closed_bid { buf_pool } else { pool_drop(buf_pool, closed_bid) }
      (next, hl_env, pool1)
    },
    RunShellCommand(cmd_str) => {
      if cmd_str == "" {
        (sized, hl_env, buf_pool)
      } else {
        let captured: (ShellOutputState, maybe<string>) = run_shell_command(cmd_str)
        let shown = EditorState { ...sized, shell_output: Some(captured.0) }
        let next = match captured.1 {
          Some(msg) => set_status_message(shown, msg),
          None      => shown
        }
        (next, hl_env, buf_pool)
      }
    },
    _         => (apply_action(sized, action), hl_env, buf_pool)
  }

fun is_shell_command(action: Action) : bool =>
  match action {
    RunShellCommand(_) => true,
    _                  => false
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
fun is_save(action: Action) : bool =>
  match action {
    Save => true,
    _    => false
  }

// registrations live on it).
fun event_loop_step(state: EditorState, buf_pool: list<(int, ref<Buffer>)>, last_frame: maybe<ScreenBuffer>, hl_env: Env) {
  if state.should_quit {
    let (_, _) = fire_hook(env_with_buffer_stats(hl_env, state.buffer), "quit", [])
    save_session_if_needed(state)
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
    let (next, hl_env2, pool2) =
      if hook_cancels(pre_results) && !is_quit(action) { (blocked_state(sized, action_to_string(action), pre_results), hl_env1, buf_pool) }
      else { dispatch_action(sized, action, buf_pool, hl_env1) }
    let synced = if view_relevant_change(sized, next) { sync_scroll(next) } else { next }
    if is_save(action) { save_session_if_needed(synced) }
    let next_frame_actual = if is_shell_command(action) { None } else { next_frame }
    event_loop_step(synced, pool2, next_frame_actual, hl_env2)
  }
}

fun record_snapshot(nodes: list<UndoNode>, curr: UndoNode, b: TextBuffer, next_id: int) : (list<UndoNode>, int, int) {
  if curr.snapshot == b {
    (nodes, next_id, curr.id)
  } else {
    match find_child_matching(nodes, curr.children, b) {
      Some(existing_cid) => (set_last_child(nodes, curr.id, existing_cid), next_id, existing_cid),
      None => {
        let nid = next_id
        let new_node = UndoNode { id: nid, snapshot: b, parent: curr.id, children: [], last_child: None }
        let updated = add_child(nodes, curr.id, nid) + [new_node]
        (updated, next_id + 1, nid)
      }
    }
  }
}

fun get_or_create_child(nodes: list<UndoNode>, curr: UndoNode, current: TextBuffer, next_id: int) : (list<UndoNode>, int, int) {
  if curr.snapshot == current {
    (nodes, next_id, curr.id)
  } else {
    match find_child_matching(nodes, curr.children, current) {
      Some(cid) => (set_last_child(nodes, curr.id, cid), next_id, cid),
      None => {
        let cid = next_id
        let child = UndoNode { id: cid, snapshot: current, parent: curr.id, children: [], last_child: None }
        let updated = add_child(nodes, curr.id, cid) + [child]
        (updated, next_id + 1, cid)
      }
    }
  }
}

fun pick_redo_child(curr: UndoNode) : maybe<int> =>
  match curr.last_child {
    Some(cid) => Some(cid),
    None => match curr.children {
      [] => None,
      [first_cid, .._] => Some(first_cid)
    }
  }

fun find_child_by_id(nodes: list<UndoNode>, cid_opt: maybe<int>) : maybe<UndoNode> =>
  match cid_opt {
    None => None,
    Some(cid) => find_undo_node(nodes, cid)
  }

fun find_sibling_by_id(nodes: list<UndoNode>, sib_id_opt: maybe<int>) : maybe<UndoNode> =>
  match sib_id_opt {
    None => None,
    Some(sib_id) => find_undo_node(nodes, sib_id)
  }

fun find_sibling_node(nodes: list<UndoNode>, parent_id: int, curr_id: int) : maybe<UndoNode> =>
  match find_undo_node(nodes, parent_id) {
    None => None,
    Some(parent_node) => find_sibling_by_id(nodes, next_sibling_id(parent_node.children, curr_id))
  }

fun step_to_parent(nodes: list<UndoNode>, eff_node: UndoNode) : (list<UndoNode>, int, maybe<TextBuffer>) =>
  match find_undo_node(nodes, eff_node.parent) {
    None => (nodes, eff_node.id, None),
    Some(parent_node) => {
      let updated = set_last_child(nodes, parent_node.id, eff_node.id)
      (updated, parent_node.id, Some(parent_node.snapshot))
    }
  }

fun execute_undo(nodes: list<UndoNode>, eff_id: int) : (list<UndoNode>, int, maybe<TextBuffer>) =>
  match find_undo_node(nodes, eff_id) {
    None => (nodes, eff_id, None),
    Some(eff_node) =>
      if eff_node.parent == 0 { (nodes, eff_node.id, None) }
      else { step_to_parent(nodes, eff_node) }
  }

fun execute_redo(nodes: list<UndoNode>, curr: UndoNode) : (list<UndoNode>, int, maybe<TextBuffer>) =>
  match find_child_by_id(nodes, pick_redo_child(curr)) {
    None => (nodes, curr.id, None),
    Some(child_node) => {
      let updated = set_last_child(nodes, curr.id, child_node.id)
      (updated, child_node.id, Some(child_node.snapshot))
    }
  }

fun cycle_children_branch(nodes: list<UndoNode>, curr: UndoNode) : (list<UndoNode>, int, maybe<TextBuffer>) {
  let active_cid = match curr.last_child {
    Some(cid) => cid,
    None => match curr.children {
      [] => 0,
      [c, .._] => c
    }
  }
  match find_sibling_by_id(nodes, next_sibling_id(curr.children, active_cid)) {
    None => (nodes, curr.id, None),
    Some(sib_node) => {
      let updated = set_last_child(nodes, curr.id, sib_node.id)
      (updated, sib_node.id, Some(sib_node.snapshot))
    }
  }
}

fun find_branch_switch(nodes: list<UndoNode>, curr: UndoNode) : (list<UndoNode>, int, maybe<TextBuffer>) {
  if curr.parent == 0 {
    cycle_children_branch(nodes, curr)
  } else {
    match find_sibling_node(nodes, curr.parent, curr.id) {
      Some(sib_node) => {
        let updated = set_last_child(nodes, curr.parent, sib_node.id)
        (updated, sib_node.id, Some(sib_node.snapshot))
      },
      None => cycle_children_branch(nodes, curr)
    }
  }
}

/// Spawn a fresh, empty-history `Buffer` instance and return its ref —
/// the unit `pool_get`/`pool_drop`/M14's per-buffer pool is built from.
// Returns a 2-tuple (both slots the same ref), not the bare ref: hica's
// escape checker flags a bare `Var` referencing a locally-spawned ref
// in return position, but doesn't inspect through a Tuple/EList/Binary
// wrapper (same idiom `named-effects-design.md`'s pool examples use,
// e.g. `[w] + spawn_workers(n - 1)`) — the underlying named-effect ref
// is a real first-class value, not a stack-scoped handle, so returning
// it (wrapped) across a function boundary is intended, not a hack.
pub fun spawn_buffer_handler() {
  spawn Buffer {
    snapshot(b) => {
      if is_empty(nodes) {
        let root = UndoNode { id: 1, snapshot: b, parent: 0, children: [], last_child: None }
        nodes = [root]
        current_id = 1
        next_id = 2
      } else {
        match find_undo_node(nodes, current_id) {
          None => {
            let root = UndoNode { id: next_id, snapshot: b, parent: 0, children: [], last_child: None }
            nodes = nodes + [root]
            current_id = next_id
            next_id = next_id + 1
          },
          Some(curr) => {
            let (nodes1, next_id1, new_curr_id) = record_snapshot(nodes, curr, b, next_id)
            nodes = nodes1
            next_id = next_id1
            current_id = new_curr_id
          }
        }
      }
    },
    undo(current) => {
      if is_empty(nodes) {
        None
      } else {
        match find_undo_node(nodes, current_id) {
          None => None,
          Some(curr) => {
            let (nodes1, next_id1, eff_id) = get_or_create_child(nodes, curr, current, next_id)
            let (nodes2, new_curr_id, res) = execute_undo(nodes1, eff_id)
            nodes = nodes2
            next_id = next_id1
            current_id = new_curr_id
            res
          }
        }
      }
    },
    redo(current) => {
      if is_empty(nodes) {
        None
      } else {
        match find_undo_node(nodes, current_id) {
          None => None,
          Some(curr) => {
            let (nodes1, new_id, res) = execute_redo(nodes, curr)
            nodes = nodes1
            current_id = new_id
            res
          }
        }
      }
    },
    next_branch(current) => {
      if is_empty(nodes) {
        None
      } else {
        match find_undo_node(nodes, current_id) {
          None => None,
          Some(curr) => {
            let (nodes1, new_id, res) = find_branch_switch(nodes, curr)
            nodes = nodes1
            current_id = new_id
            res
          }
        }
      }
    },
    snapshot_tree() => {
      UndoTree { current_id: current_id, nodes: nodes }
    },
    jump_to(target_id) => {
      match find_undo_node(nodes, target_id) {
        None => None,
        Some(target_node) => {
          nodes = set_ancestor_last_children(nodes, target_id)
          current_id = target_id
          Some(target_node.snapshot)
        }
      }
    }
  } with var nodes: list<UndoNode> = [], var current_id: int = 0, var next_id: int = 1 as buf_ref
  (buf_ref, buf_ref)
}

/// Same as `event_loop`, but threads a caller-supplied HiLisp `Env`
/// (typically `config_loader.hc`'s output, carrying `init.hl` +
/// plugin `(on ...)` registrations) through every hook firing instead
/// of a bare, hook-free one.
// Return-type annotation omitted: the full effect row (<Terminal,
// Clipboard, Buffer, fsys, div>) is inferred by Koka — explicit
// annotation would be rejected as too narrow.
/// Initialize the Buffer effect pool for all currently-open buffers.
fun init_buffer_pool(bufs: list<TextBuffer>) =>
  match bufs {
    [] => [],
    [b, ..rest] => {
      let r = spawn_buffer_handler().0
      [(b.bid, r)] + init_buffer_pool(rest)
    }
  }

pub fun event_loop_with_env(state: EditorState, hl_env0:Env) {
  let pool0 = init_buffer_pool([state.buffer] + state.background_buffers)
  // One-off initial scroll sync against the REAL terminal size (state's
  // `screen_size` is still whatever `init_editor` defaulted to) — the
  // only place a cursor can start outside the first page without a
  // preceding cursor-moving action to trigger the per-tick sync below
  // (a startup `+LINE` position, see `main.hc::set_initial_position`).
  let dims0  = get_dimensions()
  let sized0 = sync_scroll(EditorState { ...state, screen_size: dims0 })
  event_loop_step(sized0, pool0, None, hl_env0)
}

/// Entry point for callers with no HiLisp env of their own (most
/// existing tests): spawns one `Buffer` instance and hands off to
/// `event_loop_with_env` with a bare, hook-free `Env`.
pub fun event_loop(state: EditorState) {
  event_loop_with_env(state, make_env())
}
