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
| `render_help_buffer` | `fun render_help_buffer(state: EditorState) : ScreenBuffer` | *(No documentation provided)* |
| `render_editor_to_buffer` | `fun render_editor_to_buffer(state: EditorState) : ScreenBuffer` | *(No documentation provided)* |


---

# Domain Data Models & Type Dictionary

*(No structs or enums defined in this module)*

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
- **Location:** `src/render.hc:97`
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

- [`fit_to_width`](../../src/render.hc#L13)
- [`take_or_pad`](../../src/render.hc#L17)
- [`drop_n`](../../src/render.hc#L29)
- [`scroll_offset`](../../src/render.hc#L43)
- [`buffer_tab_name`](../../src/render.hc#L48)
- [`build_tabline`](../../src/render.hc#L54)
- [`prompt_label`](../../src/render.hc#L62)
- [`prompt_prefix_len`](../../src/render.hc#L72)
- [`prompt_cursor_col`](../../src/render.hc#L80)
- [`render_normal_buffer`](../../src/render.hc#L97)
- [`format_binding`](../../src/render.hc#L148)
- [`render_help_buffer`](../../src/render.hc#L151)
- [`render_editor_to_buffer`](../../src/render.hc#L169)
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
| `candidate_paths` | `fun candidate_paths(xdg: maybe<string>, home: maybe<string>) : list<string>` | *(No documentation provided)* |
| `read_first` | `fun read_first(paths: list<string>) : (string, maybe<string>)` | *(No documentation provided)* |
| `load_user_config` | `fun load_user_config(cfg0: Config) : (Config, maybe<string>)` | *(No documentation provided)* |
| `load_config_from_path` | `fun load_config_from_path(cfg0: Config, p: string) : (Config, maybe<string>)` | *(No documentation provided)* |
| `load_user_config_opts` | `fun load_user_config_opts(cfg0: Config, explicit_path: maybe<string>, skip: bool) : (Config, maybe<string>)` | *(No documentation provided)* |


---

# Domain Data Models & Type Dictionary

*(No structs or enums defined in this module)*

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

- [`opt_path`](../../src/config_loader.hc#L31)
- [`xdg_candidate`](../../src/config_loader.hc#L37)
- [`home_candidate`](../../src/config_loader.hc#L44)
- [`candidate_paths`](../../src/config_loader.hc#L53)
- [`read_first`](../../src/config_loader.hc#L60)
- [`apply_config_src`](../../src/config_loader.hc#L87)
- [`load_user_config`](../../src/config_loader.hc#L95)
- [`load_config_from_path`](../../src/config_loader.hc#L110)
- [`load_user_config_opts`](../../src/config_loader.hc#L120)
---

# Project Architecture & Export Directory: `keys.hc`

## Module Overview
- **Source File:** `src/keys.hc`
## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
| `decode_key` | `fun decode_key(code: int) : Event` | *(No documentation provided)* |

### Public Enums / ADTs

- **`Modifier`**: *(No documentation provided)*
- **`SpecialKey`**: *(No documentation provided)*
- **`Key`**: *(No documentation provided)*
- **`MouseAction`**: *(No documentation provided)*
- **`Event`**: *(No documentation provided)*


---

# Domain Data Models & Type Dictionary

## Algebraic Data Types (Enums)

### Type `Modifier` `pub`
#### Variants
- `Ctrl`
- `Alt`
- `Meta`
- `Shift`

### Type `SpecialKey` `pub`
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
#### Variants
- `KChar(c: char)`
- `KSpecial(k: SpecialKey)`
- `KShortcut(m: Modifier, c: char)`

### Type `MouseAction` `pub`
#### Variants
- `Press`
- `Release`
- `Drag`
- `ScrollUp`
- `ScrollDown`

### Type `Event` `pub`
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

- [`decode_key`](../../src/keys.hc#L62)
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
| `insert_char` | `fun insert_char(state: EditorState, c: char) : EditorState` | *(No documentation provided)* |
| `insert_newline` | `fun insert_newline(state: EditorState) : EditorState` | *(No documentation provided)* |
| `move_line_start` | `fun move_line_start(state: EditorState) : EditorState` | *(No documentation provided)* |
| `move_line_end` | `fun move_line_end(state: EditorState) : EditorState` | *(No documentation provided)* |
| `delete_backward` | `fun delete_backward(state: EditorState) : EditorState` | *(No documentation provided)* |
| `delete_forward` | `fun delete_forward(state: EditorState) : EditorState` | *(No documentation provided)* |
| `move_left` | `fun move_left(state: EditorState) : EditorState` | *(No documentation provided)* |
| `move_right` | `fun move_right(state: EditorState) : EditorState` | *(No documentation provided)* |
| `move_up` | `fun move_up(state: EditorState) : EditorState` | *(No documentation provided)* |
| `move_down` | `fun move_down(state: EditorState) : EditorState` | *(No documentation provided)* |
| `current_line` | `fun current_line(state: EditorState) : string` | *(No documentation provided)* |
| `paste_text` | `fun paste_text(state: EditorState, text: string) : EditorState` | *(No documentation provided)* |
| `kill_line_text` | `fun kill_line_text(state: EditorState) : string` | *(No documentation provided)* |
| `kill_line` | `fun kill_line(state: EditorState) : EditorState` | *(No documentation provided)* |
| `kill_word_back_text` | `fun kill_word_back_text(state: EditorState) : string` | *(No documentation provided)* |
| `delete_word_back` | `fun delete_word_back(state: EditorState) : EditorState` | *(No documentation provided)* |
| `move_word_back` | `fun move_word_back(state: EditorState) : EditorState` | *(No documentation provided)* |
| `move_word_forward` | `fun move_word_forward(state: EditorState) : EditorState` | *(No documentation provided)* |
| `kill_word_forward_text` | `fun kill_word_forward_text(state: EditorState) : string` | *(No documentation provided)* |
| `delete_word_forward` | `fun delete_word_forward(state: EditorState) : EditorState` | *(No documentation provided)* |
| `kill_whole_line_text` | `fun kill_whole_line_text(state: EditorState) : string` | *(No documentation provided)* |
| `kill_whole_line` | `fun kill_whole_line(state: EditorState) : EditorState` | *(No documentation provided)* |
| `new_buffer_action` | `fun new_buffer_action(state: EditorState) : EditorState` | *(No documentation provided)* |
| `cycle_next_buffer` | `fun cycle_next_buffer(state: EditorState) : EditorState` | *(No documentation provided)* |
| `cycle_prev_buffer` | `fun cycle_prev_buffer(state: EditorState) : EditorState` | *(No documentation provided)* |
| `close_buffer_action` | `fun close_buffer_action(state: EditorState) : EditorState` | *(No documentation provided)* |
| `prompt_insert_char` | `fun prompt_insert_char(state: EditorState, c: char) : EditorState` | *(No documentation provided)* |
| `prompt_backspace` | `fun prompt_backspace(state: EditorState) : EditorState` | *(No documentation provided)* |
| `prompt_cancel` | `fun prompt_cancel(state: EditorState) : EditorState` | *(No documentation provided)* |
| `prompt_move_start` | `fun prompt_move_start(state: EditorState) : EditorState` | *(No documentation provided)* |
| `prompt_move_end` | `fun prompt_move_end(state: EditorState) : EditorState` | *(No documentation provided)* |
| `prompt_move_left` | `fun prompt_move_left(state: EditorState) : EditorState` | *(No documentation provided)* |
| `prompt_move_right` | `fun prompt_move_right(state: EditorState) : EditorState` | *(No documentation provided)* |
| `prompt_delete_forward` | `fun prompt_delete_forward(state: EditorState) : EditorState` | *(No documentation provided)* |
| `prompt_kill_text` | `fun prompt_kill_text(state: EditorState) : string` | *(No documentation provided)* |
| `prompt_truncate` | `fun prompt_truncate(state: EditorState) : EditorState` | *(No documentation provided)* |
| `open_file_prompt` | `fun open_file_prompt(state: EditorState) : EditorState` | *(No documentation provided)* |
| `resolve_action` | `fun resolve_action(state: EditorState, evt: Event) : Action` | *(No documentation provided)* |
| `apply_action` | `fun apply_action(state: EditorState, action: Action) : EditorState` | *(No documentation provided)* |
| `handle_action` | `fun handle_action(state: EditorState, evt: Event) : EditorState` | *(No documentation provided)* |


---

# Domain Data Models & Type Dictionary

*(No structs or enums defined in this module)*

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

- [`list_set`](../../src/actions.hc#L22)
- [`list_get`](../../src/actions.hc#L31)
- [`list_split_at`](../../src/actions.hc#L41)
- [`list_remove_at`](../../src/actions.hc#L51)
- [`head_cursor`](../../src/actions.hc#L63)
- [`clamp_col`](../../src/actions.hc#L70)
- [`insert_char`](../../src/actions.hc#L78)
- [`insert_newline`](../../src/actions.hc#L101)
- [`move_line_start`](../../src/actions.hc#L122)
- [`move_line_end`](../../src/actions.hc#L131)
- [`delete_backward`](../../src/actions.hc#L143)
- [`delete_forward`](../../src/actions.hc#L177)
- [`move_left`](../../src/actions.hc#L205)
- [`move_right`](../../src/actions.hc#L219)
- [`move_up`](../../src/actions.hc#L232)
- [`move_down`](../../src/actions.hc#L241)
- [`current_line`](../../src/actions.hc#L254)
- [`paste_text`](../../src/actions.hc#L264)
- [`kill_line_text`](../../src/actions.hc#L298)
- [`kill_line`](../../src/actions.hc#L307)
- [`is_space_char`](../../src/actions.hc#L318)
- [`drop_while`](../../src/actions.hc#L324)
- [`word_back_col`](../../src/actions.hc#L333)
- [`word_forward_col`](../../src/actions.hc#L344)
- [`kill_word_back_text`](../../src/actions.hc#L352)
- [`delete_word_back`](../../src/actions.hc#L362)
- [`move_word_back`](../../src/actions.hc#L378)
- [`move_word_forward`](../../src/actions.hc#L389)
- [`kill_word_forward_text`](../../src/actions.hc#L400)
- [`delete_word_forward`](../../src/actions.hc#L410)
- [`kill_whole_line_text`](../../src/actions.hc#L424)
- [`kill_whole_line`](../../src/actions.hc#L433)
- [`new_buffer_action`](../../src/actions.hc#L455)
- [`cycle_next_buffer`](../../src/actions.hc#L467)
- [`cycle_prev_buffer`](../../src/actions.hc#L475)
- [`close_buffer_action`](../../src/actions.hc#L484)
- [`prompt_text`](../../src/actions.hc#L504)
- [`prompt_cursor`](../../src/actions.hc#L512)
- [`with_prompt`](../../src/actions.hc#L521)
- [`prompt_insert_char`](../../src/actions.hc#L529)
- [`prompt_backspace`](../../src/actions.hc#L538)
- [`prompt_cancel`](../../src/actions.hc#L550)
- [`prompt_move_start`](../../src/actions.hc#L554)
- [`prompt_move_end`](../../src/actions.hc#L560)
- [`prompt_move_left`](../../src/actions.hc#L567)
- [`prompt_move_right`](../../src/actions.hc#L574)
- [`prompt_delete_forward`](../../src/actions.hc#L583)
- [`prompt_kill_text`](../../src/actions.hc#L597)
- [`prompt_truncate`](../../src/actions.hc#L603)
- [`open_file_prompt`](../../src/actions.hc#L611)
- [`resolve_prompt_action`](../../src/actions.hc#L632)
- [`resolve_help_action`](../../src/actions.hc#L655)
- [`resolve_normal_action`](../../src/actions.hc#L668)
- [`resolve_action`](../../src/actions.hc#L686)
- [`apply_action`](../../src/actions.hc#L703)
- [`handle_action`](../../src/actions.hc#L751)
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
| `event_loop` | `fun event_loop(state: EditorState) : EditorState` | *(No documentation provided)* |


---

# Domain Data Models & Type Dictionary

*(No structs or enums defined in this module)*

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

- [`apply_write_result`](../../src/runtime.hc#L75)
- [`save_buffer`](../../src/runtime.hc#L92)
- [`submit_save_as`](../../src/runtime.hc#L110)
- [`submit_open_file`](../../src/runtime.hc#L125)
- [`submit_prompt`](../../src/runtime.hc#L145)
- [`apply_history`](../../src/runtime.hc#L157)
- [`event_loop_step`](../../src/runtime.hc#L185)
- [`event_loop`](../../src/runtime.hc#L262)
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
| `default_bindings` | `fun default_bindings() : list<(KeyChord, Action)>` | *(No documentation provided)* |
| `lookup_binding` | `fun lookup_binding(kb: list<(KeyChord, Action)>, chord: KeyChord) : Action` | *(No documentation provided)* |
| `default_config` | `fun default_config() : Config` | *(No documentation provided)* |
| `get_config` | `fun get_config(cfg: Config, key: string, default: string) : string` | *(No documentation provided)* |
| `get_config_int` | `fun get_config_int(cfg: Config, key: string, default: int) : int` | *(No documentation provided)* |
| `set_config_value` | `fun set_config_value(cfg: Config, key: string, value: string) : Config` | *(No documentation provided)* |
| `default_theme` | `fun default_theme() : Theme` | *(No documentation provided)* |
| `ilseon_theme` | `fun ilseon_theme() : Theme` | *(No documentation provided)* |
| `resolve_theme_with_status` | `fun resolve_theme_with_status(cfg: Config) : (Theme, maybe<string>)` | *(No documentation provided)* |
| `resolve_theme` | `fun resolve_theme(cfg: Config) : Theme` | *(No documentation provided)* |
| `new_buffer` | `fun new_buffer(bid: int, path: maybe<string>) : TextBuffer` | *(No documentation provided)* |
| `clamp_position` | `fun clamp_position(lines: list<string>, pos: Position) : Position` | *(No documentation provided)* |
| `set_initial_position` | `fun set_initial_position(buf: TextBuffer, pos: maybe<Position>) : TextBuffer` | *(No documentation provided)* |
| `init_editor` | `fun init_editor(path: maybe<string>) : EditorState` | *(No documentation provided)* |
| `init_editor_with_config` | `fun init_editor_with_config(path: maybe<string>, cfg: Config) : EditorState` | *(No documentation provided)* |
| `init_editor_with_buffer` | `fun init_editor_with_buffer(buf: TextBuffer, cfg: Config) : EditorState` | *(No documentation provided)* |
| `load_buffer` | `fun load_buffer(new_bid: int, path: maybe<string>) : (TextBuffer, maybe<string>)` | *(No documentation provided)* |
| `open_buffers` | `fun open_buffers(s: EditorState) : list<TextBuffer>` | *(No documentation provided)* |
| `set_status_message` | `fun set_status_message(s: EditorState, msg: string) : EditorState` | *(No documentation provided)* |
| `clear_status_message` | `fun clear_status_message(s: EditorState) : EditorState` | *(No documentation provided)* |

### Public Structs

- **`Position`**: *(No documentation provided)*
- **`Cursor`**: *(No documentation provided)*
- **`TextBuffer`**: *(No documentation provided)*
- **`KeyChord`**: *(No documentation provided)*
- **`Config`**: *(No documentation provided)*
- **`Theme`**: *(No documentation provided)*
- **`EditorState`**: *(No documentation provided)*
- **`ScreenBuffer`**: *(No documentation provided)*

### Public Enums / ADTs

- **`Action`**: *(No documentation provided)*
- **`CursorStyle`**: *(No documentation provided)*
- **`Prompt`**: *(No documentation provided)*


---

# Domain Data Models & Type Dictionary

## Structs (Data Models)

### Struct `Position` `pub`
| Field | Type | Description |
| --- | --- | --- |
| `line` | `int` | *(Field)* |
| `col` | `int` | *(Field)* |

### Struct `Cursor` `pub`
| Field | Type | Description |
| --- | --- | --- |
| `cid` | `int` | *(Field)* |
| `pos` | `Position` | *(Field)* |

### Struct `TextBuffer` `pub`
| Field | Type | Description |
| --- | --- | --- |
| `bid` | `int` | *(Field)* |
| `path` | `maybe<string>` | *(Field)* |
| `lines` | `list<string>` | *(Field)* |
| `cursors` | `list<Cursor>` | *(Field)* |
| `is_dirty` | `bool` | *(Field)* |

### Struct `KeyChord` `pub`
| Field | Type | Description |
| --- | --- | --- |
| `m` | `Modifier` | *(Field)* |
| `c` | `char` | *(Field)* |

### Struct `Config` `pub`
| Field | Type | Description |
| --- | --- | --- |
| `bindings` | `list<(KeyChord, Action)>` | *(Field)* |
| `values` | `list<(string, string)>` | *(Field)* |
| `readonly` | `bool` | *(Field)* |

### Struct `Theme` `pub`
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
| Field | Type | Description |
| --- | --- | --- |
| `width` | `int` | *(Field)* |
| `height` | `int` | *(Field)* |
| `lines` | `list<string>` | *(Field)* |
| `cursor_row` | `int` | *(Field)* |
| `cursor_col` | `int` | *(Field)* |

## Algebraic Data Types (Enums)

### Type `Action` `pub`
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
#### Variants
- `Block`
- `Bar`
- `Underscore`

### Type `Prompt` `pub`
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

- [`default_bindings`](../../src/model.hc#L122)
- [`lookup_binding`](../../src/model.hc#L154)
- [`default_config`](../../src/model.hc#L174)
- [`get_config`](../../src/model.hc#L180)
- [`parse_or`](../../src/model.hc#L192)
- [`get_config_int`](../../src/model.hc#L198)
- [`set_config_value`](../../src/model.hc#L207)
- [`default_theme`](../../src/model.hc#L230)
- [`ilseon_theme`](../../src/model.hc#L244)
- [`theme_preset`](../../src/model.hc#L255)
- [`parse_rgb`](../../src/model.hc#L265)
- [`get_rgb_override`](../../src/model.hc#L272)
- [`apply_theme_overrides`](../../src/model.hc#L281)
- [`resolve_theme_with_status`](../../src/model.hc#L295)
- [`resolve_theme`](../../src/model.hc#L304)
- [`new_buffer`](../../src/model.hc#L365)
- [`nth_line`](../../src/model.hc#L377)
- [`clamp_position`](../../src/model.hc#L386)
- [`set_initial_position`](../../src/model.hc#L396)
- [`init_editor`](../../src/model.hc#L408)
- [`init_editor_with_config`](../../src/model.hc#L418)
- [`init_editor_with_buffer`](../../src/model.hc#L426)
- [`split_lines`](../../src/model.hc#L442)
- [`load_existing_buffer`](../../src/model.hc#L451)
- [`load_buffer`](../../src/model.hc#L470)
- [`open_buffers`](../../src/model.hc#L478)
- [`set_status_message`](../../src/model.hc#L483)
- [`clear_status_message`](../../src/model.hc#L486)
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
| `eval_all` | `fun eval_all(tokens: list<Token>, env: Env, last: LVal) : (LVal, Env)` | *(No documentation provided)* |
| `eval_source` | `fun eval_source(src: string) : string` | *(No documentation provided)* |
| `eval_source_val` | `fun eval_source_val(src: string) : LVal` | *(No documentation provided)* |
| `parse_chord` | `fun parse_chord(s: string) : maybe<KeyChord>` | *(No documentation provided)* |
| `chord_to_str` | `fun chord_to_str(chord: KeyChord) : string` | *(No documentation provided)* |
| `action_to_string` | `fun action_to_string(a: Action) : string` | *(No documentation provided)* |
| `config_from_env` | `fun config_from_env(env: Env, fallback: Config) : Config` | *(No documentation provided)* |
| `env_with_config` | `fun env_with_config(env: Env, cfg: Config) : Env` | *(No documentation provided)* |
| `hedit_host_dispatch` | `fun hedit_host_dispatch(name: string, args: list<LVal>, env: Env) : (LVal, Env)` | *(No documentation provided)* |
| `make_hedit_env` | `fun make_hedit_env(cfg0: Config) : Env` | *(No documentation provided)* |
| `load_config` | `fun load_config(src: string, cfg0: Config) : (Config, maybe<string>)` | *(No documentation provided)* |


---

# Domain Data Models & Type Dictionary

*(No structs or enums defined in this module)*

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

- [`eval_all`](../../src/hilisp_host.hc#L49)
- [`eval_source`](../../src/hilisp_host.hc#L66)
- [`eval_source_val`](../../src/hilisp_host.hc#L73)
- [`mod_to_string`](../../src/hilisp_host.hc#L82)
- [`parse_mod`](../../src/hilisp_host.hc#L90)
- [`single_char_of`](../../src/hilisp_host.hc#L101)
- [`parse_chord`](../../src/hilisp_host.hc#L111)
- [`chord_to_str`](../../src/hilisp_host.hc#L127)
- [`action_to_string`](../../src/hilisp_host.hc#L133)
- [`string_to_action`](../../src/hilisp_host.hc#L177)
- [`bindings_key`](../../src/hilisp_host.hc#L215)
- [`values_key`](../../src/hilisp_host.hc#L217)
- [`bindings_to_hash`](../../src/hilisp_host.hc#L221)
- [`binding_to_entry`](../../src/hilisp_host.hc#L224)
- [`values_to_hash`](../../src/hilisp_host.hc#L232)
- [`value_to_entry`](../../src/hilisp_host.hc#L235)
- [`config_from_env`](../../src/hilisp_host.hc#L244)
- [`entries_to_bindings`](../../src/hilisp_host.hc#L256)
- [`entries_to_values`](../../src/hilisp_host.hc#L267)
- [`env_with_config`](../../src/hilisp_host.hc#L276)
- [`value_to_string`](../../src/hilisp_host.hc#L300)
- [`hedit_host_dispatch`](../../src/hilisp_host.hc#L322)
- [`host_set`](../../src/hilisp_host.hc#L331)
- [`host_get`](../../src/hilisp_host.hc#L346)
- [`bind_ok`](../../src/hilisp_host.hc#L366)
- [`host_bind`](../../src/hilisp_host.hc#L378)
- [`preamble`](../../src/hilisp_host.hc#L395)
- [`make_hedit_env`](../../src/hilisp_host.hc#L406)
- [`load_config`](../../src/hilisp_host.hc#L423)
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
| `make_spec` | `fun make_spec() : CliSpec` | *(No documentation provided)* |
| `parse_position_arg` | `fun parse_position_arg(a: string) : maybe<Position>` | *(No documentation provided)* |
| `extract_position_arg` | `fun extract_position_arg(args: list<string>) : (maybe<string>, list<string>)` | *(No documentation provided)* |


---

# Domain Data Models & Type Dictionary

*(No structs or enums defined in this module)*

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

- [`make_spec`](../../src/cli_spec.hc#L16)
- [`with_parsed_line`](../../src/cli_spec.hc#L30)
- [`parse_line_col`](../../src/cli_spec.hc#L36)
- [`parse_position_arg`](../../src/cli_spec.hc#L42)
- [`extract_position_arg`](../../src/cli_spec.hc#L62)
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

*(No public API exported)*

---

# Domain Data Models & Type Dictionary

*(No structs or enums defined in this module)*

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

- [`combine_with`](../../src/main.hc#L57)
- [`combine_status`](../../src/main.hc#L66)
- [`enable_raw_mode`](../../src/main.hc#L76)
- [`disable_raw_mode`](../../src/main.hc#L80)
- [`rgb_fg_code`](../../src/main.hc#L91)
- [`rgb_bg_code`](../../src/main.hc#L94)
- [`wrap_fg_bg`](../../src/main.hc#L97)
- [`wrap_bg`](../../src/main.hc#L100)
- [`colorize_tabline_row`](../../src/main.hc#L107)
- [`colorize_status_row`](../../src/main.hc#L118)
- [`colorize_cursor_row`](../../src/main.hc#L121)
- [`style_frame_lines`](../../src/main.hc#L127)
- [`style_frame_lines_go`](../../src/main.hc#L132)
- [`render_native`](../../src/main.hc#L163)
- [`apply_tabsize_override`](../../src/main.hc#L174)
- [`apply_readonly_override`](../../src/main.hc#L182)
- [`run_editor`](../../src/main.hc#L185)
- [`main`](../../src/main.hc#L219)
