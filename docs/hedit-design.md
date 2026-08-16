# System Design Document: hedit (Terminal Text Editor in hica)

## 1. System Overview & Goals

`hedit` is a lightweight, terminal-based text editor built in `hica` and inspired by `micro`. Its design goal is to combine the intuitive UX of modern GUI editors (standard keybindings, mouse interaction, multiple cursors, split views) with the safety, elegance, and performance of `hica`'s algebraic effects and Perceus-based memory management (Functional But In-Place / FBIP).

This document provides a baseline architecture, with explicit focus on **user-facing algebraic effect definitions**. `hedit` will serve as the primary end-to-end integration workload for validating effect syntax, effect composition, handler scoping, and performance in the `hica` compiler.

---

## 2. Core Algebraic Effect Definitions

To keep the core editor logic pure and testable, `hedit` factors all
side-effecting operations behind **user-defined algebraic effects**
(hica 0.49+). Effect names are **PascalCase**, operation names are
**snake_case**, matching the language reference.

### 2.0 Which effects are user-defined in v1

`hica` 0.49 already exposes a rich set of *built-in* effects that we
reuse directly instead of wrapping in an `effect` block:

- **`<fsys>`** — via `read_file` / `write_file`. Save / open flow rides
  on these; there is no v1 `effect FileSystem`.
- **`<console>`** — via `println` / `eprintln`. Debug output and
  status messages don't need a `Log` effect.
- **`<env>` / args** — via `get_env`, `env_or`, `get_args`. HiLisp
  config discovery lives on top of these directly.
- **`exec`** for external processes — deferred until a real
  async / long-running-process story materialises (no v1 `effect
  Process`).

The two effects that *are* worth defining as first-class hica effects
in v1:

| Effect | Ops | Real handler | Test handler |
|---|---|---|---|
| `Terminal` | `poll_event`, `render_frame`, `get_dimensions`, `set_cursor_style` | native ANSI / `std/term` (stub in M1, real in M2+) | scripted event queue, sink render, canned size |
| `Clipboard` | `get_selection`, `set_selection` | OS clipboard (deferred; in-memory placeholder to start) | in-memory `with var buf = ""` |

`Terminal` is the killer app for effect-based testing — swap real ANSI
I/O for a scripted key stream and the editor loop becomes trivially
testable. `Clipboard` is small, real-world, and cross-platform-messy —
perfect handler-swap candidate. Everything else stays as built-in
`hica` calls until a concrete use case demands a wrapper.

### 2.1 Terminal I/O Effect (`effect Terminal`)

Encapsulates ANSI/VT100 screen buffer rendering and input event
polling. This is the surface hedit's `event_loop` calls into; the
handler decides whether those calls hit a real TTY or a scripted test
queue.

```hica
// Represents raw or parsed user input
pub type Key {
  KChar(c: char),
  KSpecial(k: SpecialKey),
  KShortcut(m: Modifier, c: char)
}

pub type MouseAction { Press, Release, Drag, ScrollUp, ScrollDown }

pub type Event {
  KeyEvent(k: Key),
  MouseEvent(a: MouseAction, x: int, y: int),
  ResizeEvent(w: int, h: int),
  Tick
}

// Minimal M1 ScreenBuffer: width, height, one string per row.
// M2 upgrades this to a `list<ScreenCell>` with fg/bg + style flags.
pub struct ScreenBuffer {
  width: int,
  height: int,
  lines: list<string>
}

pub type CursorStyle { Block, Bar, Underscore }

// User-facing effect declaration (hica 0.49 syntax).
// Arm bodies auto-resume; there is no explicit `resume` call in the
// handler.
effect Terminal {
  fun poll_event() : Event
  fun render_frame(buf: ScreenBuffer)
  fun get_dimensions() : (int, int)
  fun set_cursor_style(style: CursorStyle)
}
```

### 2.2 File I/O — built-in `<fsys>` (no v1 effect)

hedit calls `read_file(path) : result<string, string>` and
`write_file(path, content) : ()` directly from `<fsys>`. That gives us
the "open / save" story in M2 without adding an `effect FileSystem`
declaration. If we ever need to mock the file system (e.g. to inject
faults), we'll introduce an `effect Fs` at that point — not before.

### 2.3 Clipboard Effect (`effect Clipboard`)

Abstracts system / X11 / Wayland / macOS clipboards and internal
fallback buffers. Lands in M3 with an in-memory handler; a real OS
handler follows in a later milestone.

```hica
effect Clipboard {
  fun get_selection() : string
  fun set_selection(text: string)
}
```

### 2.4 Deferred: Process / Env effects

`effect Process` and `effect Env` from the pre-0.49 draft are **out of
v1**. External process invocation goes through the built-in `exec`;
environment lookup goes through `get_env` / `env_or`. Wrapping either
in a hica-side effect only becomes worthwhile once we have real
handler-swap use cases (e.g. sandboxing a formatter, faking a config
path in tests) — see the effects journal (§Milestone map) for when we
revisit.


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

The `event_loop` in `src/runtime.hc` calls the `Terminal` ops
abstractly; each *handler* decides how those calls are fulfilled.
Handlers are hica 0.49 `handle E { arms } in { body }` expressions,
where each arm body auto-resumes — no explicit `resume(...)` calls in
user code.

### 4.1 Production Terminal Handler (POSIX / ANSI) — M1 stub, M2 real

In M1 the "native" handler is a **stub** that returns a canned
`Ctrl-q` so `hica run src/main.hc` exits cleanly and we prove the
handler shape compiles end-to-end. M2 replaces the arms with real ANSI
I/O (via `std/term` and a `read` primitive).

```hica
// M1 shape (src/main.hc). Deliberately trivial: one hard-coded event,
// sink render, canned size — the point is that the handler-arm shape
// type-checks against `event_loop : EditorState -> <Terminal> EditorState`.
fun main() {
  let s0 = init_editor(None)
  handle Terminal {
    poll_event()          => KeyEvent(KShortcut(Ctrl, 'q')),
    render_frame(_buf)    => (),
    get_dimensions()      => (80, 24),
    set_cursor_style(_s)  => ()
  } in {
    let _ = event_loop(s0)
    ()
  }
}
```

Once the ANSI wiring lands (M2+), the arms grow real bodies —
`poll_event` decodes a keystroke from stdin, `render_frame` flushes a
diffed `ScreenBuffer` with ANSI positioning, `get_dimensions` calls
`tcgetwinsize`, etc. The `event_loop` code above **does not change**.

### 4.2 Headless / Compiler Test Handler

For unit-testing the runtime we install a stateful handler that
scripts events from a `var` queue, sinks render calls, and returns a
canned size. This is what `tests/runtime_test.hc` uses.

```hica
// Simplified sketch of tests/runtime_test.hc pattern.
test "scripted keys 'h','i',Ctrl-q leave buffer as [\"hi\"]" {
  let events0 = [
    KeyEvent(KChar('h')),
    KeyEvent(KChar('i')),
    KeyEvent(KShortcut(Ctrl, 'q'))
  ]
  let final = handle Terminal {
    poll_event() => match events {
      []          => KeyEvent(KShortcut(Ctrl, 'q')),
      [e, ..rest] => { events = rest; e }
    },
    render_frame(_buf)   => render_count = render_count + 1,
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } with var events = events0, var render_count = 0 in {
    event_loop(init_editor(None))
  }
  assert(final.buffer.lines == ["hi"])
}
```

Two things to notice:

1. The test never touches a real terminal. It cannot flake because of
   TTY state, size queries, or CI environment.
2. The same `event_loop` runs. There is no test-only branch inside the
   loop — the divergence lives entirely in the handler.

File I/O in M2's save-on-Ctrl-s and clipboard round-trips in M3 land
as additions to `handle_action` (`write_file` via built-in `<fsys>`,
`Clipboard` ops via a second handler stack). The `Terminal` handler
above stays exactly as shown.


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

### 7.5 v1 Configuration & Plugin Language

HiLisp is the sole language for both **configuration** and **plugins** in `hedit` — there is no second scripting layer planned. Configuration files, keybindings, and (in later milestones) plugins are all authored as `.hl` files evaluated by the same embedded HiLisp interpreter.

The initial scripting scope is deliberately narrow: **settings + keybindings.** Plugin discovery, event hooks, and dynamic buffer manipulation are explicitly out of scope for v1 and slated for a follow-up milestone (see §7.9), but they will land as additional HiLisp built-ins on the same interpreter — not as a separate plugin system.

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

Everything in this section is planned to be written **in HiLisp** — the same
language users already touch for config. There is no separate plugin runtime.

Explicitly not in v1:

- **Plugin discovery.** `~/.config/hedit/plug/*/plugin.hl` files auto-loaded
  after `init.hl`, each plugin being an ordinary HiLisp file with access to the
  same built-ins plus the expanded API below.
- **Event hooks.** `(on 'buffer-open  (fn [buf] …))`,
  `(on 'pre-insert-char (fn [ch buf] …))`,
  `(on 'save (fn [buf] …))`, `(on 'quit (fn [] …))` — registered from HiLisp,
  fired by the hedit event loop.
- **Buffer introspection & mutation from HiLisp.** Built-ins such as
  `(current-buffer)`, `(insert-text s)`, `(replace-line n s)`, `(cursor-pos)`,
  `(set-cursor line col)` letting plugins drive the editor.
- **Runtime `:eval` command** inside the editor — a mini-REPL that evaluates a
  HiLisp expression against the live env, useful for plugin authors.

These land once §7.5 has been in daily use long enough to feel stable. Because
plugins are HiLisp, adding them is largely a matter of exposing more hedit
built-ins on the existing `HilispHost` — no new language, no new build step,
no second embedded runtime.

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
