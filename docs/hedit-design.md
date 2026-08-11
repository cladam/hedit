# System Design Document: hedit (Terminal Text Editor in hica)

## 1. System Overview & Goals

`hedit` is a lightweight, terminal-based text editor built in `hica` and inspired by `micro`. Its design goal is to combine the intuitive UX of modern GUI editors (standard keybindings, mouse interaction, multiple cursors, split views) with the safety, elegance, and performance of `hica`'s algebraic effects and Perceus-based memory management (Functional But In-Place / FBIP).

This document provides a baseline architecture, with explicit focus on **user-facing algebraic effect definitions**. `hedit` will serve as the primary end-to-end integration workload for validating effect syntax, effect composition, handler scoping, and performance in the `hica` compiler.

---

## 2. Core Algebraic Effect Definitions

To maintain pure, testable core logic, `hedit` decomposes all side-effecting operations into fine-grained algebraic effects. The compiler must support effect operations, performant multi-effect composition, and deep/shallow effect handlers.

### 2.1 Terminal I/O Effect (`effect terminal`)

Encapsulates ANSI/VT100 screen buffer rendering and input event polling.

```hica
// Represents raw or parsed user input
enum Key {
    Char(Char),
    Special(SpecialKey), // Enter, Backspace, Tab, Esc, Arrows, F1-F12
    Shortcut(Modifier, Char) // Ctrl, Alt, Meta
}

enum MouseAction { Press, Release, Drag, ScrollUp, ScrollDown }

enum Event {
    KeyEvent(Key),
    MouseEvent(MouseAction, Int, Int), // Action, X, Y
    ResizeEvent(Int, Int),             // Width, Height
    Tick
}

struct ScreenCell {
    glyph: Char,
    fg_color: Color,
    bg_color: Color,
    style: StyleFlags // Bold, Underline, Italic
}

struct ScreenBuffer {
    width: Int,
    height: Int,
    cells: Vector<ScreenCell>
}

// User-Facing Effect Definition
effect terminal {
    fun poll_event(): Event
    fun render_frame(buffer: ScreenBuffer): Unit
    fun get_dimensions(): (Int, Int)
    fun set_cursor_style(style: CursorStyle): Unit
}

```

### 2.2 File System Effect (`effect fs`)

Encapsulates disk access, file I/O, path metadata, and file watching.

```hica
struct FileMeta {
    path: String,
    readonly: Bool,
    size_bytes: Int64,
    modified_at: Int64
}

effect fs {
    fun read_file_to_string(path: String): Result<String, FsError>
    fun write_string_to_file(path: String, content: String): Result<Unit, FsError>
    fun fetch_metadata(path: String): Result<FileMeta, FsError>
    fun watch_file(path: String): Unit
}

```

### 2.3 Clipboard Effect (`effect clipboard`)

Abstracts system/X11/Wayland/OSX clipboards and internal fallback buffers.

```hica
effect clipboard {
    fun get_selection(): String
    fun set_selection(text: String): Unit
}

```

### 2.4 Command & Process Effect (`effect process`)

Allows `hedit` to spawn external tools (e.g., formatters, linters, Git subcommands) asynchronously.

```hica
struct ProcessOutput {
    exit_code: Int,
    stdout: String,
    stderr: String
}

effect process {
    fun exec_cmd(cmd: String, args: List<String>): ProcessOutput
    fun spawn_background(cmd: String, args: List<String>): ProcessId
}

```

### 2.5 Config & Environment Effect (`effect env`)

Handles dynamic setting lookups (e.g., `.micro/settings.json` equivalent or `hedit.hica` configs).

```hica
effect env {
    fun get_config_var(key: String): Maybe<String>
    fun set_config_var(key: String, value: String): Unit
}

```

---

## 3. Data Model & FBIP Memory Strategy

`hedit` relies on pure functional data structures. Thanks to `hica`'s Perceus reference-counting backend, updating these data structures becomes destructive in-place mutation at runtime whenever ownership is unique ($RC = 1$).

```hica
struct Position {
    line: Int,
    col: Int
}

struct Selection {
    anchor: Position,
    head: Position
}

struct Cursor {
    id: Int,
    pos: Position,
    selection: Maybe<Selection>
}

// Immutable Piece Table or Rope representation for text buffers
struct TextBuffer {
    id: BufferId,
    path: Maybe<String>,
    lines: Vector<String>, // High-performance persistent vector
    cursors: List<Cursor>,
    is_dirty: Bool,
    undo_stack: List<BufferDelta>,
    redo_stack: List<BufferDelta>
}

// Tree structure for split layouts
enum PaneNode {
    Leaf(BufferId),
    HorizontalSplit(PaneNode, PaneNode, Float), // Float = split ratio
    VerticalSplit(PaneNode, PaneNode, Float)
}

struct EditorState {
    panes: PaneNode,
    active_buffer_id: BufferId,
    buffers: Map<BufferId, TextBuffer>,
    status_message: Maybe<String>,
    screen_size: (Int, Int)
}

```

---

## 4. Effect Handlers & Executable Contexts

One of the main advantages of this architecture is complete decoupling of logic from runtime environments. Handlers translate high-level effect operations into platform-specific implementations or mock objects.

### 4.1 Production Terminal Handler (POSIX / ANSI)

```hica
fun run_native_editor(init_path: Maybe<String>): Unit => {
    with handler terminal {
        poll_event() => native_ansi_read_key(),
        render_frame(sb) => native_ansi_flush_screen(sb),
        get_dimensions() => native_tty_get_size(),
        set_cursor_style(s) => native_ansi_set_cursor(s)
    } 
    with handler fs {
        read_file_to_string(p) => host_fs_read(p),
        write_string_to_file(p, c) => host_fs_write(p, c),
        fetch_metadata(p) => host_fs_stat(p),
        watch_file(p) => host_fs_watch(p)
    }
    with handler clipboard {
        get_selection() => host_clip_get(),
        set_selection(t) => host_clip_set(t)
    }
    in {
        let state = init_editor(init_path)
        event_loop(state)
    }
}

```

### 4.2 Headless / Compiler Test Handler

For integration testing within the `hica` compiler test suite, we can instantiate `hedit` headlessly. Synthetic input events are injected, and buffer states are asserted without opening a terminal window or accessing disk.

```hica
fun test_editor_ctrl_s_saves_file(): Unit => {
    let mock_events = [
        Event.KeyEvent(Key.Char('h')),
        Event.KeyEvent(Key.Char('i')),
        Event.KeyEvent(Key.Shortcut(Modifier.Ctrl, 's'))
    ]
    
    var file_written = false
    var written_content = ""

    with handler terminal {
        poll_event() => pop_event(mock_events),
        render_frame(_) => (), // No-op rendering
        get_dimensions() => (80, 24),
        set_cursor_style(_) => ()
    }
    with handler fs {
        read_file_to_string(_) => Ok(""),
        write_string_to_file(_, content) => {
            file_written = true
            written_content = content
            Ok(())
        },
        fetch_metadata(_) => Err(FsError.NotFound),
        watch_file(_) => ()
    }
    in {
        let state = init_editor(Just("test.txt"))
        run_test_loop(state)
        
        assert(file_written == true)
        assert(written_content == "hi")
    }
}

```

---

## 5. Event Processing Core

The heart of `hedit` is a tail-recursive function performing pure state updates inside an effectful shell.

```hica
// Pure state update step (no effects)
fun handle_action(state: EditorState, evt: Event): EditorState => {
    match evt {
        Event.KeyEvent(Key.Shortcut(Modifier.Ctrl, 'q')) => {
            // Signal exit
            state
        },
        Event.KeyEvent(Key.Char(c)) => {
            insert_char_at_cursors(state, c)
        },
        Event.MouseEvent(MouseAction.Press, x, y) => {
            set_primary_cursor_from_screen(state, x, y)
        },
        _ => state
    }
}

// Main event loop leveraging combined algebraic effects
fun event_loop(state: EditorState): Unit {
    // Perform I/O operations via effects
    let screen = render_editor_to_buffer(state)
    render_frame(screen)
    
    let evt = poll_event()
    
    match evt {
        Event.KeyEvent(Key.Shortcut(Modifier.Ctrl, 'q')) => {
            // Check for unsaved changes before exiting
            if has_unsaved_buffers(state) then {
                let confirmation_state = prompt_save_warning(state)
                event_loop(confirmation_state)
            } else {
                () // Terminate loop
            }
        },
        Event.KeyEvent(Key.Shortcut(Modifier.Ctrl, 's')) => {
            let updated_state = save_active_buffer(state)
            event_loop(updated_state)
        },
        _ => {
            let next_state = handle_action(state, evt)
            event_loop(next_state)
        }
    }
}

fun save_active_buffer(state: EditorState): EditorState => {
    let buf = get_active_buffer(state)
    match buf.path {
        Just(p) => {
            let text = flatten_buffer(buf)
            match write_string_to_file(p, text) {
                Ok(()) => mark_buffer_clean(state, buf.id),
                Err(err) => set_status_message(state, "Failed to save file!")
            }
        },
        Nothing => set_status_message(state, "No file name specified!")
    }
}

```

---

## 6. Compiler Feature Validation Matrix

By building `hedit` against this design, the `hica` compiler development team can validate the following language features:

| Feature Target | `hedit` Subsystem Exercising Feature | Success Criteria |
| --- | --- | --- |
| **User-facing `effect` syntax** | Declarations of `terminal`, `fs`, `clipboard`, `process` | Clean typing, correct effect signatures, clear diagnostic error messages for missing operations. |
| **Handler scoping (`with handler`)** | Swapping Native vs Headless Test Handlers | Zero performance overhead when executing effect operations inside nested handlers. |
| **Perceus FBIP Optimization** | High-frequency text manipulation (`insert_char_at_cursors`) | Verification that unique buffers update in-place without triggering heap allocations on keystrokes. |
| **Pattern Matching & Algebraic Data Types** | Event handling (`Key`, `MouseAction`), Pane Trees (`PaneNode`) | Complete exhaustiveness checking without compiler panics on deeply nested matches. |
| **Asynchronous Effects & Continuations** | Background process invocation (`exec_cmd`) | Effect handlers can pause execution, perform background tasks, and resume continuations correctly. |

---

## 7. Scripting & Plugin System (HiLisp)

### 7.1 Rationale

`hedit` uses **[HiLisp](https://github.com/cladam/hica-lisp)** — a tiny Lisp interpreter written in `hica` — as its configuration and plugin language. This mirrors the role Lua plays in `micro`, but avoids introducing a second runtime: HiLisp compiles from the same source tree via the same `hica build`, sharing types, allocator, and Perceus reasoning with the rest of `hedit`.

Motivations:

- **Zero extra runtime dependency.** HiLisp is a hica library, not an embedded C runtime.
- **Dogfooding.** Every plugin exercises `hica` end-to-end through HiLisp, producing the same kind of compiler feedback as §6.
- **S-expressions as data.** Keybindings, hooks, and commands are quoted lists, trivially template-able and inspectable.
- **Already sufficient.** HiLisp v1 already provides closures, `loop`/`recur`, `cond`, list ops, `str`/`println`, `exec`, and `write-file` — enough for the v1 plugin API.

### 7.2 Sourcing HiLisp

HiLisp is a **git submodule** at `lib/hilisp/` (points at `hica-lisp` upstream). `hedit`'s build compiles the relevant HiLisp source files (`ast`, `types`, `tokeniser`, `parser`, `display`, `builtins`, `eval`, `lisp`) alongside its own. `main.hc` from HiLisp is intentionally excluded — `hedit` owns the entry point.

Rebuilding the submodule pointer is a deliberate act (`git submodule update --remote lib/hilisp`) so plugin authors can pin against a known HiLisp version.

### 7.3 Architecture Overview

```
┌────────────────────────────────────────────────────────────┐
│  hedit core (pure)                                         │
│    types.hc / model.hc / actions.hc                        │
│      handle_action : EditorState -> Event -> EditorState   │
│                                                            │
│  effect terminal / fs / clipboard / process / env          │
└──────────────┬─────────────────────────────────────────────┘
               │
┌──────────────▼─────────────────────────────────────────────┐
│  hedit scripting bridge (new, src/script/)                 │
│    hilisp_host.hc   ─ owns one long-lived HiLisp Env       │
│    api.hc           ─ registers Lisp built-ins that call   │
│                       into hedit (config, bindings, …)     │
│    config_loader.hc ─ locates & evaluates init.hl          │
└──────────────┬─────────────────────────────────────────────┘
               │
┌──────────────▼─────────────────────────────────────────────┐
│  User land                                                 │
│    $XDG_CONFIG_HOME/hedit/init.hl                          │
│      (fallback: $HOME/.hedit.hl)                           │
└────────────────────────────────────────────────────────────┘
```

### 7.4 Configuration File Discovery

Resolution order, first hit wins:

1. `$XDG_CONFIG_HOME/hedit/init.hl` (if `$XDG_CONFIG_HOME` is unset, `$HOME/.config/hedit/init.hl`)
2. `$HOME/.hedit.hl`

If neither exists, `hedit` runs with hard-coded defaults and no user script is executed.

### 7.5 v1 Configuration Language

The initial scripting scope is deliberately narrow: **settings + keybindings.** Plugin discovery, event hooks, and dynamic buffer manipulation are explicitly out of scope for v1 and slated for a follow-up milestone.

```lisp
;; ~/.config/hedit/init.hl — v1 example

(set "tabsize"     4)
(set "auto-indent" true)
(set "theme"       "gruvbox")

(bind "Ctrl-s" 'save)
(bind "Ctrl-q" 'quit)
(bind "Ctrl-w" 'close-buffer)
```

### 7.6 Lisp ↔ hedit API Surface (v1)

Only three built-ins are registered on the HiLisp environment during v1:

| Built-in | Purpose | Effect used |
|---|---|---|
| `(set key value)` | Set a configuration value | `env.set_config_var` |
| `(get key)` | Read a configuration value | `env.get_config_var` |
| `(bind keystroke action)` | Map a keystroke to a named built-in action | pure (updates `ConfigState`) |

`action` in `(bind …)` is a quoted symbol (`'save`, `'quit`, …) resolving to a hedit-side variant of a closed enum `type Action`. Unknown symbols fail loudly at load time with a line/column pointer from HiLisp's parser.

### 7.7 Load Sequence

```
main()
  ├─ initialise ConfigState with defaults
  ├─ locate config file  (XDG → $HOME/.hedit.hl)
  ├─ if found:
  │    ├─ create HiLisp Env
  │    ├─ register built-ins (set, get, bind)
  │    ├─ eval file contents; abort with diagnostic on parse/eval error
  │    └─ freeze ConfigState (v1: no runtime reconfiguration)
  └─ enter event_loop(state)
```

The event loop consults `ConfigState.bindings` **before** the hard-coded switch inside `handle_action`, so user bindings win over defaults but can never remove built-in fallbacks.

### 7.8 Test Strategy

- **Unit:** parse & eval a fixture `init.hl` against an in-memory `env` handler, assert the resulting `ConfigState`.
- **Integration:** run the existing headless handler stack (§4.2) with a config that rebinds `Ctrl-x` to `save`; feed a synthetic `Ctrl-x` and assert the file-written mock triggered.

### 7.9 Deferred (v2+)

Explicitly not in v1:

- Plugin discovery (`~/.config/hedit/plug/*/plugin.hl`).
- Event hooks (`onBufferOpen`, `preInsertChar`, `onSave`, `onQuit`).
- Buffer introspection / mutation from Lisp (`current-buffer`, `insert-text`, `replace-line`).
- Runtime `:eval` command inside the editor.

These land once §7.5 has been in daily use long enough to feel stable.

---

## 8. HiLisp Dependency

**Version pin:** `hica-lisp ≥ 0.8.0`.

All four gaps identified during the design phase are now resolved upstream:

| Gap | Status | Notes |
|---|---|---|
| 8.1 String escape sequences (`\n` `\t` `\r` `\\` `\"`) | ✅ shipped | Tokeniser decodes escapes; `lval_show` re-escapes on display so values round-trip. |
| 8.2 Hash-map / assoc type | ✅ shipped in 0.7.0 | `LHash` value type + eight builtins (`hash-map`, `hash-get`, `hash-set`, `hash-del`, `hash-has?`, `hash-keys`, `hash-vals`, `hash?`) plus a `{k v …}` reader literal that desugars to `(hash-map …)`. Backing store is an alist; a persistent HAMT can follow if profiling calls for it. |
| 8.3 Symbol values distinct from strings | ✅ shipped in 0.8.0 | `LSym(name, span)` was already first-class; 0.7 adds host-facing `(symbol? v)` and `(symbol-name sym)` builtins and name-based `=` for `LSym`/`LSym`. `(bind "Ctrl-s" 'save)` dispatch is idiomatic. |
| 8.4 Line/column in error messages | ✅ shipped in 0.8.0 | Spans were already tokenised/parsed and rendered via `render_snippet` for parse-time errors; 0.8 threads the call-site span through `eval_call` and stamps it onto span-less builtin errors, so runtime type/arity errors also print a caret snippet at the offending form. |

### 8.1 What the config layer relies on

The scripting bridge (§7) can assume:

- **String escapes** — status messages, generated snippets, and key labels can
  contain `\n`, `\t`, `\r`, `\\`, `\"` naturally.
- **Hash-maps** — the entire `ConfigState` can be a single `LHash` on the
  HiLisp side, with `(hash-get cfg "tabsize")` on the hedit side; no
  hand-rolled alist walk. Nested groups (`{"editor" {"tabsize" 4}}`) are fine.
- **Symbols** — `(bind "Ctrl-s" 'save)` passes an `LSym("save", span)` that
  hedit maps to a variant of the closed `Action` enum. Unknown symbols
  produce an `LError` with source location.
- **Source spans on errors** — bad `init.hl` prints a Rust-style caret snippet
  pointing at the offending token, useful even without hedit intervention.

### 8.2 Follow-ups (not blocking)

- **Persistent HAMT for `LHash`** if config sizes ever justify it. Alist walks
  are O(n) per lookup, which is fine for the tens-of-keys range of an editor
  config.
- **Non-string hash keys.** Currently keys must be `LStr`. Symbol keys would
  let us write `{'tabsize 4}`; deferred unless a hedit API actually needs it.
- **`{…}` inside quoted forms** — the reader literal always desugars; if we
  ever need literal-map data we'd add a matching quote path.
