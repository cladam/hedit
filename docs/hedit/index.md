# src

**Files:**
- [render.hc](../../src/render.hc)
- [config_loader.hc](../../src/config_loader.hc)
- [keys.hc](../../src/keys.hc)
- [actions.hc](../../src/actions.hc)
- [runtime.hc](../../src/runtime.hc)
- [model.hc](../../src/model.hc)
- [hilisp_host.hc](../../src/hilisp_host.hc)
- [cli_spec.hc](../../src/cli_spec.hc)
- [main.hc](../../src/main.hc)

---

# Project Architecture & Export Directory: `render.hc`

## Module Overview
- **Source File:** `src/render.hc`
## Dependencies
- `keys`
- `model`
- `hilisp_host`

## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
| `render_help_buffer` | `fun render_help_buffer(state: EditorState) : ScreenBuffer` | Build the full-screen help overlay ScreenBuffer listing every currently-bound chord. |
| `render_editor_to_buffer` | `fun render_editor_to_buffer(state: EditorState) : ScreenBuffer` | Build the ScreenBuffer for the current frame, dispatching on `state.show_help` ahead of the normal render pass. |


---

# Domain Data Models & Type Dictionary

*(No structs, enums or effects defined in this module)*

---

# Purity and Side Effects Tracking Matrix

| Function | Signature | Purity Status | Detected Effect Dependencies |
| --- | --- | --- | --- |
| `fit_to_width` | `fun fit_to_width(s: string, w: int) : string` | ✅ Pure | None |
| `take_or_pad` | `fun take_or_pad(xs: list<string>, n: int, pad: string) : list<string>` | ⚡ Impure | Divergent (recursion/loop) |
| `drop_n` | `fun drop_n(xs: list<string>, n: int) : list<string>` | ⚡ Impure | Divergent (recursion/loop) |
| `scroll_offset` | `fun scroll_offset(n_content: int, line: int) : int` | ✅ Pure | None |
| `buffer_tab_name` | `fun buffer_tab_name(buf: TextBuffer) : string` | ✅ Pure | None |
| `build_tabline` | `fun build_tabline(state: EditorState) : string` | ✅ Pure | None |
| `prompt_label` | `fun prompt_label(p: Prompt) : string` | ✅ Pure | None |
| `prompt_prefix_len` | `fun prompt_prefix_len(p: Prompt) : int` | ✅ Pure | None |
| `prompt_cursor_col` | `fun prompt_cursor_col(p: Prompt) : int` | ✅ Pure | None |
| `render_normal_buffer` | `fun render_normal_buffer(state: EditorState) : ScreenBuffer` | ✅ Pure | None |
| `format_binding` | `fun format_binding(b: (KeyChord, Action)) : string` | ✅ Pure | None |
| `render_help_buffer` | `fun render_help_buffer(state: EditorState) : ScreenBuffer` | ✅ Pure | None |
| `render_editor_to_buffer` | `fun render_editor_to_buffer(state: EditorState) : ScreenBuffer` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/render.hc`

## Function Context
- **Name:** `render_normal_buffer`
- **Signature:** `fun render_normal_buffer(state: EditorState) : ScreenBuffer`
- **Location:** `src/render.hc:91`
- **Debt Score:** 10 (Critical)

## Detected FP Anti-Patterns
1. **Pipelines & Allocation:** Eager list pipeline with >2 operations (score: +10)
   - *Hint:* Wrap input with 'stream(xs)' from 'std/stream' or use pipeline transducers from 'std/xform' to eliminate intermediate list allocations.

## Code Snippet
```hica
fun render_normal_buffer(state: EditorState) : ScreenBuffer {
  let (w, h)    = state.screen_size
  let buf       = state.buffer
  let n_content = h - 2

  let cur    = match buf.cursors { [] => Position { line: 0, col: 0 }, [x, .._] => x.pos }
  let offset = scroll_offset(n_content, cur.line)

  // Each content line truncated to screen width; empty rows filled with "~".
  let text_rows    = map(drop_n(buf.lines, offset), (l) => fit_to_width(l, w))
  let content_rows = take_or_pad(text_rows, n_content, "~")

  let tabline_row = fit_to_width(build_tabline(state), w)

  // Status line: an active prompt wins; otherwise an explicit message,
  // falling back to path + dirty flag.
  let path_part   = match buf.path { None => "[No Name]", Some(p) => p }
  let dirty_str   = if buf.is_dirty { " [+]" } else { "" }
  let default_msg = path_part + dirty_str
  let status_msg  = match state.status_message { None => default_msg, Some(m) => m }
  let status_row  = match state.prompt {
    NoPrompt => fit_to_width(status_msg, w),
    _        => fit_to_width(prompt_label(state.prompt), w)
  }

  let visible_line = max(min(cur.line - offset, max(n_content - 1, 0)), 0)
  let visible_col  = max(min(cur.col, max(w - 1, 0)), 0)

  let (crow, ccol) = match state.prompt {
    NoPrompt => (visible_line + 2, visible_col + 1)
    _        => (h, min(prompt_prefix_len(state.prompt) + prompt_cursor_col(state.prompt) + 1, w))
  }

  ScreenBuffer {
    width: w,
    height: h,
    lines: [tabline_row] + content_rows + [status_row],
    cursor_row: crow,
    cursor_col: ccol
  }
}
```

---

## Summary
- **Functions analysed:** 13
- **Functions with debt:** 1
- **Total debt score:** 10

**FP Quality Index: 90/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`fit_to_width`](../../src/render.hc#L10) — Truncate `s` to at most `w` characters (no-op if already shorter).
- [`take_or_pad`](../../src/render.hc#L14) — First `n` elements of `xs`, padding with `pad` when `xs` is exhausted.
- [`drop_n`](../../src/render.hc#L26) — Drop the first `n` elements of `xs` (no-op past the end).
- [`scroll_offset`](../../src/render.hc#L40) — The vertical scroll offset (first visible buffer line).
- [`buffer_tab_name`](../../src/render.hc#L45) — Display name for a buffer's tab: its path, or "scratch" for an unnamed in-memory buffer.
- [`build_tabline`](../../src/render.hc#L50) — One tabline entry per open buffer (active buffer first), joined with "|". The active tab is bracketed (`[scratch]`).
- [`prompt_label`](../../src/render.hc#L58) — Status-row label for an active Save-As/Open prompt (M9), replacing the normal path/dirty-flag or status-message row while typing.
- [`prompt_prefix_len`](../../src/render.hc#L67) — Length of the fixed label prefix in front of the typed text — needed to place the real cursor at the right screen column.
- [`prompt_cursor_col`](../../src/render.hc#L75) — The prompt's own cursor column within its typed text.
- [`render_normal_buffer`](../../src/render.hc#L91) — Build a ScreenBuffer from `state`'s normal (non-help) editing view.
- [`format_binding`](../../src/render.hc#L143) — One row: "Ctrl-s  ->  save".
- [`render_help_buffer`](../../src/render.hc#L148) — Build the full-screen help overlay ScreenBuffer listing every currently-bound chord.
- [`render_editor_to_buffer`](../../src/render.hc#L166) — Build the ScreenBuffer for the current frame, dispatching on `state.show_help` ahead of the normal render pass.
---

# Project Architecture & Export Directory: `config_loader.hc`

## Module Overview
- **Source File:** `src/config_loader.hc`
## Dependencies
- `model`
- `hilisp_host`

## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
| `candidate_paths` | `fun candidate_paths(xdg: maybe<string>, home: maybe<string>) : list<string>` | Compose the two candidate config paths in priority order. |
| `read_first` | `fun read_first(paths: list<string>) : (string, maybe<string>)` | Try each candidate path in order; the first readable file wins, returned as `(content, Some(path))`. `("", None)` on total miss. |
| `load_user_config` | `fun load_user_config(cfg0: Config) : (Config, maybe<string>)` | Resolve `$XDG_CONFIG_HOME`/`$HOME`, walk the candidate paths, and evaluate the first one found through `hilisp_host::load_config`. Returns `cfg0` unchanged with `None` status if neither candidate exists. |
| `load_config_from_path` | `fun load_config_from_path(cfg0: Config, p: string) : (Config, maybe<string>)` | `--config <path>`: load exactly that file instead of walking `candidate_paths`. A missing/unreadable path surfaces as a status message rather than a silent fallback. |
| `load_user_config_opts` | `fun load_user_config_opts(cfg0: Config, explicit_path: maybe<string>, skip: bool) : (Config, maybe<string>)` | CLI-aware entry point used by `main.hc`: `--no-config` skips loading entirely, `--config <path>` loads exactly that file, and absent both, falls back to the normal XDG/HOME search. |


---

# Domain Data Models & Type Dictionary

*(No structs, enums or effects defined in this module)*

---

# Purity and Side Effects Tracking Matrix

| Function | Signature | Purity Status | Detected Effect Dependencies |
| --- | --- | --- | --- |
| `opt_path` | `fun opt_path(dir: maybe<string>, suffix: string) : list<string>` | ✅ Pure | None |
| `xdg_candidate` | `fun xdg_candidate(xdg: maybe<string>, home: maybe<string>) : list<string>` | ✅ Pure | None |
| `home_candidate` | `fun home_candidate(home: maybe<string>) : list<string>` | ✅ Pure | None |
| `candidate_paths` | `fun candidate_paths(xdg: maybe<string>, home: maybe<string>) : list<string>` | ✅ Pure | None |
| `read_first` | `fun read_first(paths: list<string>) : (string, maybe<string>)` | ⚡ Impure | I/O & FileSystem, Divergent (recursion/loop) |
| `apply_config_src` | `fun apply_config_src(cfg0: Config, src: string, p: string) : (Config, maybe<string>)` | ✅ Pure | None |
| `load_user_config` | `fun load_user_config(cfg0: Config) : (Config, maybe<string>)` | ⚡ Impure | I/O & FileSystem |
| `load_config_from_path` | `fun load_config_from_path(cfg0: Config, p: string) : (Config, maybe<string>)` | ⚡ Impure | I/O & FileSystem |
| `load_user_config_opts` | `fun load_user_config_opts(cfg0: Config, explicit_path: maybe<string>, skip: bool) : (Config, maybe<string>)` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/config_loader.hc`

## Summary
✅ **No functional debt detected** — all 9 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`opt_path`](../../src/config_loader.hc#L11) — Wrap `dir + suffix` in a singleton list, or `[]` if `dir` is `None`.
- [`xdg_candidate`](../../src/config_loader.hc#L16) — The XDG candidate path: `$XDG_CONFIG_HOME/hedit/init.hl` if set, else `$HOME/.config/hedit/init.hl`, else `[]`.
- [`home_candidate`](../../src/config_loader.hc#L23) — The `$HOME/.hedit.hl` candidate path, or `[]` if `$HOME` is unset.
- [`candidate_paths`](../../src/config_loader.hc#L29) — Compose the two candidate config paths in priority order.
- [`read_first`](../../src/config_loader.hc#L34) — Try each candidate path in order; the first readable file wins, returned as `(content, Some(path))`. `("", None)` on total miss.
- [`apply_config_src`](../../src/config_loader.hc#L46) — Evaluate `src` (already read from `p`) through `hilisp_host::load_config` and shape the resulting status message.
- [`load_user_config`](../../src/config_loader.hc#L57) — Resolve `$XDG_CONFIG_HOME`/`$HOME`, walk the candidate paths, and evaluate the first one found through `hilisp_host::load_config`. Returns `cfg0` unchanged with `None` status if neither candidate exists.
- [`load_config_from_path`](../../src/config_loader.hc#L71) — `--config <path>`: load exactly that file instead of walking `candidate_paths`. A missing/unreadable path surfaces as a status message rather than a silent fallback.
- [`load_user_config_opts`](../../src/config_loader.hc#L80) — CLI-aware entry point used by `main.hc`: `--no-config` skips loading entirely, `--config <path>` loads exactly that file, and absent both, falls back to the normal XDG/HOME search.
---

# Project Architecture & Export Directory: `keys.hc`

## Module Overview
- **Source File:** `src/keys.hc`
## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
| `decode_key` | `fun decode_key(code: int) : Event` | Decode a raw key code from the native `Terminal` handler (`term_ffi.hedit_read_key`'s contract, see src/term_ffi.kk) into an `Event`. |

### Public Enums / ADTs

- **`Modifier`**: A modifier key that can be combined with a base char (Ctrl-s, Alt-x, ...).
- **`SpecialKey`**: A non-printable key that doesn't map to a single `char`.
- **`Key`**: A single keypress the terminal handler delivers to us.
- **`MouseAction`**: A mouse button / wheel action.
- **`Event`**: Anything the outside world can deliver into the editor's event loop.


---

# Domain Data Models & Type Dictionary

## Algebraic Data Types (Enums)

### Type `Modifier` `pub`
A modifier key that can be combined with a base char (Ctrl-s, Alt-x, ...).

#### Variants
- `Ctrl`
- `Alt`
- `Meta`
- `Shift`

### Type `SpecialKey` `pub`
A non-printable key that doesn't map to a single `char`.

#### Variants
- `Enter`
- `Backspace`
- `Tab`
- `Esc`
- `ArrowUp`
- `ArrowDown`
- `ArrowLeft`
- `ArrowRight`

### Type `Key` `pub`
A single keypress the terminal handler delivers to us.

#### Variants
- `KChar(c: char)`
- `KSpecial(k: SpecialKey)`
- `KShortcut(m: Modifier, c: char)`

### Type `MouseAction` `pub`
A mouse button / wheel action.

#### Variants
- `Press`
- `Release`
- `Drag`
- `ScrollUp`
- `ScrollDown`

### Type `Event` `pub`
Anything the outside world can deliver into the editor's event loop.

#### Variants
- `KeyEvent(k: Key)`
- `MouseEvent(a: MouseAction, x: int, y: int)`
- `ResizeEvent(w: int, h: int)`
- `Tick`


---

# Purity and Side Effects Tracking Matrix

| Function | Signature | Purity Status | Detected Effect Dependencies |
| --- | --- | --- | --- |
| `decode_key` | `fun decode_key(code: int) : Event` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/keys.hc`

## Summary
✅ **No functional debt detected** — all 1 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`decode_key`](../../src/keys.hc#L58) — Decode a raw key code from the native `Terminal` handler (`term_ffi.hedit_read_key`'s contract, see src/term_ffi.kk) into an `Event`.
---

# Project Architecture & Export Directory: `actions.hc`

## Module Overview
- **Source File:** `src/actions.hc`
## Dependencies
- `keys`
- `model`

## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
| `insert_char` | `fun insert_char(state: EditorState, c: char) : EditorState` | Insert `c` at the cursor's column and advance the cursor by one. |
| `insert_newline` | `fun insert_newline(state: EditorState) : EditorState` | Split the current line at the cursor into two lines, cursor moves to column 0 of the new (second) line. |
| `move_line_start` | `fun move_line_start(state: EditorState) : EditorState` | Move the cursor to column 0 of its current line. |
| `move_line_end` | `fun move_line_end(state: EditorState) : EditorState` | Move the cursor to the end of its current line. |
| `delete_backward` | `fun delete_backward(state: EditorState) : EditorState` | Delete the char before the cursor, merging with the previous line at column 0. A no-op at the very start of the buffer. |
| `delete_forward` | `fun delete_forward(state: EditorState) : EditorState` | Delete the char under the cursor, merging the next line up into this one at the end of a non-last line. A no-op at the very end of the buffer. |
| `move_left` | `fun move_left(state: EditorState) : EditorState` | Move the cursor left one column, wrapping onto the end of the previous line at a line boundary. |
| `move_right` | `fun move_right(state: EditorState) : EditorState` | Move the cursor right one column, wrapping onto the start of the next line at a line boundary. |
| `move_up` | `fun move_up(state: EditorState) : EditorState` | Move the cursor up one line, clamping the column to the target line's length rather than tracking a "sticky" column. |
| `move_down` | `fun move_down(state: EditorState) : EditorState` | Move the cursor down one line, clamping the column to the target line's length rather than tracking a "sticky" column. |
| `current_line` | `fun current_line(state: EditorState) : string` | Return the text of the cursor's current line, or "" if the buffer has no cursors or no lines. |
| `paste_text` | `fun paste_text(state: EditorState, text: string) : EditorState` | Append `text` to the end of the cursor's line and advance the cursor by `length(text)`. |
| `kill_line_text` | `fun kill_line_text(state: EditorState) : string` | Return the text from the cursor to the end of the current line. |
| `kill_line` | `fun kill_line(state: EditorState) : EditorState` | Truncate the current line at the cursor. |
| `kill_word_back_text` | `fun kill_word_back_text(state: EditorState) : string` | Return the whitespace-delimited word before the cursor. |
| `delete_word_back` | `fun delete_word_back(state: EditorState) : EditorState` | Delete the whitespace-delimited word before the cursor, moving the cursor to the start of the removed span. |
| `move_word_back` | `fun move_word_back(state: EditorState) : EditorState` | Move the cursor one whitespace-delimited word back. |
| `move_word_forward` | `fun move_word_forward(state: EditorState) : EditorState` | Move the cursor one whitespace-delimited word forward. |
| `kill_word_forward_text` | `fun kill_word_forward_text(state: EditorState) : string` | Return the whitespace-delimited word after the cursor. |
| `delete_word_forward` | `fun delete_word_forward(state: EditorState) : EditorState` | Delete the whitespace-delimited word after the cursor. The cursor column is unchanged (still valid at the truncation point). |
| `kill_whole_line_text` | `fun kill_whole_line_text(state: EditorState) : string` | Return the full text of the cursor's current line. |
| `kill_whole_line` | `fun kill_whole_line(state: EditorState) : EditorState` | Clear the current line's content; the line itself stays (an empty line, not removed from the buffer). Cursor moves to column 0. |
| `new_buffer_action` | `fun new_buffer_action(state: EditorState) : EditorState` | Push the active buffer onto the background ring and make a fresh, empty scratch buffer active. |
| `cycle_next_buffer` | `fun cycle_next_buffer(state: EditorState) : EditorState` | Rotate to the next open buffer. A no-op with 0 or 1 open buffers. |
| `cycle_prev_buffer` | `fun cycle_prev_buffer(state: EditorState) : EditorState` | Rotate to the previous open buffer. A no-op with 0 or 1 open buffers. |
| `close_buffer_action` | `fun close_buffer_action(state: EditorState) : EditorState` | Close the active buffer and activate the next background buffer. |
| `prompt_insert_char` | `fun prompt_insert_char(state: EditorState, c: char) : EditorState` | Insert `c` at the prompt's cursor column, advancing the cursor by one. |
| `prompt_backspace` | `fun prompt_backspace(state: EditorState) : EditorState` | Delete the char before the prompt's cursor. A no-op at column 0. |
| `prompt_cancel` | `fun prompt_cancel(state: EditorState) : EditorState` | Dismiss the active prompt. |
| `prompt_move_start` | `fun prompt_move_start(state: EditorState) : EditorState` | Move the prompt's cursor to column 0. |
| `prompt_move_end` | `fun prompt_move_end(state: EditorState) : EditorState` | Move the prompt's cursor to the end of the typed text. |
| `prompt_move_left` | `fun prompt_move_left(state: EditorState) : EditorState` | Move the prompt's cursor left one column. |
| `prompt_move_right` | `fun prompt_move_right(state: EditorState) : EditorState` | Move the prompt's cursor right one column. |
| `prompt_delete_forward` | `fun prompt_delete_forward(state: EditorState) : EditorState` | Delete the char under the prompt's cursor. A no-op at the end of the typed text. |
| `prompt_kill_text` | `fun prompt_kill_text(state: EditorState) : string` | Return the prompt's typed text from the cursor to the end. |
| `prompt_truncate` | `fun prompt_truncate(state: EditorState) : EditorState` | Truncate the prompt's typed text at the cursor. |
| `open_file_prompt` | `fun open_file_prompt(state: EditorState) : EditorState` | Open the "open file" prompt with empty text. |
| `resolve_action` | `fun resolve_action(state: EditorState, evt: Event) : Action` | Resolve a raw event to a semantic Action, dispatching by editor mode (help overlay, active prompt, or normal editing). |
| `apply_action` | `fun apply_action(state: EditorState, action: Action) : EditorState` | Apply an Action to state, producing the next EditorState. |
| `handle_action` | `fun handle_action(state: EditorState, evt: Event) : EditorState` | Resolve and apply an event against state in one step. |


---

# Domain Data Models & Type Dictionary

*(No structs, enums or effects defined in this module)*

---

# Purity and Side Effects Tracking Matrix

| Function | Signature | Purity Status | Detected Effect Dependencies |
| --- | --- | --- | --- |
| `list_set` | `fun list_set(xs: list<string>, idx: int, new_val: string) : list<string>` | ⚡ Impure | Divergent (recursion/loop) |
| `list_get` | `fun list_get(xs: list<string>, idx: int, default: string) : string` | ⚡ Impure | Divergent (recursion/loop) |
| `list_split_at` | `fun list_split_at(xs: list<string>, idx: int, a: string, b: string) : list<string>` | ⚡ Impure | Divergent (recursion/loop) |
| `list_remove_at` | `fun list_remove_at(xs: list<string>, idx: int) : list<string>` | ⚡ Impure | Divergent (recursion/loop) |
| `head_cursor` | `fun head_cursor(buf: TextBuffer) : Cursor` | ✅ Pure | None |
| `clamp_col` | `fun clamp_col(lines: list<string>, line_idx: int, col: int) : int` | ✅ Pure | None |
| `insert_char` | `fun insert_char(state: EditorState, c: char) : EditorState` | ✅ Pure | None |
| `insert_newline` | `fun insert_newline(state: EditorState) : EditorState` | ✅ Pure | None |
| `move_line_start` | `fun move_line_start(state: EditorState) : EditorState` | ✅ Pure | None |
| `move_line_end` | `fun move_line_end(state: EditorState) : EditorState` | ✅ Pure | None |
| `delete_backward` | `fun delete_backward(state: EditorState) : EditorState` | ✅ Pure | None |
| `delete_forward` | `fun delete_forward(state: EditorState) : EditorState` | ✅ Pure | None |
| `move_left` | `fun move_left(state: EditorState) : EditorState` | ✅ Pure | None |
| `move_right` | `fun move_right(state: EditorState) : EditorState` | ✅ Pure | None |
| `move_up` | `fun move_up(state: EditorState) : EditorState` | ✅ Pure | None |
| `move_down` | `fun move_down(state: EditorState) : EditorState` | ✅ Pure | None |
| `current_line` | `fun current_line(state: EditorState) : string` | ✅ Pure | None |
| `paste_text` | `fun paste_text(state: EditorState, text: string) : EditorState` | ✅ Pure | None |
| `kill_line_text` | `fun kill_line_text(state: EditorState) : string` | ✅ Pure | None |
| `kill_line` | `fun kill_line(state: EditorState) : EditorState` | ✅ Pure | None |
| `is_space_char` | `fun is_space_char(c: char) : bool` | ✅ Pure | None |
| `drop_while` | `fun drop_while(chs: list<char>, pred: (char) -> bool) : list<char>` | ⚡ Impure | Divergent (recursion/loop) |
| `word_back_col` | `fun word_back_col(line: string, col: int) : int` | ✅ Pure | None |
| `word_forward_col` | `fun word_forward_col(line: string, col: int) : int` | ✅ Pure | None |
| `kill_word_back_text` | `fun kill_word_back_text(state: EditorState) : string` | ✅ Pure | None |
| `delete_word_back` | `fun delete_word_back(state: EditorState) : EditorState` | ✅ Pure | None |
| `move_word_back` | `fun move_word_back(state: EditorState) : EditorState` | ✅ Pure | None |
| `move_word_forward` | `fun move_word_forward(state: EditorState) : EditorState` | ✅ Pure | None |
| `kill_word_forward_text` | `fun kill_word_forward_text(state: EditorState) : string` | ✅ Pure | None |
| `delete_word_forward` | `fun delete_word_forward(state: EditorState) : EditorState` | ✅ Pure | None |
| `kill_whole_line_text` | `fun kill_whole_line_text(state: EditorState) : string` | ✅ Pure | None |
| `kill_whole_line` | `fun kill_whole_line(state: EditorState) : EditorState` | ✅ Pure | None |
| `new_buffer_action` | `fun new_buffer_action(state: EditorState) : EditorState` | ✅ Pure | None |
| `cycle_next_buffer` | `fun cycle_next_buffer(state: EditorState) : EditorState` | ✅ Pure | None |
| `cycle_prev_buffer` | `fun cycle_prev_buffer(state: EditorState) : EditorState` | ✅ Pure | None |
| `close_buffer_action` | `fun close_buffer_action(state: EditorState) : EditorState` | ✅ Pure | None |
| `prompt_text` | `fun prompt_text(p: Prompt) : string` | ✅ Pure | None |
| `prompt_cursor` | `fun prompt_cursor(p: Prompt) : int` | ✅ Pure | None |
| `with_prompt` | `fun with_prompt(p: Prompt, t: string, c: int) : Prompt` | ✅ Pure | None |
| `prompt_insert_char` | `fun prompt_insert_char(state: EditorState, c: char) : EditorState` | ✅ Pure | None |
| `prompt_backspace` | `fun prompt_backspace(state: EditorState) : EditorState` | ✅ Pure | None |
| `prompt_cancel` | `fun prompt_cancel(state: EditorState) : EditorState` | ✅ Pure | None |
| `prompt_move_start` | `fun prompt_move_start(state: EditorState) : EditorState` | ✅ Pure | None |
| `prompt_move_end` | `fun prompt_move_end(state: EditorState) : EditorState` | ✅ Pure | None |
| `prompt_move_left` | `fun prompt_move_left(state: EditorState) : EditorState` | ✅ Pure | None |
| `prompt_move_right` | `fun prompt_move_right(state: EditorState) : EditorState` | ✅ Pure | None |
| `prompt_delete_forward` | `fun prompt_delete_forward(state: EditorState) : EditorState` | ✅ Pure | None |
| `prompt_kill_text` | `fun prompt_kill_text(state: EditorState) : string` | ✅ Pure | None |
| `prompt_truncate` | `fun prompt_truncate(state: EditorState) : EditorState` | ✅ Pure | None |
| `open_file_prompt` | `fun open_file_prompt(state: EditorState) : EditorState` | ✅ Pure | None |
| `resolve_prompt_action` | `fun resolve_prompt_action(evt: Event) : Action` | ✅ Pure | None |
| `resolve_help_action` | `fun resolve_help_action(evt: Event) : Action` | ✅ Pure | None |
| `resolve_normal_action` | `fun resolve_normal_action(state: EditorState, evt: Event) : Action` | ✅ Pure | None |
| `resolve_action` | `fun resolve_action(state: EditorState, evt: Event) : Action` | ✅ Pure | None |
| `apply_action` | `fun apply_action(state: EditorState, action: Action) : EditorState` | ✅ Pure | None |
| `handle_action` | `fun handle_action(state: EditorState, evt: Event) : EditorState` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/actions.hc`

## Summary
✅ **No functional debt detected** — all 56 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`list_set`](../../src/actions.hc#L14) — Return a copy of `xs` with the element at `idx` replaced by `new_val`.
- [`list_get`](../../src/actions.hc#L23) — Return the element of `xs` at `idx`, or `default` if out of range.
- [`list_split_at`](../../src/actions.hc#L33) — Return a copy of `xs` with the element at `idx` replaced by two elements `a` and `b`.
- [`list_remove_at`](../../src/actions.hc#L42) — Return a copy of `xs` with the element at `idx` removed.
- [`head_cursor`](../../src/actions.hc#L54) — Return the buffer's primary cursor (multi-cursor is future work), defaulting to (0, 0) if the buffer has none.
- [`clamp_col`](../../src/actions.hc#L61) — Clamp `col` to a valid column within the line at `line_idx`.
- [`insert_char`](../../src/actions.hc#L69) — Insert `c` at the cursor's column and advance the cursor by one.
- [`insert_newline`](../../src/actions.hc#L92) — Split the current line at the cursor into two lines, cursor moves to column 0 of the new (second) line.
- [`move_line_start`](../../src/actions.hc#L113) — Move the cursor to column 0 of its current line.
- [`move_line_end`](../../src/actions.hc#L122) — Move the cursor to the end of its current line.
- [`delete_backward`](../../src/actions.hc#L133) — Delete the char before the cursor, merging with the previous line at column 0. A no-op at the very start of the buffer.
- [`delete_forward`](../../src/actions.hc#L166) — Delete the char under the cursor, merging the next line up into this one at the end of a non-last line. A no-op at the very end of the buffer.
- [`move_left`](../../src/actions.hc#L193) — Move the cursor left one column, wrapping onto the end of the previous line at a line boundary.
- [`move_right`](../../src/actions.hc#L209) — Move the cursor right one column, wrapping onto the start of the next line at a line boundary.
- [`move_up`](../../src/actions.hc#L224) — Move the cursor up one line, clamping the column to the target line's length rather than tracking a "sticky" column.
- [`move_down`](../../src/actions.hc#L235) — Move the cursor down one line, clamping the column to the target line's length rather than tracking a "sticky" column.
- [`current_line`](../../src/actions.hc#L247) — Return the text of the cursor's current line, or "" if the buffer has no cursors or no lines.
- [`paste_text`](../../src/actions.hc#L256) — Append `text` to the end of the cursor's line and advance the cursor by `length(text)`.
- [`kill_line_text`](../../src/actions.hc#L283) — Return the text from the cursor to the end of the current line.
- [`kill_line`](../../src/actions.hc#L291) — Truncate the current line at the cursor.
- [`is_space_char`](../../src/actions.hc#L303) — Return whether `c` is a space or tab character.
- [`drop_while`](../../src/actions.hc#L307) — Return the suffix of `chs` after dropping the leading run of elements matching `pred`.
- [`word_back_col`](../../src/actions.hc#L315) — Return the column one whitespace-delimited word back from `col` (readline/bash-style `unix-word-rubout`).
- [`word_forward_col`](../../src/actions.hc#L324) — Return the column one whitespace-delimited word forward from `col`.
- [`kill_word_back_text`](../../src/actions.hc#L332) — Return the whitespace-delimited word before the cursor.
- [`delete_word_back`](../../src/actions.hc#L342) — Delete the whitespace-delimited word before the cursor, moving the cursor to the start of the removed span.
- [`move_word_back`](../../src/actions.hc#L358) — Move the cursor one whitespace-delimited word back.
- [`move_word_forward`](../../src/actions.hc#L369) — Move the cursor one whitespace-delimited word forward.
- [`kill_word_forward_text`](../../src/actions.hc#L380) — Return the whitespace-delimited word after the cursor.
- [`delete_word_forward`](../../src/actions.hc#L390) — Delete the whitespace-delimited word after the cursor. The cursor column is unchanged (still valid at the truncation point).
- [`kill_whole_line_text`](../../src/actions.hc#L404) — Return the full text of the cursor's current line.
- [`kill_whole_line`](../../src/actions.hc#L411) — Clear the current line's content; the line itself stays (an empty line, not removed from the buffer). Cursor moves to column 0.
- [`new_buffer_action`](../../src/actions.hc#L429) — Push the active buffer onto the background ring and make a fresh, empty scratch buffer active.
- [`cycle_next_buffer`](../../src/actions.hc#L440) — Rotate to the next open buffer. A no-op with 0 or 1 open buffers.
- [`cycle_prev_buffer`](../../src/actions.hc#L447) — Rotate to the previous open buffer. A no-op with 0 or 1 open buffers.
- [`close_buffer_action`](../../src/actions.hc#L456) — Close the active buffer and activate the next background buffer.
- [`prompt_text`](../../src/actions.hc#L472) — Return the text typed so far in `p`.
- [`prompt_cursor`](../../src/actions.hc#L480) — Return the cursor column within `p`'s typed text.
- [`with_prompt`](../../src/actions.hc#L489) — Return a copy of `p` with updated text and cursor column, preserving its variant.
- [`prompt_insert_char`](../../src/actions.hc#L497) — Insert `c` at the prompt's cursor column, advancing the cursor by one.
- [`prompt_backspace`](../../src/actions.hc#L506) — Delete the char before the prompt's cursor. A no-op at column 0.
- [`prompt_cancel`](../../src/actions.hc#L519) — Dismiss the active prompt.
- [`prompt_move_start`](../../src/actions.hc#L523) — Move the prompt's cursor to column 0.
- [`prompt_move_end`](../../src/actions.hc#L529) — Move the prompt's cursor to the end of the typed text.
- [`prompt_move_left`](../../src/actions.hc#L536) — Move the prompt's cursor left one column.
- [`prompt_move_right`](../../src/actions.hc#L543) — Move the prompt's cursor right one column.
- [`prompt_delete_forward`](../../src/actions.hc#L552) — Delete the char under the prompt's cursor. A no-op at the end of the typed text.
- [`prompt_kill_text`](../../src/actions.hc#L565) — Return the prompt's typed text from the cursor to the end.
- [`prompt_truncate`](../../src/actions.hc#L571) — Truncate the prompt's typed text at the cursor.
- [`open_file_prompt`](../../src/actions.hc#L579) — Open the "open file" prompt with empty text.
- [`resolve_prompt_action`](../../src/actions.hc#L592) — Resolve a raw event to an Action while a Save-As/Open prompt is active, routing keystrokes to the Prompt* actions instead of the normal Insert/Enter/Backspace dispatch.
- [`resolve_help_action`](../../src/actions.hc#L614) — Resolve a raw event to an Action while the help overlay (M10) is showing: any key closes it again.
- [`resolve_normal_action`](../../src/actions.hc#L627) — Resolve a raw event to an Action during normal editing, via `state.config.bindings` for user-remappable shortcuts.
- [`resolve_action`](../../src/actions.hc#L644) — Resolve a raw event to a semantic Action, dispatching by editor mode (help overlay, active prompt, or normal editing).
- [`apply_action`](../../src/actions.hc#L661) — Apply an Action to state, producing the next EditorState.
- [`handle_action`](../../src/actions.hc#L708) — Resolve and apply an event against state in one step.
---

# Project Architecture & Export Directory: `runtime.hc`

## Module Overview
- **Source File:** `src/runtime.hc`
## Dependencies
- `keys`
- `model`
- `actions`
- `render`

## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
| `event_loop` | `fun event_loop(state: EditorState) : EditorState` | Entry point: spawns one `Buffer` instance (fresh undo/redo stacks) and hands off to the tail-recursive `event_loop_step`. |

### Public Effects

- **`Terminal`**: Screen I/O: render a frame, query dimensions/cursor style, and poll
for the next input event. Arm bodies auto-resume (hica 0.49 syntax).
  - `fun poll_event() : Event`
  - `fun render_frame(buf: ScreenBuffer) : ()`
  - `fun get_dimensions() : (int, int)`
  - `fun set_cursor_style(style: CursorStyle) : ()`
- **`Clipboard`**: Cross-platform clipboard abstraction.
  - `fun get_selection() : string`
  - `fun set_selection(text: string) : ()`
- **`Buffer`**: Per-buffer undo/redo history, spawned once per `event_loop` call.
  - `fun snapshot(b: TextBuffer) : ()`
  - `fun undo(current: TextBuffer) : maybe<TextBuffer>`
  - `fun redo(current: TextBuffer) : maybe<TextBuffer>`


---

# Domain Data Models & Type Dictionary

## Effects (Capabilities)

### Effect `Terminal` `pub`
Screen I/O: render a frame, query dimensions/cursor style, and poll
for the next input event. Arm bodies auto-resume (hica 0.49 syntax).

#### Operations
- `fun poll_event() : Event`
- `fun render_frame(buf: ScreenBuffer) : ()`
- `fun get_dimensions() : (int, int)`
- `fun set_cursor_style(style: CursorStyle) : ()`

### Effect `Clipboard` `pub`
Cross-platform clipboard abstraction.

#### Operations
- `fun get_selection() : string`
- `fun set_selection(text: string) : ()`

### Effect `Buffer` `pub`
Per-buffer undo/redo history, spawned once per `event_loop` call.

#### Operations
- `fun snapshot(b: TextBuffer) : ()`
- `fun undo(current: TextBuffer) : maybe<TextBuffer>`
- `fun redo(current: TextBuffer) : maybe<TextBuffer>`


---

# Purity and Side Effects Tracking Matrix

| Function | Signature | Purity Status | Detected Effect Dependencies |
| --- | --- | --- | --- |
| `apply_write_result` | `fun apply_write_result(state: EditorState, result: result<(), string>) : EditorState` | ✅ Pure | None |
| `save_buffer` | `fun save_buffer(state: EditorState) : EditorState` | ⚡ Impure | I/O & FileSystem |
| `submit_save_as` | `fun submit_save_as(state: EditorState, path: string) : EditorState` | ⚡ Impure | I/O & FileSystem |
| `submit_open_file` | `fun submit_open_file(state: EditorState, path: string) : EditorState` | ✅ Pure | None |
| `submit_prompt` | `fun submit_prompt(state: EditorState) : EditorState` | ✅ Pure | None |
| `apply_history` | `fun apply_history(state: EditorState, result: maybe<TextBuffer>, verb: string) : EditorState` | ✅ Pure | None |
| `event_loop_step` | `fun event_loop_step(state: EditorState, buf_ref: ref<Buffer>, last_frame: maybe<ScreenBuffer>) : EditorState` | ⚡ Impure | Divergent (recursion/loop) |
| `event_loop` | `fun event_loop(state: EditorState) : EditorState` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/runtime.hc`

## Summary
✅ **No functional debt detected** — all 8 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`apply_write_result`](../../src/runtime.hc#L57) — Apply a `write_file` result to state: clear dirty + status on success, error status on failure.
- [`save_buffer`](../../src/runtime.hc#L73) — Write buffer content to disk for the `Save` action.
- [`submit_save_as`](../../src/runtime.hc#L91) — Write the buffer to a freshly-entered path (Save-As prompt submit, M9), naming the buffer on success so subsequent Ctrl-s saves go straight to disk without re-prompting.
- [`submit_open_file`](../../src/runtime.hc#L104) — Load a path entered in the Open prompt into a new buffer, backgrounding the current one (same shape as `NewBuffer`).
- [`submit_prompt`](../../src/runtime.hc#L125) — Dispatch `PromptSubmit` (Enter while a prompt is active) to the right effectful handler.
- [`apply_history`](../../src/runtime.hc#L137) — Apply an undo/redo result to state: restore the buffer on `Some`, leave state untouched (with a status note) on `None` (empty stack).
- [`event_loop_step`](../../src/runtime.hc#L155) — One tick of the event loop: query dimensions, render (if the frame changed), poll for the next event, resolve + dispatch it, and recurse. Returns the final `EditorState` once `should_quit` flips true.
- [`event_loop`](../../src/runtime.hc#L232) — Entry point: spawns one `Buffer` instance (fresh undo/redo stacks) and hands off to the tail-recursive `event_loop_step`.
---

# Project Architecture & Export Directory: `model.hc`

## Module Overview
- **Source File:** `src/model.hc`
## Dependencies
- `keys`

## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
| `default_bindings` | `fun default_bindings() : list<(KeyChord, Action)>` | Default keybindings, every binding is overridable via HiLisp `(bind ...)`. |
| `lookup_binding` | `fun lookup_binding(kb: list<(KeyChord, Action)>, chord: KeyChord) : Action` | Resolve a `KeyChord` against a bindings map. Unbound chords resolve to `Ignore`. |
| `default_config` | `fun default_config() : Config` | The default `Config`: default bindings, no HiLisp values, not readonly. |
| `get_config` | `fun get_config(cfg: Config, key: string, default: string) : string` | Look up a `(set key value)` value from the config, or `default` if absent. |
| `get_config_int` | `fun get_config_int(cfg: Config, key: string, default: int) : int` | Numeric convenience over `get_config`: reads `key`, parses as int, falling back to `default` on a missing key or non-numeric content. |
| `set_config_value` | `fun set_config_value(cfg: Config, key: string, value: string) : Config` | Set (or override) a single `(key, value)` config entry. |
| `default_theme` | `fun default_theme() : Theme` | hedit's built-in default theme. |
| `ilseon_theme` | `fun ilseon_theme() : Theme` | A dark, low-sensory preset (`(set "theme" "ilseon")`), using the same RGB values as std/term's ilseon palette (github.com/cladam/ilseon). |
| `resolve_theme_with_status` | `fun resolve_theme_with_status(cfg: Config) : (Theme, maybe<string>)` | Resolve `Config.values` into a concrete `Theme` plus an optional status message when an unrecognised `theme` preset name falls back to `default_theme()`. |
| `resolve_theme` | `fun resolve_theme(cfg: Config) : Theme` | Resolve `Config.values` into a concrete `Theme`, discarding any unknown-preset warning. |
| `new_buffer` | `fun new_buffer(bid: int, path: maybe<string>) : TextBuffer` | A fresh buffer with one empty line and one cursor at (0, 0). |
| `clamp_position` | `fun clamp_position(lines: list<string>, pos: Position) : Position` | Clamp a `+LINE:COL`-derived `Position` into a buffer's actual bounds so an out-of-range startup position can never crash. |
| `set_initial_position` | `fun set_initial_position(buf: TextBuffer, pos: maybe<Position>) : TextBuffer` | Apply an optional `+LINE:COL` startup position to every cursor on a freshly loaded buffer. `None` leaves the buffer untouched. |
| `init_editor` | `fun init_editor(path: maybe<string>) : EditorState` | Initial editor state with a default `Config`. `path` is `None` for an unnamed scratch buffer. |
| `init_editor_with_config` | `fun init_editor_with_config(path: maybe<string>, cfg: Config) : EditorState` | Same as `init_editor` but takes a caller-supplied `Config` (typically `default_config()` merged with the user's HiLisp `init.hl`, built by `hilisp_host.hc::load_config`). |
| `init_editor_with_buffer` | `fun init_editor_with_buffer(buf: TextBuffer, cfg: Config) : EditorState` | Same as `init_editor_with_config`, but takes an already-built `TextBuffer` (typically the result of `load_buffer`) instead of constructing an empty one from a path. |
| `load_buffer` | `fun load_buffer(new_bid: int, path: maybe<string>) : (TextBuffer, maybe<string>)` | Load a buffer's content from disk. `None` (no file given) and a failed read both fall back to `new_buffer`'s empty-scratch shape; this never crashes. On failure the second element carries a status message the caller can hand to `set_status_message`. |
| `open_buffers` | `fun open_buffers(s: EditorState) : list<TextBuffer>` | All currently-open buffers, active buffer first — the order a tabline should render them in. |
| `set_status_message` | `fun set_status_message(s: EditorState, msg: string) : EditorState` | Set the status line message. |
| `clear_status_message` | `fun clear_status_message(s: EditorState) : EditorState` | Clear the status line message. |

### Public Structs

- **`Position`**: A caret position inside a `TextBuffer`.
- **`Cursor`**: One cursor. `cid` avoids clashing with the `TextBuffer.id` accessor
Koka generates.
- **`TextBuffer`**: A buffer of text lines plus its cursors and dirty flag.
- **`KeyChord`**: A key chord: a modifier + a printable char. Bare `KChar`s route
straight to `Insert`, so bindings only need to cover `KShortcut`s.
- **`Config`**: Config bundle carried through the editor.
- **`Theme`**: hedit's chrome color palette (tabline, status line, cursor line).
- **`EditorState`**: Full editor state. `buffer` is always the active buffer;
`background_buffers` holds the rest of the open buffers as a
rotation ring with no separate active index to keep in sync.
- **`ScreenBuffer`**: The pixel-free "screen buffer" the Terminal handler flushes.

### Public Enums / ADTs

- **`Action`**: A semantic editor operation that `resolve_action`/`apply_action`
dispatch on, decoupled from the raw keystroke that triggered it.
- **`CursorStyle`**: Cursor-shape hint forwarded to the Terminal handler.
- **`Prompt`**: A minimal single-line input widget (M9). `NoPrompt` is the normal-
editing state; `SaveAsPrompt`/`OpenPrompt` carry the text typed so
far. Only one prompt can be active at a time.


---

# Domain Data Models & Type Dictionary

## Structs (Data Models)

### Struct `Position` `pub`
A caret position inside a `TextBuffer`.

| Field | Type | Description |
| --- | --- | --- |
| `line` | `int` | *(Field)* |
| `col` | `int` | *(Field)* |

### Struct `Cursor` `pub`
One cursor. `cid` avoids clashing with the `TextBuffer.id` accessor
Koka generates.

| Field | Type | Description |
| --- | --- | --- |
| `cid` | `int` | *(Field)* |
| `pos` | `Position` | *(Field)* |

### Struct `TextBuffer` `pub`
A buffer of text lines plus its cursors and dirty flag.

| Field | Type | Description |
| --- | --- | --- |
| `bid` | `int` | *(Field)* |
| `path` | `maybe<string>` | *(Field)* |
| `lines` | `list<string>` | *(Field)* |
| `cursors` | `list<Cursor>` | *(Field)* |
| `is_dirty` | `bool` | *(Field)* |

### Struct `KeyChord` `pub`
A key chord: a modifier + a printable char. Bare `KChar`s route
straight to `Insert`, so bindings only need to cover `KShortcut`s.

| Field | Type | Description |
| --- | --- | --- |
| `m` | `Modifier` | *(Field)* |
| `c` | `char` | *(Field)* |

### Struct `Config` `pub`
Config bundle carried through the editor.

| Field | Type | Description |
| --- | --- | --- |
| `bindings` | `list<(KeyChord, Action)>` | *(Field)* |
| `values` | `list<(string, string)>` | *(Field)* |
| `readonly` | `bool` | *(Field)* |

### Struct `Theme` `pub`
hedit's chrome color palette (tabline, status line, cursor line).

| Field | Type | Description |
| --- | --- | --- |
| `tabline_fg` | `(int, int, int)` | *(Field)* |
| `tabline_bg` | `(int, int, int)` | *(Field)* |
| `status_fg` | `(int, int, int)` | *(Field)* |
| `status_bg` | `(int, int, int)` | *(Field)* |
| `active_tab_fg` | `(int, int, int)` | *(Field)* |
| `active_tab_bg` | `(int, int, int)` | *(Field)* |
| `cursor_line_bg` | `(int, int, int)` | *(Field)* |

### Struct `EditorState` `pub`
Full editor state. `buffer` is always the active buffer;
`background_buffers` holds the rest of the open buffers as a
rotation ring with no separate active index to keep in sync.

| Field | Type | Description |
| --- | --- | --- |
| `buffer` | `TextBuffer` | *(Field)* |
| `background_buffers` | `list<TextBuffer>` | *(Field)* |
| `next_bid` | `int` | *(Field)* |
| `status_message` | `maybe<string>` | *(Field)* |
| `screen_size` | `(int, int)` | *(Field)* |
| `should_quit` | `bool` | *(Field)* |
| `config` | `Config` | *(Field)* |
| `prompt` | `Prompt` | *(Field)* |
| `show_help` | `bool` | *(Field)* |

### Struct `ScreenBuffer` `pub`
The pixel-free "screen buffer" the Terminal handler flushes.

| Field | Type | Description |
| --- | --- | --- |
| `width` | `int` | *(Field)* |
| `height` | `int` | *(Field)* |
| `lines` | `list<string>` | *(Field)* |
| `cursor_row` | `int` | *(Field)* |
| `cursor_col` | `int` | *(Field)* |

## Algebraic Data Types (Enums)

### Type `Action` `pub`
A semantic editor operation that `resolve_action`/`apply_action`
dispatch on, decoupled from the raw keystroke that triggered it.

#### Variants
- `Quit`
- `Save`
- `Insert(c: char)`
- `NewLine`
- `DeleteBackward`
- `DeleteForward`
- `MoveUp`
- `MoveDown`
- `MoveLeft`
- `MoveRight`
- `MoveLineStart`
- `MoveLineEnd`
- `MoveWordForward`
- `MoveWordBack`
- `Resize(w: int, h: int)`
- `Copy`
- `Paste`
- `Undo`
- `Redo`
- `KillLine`
- `KillWordBack`
- `KillWordForward`
- `KillWholeLine`
- `NewBuffer`
- `NextBuffer`
- `PrevBuffer`
- `CloseBuffer`
- `OpenFile`
- `PromptChar(c: char)`
- `PromptBackspace`
- `PromptSubmit`
- `PromptCancel`
- `PromptMoveStart`
- `PromptMoveEnd`
- `PromptMoveLeft`
- `PromptMoveRight`
- `PromptDeleteForward`
- `PromptKillLine`
- `ToggleHelp`
- `Ignore`

### Type `CursorStyle` `pub`
Cursor-shape hint forwarded to the Terminal handler.

#### Variants
- `Block`
- `Bar`
- `Underscore`

### Type `Prompt` `pub`
A minimal single-line input widget (M9). `NoPrompt` is the normal-
editing state; `SaveAsPrompt`/`OpenPrompt` carry the text typed so
far. Only one prompt can be active at a time.

#### Variants
- `NoPrompt`
- `SaveAsPrompt(text: string, cursor: int)`
- `OpenPrompt(text: string, cursor: int)`


---

# Purity and Side Effects Tracking Matrix

| Function | Signature | Purity Status | Detected Effect Dependencies |
| --- | --- | --- | --- |
| `default_bindings` | `fun default_bindings() : list<(KeyChord, Action)>` | ✅ Pure | None |
| `lookup_binding` | `fun lookup_binding(kb: list<(KeyChord, Action)>, chord: KeyChord) : Action` | ✅ Pure | None |
| `default_config` | `fun default_config() : Config` | ✅ Pure | None |
| `get_config` | `fun get_config(cfg: Config, key: string, default: string) : string` | ✅ Pure | None |
| `parse_or` | `fun parse_or(v: string, fallback: int) : int` | ✅ Pure | None |
| `get_config_int` | `fun get_config_int(cfg: Config, key: string, default: int) : int` | ✅ Pure | None |
| `set_config_value` | `fun set_config_value(cfg: Config, key: string, value: string) : Config` | ✅ Pure | None |
| `default_theme` | `fun default_theme() : Theme` | ✅ Pure | None |
| `ilseon_theme` | `fun ilseon_theme() : Theme` | ✅ Pure | None |
| `theme_preset` | `fun theme_preset(name: string) : maybe<Theme>` | ✅ Pure | None |
| `parse_rgb` | `fun parse_rgb(s: string, fallback: (int, int, int)) : (int, int, int)` | ✅ Pure | None |
| `get_rgb_override` | `fun get_rgb_override(cfg: Config, key: string, fallback: (int, int, int)) : (int, int, int)` | ✅ Pure | None |
| `apply_theme_overrides` | `fun apply_theme_overrides(cfg: Config, base: Theme) : Theme` | ✅ Pure | None |
| `resolve_theme_with_status` | `fun resolve_theme_with_status(cfg: Config) : (Theme, maybe<string>)` | ✅ Pure | None |
| `resolve_theme` | `fun resolve_theme(cfg: Config) : Theme` | ✅ Pure | None |
| `new_buffer` | `fun new_buffer(bid: int, path: maybe<string>) : TextBuffer` | ✅ Pure | None |
| `nth_line` | `fun nth_line(lines: list<string>, idx: int) : string` | ⚡ Impure | Divergent (recursion/loop) |
| `clamp_position` | `fun clamp_position(lines: list<string>, pos: Position) : Position` | ✅ Pure | None |
| `set_initial_position` | `fun set_initial_position(buf: TextBuffer, pos: maybe<Position>) : TextBuffer` | ✅ Pure | None |
| `init_editor` | `fun init_editor(path: maybe<string>) : EditorState` | ✅ Pure | None |
| `init_editor_with_config` | `fun init_editor_with_config(path: maybe<string>, cfg: Config) : EditorState` | ✅ Pure | None |
| `init_editor_with_buffer` | `fun init_editor_with_buffer(buf: TextBuffer, cfg: Config) : EditorState` | ✅ Pure | None |
| `split_lines` | `fun split_lines(content: string) : list<string>` | ✅ Pure | None |
| `load_existing_buffer` | `fun load_existing_buffer(new_bid: int, p: string) : (TextBuffer, maybe<string>)` | ⚡ Impure | I/O & FileSystem |
| `load_buffer` | `fun load_buffer(new_bid: int, path: maybe<string>) : (TextBuffer, maybe<string>)` | ✅ Pure | None |
| `open_buffers` | `fun open_buffers(s: EditorState) : list<TextBuffer>` | ✅ Pure | None |
| `set_status_message` | `fun set_status_message(s: EditorState, msg: string) : EditorState` | ✅ Pure | None |
| `clear_status_message` | `fun clear_status_message(s: EditorState) : EditorState` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/model.hc`

## Summary
✅ **No functional debt detected** — all 28 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`default_bindings`](../../src/model.hc#L102) — Default keybindings, every binding is overridable via HiLisp `(bind ...)`.
- [`lookup_binding`](../../src/model.hc#L133) — Resolve a `KeyChord` against a bindings map. Unbound chords resolve to `Ignore`.
- [`default_config`](../../src/model.hc#L153) — The default `Config`: default bindings, no HiLisp values, not readonly.
- [`get_config`](../../src/model.hc#L158) — Look up a `(set key value)` value from the config, or `default` if absent.
- [`parse_or`](../../src/model.hc#L168) — Parse `v` as an int, falling back to `fallback` if it isn't numeric.
- [`get_config_int`](../../src/model.hc#L176) — Numeric convenience over `get_config`: reads `key`, parses as int, falling back to `default` on a missing key or non-numeric content.
- [`set_config_value`](../../src/model.hc#L186) — Set (or override) a single `(key, value)` config entry.
- [`default_theme`](../../src/model.hc#L211) — hedit's built-in default theme.
- [`ilseon_theme`](../../src/model.hc#L225) — A dark, low-sensory preset (`(set "theme" "ilseon")`), using the same RGB values as std/term's ilseon palette (github.com/cladam/ilseon).
- [`theme_preset`](../../src/model.hc#L237) — Look up a built-in theme preset by name.
- [`parse_rgb`](../../src/model.hc#L246) — Parse a "R,G,B" override string into a color triple, falling back to `fallback` on any malformed or missing component.
- [`get_rgb_override`](../../src/model.hc#L254) — Look up a single `theme.<slot>` RGB override from config.
- [`apply_theme_overrides`](../../src/model.hc#L263) — Apply every `theme.<slot>` override on top of a resolved preset.
- [`resolve_theme_with_status`](../../src/model.hc#L276) — Resolve `Config.values` into a concrete `Theme` plus an optional status message when an unrecognised `theme` preset name falls back to `default_theme()`.
- [`resolve_theme`](../../src/model.hc#L287) — Resolve `Config.values` into a concrete `Theme`, discarding any unknown-preset warning.
- [`new_buffer`](../../src/model.hc#L342) — A fresh buffer with one empty line and one cursor at (0, 0).
- [`nth_line`](../../src/model.hc#L354) — `line`-th element of `lines`, or "" past the end.
- [`clamp_position`](../../src/model.hc#L362) — Clamp a `+LINE:COL`-derived `Position` into a buffer's actual bounds so an out-of-range startup position can never crash.
- [`set_initial_position`](../../src/model.hc#L371) — Apply an optional `+LINE:COL` startup position to every cursor on a freshly loaded buffer. `None` leaves the buffer untouched.
- [`init_editor`](../../src/model.hc#L383) — Initial editor state with a default `Config`. `path` is `None` for an unnamed scratch buffer.
- [`init_editor_with_config`](../../src/model.hc#L392) — Same as `init_editor` but takes a caller-supplied `Config` (typically `default_config()` merged with the user's HiLisp `init.hl`, built by `hilisp_host.hc::load_config`).
- [`init_editor_with_buffer`](../../src/model.hc#L398) — Same as `init_editor_with_config`, but takes an already-built `TextBuffer` (typically the result of `load_buffer`) instead of constructing an empty one from a path.
- [`split_lines`](../../src/model.hc#L413) — Split file content into lines, dropping one trailing newline artifact so this round-trips exactly with `runtime.hc::save_buffer`.
- [`load_existing_buffer`](../../src/model.hc#L423) — Read `p` from disk into a fresh buffer, or fall back to an empty one with an error status.
- [`load_buffer`](../../src/model.hc#L441) — Load a buffer's content from disk. `None` (no file given) and a failed read both fall back to `new_buffer`'s empty-scratch shape; this never crashes. On failure the second element carries a status message the caller can hand to `set_status_message`.
- [`open_buffers`](../../src/model.hc#L449) — All currently-open buffers, active buffer first — the order a tabline should render them in.
- [`set_status_message`](../../src/model.hc#L455) — Set the status line message.
- [`clear_status_message`](../../src/model.hc#L459) — Clear the status line message.
---

# Project Architecture & Export Directory: `hilisp_host.hc`

## Module Overview
- **Source File:** `src/hilisp_host.hc`
## Dependencies
- `keys`
- `model`
- `../lib/hilisp/src/lisp`

## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
| `eval_all` | `fun eval_all(tokens: list<Token>, env: Env, last: LVal) : (LVal, Env)` | Evaluate every top-level form in `tokens` against `env`, threading env through, and return the final value + updated env. |
| `eval_source` | `fun eval_source(src: string) : string` | Evaluate `src` in a fresh env and return the final value's display string. |
| `eval_source_val` | `fun eval_source_val(src: string) : LVal` | Evaluate `src` in a fresh env and return the final `LVal`. |
| `parse_chord` | `fun parse_chord(s: string) : maybe<KeyChord>` | Parse `"Ctrl-s"`-style chord strings (docs/hedit-design.md §7.5) into a `KeyChord`. |
| `chord_to_str` | `fun chord_to_str(chord: KeyChord) : string` | Inverse of `parse_chord`. |
| `action_to_string` | `fun action_to_string(a: Action) : string` | Render an `Action` as its `(bind ...)`-facing symbol name. |
| `config_from_env` | `fun config_from_env(env: Env, fallback: Config) : Config` | Extract the env's hash entries back into a hedit-side `Config`. |
| `env_with_config` | `fun env_with_config(env: Env, cfg: Config) : Env` | Seed `env` with `cfg`'s bindings + values under the well-known keys. |
| `hedit_host_dispatch` | `fun hedit_host_dispatch(name: string, args: list<LVal>, env: Env) : (LVal, Env)` | Dispatch a `host/...` op name to its hedit-side handler. |
| `make_hedit_env` | `fun make_hedit_env(cfg0: Config) : Env` | Build a HiLisp env seeded with core HiLisp builtins, the hedit host-dispatch callback, the initial `Config` snapshot, and the `set`/`get`/`bind` aliases. |
| `load_config` | `fun load_config(src: string, cfg0: Config) : (Config, maybe<string>)` | Evaluate a HiLisp source string as a hedit config file, returning the merged `Config` plus a status message (`None` on clean load, `Some(msg)` on an `LError`). |


---

# Domain Data Models & Type Dictionary

*(No structs, enums or effects defined in this module)*

---

# Purity and Side Effects Tracking Matrix

| Function | Signature | Purity Status | Detected Effect Dependencies |
| --- | --- | --- | --- |
| `eval_all` | `fun eval_all(tokens: list<Token>, env: Env, last: LVal) : (LVal, Env)` | ⚡ Impure | Divergent (recursion/loop) |
| `eval_source` | `fun eval_source(src: string) : string` | ✅ Pure | None |
| `eval_source_val` | `fun eval_source_val(src: string) : LVal` | ✅ Pure | None |
| `mod_to_string` | `fun mod_to_string(m: Modifier) : string` | ✅ Pure | None |
| `parse_mod` | `fun parse_mod(s: string) : maybe<Modifier>` | ✅ Pure | None |
| `single_char_of` | `fun single_char_of(s: string) : maybe<char>` | ✅ Pure | None |
| `parse_chord` | `fun parse_chord(s: string) : maybe<KeyChord>` | ✅ Pure | None |
| `chord_to_str` | `fun chord_to_str(chord: KeyChord) : string` | ✅ Pure | None |
| `action_to_string` | `fun action_to_string(a: Action) : string` | ✅ Pure | None |
| `string_to_action` | `fun string_to_action(s: string) : maybe<Action>` | ✅ Pure | None |
| `bindings_key` | `fun bindings_key() : string` | ✅ Pure | None |
| `values_key` | `fun values_key() : string` | ✅ Pure | None |
| `bindings_to_hash` | `fun bindings_to_hash(kb: list<(KeyChord, Action)>) : LVal` | ✅ Pure | None |
| `binding_to_entry` | `fun binding_to_entry(pair: (KeyChord, Action)) : (string, LVal)` | ✅ Pure | None |
| `values_to_hash` | `fun values_to_hash(kv: list<(string, string)>) : LVal` | ✅ Pure | None |
| `value_to_entry` | `fun value_to_entry(pair: (string, string)) : (string, LVal)` | ✅ Pure | None |
| `config_from_env` | `fun config_from_env(env: Env, fallback: Config) : Config` | ✅ Pure | None |
| `entries_to_bindings` | `fun entries_to_bindings(entries: list<(string, LVal)>) : list<(KeyChord, Action)>` | ⚡ Impure | Divergent (recursion/loop) |
| `entries_to_values` | `fun entries_to_values(entries: list<(string, LVal)>) : list<(string, string)>` | ⚡ Impure | Divergent (recursion/loop) |
| `env_with_config` | `fun env_with_config(env: Env, cfg: Config) : Env` | ✅ Pure | None |
| `value_to_string` | `fun value_to_string(v: LVal) : string` | ✅ Pure | None |
| `hedit_host_dispatch` | `fun hedit_host_dispatch(name: string, args: list<LVal>, env: Env) : (LVal, Env)` | ✅ Pure | None |
| `host_set` | `fun host_set(args: list<LVal>, env: Env) : (LVal, Env)` | ✅ Pure | None |
| `host_get` | `fun host_get(args: list<LVal>, env: Env) : (LVal, Env)` | ✅ Pure | None |
| `bind_ok` | `fun bind_ok(env: Env, chord_str: string, action_name: string) : (LVal, Env)` | ✅ Pure | None |
| `host_bind` | `fun host_bind(args: list<LVal>, env: Env) : (LVal, Env)` | ✅ Pure | None |
| `preamble` | `fun preamble() : string` | ✅ Pure | None |
| `make_hedit_env` | `fun make_hedit_env(cfg0: Config) : Env` | ✅ Pure | None |
| `load_config` | `fun load_config(src: string, cfg0: Config) : (Config, maybe<string>)` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/hilisp_host.hc`

## Summary
✅ **No functional debt detected** — all 29 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`eval_all`](../../src/hilisp_host.hc#L28) — Evaluate every top-level form in `tokens` against `env`, threading env through, and return the final value + updated env.
- [`eval_source`](../../src/hilisp_host.hc#L46) — Evaluate `src` in a fresh env and return the final value's display string.
- [`eval_source_val`](../../src/hilisp_host.hc#L54) — Evaluate `src` in a fresh env and return the final `LVal`.
- [`mod_to_string`](../../src/hilisp_host.hc#L64) — Render a `Modifier` as its `(bind ...)` chord-string name.
- [`parse_mod`](../../src/hilisp_host.hc#L73) — Parse a `(bind ...)` chord-string modifier name back into a `Modifier`.
- [`single_char_of`](../../src/hilisp_host.hc#L83) — Pull the single char out of a 1-char string, or `None` otherwise.
- [`parse_chord`](../../src/hilisp_host.hc#L93) — Parse `"Ctrl-s"`-style chord strings (docs/hedit-design.md §7.5) into a `KeyChord`.
- [`chord_to_str`](../../src/hilisp_host.hc#L110) — Inverse of `parse_chord`.
- [`action_to_string`](../../src/hilisp_host.hc#L117) — Render an `Action` as its `(bind ...)`-facing symbol name.
- [`string_to_action`](../../src/hilisp_host.hc#L162) — Inverse of `action_to_string`; unrecognised names resolve to `None`.
- [`bindings_key`](../../src/hilisp_host.hc#L200) — The env key under which the bindings alist is stored.
- [`values_key`](../../src/hilisp_host.hc#L203) — The env key under which the `(set ...)` values alist is stored.
- [`bindings_to_hash`](../../src/hilisp_host.hc#L207) — Serialise a `Config.bindings` alist into an `LHash` keyed by `"Modifier-c"` chord strings, values = LStr(action-name).
- [`binding_to_entry`](../../src/hilisp_host.hc#L211) — Serialise a single `(KeyChord, Action)` pair into a hash entry.
- [`values_to_hash`](../../src/hilisp_host.hc#L219) — Serialise the `(set k v)` values alist into an `LHash`.
- [`value_to_entry`](../../src/hilisp_host.hc#L223) — Serialise a single `(key, value)` pair into a hash entry.
- [`config_from_env`](../../src/hilisp_host.hc#L232) — Extract the env's hash entries back into a hedit-side `Config`.
- [`entries_to_bindings`](../../src/hilisp_host.hc#L246) — Decode a hash's entries into a hedit-side bindings alist, dropping any entry that doesn't parse as a chord + known action.
- [`entries_to_values`](../../src/hilisp_host.hc#L258) — Decode a hash's entries into a hedit-side `(key, value)` alist.
- [`env_with_config`](../../src/hilisp_host.hc#L268) — Seed `env` with `cfg`'s bindings + values under the well-known keys.
- [`value_to_string`](../../src/hilisp_host.hc#L288) — Stringify an `LVal` for storage in `Config.values`.
- [`hedit_host_dispatch`](../../src/hilisp_host.hc#L311) — Dispatch a `host/...` op name to its hedit-side handler.
- [`host_set`](../../src/hilisp_host.hc#L320) — `(set key value)` — record a string-typed value.
- [`host_get`](../../src/hilisp_host.hc#L335) — `(get key)` — look up a value; returns nil when missing so `(if (get "foo") ...)` reads naturally.
- [`bind_ok`](../../src/hilisp_host.hc#L354) — Record a binding once chord & action have both parsed, using the same canonical chord string the user typed.
- [`host_bind`](../../src/hilisp_host.hc#L366) — `(bind "Ctrl-x" 'save)` — replace (or add) a binding.
- [`preamble`](../../src/hilisp_host.hc#L385) — The HiLisp preamble that aliases `host/set`/`host/get`/`host/bind` to the idiomatic `set`/`get`/`bind` names.
- [`make_hedit_env`](../../src/hilisp_host.hc#L393) — Build a HiLisp env seeded with core HiLisp builtins, the hedit host-dispatch callback, the initial `Config` snapshot, and the `set`/`get`/`bind` aliases.
- [`load_config`](../../src/hilisp_host.hc#L410) — Evaluate a HiLisp source string as a hedit config file, returning the merged `Config` plus a status message (`None` on clean load, `Some(msg)` on an `LError`).
---

# Project Architecture & Export Directory: `cli_spec.hc`

## Module Overview
- **Source File:** `src/cli_spec.hc`
## Dependencies
- `std/cli`
- `model`

## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
| `make_spec` | `fun make_spec() : CliSpec` | Build hedit's `std/cli` spec. |
| `parse_position_arg` | `fun parse_position_arg(a: string) : maybe<Position>` | Parse a `+LINE[:COL]` token into a 0-indexed `Position`. Malformed tokens (non-numeric, too many `:` parts) resolve to `None` rather than erroring. |
| `extract_position_arg` | `fun extract_position_arg(args: list<string>) : (maybe<string>, list<string>)` | Pull the first `+`-prefixed token out of argv, leaving everything else untouched for `cli_parse_args`. |


---

# Domain Data Models & Type Dictionary

*(No structs, enums or effects defined in this module)*

---

# Purity and Side Effects Tracking Matrix

| Function | Signature | Purity Status | Detected Effect Dependencies |
| --- | --- | --- | --- |
| `make_spec` | `fun make_spec() : CliSpec` | ✅ Pure | None |
| `with_parsed_line` | `fun with_parsed_line(n: int, col_str: string) : maybe<Position>` | ✅ Pure | None |
| `parse_line_col` | `fun parse_line_col(line_str: string, col_str: string) : maybe<Position>` | ✅ Pure | None |
| `parse_position_arg` | `fun parse_position_arg(a: string) : maybe<Position>` | ✅ Pure | None |
| `extract_position_arg` | `fun extract_position_arg(args: list<string>) : (maybe<string>, list<string>)` | ⚡ Impure | Divergent (recursion/loop) |

---

# Hica Analysis Hotspot: `src/cli_spec.hc`

## Summary
✅ **No functional debt detected** — all 5 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`make_spec`](../../src/cli_spec.hc#L10) — Build hedit's `std/cli` spec.
- [`with_parsed_line`](../../src/cli_spec.hc#L22) — Parse the `:COL` part of a `+LINE:COL` token, given the already-parsed 1-indexed line number `n`.
- [`parse_line_col`](../../src/cli_spec.hc#L29) — Parse a `+LINE:COL` token's two numeric parts into a `Position`.
- [`parse_position_arg`](../../src/cli_spec.hc#L38) — Parse a `+LINE[:COL]` token into a 0-indexed `Position`. Malformed tokens (non-numeric, too many `:` parts) resolve to `None` rather than erroring.
- [`extract_position_arg`](../../src/cli_spec.hc#L58) — Pull the first `+`-prefixed token out of argv, leaving everything else untouched for `cli_parse_args`.
---

# Project Architecture & Export Directory: `main.hc`

## Module Overview
- **Source File:** `src/main.hc`
## Dependencies
- `keys`
- `model`
- `runtime`
- `hilisp_host`
- `config_loader`
- `cli_spec`
- `std/cli`
- `std/term`
- `term_ffi` (extern)

## Public API Catalog

### Public Effects

- **`Terminal`**: Screen I/O: render a frame, query dimensions/cursor style, and poll
for the next input event. Arm bodies auto-resume (hica 0.49 syntax).
  - `fun poll_event() : Event`
  - `fun render_frame(buf: ScreenBuffer) : ()`
  - `fun get_dimensions() : (int, int)`
  - `fun set_cursor_style(style: CursorStyle) : ()`
- **`Clipboard`**: Cross-platform clipboard abstraction.
  - `fun get_selection() : string`
  - `fun set_selection(text: string) : ()`
- **`Buffer`**: Per-buffer undo/redo history, spawned once per `event_loop` call.
  - `fun snapshot(b: TextBuffer) : ()`
  - `fun undo(current: TextBuffer) : maybe<TextBuffer>`
  - `fun redo(current: TextBuffer) : maybe<TextBuffer>`


---

# Domain Data Models & Type Dictionary

## Effects (Capabilities)

### Effect `Terminal` `pub`
Screen I/O: render a frame, query dimensions/cursor style, and poll
for the next input event. Arm bodies auto-resume (hica 0.49 syntax).

#### Operations
- `fun poll_event() : Event`
- `fun render_frame(buf: ScreenBuffer) : ()`
- `fun get_dimensions() : (int, int)`
- `fun set_cursor_style(style: CursorStyle) : ()`

### Effect `Clipboard` `pub`
Cross-platform clipboard abstraction.

#### Operations
- `fun get_selection() : string`
- `fun set_selection(text: string) : ()`

### Effect `Buffer` `pub`
Per-buffer undo/redo history, spawned once per `event_loop` call.

#### Operations
- `fun snapshot(b: TextBuffer) : ()`
- `fun undo(current: TextBuffer) : maybe<TextBuffer>`
- `fun redo(current: TextBuffer) : maybe<TextBuffer>`


---

# Purity and Side Effects Tracking Matrix

| Function | Signature | Purity Status | Detected Effect Dependencies |
| --- | --- | --- | --- |
| `combine_with` | `fun combine_with(x: string, b: maybe<string>) : maybe<string>` | ✅ Pure | None |
| `combine_status` | `fun combine_status(a: maybe<string>, b: maybe<string>) : maybe<string>` | ✅ Pure | None |
| `enable_raw_mode` | `fun enable_raw_mode() : ()` | ✅ Pure | None |
| `disable_raw_mode` | `fun disable_raw_mode() : ()` | ✅ Pure | None |
| `rgb_fg_code` | `fun rgb_fg_code(c: (int, int, int)) : string` | ✅ Pure | None |
| `rgb_bg_code` | `fun rgb_bg_code(c: (int, int, int)) : string` | ✅ Pure | None |
| `wrap_fg_bg` | `fun wrap_fg_bg(fg: (int, int, int), bg: (int, int, int), s: string) : string` | ✅ Pure | None |
| `wrap_bg` | `fun wrap_bg(bg: (int, int, int), s: string) : string` | ✅ Pure | None |
| `colorize_tabline_row` | `fun colorize_tabline_row(theme: Theme, row: string) : string` | ✅ Pure | None |
| `colorize_status_row` | `fun colorize_status_row(theme: Theme, row: string) : string` | ✅ Pure | None |
| `colorize_cursor_row` | `fun colorize_cursor_row(theme: Theme, row: string) : string` | ✅ Pure | None |
| `style_frame_lines` | `fun style_frame_lines(theme: Theme, lines: list<string>, cursor_row: int) : list<string>` | ✅ Pure | None |
| `style_frame_lines_go` | `fun style_frame_lines_go(theme: Theme, lines: list<string>, idx: int, total: int, cursor_row: int) : list<string>` | ⚡ Impure | Divergent (recursion/loop) |
| `render_native` | `fun render_native(theme: Theme, buf: ScreenBuffer) : ()` | ⚡ Impure | I/O & FileSystem |
| `apply_tabsize_override` | `fun apply_tabsize_override(cfg: Config, tabsize: maybe<string>) : Config` | ✅ Pure | None |
| `apply_readonly_override` | `fun apply_readonly_override(cfg: Config, ro: bool) : Config` | ✅ Pure | None |
| `run_editor` | `fun run_editor(r: CliResult, pos_arg: maybe<string>) : ()` | ✅ Pure | None |
| `main` | `fun main() : ()` | ⚡ Impure | I/O & FileSystem, Console |

---

# Hica Analysis Hotspot: `src/main.hc`

## Summary
✅ **No functional debt detected** — all 18 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`combine_with`](../../src/main.hc#L19) — Combine a status message `x` (config/file load result) with an optional second one `b` (e.g. the theme resolver's warning).
- [`combine_status`](../../src/main.hc#L31) — Combine two optional status messages (either, both, or neither may be present) into the single message primed onto `EditorState.status_message` for the first render tick.
- [`enable_raw_mode`](../../src/main.hc#L42) — Put the terminal into raw mode via `stty` (through hica's built-in `exec`) rather than a hand-written termios FFI.
- [`disable_raw_mode`](../../src/main.hc#L47) — Restore normal terminal mode (`stty sane`).
- [`rgb_fg_code`](../../src/main.hc#L60) — The ANSI SGR foreground true-color code for `c`.
- [`rgb_bg_code`](../../src/main.hc#L64) — The ANSI SGR background true-color code for `c`.
- [`wrap_fg_bg`](../../src/main.hc#L68) — Wrap `s` in an ANSI SGR foreground+background pair, reset afterward.
- [`wrap_bg`](../../src/main.hc#L72) — Wrap `s` in an ANSI SGR background-only code, reset afterward.
- [`colorize_tabline_row`](../../src/main.hc#L78) — Colorize a rendered tabline row: the active tab (leading "[name]" segment) gets `active_tab_fg`/`active_tab_bg`, the rest of the row gets the plain `tabline_fg`/`tabline_bg` pair.
- [`colorize_status_row`](../../src/main.hc#L90) — Colorize a rendered status-line row.
- [`colorize_cursor_row`](../../src/main.hc#L94) — Colorize a rendered content row that the cursor currently sits on.
- [`style_frame_lines`](../../src/main.hc#L101) — Style the tabline (first row), status line (last row), and the row the cursor currently sits on (everything else, plain).
- [`style_frame_lines_go`](../../src/main.hc#L107) — Recursive worker for `style_frame_lines`, tracking the current row index.
- [`render_native`](../../src/main.hc#L134) — Full-redraw a `ScreenBuffer` to the real terminal via ANSI escapes, including moving the terminal's real cursor to `buf.cursor_row`/`buf.cursor_col`.
- [`apply_tabsize_override`](../../src/main.hc#L145) — `--tabsize <n>`: applied to Config.values after init.hl has loaded, so it always wins over a config-file setting.
- [`apply_readonly_override`](../../src/main.hc#L153) — `--readonly`: can only turn the flag on (there's no "un-readonly" CLI flag — omit it and the default `false` stands).
- [`run_editor`](../../src/main.hc#L159) — Build the initial `EditorState` from parsed CLI args (config, theme, target file, `+LINE:COL` start position), then install the native Terminal/Clipboard handlers and run `event_loop`.
- [`main`](../../src/main.hc#L195) — hedit's entry point: parse argv, then dispatch to `--help`/`--version` or `run_editor`.
