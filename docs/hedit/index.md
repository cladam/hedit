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

## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
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
| `buffer_tab_name` | `fun buffer_tab_name(buf: TextBuffer) : string` | ✅ Pure | None |
| `build_tabline` | `fun build_tabline(state: EditorState) : string` | ✅ Pure | None |
| `render_editor_to_buffer` | `fun render_editor_to_buffer(state: EditorState) : ScreenBuffer` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/render.hc`

## Summary
✅ **No functional debt detected** — all 5 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`fit_to_width`](../../src/render.hc#L12)
- [`take_or_pad`](../../src/render.hc#L16)
- [`buffer_tab_name`](../../src/render.hc#L29)
- [`build_tabline`](../../src/render.hc#L35)
- [`render_editor_to_buffer`](../../src/render.hc#L42)
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
| `load_user_config` | `fun load_user_config(cfg0: Config) : (Config, maybe<string>)` | ⚡ Impure | I/O & FileSystem |

---

# Hica Analysis Hotspot: `src/config_loader.hc`

## Summary
✅ **No functional debt detected** — all 6 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`opt_path`](../../src/config_loader.hc#L25)
- [`xdg_candidate`](../../src/config_loader.hc#L31)
- [`home_candidate`](../../src/config_loader.hc#L38)
- [`candidate_paths`](../../src/config_loader.hc#L47)
- [`read_first`](../../src/config_loader.hc#L54)
- [`load_user_config`](../../src/config_loader.hc#L78)
---

# Project Architecture & Export Directory: `keys.hc`

## Module Overview
- **Source File:** `src/keys.hc`
## Public API Catalog

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

---

# Hica Analysis Hotspot: `src/keys.hc`

## Summary
✅ **No functional debt detected** — all 0 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

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
| `current_line` | `fun current_line(state: EditorState) : string` | *(No documentation provided)* |
| `paste_text` | `fun paste_text(state: EditorState, text: string) : EditorState` | *(No documentation provided)* |
| `new_buffer_action` | `fun new_buffer_action(state: EditorState) : EditorState` | *(No documentation provided)* |
| `cycle_next_buffer` | `fun cycle_next_buffer(state: EditorState) : EditorState` | *(No documentation provided)* |
| `cycle_prev_buffer` | `fun cycle_prev_buffer(state: EditorState) : EditorState` | *(No documentation provided)* |
| `close_buffer_action` | `fun close_buffer_action(state: EditorState) : EditorState` | *(No documentation provided)* |
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
| `advance_cursor` | `fun advance_cursor(c: Cursor) : Cursor` | ✅ Pure | None |
| `insert_char` | `fun insert_char(state: EditorState, c: char) : EditorState` | ✅ Pure | None |
| `current_line` | `fun current_line(state: EditorState) : string` | ✅ Pure | None |
| `paste_text` | `fun paste_text(state: EditorState, text: string) : EditorState` | ✅ Pure | None |
| `new_buffer_action` | `fun new_buffer_action(state: EditorState) : EditorState` | ✅ Pure | None |
| `cycle_next_buffer` | `fun cycle_next_buffer(state: EditorState) : EditorState` | ✅ Pure | None |
| `cycle_prev_buffer` | `fun cycle_prev_buffer(state: EditorState) : EditorState` | ✅ Pure | None |
| `close_buffer_action` | `fun close_buffer_action(state: EditorState) : EditorState` | ✅ Pure | None |
| `resolve_action` | `fun resolve_action(state: EditorState, evt: Event) : Action` | ✅ Pure | None |
| `apply_action` | `fun apply_action(state: EditorState, action: Action) : EditorState` | ✅ Pure | None |
| `handle_action` | `fun handle_action(state: EditorState, evt: Event) : EditorState` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/actions.hc`

## Summary
✅ **No functional debt detected** — all 13 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`list_set`](../../src/actions.hc#L22)
- [`list_get`](../../src/actions.hc#L31)
- [`advance_cursor`](../../src/actions.hc#L42)
- [`insert_char`](../../src/actions.hc#L48)
- [`current_line`](../../src/actions.hc#L71)
- [`paste_text`](../../src/actions.hc#L85)
- [`new_buffer_action`](../../src/actions.hc#L122)
- [`cycle_next_buffer`](../../src/actions.hc#L134)
- [`cycle_prev_buffer`](../../src/actions.hc#L142)
- [`close_buffer_action`](../../src/actions.hc#L151)
- [`resolve_action`](../../src/actions.hc#L165)
- [`apply_action`](../../src/actions.hc#L180)
- [`handle_action`](../../src/actions.hc#L201)
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
| `apply_history` | `fun apply_history(state: EditorState, result: maybe<TextBuffer>, verb: string) : EditorState` | ✅ Pure | None |
| `event_loop_step` | `fun event_loop_step(state: EditorState, buf_ref: ref<Buffer>) : EditorState` | ⚡ Impure | Divergent (recursion/loop) |
| `event_loop` | `fun event_loop(state: EditorState) : EditorState` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/runtime.hc`

## Summary
✅ **No functional debt detected** — all 5 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`apply_write_result`](../../src/runtime.hc#L75)
- [`save_buffer`](../../src/runtime.hc#L89)
- [`apply_history`](../../src/runtime.hc#L103)
- [`event_loop_step`](../../src/runtime.hc#L123)
- [`event_loop`](../../src/runtime.hc#L160)
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
| `new_buffer` | `fun new_buffer(bid: int, path: maybe<string>) : TextBuffer` | *(No documentation provided)* |
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
- **`EditorState`**: *(No documentation provided)*
- **`ScreenBuffer`**: *(No documentation provided)*

### Public Enums / ADTs

- **`Action`**: *(No documentation provided)*
- **`CursorStyle`**: *(No documentation provided)*


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

### Struct `ScreenBuffer` `pub`
| Field | Type | Description |
| --- | --- | --- |
| `width` | `int` | *(Field)* |
| `height` | `int` | *(Field)* |
| `lines` | `list<string>` | *(Field)* |

## Algebraic Data Types (Enums)

### Type `Action` `pub`
#### Variants
- `Quit`
- `Save`
- `Insert(c: char)`
- `Resize(w: int, h: int)`
- `Copy`
- `Paste`
- `Undo`
- `Redo`
- `NewBuffer`
- `NextBuffer`
- `PrevBuffer`
- `CloseBuffer`
- `Ignore`

### Type `CursorStyle` `pub`
#### Variants
- `Block`
- `Bar`
- `Underscore`


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
| `new_buffer` | `fun new_buffer(bid: int, path: maybe<string>) : TextBuffer` | ✅ Pure | None |
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
✅ **No functional debt detected** — all 16 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`default_bindings`](../../src/model.hc#L88)
- [`lookup_binding`](../../src/model.hc#L105)
- [`default_config`](../../src/model.hc#L121)
- [`get_config`](../../src/model.hc#L127)
- [`parse_or`](../../src/model.hc#L139)
- [`get_config_int`](../../src/model.hc#L145)
- [`new_buffer`](../../src/model.hc#L190)
- [`init_editor`](../../src/model.hc#L201)
- [`init_editor_with_config`](../../src/model.hc#L211)
- [`init_editor_with_buffer`](../../src/model.hc#L219)
- [`split_lines`](../../src/model.hc#L233)
- [`load_existing_buffer`](../../src/model.hc#L242)
- [`load_buffer`](../../src/model.hc#L261)
- [`open_buffers`](../../src/model.hc#L269)
- [`set_status_message`](../../src/model.hc#L274)
- [`clear_status_message`](../../src/model.hc#L277)
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
- [`chord_to_str`](../../src/hilisp_host.hc#L126)
- [`action_to_string`](../../src/hilisp_host.hc#L131)
- [`string_to_action`](../../src/hilisp_host.hc#L148)
- [`bindings_key`](../../src/hilisp_host.hc#L173)
- [`values_key`](../../src/hilisp_host.hc#L175)
- [`bindings_to_hash`](../../src/hilisp_host.hc#L179)
- [`binding_to_entry`](../../src/hilisp_host.hc#L182)
- [`values_to_hash`](../../src/hilisp_host.hc#L190)
- [`value_to_entry`](../../src/hilisp_host.hc#L193)
- [`config_from_env`](../../src/hilisp_host.hc#L202)
- [`entries_to_bindings`](../../src/hilisp_host.hc#L214)
- [`entries_to_values`](../../src/hilisp_host.hc#L225)
- [`env_with_config`](../../src/hilisp_host.hc#L234)
- [`value_to_string`](../../src/hilisp_host.hc#L258)
- [`hedit_host_dispatch`](../../src/hilisp_host.hc#L280)
- [`host_set`](../../src/hilisp_host.hc#L289)
- [`host_get`](../../src/hilisp_host.hc#L304)
- [`bind_ok`](../../src/hilisp_host.hc#L324)
- [`host_bind`](../../src/hilisp_host.hc#L336)
- [`preamble`](../../src/hilisp_host.hc#L353)
- [`make_hedit_env`](../../src/hilisp_host.hc#L364)
- [`load_config`](../../src/hilisp_host.hc#L381)
---

# Project Architecture & Export Directory: `cli_spec.hc`

## Module Overview
- **Source File:** `src/cli_spec.hc`
## Dependencies
- `std/cli`

## Public API Catalog

### Public Functions

| Function | Signature | Description |
| --- | --- | --- |
| `make_spec` | `fun make_spec() : CliSpec` | *(No documentation provided)* |


---

# Domain Data Models & Type Dictionary

*(No structs or enums defined in this module)*

---

# Purity and Side Effects Tracking Matrix

| Function | Signature | Purity Status | Detected Effect Dependencies |
| --- | --- | --- | --- |
| `make_spec` | `fun make_spec() : CliSpec` | ✅ Pure | None |

---

# Hica Analysis Hotspot: `src/cli_spec.hc`

## Summary
✅ **No functional debt detected** — all 1 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`make_spec`](../../src/cli_spec.hc#L12)
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
| `run_editor` | `fun run_editor(r: CliResult) : ()` | ⚡ Impure | Console |
| `main` | `fun main() : ()` | ⚡ Impure | Console |

---

# Hica Analysis Hotspot: `src/main.hc`

## Summary
✅ **No functional debt detected** — all 4 function(s) are clean.

**FP Quality Index: 100/100**

---

# Router Map & Symbolic Index

This index maps symbol names to their original file ranges, for tool and human reference.

- [`combine_with`](../../src/main.hc#L37)
- [`combine_status`](../../src/main.hc#L46)
- [`run_editor`](../../src/main.hc#L52)
- [`main`](../../src/main.hc#L78)
