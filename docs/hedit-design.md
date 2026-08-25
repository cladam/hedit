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

### 4.1 Production Terminal Handler (POSIX / ANSI) — M1 stub, M7 real

In M1 the "native" handler is a **stub** that returns a canned
`Ctrl-q` so `hica run src/main.hc` exits cleanly and we prove the
handler shape compiles end-to-end.

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

M7 replaces the arms with the real handler:

```hica
// M7 shape (src/main.hc).
extern import "term_ffi"
import "std/term"

handle Terminal {
  poll_event()         => decode_key(read_key()),
  render_frame(buf)    => render_native(buf),
  get_dimensions()     => (term_cols(), term_rows()),
  set_cursor_style(_s) => ()
} in {
  event_loop(s1)
}
```

- `read_key` / `term_cols` / `term_rows` / `flush_stdout` are a
  hand-written Koka + C FFI module, `src/term_ffi.kk` +
  `src/term_ffi_inline.c` (`extern import "term_ffi"` — hica reads the
  `pub extern` signatures straight from the `.kk` file, no `hica`
  codegen involved). The C shim reads one raw byte from stdin at a
  time and — following the exact contract of hica-ecosystem's
  `programs/myeon/term_raw_ffi.c` reference implementation —
  assembles `ESC [ A/B/C/D` escape sequences into synthetic key codes
  `1001..1004` (arrows) with a 100ms `select()` window, so the pure
  Koka/hica side never has to see raw escape bytes at all.
- `src/keys.hc::decode_key(code: int) : Event` is the pure, unit-
  tested (`tests/keys_test.hc`) seam that turns one of those int codes
  into hedit's own `Event`/`Key` types. It's the one piece of this
  milestone testable without a real tty.
- Raw mode on/off is **not** a hand-written termios FFI — `stty raw
  -echo icrnl` / `stty sane`, shelled out to via hica's built-in
  `exec`, is enough (same approach `programs/myeon` uses) and avoids
  ~70 lines of termios save/restore C for no real benefit.
- `render_frame`'s `render_native` does a full clear + redraw
  (`ESC[2J` `ESC[H` then the buffer lines) each tick — no
  diffing/partial-redraw optimization yet. Raw mode disables output
  post-processing, so lines are joined with `"\r\n"` rather than
  relying on `println`'s bare `"\n"` (otherwise every line staircases
  one column to the right of the last).
- `set_cursor_style` stays a no-op — the ANSI cursor-shape escape is
  explicitly deferred, not silently skipped.

The `event_loop` code itself **does not change** between M1 and M7 —
only the handler arms installed around it in `main.hc`.

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

The heart of `hedit` is a tail-recursive `event_loop` around a pure
`Event → Action → EditorState` pipeline. Bindings live in
`state.config.bindings` (see §7 for the HiLisp source), so **no
keystroke is hard-coded in the dispatcher**. This mirrors micro's model
([keybindings.md](https://github.com/micro-editor/micro/blob/master/runtime/help/keybindings.md))
— every op is a named `Action`, users remap by editing the binding
table.

### 5.1 Pure core: `resolve_action` + `apply_action`

`resolve_action` looks the incoming `Event` up against the user's
bindings and returns a semantic `Action`. `apply_action` then folds
that action into a new `EditorState`. Both are pure — no effects.

```hica
// keys.hc / model.hc (shape only)
pub type Action {
  Quit,
  Save,
  Insert(c: char),
  Resize(w: int, h: int),
  Ignore
}
pub struct KeyChord { m: Modifier, c: char }

// actions.hc
pub fun resolve_action(state: EditorState, evt: Event) : Action =>
  match evt {
    KeyEvent(KChar(c))        => Insert(c),
    KeyEvent(KShortcut(m, c)) =>
      lookup_binding(state.config.bindings, KeyChord { m: m, c: c }),
    ResizeEvent(w, h)         => Resize(w, h),
    _                         => Ignore
  }

pub fun apply_action(state: EditorState, action: Action) : EditorState =>
  match action {
    Quit         => EditorState { ...state, should_quit: true },
    Insert(c)    => insert_char(state, c),
    Resize(w, h) => EditorState { ...state, screen_size: (w, h) },
    Save         => state,   // event_loop peels Save off (needs <fsys>)
    Ignore       => state
  }

// Convenience for pure callers (all tests).
pub fun handle_action(state: EditorState, evt: Event) : EditorState =>
  apply_action(state, resolve_action(state, evt))
```

### 5.2 Effectful shell: `event_loop`

`event_loop` runs inside a `handle Terminal { … }` context. It renders,
polls, resolves an action, and then either handles it inline (for
effectful actions like `Save` that need `<fsys>`) or delegates to the
pure `apply_action`.

```hica
// runtime.hc — return type is inferred as <Terminal, fsys, div>.
pub fun event_loop(state: EditorState) {
  if state.should_quit {
    state
  } else {
    let dims  = get_dimensions()
    let sized = EditorState { ...state, screen_size: dims }
    render_frame(render_editor_to_buffer(sized))
    let evt    = poll_event()
    let action = resolve_action(sized, evt)
    let next   = match action {
      Save => save_buffer(sized),        // <fsys> lives here
      _    => apply_action(sized, action) // pure
    }
    event_loop(next)
  }
}

// Effectful save; only called from event_loop.
fun save_buffer(state: EditorState) {
  match state.buffer.path {
    None    => set_status_message(state, "No file — save not possible"),
    Some(p) => {
      let body = join(state.buffer.lines, "\n") + "\n"
      apply_write_result(state, write_file(p, body))
    }
  }
}
```

Two invariants worth calling out:

1. **`handle_action` stays pure.** Any future keybinding that needs
   I/O gets added as a new `Action` variant *and* an arm in
   `event_loop`'s inline match — never inside `apply_action`.
2. **No keystroke → op mapping in code.** `resolve_action` reads the
   entire mapping from `state.config.bindings`, which the defaults in
   `default_bindings()` seed and HiLisp `(bind …)` (M4) overrides.
```

---

## 6. Compiler Feature Validation Matrix

By building `hedit` against this design, the `hica` compiler development team can validate the following language features:

| Feature Target | `hedit` Subsystem Exercising Feature | Success Criteria |
| --- | --- | --- |
| **User-facing `effect` syntax (0.49 `effect Name { fun … }`)** | `effect Terminal` in `src/runtime.hc`; M3 adds `effect Clipboard`. | Clean typing, correct effect signatures, clear diagnostic error messages for missing operations. |
| **Cross-module effects (`pub effect`)** | `Terminal` declared in `runtime.hc`, handled from `main.hc` and `tests/runtime_test.hc`. | Effect row propagates through imports; consumer `handle` blocks type-check. |
| **Handler scoping (`handle E { arms } in { body }`)** | Native vs headless `Terminal` handlers swapped without touching `event_loop`. | Zero performance overhead when executing effect operations inside nested handlers. |
| **Handler-local state (`with var …`)** | `tests/runtime_test.hc` scripts events + counts renders via `with var events = …, var render_count = 0`. | State scoped to the `in { … }` block; observations return through the block's value, cannot escape. |
| **Perceus FBIP Optimization** | High-frequency text manipulation (`insert_char`). | Unique buffers update in-place without triggering heap allocations on keystrokes. |
| **Pattern matching & ADTs** | `Event` / `Key` / `Action` dispatched in `resolve_action` + `apply_action`. | Complete exhaustiveness checking without compiler panics on deeply nested matches. |
| **Structural `==` on enums/structs** | `Action == Action`, `KeyChord == KeyChord` in `actions_test.hc`. | Auto-derived `==` covers user-declared types without hand-written instances. |

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
│  hedit core                                                │
│    keys.hc / model.hc / actions.hc  (pure)                 │
│    render.hc                        (pure)                 │
│    runtime.hc                       (effectful shell)      │
│      resolve_action + apply_action + event_loop            │
│                                                            │
│  User-defined effect (v1):  Terminal   (M3: + Clipboard)   │
│  Built-ins used directly :  <fsys> <console> <env>         │
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

The initial scripting scope was deliberately narrow at launch: **settings + keybindings**, with plugin loading, event hooks, and buffer introspection landing later as additional HiLisp built-ins on the same interpreter (see §7.9, Milestone M11) — not as a separate plugin system.

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

`ConfigState.bindings` is the single source of truth for keystroke
resolution — there is no hard-coded switch inside `handle_action` to
fall back to. User bindings that shadow a default *replace* the
default; unbound chords resolve to the `Ignore` action (a no-op) so a
stale `init.hl` binding never wedges the editor. `default_bindings()`
in `src/model.hc` seeds the map before the user's `init.hl` is
evaluated, so out-of-the-box behaviour is preserved even with an empty
config file.

### 7.8 Test Strategy

- **Unit:** parse & eval a fixture `init.hl` against an in-memory `env` handler, assert the resulting `ConfigState`.
- **Integration:** run the existing headless handler stack (§4.2) with a config that rebinds `Ctrl-x` to `save`; feed a synthetic `Ctrl-x` and assert the file-written mock triggered.

### 7.9 Plugin System (M11)

hedit's plugin system is modelled directly on
[micro's](https://github.com/micro-editor/micro) — see
[`help/plugins.md`](https://github.com/micro-editor/micro/blob/master/runtime/help/plugins.md)
and the bundled examples under
[`runtime/plugins/`](https://github.com/micro-editor/micro/tree/master/runtime/plugins) —
with the Lua runtime replaced by HiLisp everywhere micro would reach
for a Lua callback or host package. There is still no second embedded
runtime: a plugin is just another `.hl` file evaluated by the same
`HilispHost` that already evaluates `init.hl`.

**What carries over from micro, and what doesn't:**

| micro concept | hedit v1 equivalent |
|---|---|
| Plugin folder auto-scanned from `~/.config/micro/plug/*` | **Explicit opt-in.** `init.hl` lists plugins by name: `(plugin "greeter")`. hedit resolves `<config-root>/plug/<name>/plugin.hl` and evaluates it into the same `Env` `init.hl` used — no directory listing needed (see below for why). |
| Lifecycle callbacks (`init`, `onBufferOpen`, `onAction`/`preAction`, `deinit`, …) | `(on 'event-name (fn […] …))` — a hook registry builtin. Five v1 events: `buffer-open`, `pre-save`, `post-save`, `pre-action`, `quit`. |
| `preAction(bp)` returns bool to cancel | `pre-action`/`pre-save` hooks use the same convention: any hook returning `false` cancels the pending action/save. |
| `micro.InfoBar():Message(...)`, `buffer.Log(...)` host functions | **Return-value-as-status convention** instead of a new builtin: if a hook returns a string, hedit shows it as the next status-bar message. |
| `micro.CurPane()`, `buffer.NewBuffer(...)`, full buffer mutation API | **Not in v1.** Hooks are pure observers — they receive data (`path`, `action-name`) as arguments and communicate back only via the status-message convention. Two-way buffer mutation from HiLisp is deferred (see below). |
| `config.MakeCommand(...)` (plugins add new commands) | **Not in v1.** `Action` stays a closed, exhaustively-matched enum on the hedit side; plugins can only rebind existing actions via `(bind …)` and observe/cancel via `(on 'pre-action …)`. |
| Plugin manager (`channels`, `repo.json`, `> plugin install`) | **Out of scope indefinitely.** No remote install story; plugins are files the user places by hand. |

**Why explicit opt-in instead of directory auto-scan:** hedit's HiLisp
bridge has only ever needed `read_file`/`write_file`/`get_env`/
`get_args` from `hica`'s stdlib — no directory-listing builtin exists
yet. Rather than block M11 on that (or add one speculatively), `init.hl`
declares the plugins it wants by name, and hedit resolves each to a
concrete path the same way it already resolves `init.hl` itself (§7.4's
XDG/HOME candidate search, one level deeper: `plug/<name>/plugin.hl`).
This also means nothing executes just because a file exists in a
folder — a deliberately more conservative default than micro's.

**Error isolation:** unlike `init.hl` (which aborts config loading on
the first error), a broken `plugin.hl` is caught, surfaced as a
one-line status message naming the plugin, and skipped — it does not
stop other plugins or the rest of startup.

**Example plugin** (`plug/greeter/plugin.hl`):

```lisp
;; Shows a welcome message the first time any buffer is opened.
(on 'buffer-open (fn (path) "Welcome to hedit!"))
```

```lisp
;; init.hl
(plugin "greeter")
```

See `docs/effects-journal.md`'s Milestone M11 for the full plan, the
hook-firing points inside `event_loop`, and what's explicitly deferred
(directory auto-discovery, a plugin manager, buffer mutation, new
actions from plugins, syntax-highlighting hooks).

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

---

## 9. Per-buffer state via `spawn Buffer` (M5)

### 9.1 Rationale

Undo/redo history has nowhere clean to live in the pure
`EditorState`/`TextBuffer` shape: it isn't part of the buffer's saved
content, it must survive across many `apply_action` calls, and it
should never leak into the pure test surface that `actions_test.hc`
relies on. hica's **named effects** (`spawn Name { … } as ref`) are
the mechanism: a `spawn`ed instance owns private mutable state (here,
two stacks) and is dispatched on by reference (`ref.op(args)`),
independent of lexical `handle … in { … }` nesting.

### 9.2 The `Buffer` effect

```hica
pub effect Buffer {
  fun snapshot(b: TextBuffer)
  fun undo(current: TextBuffer) : maybe<TextBuffer>
  fun redo(current: TextBuffer) : maybe<TextBuffer>
}
```

Every op takes the *current* `TextBuffer` as an explicit argument
rather than mirroring it inside handler-local state. This was a
deliberate fork away from the milestone's original draft (`get()` /
`put(b)` / stateless `snapshot()`): mirroring the buffer inside the
handler creates a second source of truth that can drift out of sync
with `EditorState.buffer`. Passing it explicitly means the handler
only ever owns the two stacks:

```hica
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
```

### 9.3 Why `EditorState.buffer` stays a plain `TextBuffer`

`spawn` is a **statement**, not a pure expression — it installs a
handler and returns a `ref<Name>` you keep using for the rest of the
enclosing block. Migrating `EditorState.buffer` to `ref<Buffer>` would
force `init_editor`, `apply_action`, `insert_char`, `current_line`,
`paste_text`, and every pure test in `actions_test.hc` to become
effectful in `<Buffer>` — undoing the M2/M3 invariant that
`handle_action`/`apply_action` are 100% pure.

Instead, `EditorState.buffer: TextBuffer` is unchanged, and only
`event_loop` (in `src/runtime.hc`) knows about `Buffer`:

- `event_loop(state)` spawns one `ref<Buffer>` (fresh stacks) and
  delegates to the tail-recursive `event_loop_step(state, buf_ref)`.
- `Insert` / `Paste` call `buf_ref.snapshot(sized.buffer)` *before*
  mutating, so Undo always has a valid history entry.
- `Undo` / `Redo` call `buf_ref.undo(...)` / `buf_ref.redo(...)` and
  route the `maybe<TextBuffer>` result through `apply_history`, which
  restores the buffer on `Some` or sets a "Nothing to undo/redo"
  status message on `None` (empty history is a no-op, not an error).

This keeps the mechanism's isolation property (proven by
`tests/spawn_test.hc`, which spawns two independent `Buffer`
instances in one test and asserts their history doesn't cross-talk)
without touching the pure core.

### 9.4 Default bindings

`Ctrl-z` → `Undo`, `Ctrl-y` → `Redo` — overridable via HiLisp
`(bind "Ctrl-z" 'undo)` like every other action.

### 9.5 Non-goals (deferred to M5.5+)

Multi-buffer navigation, a persistent/on-disk undo log, and coalescing
consecutive `Insert` keystrokes into a single undo step (today every
keystroke is its own snapshot) are all out of scope for M5.

## 10. Multi-buffer navigation (M5.5)

§3's original sketch (`buffers: Map<BufferId, TextBuffer>` +
`active_buffer_id`) was aspirational, not binding — see
`docs/effects-journal.md`'s M5.5 Log for why the shipped shape differs.

### 10.1 The ring shape

`EditorState.buffer` stays the sole active-buffer field (unchanged
since M1 — every pure helper written against it keeps working).
`EditorState.background_buffers: list<TextBuffer>` holds the rest of
the open buffers as a **rotation ring** — there is no separate
`active` index that could point at a stale or missing id:

```hica
pub struct EditorState {
  buffer: TextBuffer,
  background_buffers: list<TextBuffer>,
  next_bid: int,
  ...
}

pub fun open_buffers(s: EditorState) : list<TextBuffer> =>
  [s.buffer] + s.background_buffers
```

`NextBuffer`/`PrevBuffer` rotate the ring (`cycle_next_buffer`
pops the ring's head into `buffer`, pushing the old `buffer` to the
back; `cycle_prev_buffer` is the same traversal run against
`reverse(background_buffers)`). `NewBuffer` pushes the current
`buffer` onto the ring and makes a fresh empty scratch buffer active.
`CloseBuffer` drops the active buffer and promotes the ring's head —
refusing (with a status message) to close the last remaining buffer.
All four are pure — no `<fsys>`, no effect handler — so they live
entirely in `apply_action` (`src/actions.hc`), with zero changes to
`event_loop`.

### 10.2 Default bindings

`Ctrl-o` → `NewBuffer`, `Ctrl-n` → `NextBuffer`, `Ctrl-p` →
`PrevBuffer`, `Ctrl-w` → `CloseBuffer`. Not `Ctrl-tab`/`Ctrl-o`-for-open
as originally sketched — see the effects journal for why `Ctrl-tab`
isn't representable and why "open" here means "new scratch buffer",
not "open a file from disk".

### 10.3 Tabline

`render_editor_to_buffer` (`src/render.hc`) reserves row 0 for a
tabline: every open buffer (`open_buffers`, active first) joined by
`|`, with the active tab bracketed (`[scratch]`). Content rows and the
status row are unchanged other than shrinking by one row
(`n_content = h - 2`).

### 10.4 Non-goals (deferred)

- **Per-buffer isolated undo/redo.** The M5 `spawn Buffer` instance in
  `event_loop` is still a single shared undo/redo stack; switching
  buffers does not swap in separate history. A `spawn`-per-buffer pool
  is the natural fix, deferred until there's real demand.
- **`Action::OpenFile(path)`** — opening a file from disk needs a
  command-line/path-prompt input widget; `(bind chord 'symbol)` can
  only reach zero-argument actions today.
- Split panes / windows (`PaneNode`, §3) — untouched.

## 11. CLI arg parsing + real file loading (M6)

`src/main.hc` no longer hardcodes `init_editor(None)` — `argv` is
parsed via `std/cli` and a real file path (if given) is loaded from
disk before `EditorState` is assembled.

### 11.1 The spec

`src/cli_spec.hc` is a one-function module, mirroring the
already-shipped `std/cli` usage in `lib/hilisp/src/main.hc`:

```hica
pub fun make_spec() : CliSpec =>
  cli("hedit", "0.2.0", "a terminal text editor in hica")
    |> arg("file", "file to open", false)
```

A single optional `[file]` positional. `--help`/`--version` are free
from `std/cli` (`cli_help`/`cli_version_str`) — `main.hc` only needs to
wire the `Help`/`Version`/`CliError`/`Parsed` arms of `cli_parse`.

### 11.2 Real file loading

`src/model.hc` gains `load_buffer(new_bid, path)`, mirroring
`config_loader.hc::load_user_config`'s `(value, maybe<string>)` shape
so a missing/unreadable file never crashes — it falls back to the same
empty-scratch-buffer shape `new_buffer` has always produced, with the
error surfaced as a status message instead. `new_buffer` itself is
untouched; a new `init_editor_with_buffer(buf, cfg)` constructor lets
`main.hc` assemble `EditorState` from an already-loaded buffer without
touching `init_editor`/`init_editor_with_config`'s existing pure
contract (every test written before M6 still calls those unchanged).

`main.hc` merges the config-load status message (M4b) and the
file-load status message (M6) via a small `combine_status` helper
before priming `EditorState.status_message` — either, both, or neither
may be present on a given run.

### 11.3 Non-goals (deferred to M8)

`--config`/`--no-config`, `--tabsize`, `--readonly`, `+LINE:COL`, and
opening multiple files from argv into `background_buffers` are all out
of scope — see `docs/effects-journal.md`'s M6 entry.


