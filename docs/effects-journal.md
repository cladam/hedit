# hedit Effects — Implementation Journal

Working log for wiring **hica 0.49's user-facing algebraic effects** into
hedit. Sibling to `docs/hedit-design.md` (the design) — this file is the
running "what did we actually do, in what order, and what tripped us up"
diary.

The pattern is copied wholesale from
`hica-ecosystem/hica/documentation/named-effects-journal.md`, which
proved out the "small milestones, green build + tests each session" loop
during the effects M1–M4 work.

Each milestone gets its own section with:

- **Goal** — what "done" looks like for this milestone.
- **Plan** — a small, ordered checklist of concrete edits.
- **Log** — running notes made *while* implementing (surprises,
  dead-ends, fixes).
- **Reflection** — written **after** the milestone is green: what
  changed vs the plan, what to carry forward, what to change in the
  design doc.

We ship one milestone at a time. **We do not start Mn+1 until Mn is
green, reflected on, and documented.**

---

## Ground Rules

Inherited (and lightly adapted) from the named-effects journal:

0. **Small edits, frequent checks.** Every change ends with:
   - `hica check src/main.hc` clean (0 errors),
   - `hica build` succeeds,
   - `hica test tests/actions_test.hc` and `hica test
     tests/hilisp_host_test.hc` (and any new suites we add) all green.
1. **Regression tests before green.** Every milestone must add at least
   one test to a `tests/*_test.hc` file — failing first if we can arrange
   it, then passing.
2. **One runnable artefact per milestone.** Either a headless demo run
   via `hica run src/main.hc`, or an example under `examples/` (create
   the directory when we first need it).
3. **Docs updated in the same milestone.** `docs/hedit-design.md` and
   `README.md` are amended alongside the code — not "later".
4. **`hica fmt --check` and `hica analyse` on every artefact.** Every
   `.hc` file we ship (or edit) must pass:
   - `hica fmt --check <file>` → exit 0 (no formatting changes needed).
   - `hica analyse <file>` → clean report, no warnings/penalties beyond
     any sanctioned ones we've explicitly noted here.
5. **Clean the workspace.** `hica clean` will remove all generated .kk 
   files and binaries, use `hica clean --cache` to remove ~/.hica/stdlib.
   `hica clean --full` will also remove the .koka directory, the build cache and it will be needed as the std/cli .kki files will get out of sync. 
6. **Reflection is mandatory.** Before starting Mn+1 we write a
   Reflection section for Mn. If we skip it, we lose the pattern.
7. **Context-window discipline.** hica compiler internals are large — do
   NOT read them exhaustively. For each milestone, read only what the
   "Files to touch" section lists. Prefer `grep -n` over `read_file`
   when you only need to find a definition. If you find yourself over
   60% context and still exploring, **stop and commit what you have**
   with a Handoff Log entry.

---

## Design-doc alignment (baseline reset)

Section 2 of `docs/hedit-design.md` was drafted before hica 0.49 shipped
user-facing effects. Two things need reconciling before we start M1:

1. **Effect naming.** hica 0.49 requires **PascalCase** effect names and
   snake_case op names (`effect Terminal { fun poll_event() : Event }`).
   The design doc uses lowercase `effect terminal { … }`. We update the
   doc as part of M1.
2. **Which effects are user-defined vs built-in in v1.** hica 0.49
   already exposes:
   - `<fsys>` via `read_file` / `write_file` — so `effect fs` in the
     design doc is redundant for v1.
   - `<console>` via `println` / `eprintln` — so debug output doesn't
     need a `Log` effect.
   - `get_env` / `set_env` / `get_args` — so `effect env` is redundant
     for v1 (HiLisp config stays in HiLisp — no need for a hica-side
     effect).
   - `exec` for external processes — so `effect process` can wait for a
     real async story to justify itself.

   The two effects worth carrying into v1 are **`Terminal`** (the
   killer app for effect-based testing — swap real ANSI I/O for
   scripted key streams) and **`Clipboard`** (nicely small,
   real-world, and cross-platform-messy — perfect handler-swap
   candidate). Everything else defers to a v2 pass or stays as
   built-ins.

The revised v1 effect surface is therefore:

| Effect | Ops | Real handler | Test handler |
|---|---|---|---|
| `Terminal` | `poll_event`, `render_frame`, `get_dimensions`, `set_cursor_style` | native ANSI / `std/term` | scripted event queue, sink render |
| `Clipboard` | `get_selection`, `set_selection` | OS clipboard (later; in-memory to start) | in-memory `var` |

`FileSystem` / `Process` / `Env` stay as **built-in** hica calls
(`<fsys>`, `<console>`, etc.) until a concrete use case justifies
wrapping them.

---

## Cross-cutting deliverables

Track their state here so we know what still needs backfilling.

| Artefact | Purpose | Grows through |
|---|---|---|
| `docs/hedit-design.md` §2 | Refreshed effect surface (PascalCase, drop `fs`/`process`/`env`) | M1 baseline, refined per milestone |
| `docs/hedit-design.md` §4 | Real handler examples using hica 0.49 syntax | M1 (Terminal), M3 (Clipboard) |
| `src/runtime.hc` | New — owns the `event_loop`, installs handlers | M1 baseline, M2 expand |
| `src/render.hc` | New — pure `render_editor_to_buffer` + `ScreenBuffer` | M2 |
| `tests/runtime_test.hc` | Headless-handler regression tests | M1 → M3 |
| `tests/render_test.hc` | Pure render tests | M2 |
| `README.md` §Status | One-line update per milestone | after each milestone |
| `docs/notes.md` | User-facing usage tips as behaviour lands | ongoing |

---

## Milestone map

| Milestone | Goal (one-line) | Effects touched |
|---|---|---|
| **M1** | Extract `event_loop` + install a `Terminal` handler; keep `handle_action` pure; ship a headless test-handler that scripts events | `Terminal` |
| **M2** | Add `ScreenBuffer` + pure `render_editor_to_buffer`; wire save-on-Ctrl-s using built-in `write_file`; render sink via `Terminal.render_frame` | `Terminal` |
| **M3** | Add `Clipboard` effect (in-memory handler first, native later); support Ctrl-c/Ctrl-v via `handle_action` reading from clipboard | `Terminal`, `Clipboard` |
| **M4** | HiLisp bridge: turn `(set …)` / `(get …)` / `(bind …)` into real builtins backed by handler-local `ConfigState`; load `~/.config/hedit/init.hl` at startup | (config bridge, no new effect) |
| **M5** *(stretch)* | Named-effect experiment: `spawn Buffer { … }` per open file, so per-buffer state (undo, cursors) lives inside its own handler | `Buffer` (spawned) |
| **M5.5** | Multi-buffer navigation ring (`NewBuffer`/`Next`/`Prev`/`CloseBuffer` + tabline) | (pure, no new effect) |
| **M6** | CLI arg parsing (`std/cli`) + wire `[FILE]` positional into a *real* `read_file` load — buffers stop being path-only stubs | (none — `<fsys>` only) |
| **M7** | Native `Terminal` handler: raw-mode tty, real keyboard decode, real ANSI render — replaces the M1 stub. **This is the milestone that makes hedit usable by an end user.** | `Terminal` (real handler) |
| **M8** | CLI polish for end users: `--config`/`--no-config`, `--tabsize`, `--readonly`, `+LINE:COL`; docs/README updated with a real quick-start | (none) |
| **M9** | "Save As" / `OpenFile` prompt: a minimal single-line input widget so a scratch buffer (`path: None`) can be saved for the first time, and an existing file can be opened without restarting hedit | (none — reuses `Terminal`/`<fsys>`) |
| **M10** | Usability polish: a discoverable help/keybindings overlay + a small theming system (configurable chrome colors via HiLisp `(set …)`) | (none — reuses `Terminal`) |

M6-M9 are kept in this same journal (the M5 note above about opening a
new journal never happened in practice — M5.5 landed here too, so we
keep one running journal rather than fragment the log).

---

## Files to read per milestone (context-window budget)

Always start each session by (re-)reading:

- `docs/hedit-design.md` (the design — skim the sections relevant to
  the milestone; do not re-read end-to-end).
- `docs/effects-journal.md` (this file — for prior Log/Reflection).
- `hica-ecosystem/hica/docs/effects.md` (the language-level effects
  cheat sheet — the milestone's syntax reference).

Milestone-specific reading (kept intentionally short):

| Milestone | Read (in order) | Grep for (don't read whole file) |
|-----------|-----------------|----------------------------------|
| **M1** | `src/main.hc`, `src/actions.hc`, `src/types.hc`, `src/model.hc`; hica `examples/effects/hello-effect.hc` and `examples/effects/counter.hc` | `handle` in the hica examples for the exact syntax we're about to adopt |
| **M2** | `src/actions.hc`, hica `docs/standard-library.md` for `write_file` | `render` in hica examples/learn for any prior TUI-style patterns |
| **M3** | `src/actions.hc`, `src/types.hc`; hica `examples/effects/buffer.hc` for stateful handler shape | `with var` in effects docs for state-binding syntax |
| **M4** | `src/script/hilisp_host.hc`, `tests/hilisp_host_test.hc`; hica `docs/effects.md` §handler-local state | `with var` (config as handler-local state) |
| **M5** | `hica-ecosystem/hica/documentation/named-effects-design.md`, hica `examples/effects/two-counters.hc`, `counter-pool.hc` | `spawn`, `ref<` |

**Anti-patterns to avoid** (inherited from the named-effects journal):

- ❌ Reading hica's compiler internals (`src/emit/codegen.kk`, etc.) —
  we're a *user* of hica, not a hica contributor here.
- ❌ Re-reading a file already opened in the same session.
- ❌ Reading "just in case."

---

## Milestone M1 — Extract `event_loop` + install `Terminal` handler

### Goal

The core editor step (`handle_action`) stays 100% pure. A new
`src/runtime.hc` owns the impure surface: it declares `effect
Terminal`, defines an `event_loop(state)` that calls `poll_event()` /
`render_frame(...)` / `get_dimensions()`, and offers **two** installable
handlers:

1. **Headless test handler** — scripts events out of a `var` queue,
   sinks render calls, returns a canned size. Used by
   `tests/runtime_test.hc`.
2. **Native handler stub** — for M1 this is a placeholder that reads
   a single hard-coded event and quits; it exists to prove the
   handler-arm shape compiles under a real `println`-style backend.
   Real ANSI wiring lands in a later pass.

`src/main.hc` is trimmed to: pick a handler, install it, call
`event_loop(init_editor(None))`. Nothing else.

**Exit criteria:**

- `hica check src/main.hc` clean, effect row includes `<Terminal,
  console>`.
- `hica build` succeeds.
- `hica test tests/actions_test.hc` — still 8/8 green (no regression).
- `hica test tests/hilisp_host_test.hc` — still 9/9 green (no regression).
- `hica test tests/runtime_test.hc` — at least 3 tests, all green:
  - "scripted Ctrl-q terminates the loop immediately",
  - "scripted keys 'h','i',Ctrl-q leave buffer as [\"hi\"]",
  - "handler runs render_frame at least once per iteration
    (spy-counter reaches ≥ 1)".
- `hica run src/main.hc` prints the same shape as today (or a very
  small transcript from the native stub handler) — no runtime crash.
- `docs/hedit-design.md` §2.1 rewritten to hica 0.49 syntax
  (`effect Terminal`, PascalCase, `fun` ops, `resume`-implicit body).
- `docs/hedit-design.md` §2 introduction updated to say `fs`/`process`/
  `env` are *out* of v1 (see "Design-doc alignment" above).
- `README.md` Status block flips "Core editor / event loop / effects"
  from ⏳ to 🚧.

### Plan

- [x] **Docs refresh (before code).** Rewrite `docs/hedit-design.md`
  §2 baseline: PascalCase effects, `Terminal` + `Clipboard` are the
  only v1 effects, drop `fs`/`process`/`env` (referenced as built-ins
  instead). This is what M1 targets.
- [x] **`src/runtime.hc` (new).** Declare `effect Terminal` with the
  four ops from the design doc §2.1 (PascalCase now). Define
  `ScreenBuffer` (minimal — width/height plus a `list<string>` of
  rendered lines; M2 upgrades to full cells). Define
  `pub fun event_loop(state: EditorState) : <Terminal> EditorState`
  that:
  - queries `get_dimensions()` once per tick (M2 will use this to
    resize),
  - calls `render_frame(build_screen(state))`,
  - `poll_event()` for one event,
  - delegates to `handle_action` (pure),
  - short-circuits when `state.should_quit == true`.
  `build_screen` for M1 is a trivial helper that dumps `state.buffer.lines`
  into a `ScreenBuffer` with the current size — a real renderer arrives
  in M2.
- [x] **`src/main.hc`.** Trims to: `let s0 = init_editor(None); handle
  Terminal { …native stub arms… } in { event_loop(s0) }`. Unblocked
  by hica 0.49.2 (cross-module effect propagation) + the `pub effect
  Terminal` fix documented in `docs/hica-issues.md` Issue #3.
- [x] **`tests/runtime_test.hc` (new).** Four tests using a headless
  handler with `with var events = […], var render_count = 0`. All
  green under `hica test tests/runtime_test.hc`.

- [ ] **Named-effect NOT used in M1.** Even if `Terminal` looks like it
  wants to be spawned, M1 uses plain `handle … in { … }`. Spawn is
  reserved for M5.
- [x] **`hica fmt --check` + `hica analyse` on every new/edited file.**
  `src/runtime.hc` — fmt ok, analyse 100/100. `src/main.hc` — fmt ok.
  Docs pass through untouched.
- [x] **Journal.** Log filled in with the blocker + handoff (below).
  Reflection deferred until the checker can see cross-module effects
  and M1 actually goes green end-to-end.


### Log

**Session 1 — 2026-08-16.** Held to the "small edits, frequent checks"
rule. Sequence of edits:

1. Refreshed `docs/hedit-design.md` §2 to hica 0.49 syntax (PascalCase
   effects, drop `fs`/`process`/`env`, note the 2-effect v1 surface).
2. Refreshed §4 handler examples: dropped the pre-0.49 `with handler …
   in` syntax in favour of `handle Terminal { arms } in { body }`;
   documented the M1 native *stub* vs the M2 real ANSI handler, and
   added a sketch of the headless test handler using `with var events
   = […], var render_count = 0`.
3. Created `src/runtime.hc` with:
   - `pub struct ScreenBuffer { width, height, lines: list<string> }`
     (deliberately minimal — M2 upgrades to cells).
   - `pub type CursorStyle { Block, Bar, Underscore }`.
   - `effect Terminal { poll_event, render_frame, get_dimensions,
     set_cursor_style }` — no `pub` keyword on the effect (hica 0.49
     rejects that; effects are always module-visible under the current
     visibility rules).
   - `pub fun build_screen(state, dims) : ScreenBuffer` — trivial pass
     -through, real render is M2.
   - `pub fun event_loop(state: EditorState) : <Terminal> EditorState`
     — recursive, short-circuits on `state.should_quit`, updates
     `screen_size` from `get_dimensions()` each tick.
4. `hica check src/runtime.hc` — ✅ `ok (2 declarations, 0 errors)
   [<Terminal>]`.

**Then the wall.** Wrote `src/main.hc` with the M1-shape native stub
handler, `import "runtime"` at the top. `hica check` errored with:

```
error[src/main.hc:17:15]: unknown effect: 'Terminal'
 17 |   let final = handle Terminal { … }
```

Confirmed against hica's own docs / journals:

- `hica/documentation/effects-design.md` §12 Q1 flags "cross-module
  effect identity" as a deferred invariant ("an effect must be defined
  exactly once in a module graph; imports refer to that definition —
  enforced by the checker at module load").
- `hica/documentation/effects-journal.md` M1 reflection: "imports
  currently carry `decls`, `structs`, `types` — but not `effects`.
  `compile-imports-impl` will need to collect and merge them."

So the design's separation-of-concerns (`event_loop` in `runtime.hc`,
handlers at the call sites in `main.hc` and `runtime_test.hc`) cannot
be realised on hica 0.49 without either duplicating the `effect
Terminal { … }` in every consumer (which the design doc §12 Q1
explicitly says won't unify) or collapsing the whole thing into one
file.

**Decision (Option C from the ask-followup).** File the blocker
upstream as `docs/hica-issues.md` §Issue 3, and *pause* M1 rather than
degrade the design to work around it. `src/runtime.hc` is committed in
its intended shape and passes `hica check src/runtime.hc` cleanly (row
`[<Terminal>]`). `src/main.hc` is left in its pre-M1 synthetic shape
(imports `runtime` so we exercise the merge path — the import
type-checks even though the effect doesn't cross — plus a comment
pointing at the issue). No `tests/runtime_test.hc` is created; adding
it now would either duplicate the effect (silently breaks on unify) or
depend on the same blocker.

**Current green surface (2026-08-16):**

- `hica check src/main.hc` → ok, `[<console>]` (unchanged from before M1).
- `hica check src/runtime.hc` → ok, `[<Terminal>]` (new).
- `hica build` → succeeds, `src/main` binary generated.
- `hica run src/main.hc` → prints the synthetic transcript, exits 0.
- `hica test tests/actions_test.hc` → 8/8 green (no regression).
- `hica test tests/hilisp_host_test.hc` → 9/9 green (no regression).
- `hica fmt --check src/runtime.hc` / `src/main.hc` → both ok.
- `hica analyse src/runtime.hc` → 100/100, zero issues.

**Exit criteria status:**

- ✅ `docs/hedit-design.md` §2 and §4 rewritten to hica 0.49 syntax
  (PascalCase, `fun` ops, `handle E { arms } in { body }`, `fs`/
  `process`/`env` demoted to built-ins).
- ✅ `src/runtime.hc` exists with `effect Terminal`, `ScreenBuffer`,
  `build_screen`, `event_loop`. Green on its own.
- ⏸ `hica check src/main.hc` effect row **still `[<console>]`**, not
  `[<Terminal, console>]` — waiting on hica issue #3.
- ⏸ `tests/runtime_test.hc` **not yet created** — same reason.
- ⏸ `README.md` Status line **not yet flipped** — flip when the row
  actually shows `<Terminal>` end-to-end.

**Handoff.** Next session, once hica ships the cross-module effect
merge:

1. Rewrite `src/main.hc` to the shape sketched in
   `docs/hedit-design.md` §4.1 (native stub handler + `event_loop(s0)`).
2. Add `tests/runtime_test.hc` with the three headless-handler tests
   (`with var events = […], var render_count = 0`).
3. Return to this Log and write the Reflection.
4. Flip the README status.

**Session 2 — 2026-08-16 (evening).** hica 0.49.2 shipped
cross-module effect propagation. Unblock pass:

1. Rewrote `src/main.hc` to the M1 shape (native stub Terminal
   handler → `event_loop(init_editor(None))`). `hica check` → ok.
2. `hica build` → **failed** with `Core.Parse.envQualify: unable to
   expand name: types/event` and `identifier hc_poll_event cannot be
   found`. The checker was happy, the emitter was not — the effect
   decl in `src/runtime.hc` was still module-private under codegen.
3. Fix: add `pub` to the effect declaration
   (`pub effect Terminal { … }`). `hica build` → green immediately;
   `hica run src/main.hc` prints the M1 stub transcript and exits 0.
   Updated `docs/hica-issues.md` Issue #3 with the `pub`-on-effect
   caveat as a follow-up wishlist item for hica.
4. Added `tests/runtime_test.hc` with four tests. First run hit two
   surprises:
   - **Escaped quotes in `test "…"` titles break Koka codegen.**
     `test "scripted keys 'h','i',Ctrl-q leave buffer as [\"hi\"]"`
     emitted `println("… as [\\"hi\\"]")` in the generated `.kk`,
     which Koka's parser rejects as invalid syntax. Renamed to
     `"scripted keys h i Ctrl-q leave buffer as [hi]"`. Worth filing
     upstream (should either escape properly or reject at hica-parse
     time, not lower into Koka).
   - **Outer `var seen` can't be assigned from inside a handler
     arm.** First cut used `var seen = 0` outside the `handle`, then
     `seen := render_count` inside `render_frame(_buf)`. Koka
     rejected it: "abstract type(s) escape into the context …
     `<local<$h>,div,exn|_e>`". Handler-local state is scoped to the
     `handle … in { … }` expression, so we must extract observations
     by *returning* them from the `in` block. Refactored test 3 to
     `let (final, renders) = handle Terminal { … } with var
     render_count = 0 in { let s = event_loop(init_editor(None)); (s,
     render_count) }`. Passes cleanly. Good learning: the escape rule
     from the effects docs applies to handler-local state, not just
     to spawned refs.
5. `hica fmt tests/runtime_test.hc` reformatted whitespace once, then
   `--check` green on every touched `.hc`. Analyse 100/100.
6. All test suites: 8/8 + 9/9 + 4/4 = **21/21** green.
7. **Late surprise: module-name collision with HiLisp.** After the
   submodule bump (`git submodule update --recursive --remote` pulled
   hica-lisp v0.9.0), `hica test tests/hilisp_host_test.hc` started
   failing with `identifier hc_env_set_host cannot be found` inside
   `lib/hilisp/src/builtins.kk`. Diagnosis: hedit's `src/types.hc`
   compiles to Koka `module types`, and HiLisp's `src/types.hc`
   *also* compiles to `module types`. Koka sees two modules with the
   same name in the graph and the wrong one wins. Fix: renamed
   hedit's `src/types.hc` → `src/keys.hc` (Koka module `keys`) and
   updated the three `import "types"` → `import "keys"` sites +
   two `import "../src/types"` → `import "../src/keys"` in the test
   files. After a `hica clean`, all three suites went green: 8/8 +
   9/9 + 4/4 = **21/21**. Worth noting upstream — a namespaced
   `import "hedit/types"` or a `@koka { module_prefix = "hedit_" }`
   knob in `hica.hml` would prevent this class of collision
   automatically when consuming submodules.


**Exit criteria (final):**

- ✅ `hica check src/main.hc` clean; effect row is `[<console>]`
  (the `handle Terminal { … } in { … }` discharges Terminal fully,
  so main() itself only carries `<console>` from its `println`s).
  The intended `<Terminal, console>` shape would surface on a
  function that calls Terminal ops without handling them — which
  `event_loop` does (`hica check src/runtime.hc` → `[<Terminal>]`).
- ✅ `hica build` succeeds.
- ✅ 8/8 actions_test, 9/9 hilisp_host_test, 4/4 runtime_test.
- ✅ `hica run src/main.hc` — stub transcript, exit 0.
- ✅ `hica fmt --check` + `hica analyse` green on all touched files.
- ✅ Docs (hedit-design §2/§4, hica-issues #3) updated in-milestone.
- ✅ README Status line flipped from ⏳ to 🚧 with an "M1 green" note.

### Reflection

**What changed vs the plan.** The blocker in session 1 (hica issue
#3) resolved between sessions, so the M1 code that was gated on it
landed clean in one pass — plus the small `pub`-on-effect fix and
two test-file quirks the plan didn't anticipate. Everything else went
exactly as spec'd.

**What to carry forward:**

- **`pub effect X { … }` is mandatory for any effect a library
  module exports.** Bare `effect X { … }` type-checks but codegens
  as module-private; consumers hit a Koka linker error, not a
  friendly hica diagnostic. This should be the *first* thing we
  check whenever an effect gets extracted into a shared module.
- **Handler-local state is truly scoped.** You cannot smuggle a spy
  variable out of a `handle E { … } in { body }` — the escape rule
  applies. Return the observation from the `in` block as part of a
  tuple (`(result, spy)`) instead. This pattern will repeat any time
  we want to assert on internals; the test-3 shape is a good
  template.
- **Test titles must be Koka-safe strings.** Backslash-escaped
  quotes in `test "…"` reach codegen unfiltered and break Koka's
  parser. Keep titles ASCII-punctuation-lite (no `\"`, no square
  brackets around embedded quotes). File this upstream when the
  bandwidth's there.

**What to change in the design doc:**

- Nothing structural. The two-file split (runtime.hc for the effect
  + loop, main.hc for the handler) is exactly what §4.1 sketched;
  the `pub` requirement is a hica-language detail, not a design
  concern.
- §4.2's "with var events = […], var render_count = 0" sketch
  should note that render-count observations must be returned from
  the `in` block, not assigned into an outer `var`. Small tweak;
  can slot into M2 alongside the ScreenBuffer upgrade.

**Ready for M2.** All exit criteria for M1 are green, the ground
rules held (small edits, no regressions, docs updated in-milestone),
and the render/save workstream can start against a stable
`event_loop` foundation.


---

## Milestone M2 — Rendering + save via built-in `write_file`


### Goal

`build_screen` gains a real implementation: it materialises a
`ScreenBuffer` from the active buffer's lines + cursor position, ready
for the handler to flush. `handle_action` learns Ctrl-s and calls
built-in `write_file` (giving the enclosing function `<fsys, Terminal>`
in its effect row).

**Exit criteria (draft — refined when M1 lands):**

- `src/render.hc` with `pub fun render_editor_to_buffer(state) :
  ScreenBuffer` — pure, tested.
- `handle_action` extended for Ctrl-s: if the buffer has a path, call
  `write_file`, mark clean, set a status message; if not, set an
  error status message.
- `tests/render_test.hc` — at least 3 render tests (empty buffer,
  single line, multi-line with cursor on last line).
- `tests/runtime_test.hc` — new test: Ctrl-s on a buffer with a
  temp path actually writes the file (uses `read_file` afterwards
  to assert content).
- Native handler stub in `src/main.hc` updated to actually flush the
  `ScreenBuffer` to stdout with ANSI positioning — good enough to
  eyeball behaviour.
- `docs/hedit-design.md` §4.1 rewritten with the M1 + M2 shape.

### Plan

*(plan section intentionally brief — M2 plan was drafted as exit criteria above)*

Key structural decision made during implementation: **Ctrl-s save lives
in `event_loop` (runtime.hc), NOT in `handle_action` (actions.hc)**,
keeping `handle_action` 100% pure with its `: EditorState` return-type
annotation. This matches `docs/hedit-design.md` §5's event-loop dispatch
sketch and avoids a downstream type-inference issue (see Log below).
The exit criteria wording ("handle_action extended for Ctrl-s") is
superseded by this design decision, noted in the Reflection.

### Log

**Session 1 — 2026-08-17.** Sequence of edits, in order:

1. Moved `ScreenBuffer` and `CursorStyle` from `src/runtime.hc` to
   `src/model.hc`. Reason: `render.hc` needs `ScreenBuffer` but
   `runtime.hc` also imports `render.hc`; keeping both types in
   `model.hc` (pure data) breaks the circular dependency. Both files
   import `model` already.

2. Created `src/render.hc` with `render_editor_to_buffer`:
   - Two private helpers: `fit_to_width` (truncate line to width) and
     `take_or_pad` (take first n rows, fill with "~"). The `else {
     match xs { … } }` fix was immediately needed — `else match xs {
     … }` without braces is a parse error ("expected {, got match").
   - Layout: rows 0..(h-2) are content lines (or "~"), row h-1 is the
     status line (path + dirty flag, or explicit status_message).
   - `hica check src/render.hc` → `[pure]`, 100/100 analyse score.

3. Rewrote `src/runtime.hc`: removed the old ScreenBuffer/CursorStyle
   struct declarations (moved to model), removed `build_screen`,
   added `import "render"`, updated `event_loop` to call
   `render_editor_to_buffer`.

4. Initial `event_loop` annotation `: <Terminal> EditorState` caused
   the Koka build to fail ("effects do not match: inferred <fsys>").
   Dropped the annotation entirely per user-memory rule ("functions
   that call write_file must NOT have explicit return-type annotations
   — Koka infers the full effect row"). The `<Terminal>` annotation
   alone was too narrow; the full row is `<Terminal, fsys, div>`.

5. Updated `src/actions.hc` (first attempt) to add `save_buffer` +
   extend `handle_action` with Ctrl-s. The checker showed `[<fsys>]`
   at module level. The build succeeded. BUT: the `handle_action`
   return-type annotation `: EditorState` had to be removed (effectful
   function), which triggered the **`hc_lines` prelude collision**
   (Issue 4 in `docs/hica-issues.md`).

   Root cause: when a `let` binding's type is not pinned (no annotation,
   no downstream constraint), hica emits `hc_lines(var)` as a
   free-function call instead of `var.lines`. The prelude's
   `hc_lines(s : string)` clashes, causing Koka to infer the receiver as
   `string` rather than `TextBuffer`. Result: every `actions_test.hc`
   and `runtime_test.hc` test that accessed `.buffer.lines` on an
   unannotated variable failed with "inferred type: string, expected
   type: textbuffer".

6. **Design pivot.** Moved Ctrl-s out of `handle_action` (restoring it
   to pure with `: EditorState`) and into `event_loop` in `runtime.hc`.
   This matches the design doc §5 event-loop dispatch pattern AND
   eliminates the type-inference problem. `handle_action` retains its
   `: EditorState` annotation; `event_loop` is the only function that
   carries `<fsys>`.

7. Added `save_buffer` as a private helper in `runtime.hc`, split into
   `apply_write_result` + `save_buffer` to eliminate the nested-match
   HIGH warning from `hica analyse`. Final analyse score: 100/100.

8. Created `tests/render_test.hc` with four tests (height, first
   content row, status with dirty flag, explicit status message). All
   4/4 green on first run.

9. Updated `tests/runtime_test.hc` (new test 5: Ctrl-s writes file):
   - Tests 1, 2, 3 still needed explicit `: EditorState` annotations
     (see Issue 4 workaround) to avoid the `hc_lines` collision even
     after `handle_action` was restored to pure. The `let final:
     EditorState = handle Terminal { … }` pattern pins the type and
     makes Koka use `.lines` instead of `hc_lines(…)`.
   - Test 3 restructured to `let pair: (EditorState, int) = …; let
     final = pair.0; let renders = pair.1` to carry the type through
     tuple access.
   - Test 5 (`ctrl-s on a named buffer writes content to disk`) uses
     `read_file(tmp_path)` to verify the write. This test probes the
     known open bug "BUG (OPEN): `read_file` in test mode doesn't emit
     `import std/os/path`". In practice the test compiled and passed
     (5/5 green), so the bug may be fixed or the repro path is
     different in newer hica.

10. Updated `src/main.hc` render_frame arm: now calls
    `foreach(buf.lines, (l) => println(l))` — real line-by-line dump
    to stdout. Verified `hica run src/main.hc` prints 24 rows (1 empty
    content row, 22 "~" rows, "[No Name]" status).

11. Ran `hica fmt --check` + `hica analyse` on all touched files:
    100/100 across the board after the `apply_write_result` split.

**Exit criteria status (final):**

- ✅ `src/render.hc` with `pub fun render_editor_to_buffer` — pure,
  4/4 render tests green.
- ✅ `handle_action` remains pure (Ctrl-s moved to `event_loop`). This
  deviates from the exit-criteria wording ("handle_action extended for
  Ctrl-s") but matches the design doc §5 and is architecturally
  superior; documented in Reflection below.
- ✅ `tests/render_test.hc` — 4 tests, all green.
- ✅ `tests/runtime_test.hc` test 5: Ctrl-s writes + `read_file`
  verify. Green.
- ✅ `src/main.hc` `render_frame` arm flushes `ScreenBuffer.lines` to
  stdout via `foreach`. `hica run` shows rendered output.
- ✅ All test suites: 8/8 + 9/9 + 4/4 + 5/5 = **26/26** green.
- ✅ `hica fmt --check` + `hica analyse` 100/100 on all touched files.
- ✅ `docs/hica-issues.md` updated with Issue 4 (`hc_lines` collision).

### Reflection

**What changed vs the plan.**

The M2 exit criteria said "extend `handle_action` for Ctrl-s". We
moved it to `event_loop` instead. This was forced by a cascade:
removing the `: EditorState` annotation from `handle_action`
(required when `write_file` is called) triggers the `hc_lines` prelude
collision, which breaks every test that reads `.buffer.lines` from an
unannotated variable. The design doc §5 always showed Ctrl-s in the
event-loop dispatch, not in `handle_action`; the exit criteria wording
was a drafting slip. The resulting architecture is cleaner.

**What to carry forward.**

- **`handle_action` stays pure.** This is the correct invariant. Any
  new key binding that needs file I/O (Ctrl-n new file, Ctrl-o open
  file) should be handled in `event_loop`, not in `handle_action`.
  `handle_action` is the pure state-update core; `event_loop` is the
  effectful shell.
- **`hc_lines` prelude collision (Issue 4).** When accessing
  `EditorState.buffer.lines` through an unannotated variable, always
  annotate the binding with `: EditorState`. The pattern `let final:
  EditorState = handle Terminal { … }` and `let pair: (EditorState,
  int) = …; let final = pair.0` are the established workarounds.
  File this with hica upstream (already in `docs/hica-issues.md`).
- **`else { match … { } }` requires braces.** `else match xs { … }`
  is a parse error — wrap in `else { match xs { … } }`. Record in
  SKILL.md.
- **`take_or_pad` pattern.** Reusable recursive helper for "take N
  from list, pad with default". Worth promoting to the hedit prelude
  or a `src/list_utils.hc` when we need it again in M3+.

**What to change in the design doc.**

- §5 is already consistent with the final shape (Ctrl-s in event-loop).
  No change needed.
- §4.2 note: "the `in { … }` block type must be annotated (`: T`)
  when the result variable will be used for `.buffer.lines` access".
  Small addition; can be batched with the next docs touch.

**Ready for M3.** All M2 exit criteria met (with the design-doc-
consistent deviation noted above). The render + save workstream is
stable; `Clipboard` effect can be layered on top.

---

## Pre-M3 cleanup pass (2026-08-17, session 2)

Before opening M3, a short cleanup pass driven by a review of M2
against the design doc + user's explicit requirement that "no
keybindings should be hard-coded in the codebase; users should be
able to remap via a HiLisp `.hl` file". Rationale for doing this now
(as opposed to inside M4): every subsequent action we add (`Copy`,
`Paste`, `Open`, `Close`, …) would otherwise land as another
hard-coded chord match, and unwinding that later means changing every
call site.

**What we changed:**

1. **`Action` enum + `KeyBindings` alist in `src/model.hc`.**
   Every editor op is now a named `Action` (`Quit`, `Save`,
   `Insert(c)`, `Resize(w, h)`, `Ignore`). `KeyBindings =
   list<(KeyChord, Action)>` (typed inline — hica has no `pub type
   Alias = …` yet, hence the repetition at every use site).
   `default_bindings()` seeds Ctrl-q → Quit, Ctrl-s → Save. Every
   `EditorState` now carries a `Config` (M4 will grow this beyond
   bindings).
2. **`actions.hc` split into `resolve_action` + `apply_action`.**
   The old `handle_action` becomes a thin `apply_action(state,
   resolve_action(state, evt))` combinator — kept as a convenience
   for pure callers (all tests). `resolve_action` consults
   `state.config.bindings`; there is **no** `if c == 'q'` branch
   anywhere in the dispatcher.
3. **`event_loop` in `runtime.hc` matches on `Action`, not on the
   raw event.** Only effectful variants (`Save`) have an inline
   arm; everything else falls through to `apply_action`. That
   preserves the M2 invariant (`handle_action` stays pure) *and*
   fixes the design-vs-code inconsistency where Ctrl-s and Ctrl-q
   dispatch lived in two different files.
4. **`save_buffer` writes with a trailing newline.** `join(lines,
   "\n") + "\n"` — POSIX-friendly, and `tests/runtime_test.hc`
   test 5 was updated to assert `Ok("hi\n")` rather than `Ok("hi")`.
5. **5 new tests in `actions_test.hc`.** Every branch of
   `resolve_action` (`Quit`, `Save`, `Ignore`, `Insert`, plus a
   custom-bindings override that swaps Ctrl-x → Quit + Ctrl-q →
   Ignore) is now guarded. Total: 13/13 actions, 9/9 hilisp_host,
   4/4 render, 5/5 runtime = **31/31 green**.
6. **Doc alignment.** `docs/hedit-design.md`:
   - §5 rewritten to hica 0.49 syntax with the new
     `resolve_action` / `apply_action` split;
   - §6 feature-validation matrix refreshed (real hedit subsystems,
     PascalCase effect names, drop `with handler` mention);
   - §7.3 architecture diagram fixed (`keys.hc` not `types.hc`,
     `render.hc`/`runtime.hc` shown, only `Terminal` + `Clipboard`
     as v1 user-defined effects);
   - §7.7 rewritten so `ConfigState.bindings` is the *single source
     of truth* (no more "before the hard-coded switch" wording).
   - New `docs/notes.md` — a user-facing living reference (default
     bindings, save semantics, known ASCII-truncation limitation
     in `render.hc`).
   - README.md Status line updated (removed misleading "M3+" ANSI
     phrasing, called out 31/31 test count + config-driven bindings).

**What we deliberately did NOT do (defers to M4):**

- No HiLisp bridge for `(bind …)` yet. Bindings are pure hica
  values today; M4 will parse an `init.hl`, resolve symbols to
  `Action` variants, and merge with `default_bindings()`. The
  contract with hica (the `Action` enum, the `KeyChord` key, the
  `EditorState.config.bindings` field) is stable and won't need to
  churn again in M4.
- No `Copy` / `Paste` `Action` variants yet — those land with the
  `Clipboard` effect in M3 alongside the arms in `event_loop`.
- No native ANSI positioning in the `render_frame` handler — still
  a line-by-line `println` dump for the stub.

**Green surface after the cleanup:**

- `hica check` clean on every module (`src/main.hc` [<console>],
  `src/runtime.hc` [<fsys, Terminal>], every other file pure).
- `hica build` succeeds; `hica run src/main.hc` prints the stub
  transcript.
- 13 actions + 9 hilisp_host + 4 render + 5 runtime = **31/31 tests**
  green.
- `hica fmt --check` + `hica analyse` 100/100 on all edited files.

**What to carry forward:**

- **Never spell out `list<(K, V)>` twice — inline the alist type at
  every use site.** hica 0.49 doesn't have `pub type Alias = …`,
  and the workaround (a `pub type KeyBindings { … }` wrapper enum)
  costs more ceremony than the duplication. If aliases land upstream
  we revisit.
- **Test 5's tmp file needs cleanup between runs.** After bumping the
  save format (trailing `\n`), the stale `/tmp/hedit_test_m2_save.txt`
  from the previous test run caused the assertion to fail silently
  until we `rm -f` it. Consider a hedit-specific `tmp_test_path()`
  helper that uses a fresh dir per run.
- **`Action` is a stable protocol.** Everything downstream (HiLisp
  `(bind …)` in M4, plugin hooks in v2+) speaks `Action` symbols,
  not keystroke strings. Growing the enum is a compatible change
  (add a variant, add an arm), shrinking it is not — so add
  liberally but never remove.


---

## Milestone M3 — `Clipboard` effect

### Goal

`effect Clipboard { fun get_selection() : string; fun set_selection(s:
string) }` added. `event_loop` learns Ctrl-c / Ctrl-v (copy the
current line, paste at cursor — simplified for v1) via the same
`Action`-dispatch pattern M2 established for `Save`. Two handlers:

1. In-memory (`with var buf = ""`) for tests.
2. Real OS handler for production (stubbed to in-memory in M3; real
   `pbcopy`/`xclip`/wl-copy call-outs land in a follow-up).

**Exit criteria (as revised during M3):**

- `src/runtime.hc` grows a second `pub effect Clipboard { … }`
  declaration and Copy/Paste arms inside `event_loop`'s Action
  dispatch. Effect row becomes `<fsys, Terminal, Clipboard>`.
- `src/actions.hc` grows two pure helpers `current_line` and
  `paste_text`; `apply_action` learns no-op arms for `Copy` / `Paste`
  so the pure surface stays total (effectful branches live in
  `event_loop`).
- `src/model.hc` — Ctrl-c → Copy, Ctrl-v → Paste added to
  `default_bindings()`; two new variants added to `Action`.
- `src/main.hc` — in-memory Clipboard handler stacked outside the
  Terminal handler; `hica run` demonstrates a round-trip.
- `tests/actions_test.hc` — 6 new pure-unit tests covering
  `resolve_action → Copy/Paste`, `apply_action` no-op behaviour on
  both, and pure-helper coverage for `current_line` + `paste_text`.
- `tests/runtime_test.hc` — 3 new integration tests (Ctrl-c, Ctrl-v,
  round-trip) driving the full Terminal + Clipboard handler stack.

### Plan

- [x] **Docs alignment.** Reread §2.3 (Clipboard) + §4.2 (headless
  handler) of `docs/hedit-design.md`; skim
  `hica-ecosystem/hica/examples/effects/buffer.hc` for the
  stateful-handler shape. No design changes expected.
- [x] **Extend `Action` + defaults.** Add `Copy` / `Paste` to
  `src/model.hc`; add `(KeyChord{Ctrl,'c'}, Copy)` and
  `(KeyChord{Ctrl,'v'}, Paste)` to `default_bindings()`.
- [x] **Pure helpers in `actions.hc`.** `current_line(state) :
  string` (what Copy hands to `set_selection`); `paste_text(state,
  text) : EditorState` (what Paste applies after `get_selection`).
  Update `apply_action` to no-op on Copy/Paste.
- [x] **`pub effect Clipboard` + `event_loop` arms in `runtime.hc`.**
  Copy arm calls `set_selection(current_line(state))`, sets status;
  Paste arm calls `paste_text(state, get_selection())`. Effect row
  becomes `<fsys, Terminal, Clipboard>`.
- [x] **`src/main.hc`.** Wrap the existing Terminal handler in
  `handle Clipboard { … } with var clip = "" in { … }`.
- [x] **Tests.** Extend `actions_test.hc` with 6 pure tests. Add 3
  integration tests to `runtime_test.hc` for the Ctrl-c/Ctrl-v
  round-trip.
- [x] **Docs.** Update `README.md` Status line, `docs/notes.md`
  (Copy/Paste semantics), and this journal's Log/Reflection.

### Log

**Session 1 — 2026-08-17.** Sequence of edits, in order:

1. Extended `Action` enum with `Copy` / `Paste` in `src/model.hc`;
   added the two chord defaults. `apply_action` in `src/actions.hc`
   grew two no-op arms and a comment explaining the effectful dispatch
   lives in `event_loop`. Everything green.
2. Added pure helpers `current_line` and `paste_text` in
   `src/actions.hc` — same shape as `insert_char`, no multi-line
   splitting on `\n` yet, cursor bookkeeping trivially additive.
3. Declared `pub effect Clipboard { … }` in `src/runtime.hc` and
   added Copy / Paste arms to `event_loop`'s `match action { … }`.
   `hica check src/runtime.hc` → `[<fsys, Terminal, Clipboard>]`.
4. `src/main.hc`: wrapped the existing Terminal handler in an
   in-memory Clipboard handler (`with var clip = ""`). `hica run
   src/main.hc` prints the M2 stub transcript, exit 0.
5. Added 6 pure unit tests to `tests/actions_test.hc`. All green,
   19/19.

**The wall (session 1).** Adding 3 integration tests to
`tests/runtime_test.hc` immediately failed at build:

```
(1, 0): build error: there are unhandled effects for the main expression
   inferred effect : <st<global>,runtime/clipboard,console/console,div,fsys,ndet,net,ui>
   unhandled effect: runtime/clipboard
```

Debugging surfaced hica bug (`docs/hica-issues.md` **Issue #5**):

- **Shape A** — inline nested `handle Clipboard { … } in { handle
  Terminal { … } in { event_loop(…) } }`: fails.
- **Shape B** — extract the whole handler stack into a `pub fun
  run_scripted(…)` inside `src/runtime.hc` itself: fails identically.
- **Shape C — the real bug** — the moment `event_loop`'s inferred row
  carries `<Clipboard>`, **every** pre-existing test that installs
  only a `Terminal` handler around `event_loop` also fails with
  `unhandled effect: runtime/clipboard`. Even the M1/M2 tests that
  don't script any Ctrl-c/Ctrl-v.

Standalone single-file probes with the same nested-handler shape
compile and run cleanly, so the trigger is specifically the
cross-module `pub fun` + test-mode `main`. hica's test-mode `main`
wraps each test body in `try({ hctest_() })` — and Koka's `try`
discharges only `exn`, not user effects, so any residual
`<Clipboard>` bubbles all the way out.

**Decision.** File Issue #5 upstream with shape A/B/C reproductions.
Since hica-side work is ongoing, park M3 here (partial-green: 19+9+4
tests pass in the pure suites, runtime_test blocked).

**Session 2 — same day.** hica shipped "auto-install panic handlers
in test-mode `main`" (the fix landed as 0.49.3, was reverted, then
re-landed as 0.49.4 with the panic-emitting variant kept as the
stable release) — exactly the fix sketched as option 3 in the
Issue #5 write-up. Re-added the three integration tests to
`tests/runtime_test.hc` (Ctrl-c copy, Ctrl-v paste, copy → paste
round-trip), all with the tuple-return shape (`let pair:
(EditorState, string) = handle Clipboard { … } in { let inner:
EditorState = handle Terminal { … } in { event_loop(…) }; (inner,
clip) }`). Cleared build cache, reran under the fixed compiler at
`/Users/claes.adamsson/cladam/code/hica-ecosystem/hica/hica`: 8/8
green.

**Final green surface (2026-08-17):**

- `hica check src/main.hc` → ok, `[<console>]`.
- `hica check src/runtime.hc` → ok, `[<fsys, Terminal, Clipboard>]`.
- `hica build` → succeeds, `src/main` binary generated.
- `hica run src/main.hc` → prints the stub transcript, exit 0.
- `hica test tests/actions_test.hc` → **19/19** green.
- `hica test tests/hilisp_host_test.hc` → 9/9 green.
- `hica test tests/render_test.hc` → 4/4 green.
- `hica test tests/runtime_test.hc` → **8/8** green (5 pre-existing +
  3 Clipboard integration).
- `hica fmt --check` clean on every touched file.
- `hica analyse` 100/100 on every `src/` file.

Grand total: **40/40 tests green.**

**Exit criteria (final):**

- ✅ `pub effect Clipboard` declared in `src/runtime.hc`.
- ✅ Copy/Paste `Action` variants + defaults in `src/model.hc`.
- ✅ `event_loop` dispatches Copy/Paste via `set_selection` /
  `get_selection` + `paste_text`.
- ✅ `src/main.hc` installs the in-memory Clipboard handler.
- ✅ 6 new unit tests in `actions_test.hc`, all green.
- ✅ 3 new integration tests in `runtime_test.hc`, all green under
  hica ≥ 0.49.4 (the test-mode panic-handler fix).
- ✅ hica Issue #5 filed *and resolved upstream* (`docs/hica-issues.md`
  updated with the 0.49.3 resolution note).
- ✅ `docs/hedit-design.md` §2.3 already documented the Clipboard
  effect and matches what shipped.
- ✅ README.md Status line updated + `docs/notes.md` grew a Copy/Paste
  section.

### Reflection

**What changed vs the plan.**

Steps 1–5 landed clean. The integration-test story went sideways when
hica 0.49.2 leaked `<Clipboard>` from the test-mode `main` (Issue #5).
Rather than concede a partial-green milestone or refactor Copy/Paste
out of `event_loop`, we filed the issue with three sharpened repros
(shape A/B/C in `docs/hica-issues.md`), and the hica team shipped the
panic-handler fix as 0.49.3 the same day. Re-added the integration
tests unchanged and they went green on first try. Total detour: one
session's worth of diagnostic work, plus one hica release.

**What to carry forward.**

- **Adding an effect to a `pub fun`'s inferred row is a load-bearing
  API change.** Downstream tests that install only a *subset* of the
  effects will silently break with `unhandled effect: …` from Koka —
  not a friendly hica diagnostic. Whenever a new effect lands, audit
  every existing test that touches a `pub fun` in that module.
- **Small-repro probes save hours.** The `/tmp/probe2.hc` single-file
  repro that reproduced shape A cleanly proved the failure isn't a
  general nested-handler problem — narrowing the search to the
  cross-module + test-mode-main combination made the upstream fix
  actionable.
- **Two-workspace debugging is normal here.** hica evolves alongside
  hedit; when hedit hits an issue, filing it in `docs/hica-issues.md`
  with a reproduction is often the fastest path to unblock. Same
  pattern as HiLisp during M0 — treat hica as a living dependency,
  not a fixed compiler.
- **`docs/hica-issues.md` earned its keep.** Two of the three OPEN
  issues (#3, #5) landed as `RESOLVED` in-milestone once the write-up
  gave the hica team a clear target. Keep the format tight and the
  repros minimal.
- **Test-mode `fun main()` is now robust.** hica ≥ 0.49.4 installs
  panic handlers for user effects automatically, so residual effects
  from a `test { … }` body no longer break the whole test binary.
  Worth noting when we grow a `Config` effect in M4 — it should Just
  Work.

**What to change in the design doc.**

- Nothing structural for §2.3 (Clipboard effect surface is correct).
- §5 (event-loop dispatch) already shows Copy/Paste as effectful arms
  alongside Save — the shape we shipped.
- README.md Status line now says "M3 green" with a 40/40 tally.

**Ready for M4.** All M3 exit criteria met, all tests green, ground
rules held (small edits, docs updated in-milestone, `hica fmt` +
`hica analyse` clean). The HiLisp bridge (M4) can layer on top of a
stable `EditorState.config` foundation — the `default_bindings()`
plumbing landed with the pre-M3 cleanup pass and is unchanged.

---

## Milestone M4 — HiLisp bridge: real `(set)`/`(get)`/`(bind)`

### Goal

`src/hilisp_host.hc` grows from "eval a string, return display" to
"install our three built-ins on a long-lived Env, mutate a `Config`
via the HiLisp host-dispatch callback". Config discovery follows §7.4
of the design doc (`$XDG_CONFIG_HOME/hedit/init.hl` then
`$HOME/.hedit.hl`, first hit wins) and lives in the new
`src/config_loader.hc`.

**Design decision (locked in during the plan phase, ratified by the
implementation):** `Config` is a *plain returned struct*, not a
hica-side effect. Rationale:

- The design doc §7 explicitly says "no runtime reconfiguration" —
  `Config` is built once at startup and frozen before `event_loop`.
  Effects would over-engineer the load-once-then-freeze contract.
- We already had `EditorState.config: Config` from the pre-M3 cleanup
  pass. Extending it with a `values: list<(string, string)>` field
  keeps the whole flow pure hica data.
- HiLisp already exposes `register_host_dispatch` — the intended
  extension point for embedders wanting to mutate host state from
  Lisp code. The mutation lives *inside* the HiLisp Env under two
  well-known keys (`__hedit_bindings`, `__hedit_values`) and gets
  extracted back into a `Config` by `config_from_env` at end of load.

**Exit criteria (final, matches what shipped):**

- `src/model.hc`: `Config` gains a `values: list<(string, string)>`
  field + `get_config` / `get_config_int` helpers.
  `init_editor_with_config(path, cfg)` constructor added so callers
  can seed the editor state with a config other than
  `default_config()`.
- `src/hilisp_host.hc`: `pub fun make_hedit_env(cfg0)` +
  `pub fun load_config(src, cfg0) : (Config, maybe<string>)` +
  `pub fun parse_chord(s) : maybe<KeyChord>`. Host dispatch routes
  `host/set`, `host/get`, `host/bind` to hedit-side config mutations.
  Preamble aliases `(set …)` / `(get …)` / `(bind …)` on top of the
  raw `host/…` names.
- `src/config_loader.hc` (new): XDG discovery + `load_user_config`
  wrapper that surfaces status messages hedit can drop onto
  `EditorState.status_message`.
- `tests/hilisp_host_test.hc`: 10 new tests (3 for `parse_chord`, 7
  for `load_config` end-to-end coverage of `(set …)` / `(bind …)`).
- All 5 test suites green: 19 actions + 4 render + 8 runtime + 19
  hilisp_host + (no dedicated config_loader_test yet — see plan).

### Plan

- [x] **Extend `Config` in `src/model.hc`.** Add `values` field,
  `get_config` / `get_config_int` helpers, `init_editor_with_config`
  constructor. Migrate existing `Config { bindings: … }` literals
  to `Config { bindings: …, values: [] }`.
- [x] **Grow `src/hilisp_host.hc`.** Replace M0 stub with the full
  bridge: `make_hedit_env`, `hedit_host_dispatch`, `load_config`,
  `parse_chord`. Storage inside the env as `LHash` for both bindings
  (keyed by canonical chord string `"Modifier-c"`) and values (keyed
  by plain string). Keep every mutation on `list<(string, LVal)>`
  via HiLisp's own `map_set` (`env_set`) so the callback stays
  `total` under HiLisp's `register_host_dispatch` signature.
- [x] **`src/config_loader.hc` (new).** `candidate_paths(xdg, home)`
  + `read_first(paths)` + `load_user_config(cfg0)` composing the
  XDG lookup on top of `hilisp_host::load_config`.
- [x] **`src/main.hc` — call `load_user_config` at startup.** Landed
  in Session 3 once hica shipped the `hica build` include-path fix
  (`docs/hica-issues.md` Issue #7). `hica check src/main.hc` →
  `[<console>]`, `hica build` green, `hica run` prints the M3 stub.
- [x] **`tests/hilisp_host_test.hc`.** Grew from 9 to 19 tests: the
  9 M0 smoke tests + 3 pure `parse_chord` tests + 7 end-to-end
  `load_config` tests covering (set) with int/string, (bind)
  overriding + preserving defaults, multi-form composition, bad
  chord + unknown action error paths.
- [x] **Runtime integration test (HiLisp-rebound Ctrl-x → quit).**
  `tests/runtime_test.hc` test 9 landed in Session 3 alongside the
  `main.hc` wiring and the HiLisp v0.9.2 apply-carve-out fix
  (`docs/hica-issues.md` Issue #8).
- [x] **Docs.** Design doc §7, journal Log/Reflection, README status
  line, hica-issues.md Issues #6, #7, #8 write-ups.

### Log

**Session 1 — 2026-08-18.** Sequence of edits, in order:

1. Extended `Config` in `src/model.hc` with `values: list<(string,
   string)>` and helpers. Updated the one `Config { bindings }`
   literal in `tests/actions_test.hc`. All 4 pure test suites still
   green (8/8 + 9/9 + 4/4 + pre-M4 hilisp_host 9/9 = 30/30).

2. **First wall: `<div>` totality gap.** Wrote `src/hilisp_host.hc`
   with `hedit_host_dispatch` storing bindings as a `list<(KeyChord,
   Action)>` LList inside the env, using `map_set` for updates. Both
   `hica check` and `hica analyse` were clean, but `hica test`
   failed to *build* with:

   ```
   src/hilisp_host.kk(507,58): type error: effects do not match
     context : hc_register_host_dispatch(base, hc_hedit_host_dispatch)
     term    : hc_hedit_host_dispatch
     inferred effect: <div|_e>
     expected effect: total
   ```

   HiLisp's `register_host_dispatch` requires a `total` callback,
   but hica codegen emits `map_set` on any `list<(K, V)>` as
   `if cur.any(fn((k, _)) k == key) then cur.map(...) else cur ++
   [...]` — the `any`/`map` chain over `list<t>` is recursive without
   a termination witness, so Koka infers `<div>`.

   Filed as `docs/hica-issues.md` Issue #6 with a minimal repro.
   Tried four workarounds (rewrite recursive helpers by hand, widen
   the callback signature to `<div>` in HiLisp, per-key `env_set`
   with prefix, bounce through `apply_builtin` directly) — each hit
   the same wall or contradicted design constraints.

3. **hica fix + refactor.** hica shipped a fix mid-session
   (`c6dc250c`, "map operations on list(k, v) now emit through a
   single list.foldr pass"), which resolved Issue #6 for the
   straight-string case. The bindings side still tripped because
   `KeyChord` equality is a recursive struct compare — refactored
   storage to be string-keyed (`"Ctrl-x"` → `LStr("save")`) and
   let HiLisp's own `env_set` do the alist update. That inherits
   totality for free and keeps every callback branch total.
   `hica test` for hilisp_host now compiled, 12/12 green
   (9 M0 + 3 parse_chord).

4. **Second wall: host state doesn't persist.** Added 7 end-to-end
   `load_config` tests. 4 failed — the mutation Koka reported inside
   `hedit_host_dispatch` never reached the outer eval loop's env.
   Ran a probe: direct `(host/set …)` worked (values len → 1),
   wrapped `(set …)` didn't (values len → 0). Root cause: HiLisp's
   `apply` explicitly discards a called function's env (`(result,
   env)` returns the *caller's* env, not the callee's) — standard
   Lisp scope. But our `(def set (fn (k v) (host/set k v)))` puts
   the `host/set` call inside a function body, so the mutation was
   scoped to the callee's frame and thrown away.

5. **Third fix: carve-out in HiLisp's `apply`.** Added
   `body_touches_host(body) : bool` + `merge_host_bindings(receiver,
   donor) : Env` to `lib/hilisp/src/eval.hc`. When an `LFun`'s body
   ends up calling a `host/…` builtin, `apply` now merges the
   callee's `__`-prefixed bindings (host-visible state, by
   convention) back into the caller's env. Non-`__` bindings stay
   inside the callee's frame, preserving normal Lisp scope for the
   user's `def`s and lambda params.

   **Sub-bug caught by probing:** first implementation walked the
   *whole donor chain* and re-copied stale `__hedit_values` from the
   caller's original snapshot back over our fresh values. Restricted
   the walk to donor's *topmost frame only* — where `env_set` always
   deposits its writes — and everything went green.

6. **`hica analyse` cleanup.** Three modules dropped from 100 → 92
   with "nested match on maybe" HIGH severities. Refactored:
   - `src/model.hc::get_config_int` — used to nest `match ... {
     Some(v) => match parse_int(v) { … } }`. Extracted `parse_or(v,
     fallback)` helper; renamed the internal parameter to avoid
     colliding with hica's `default` method on `maybe`.
   - `src/config_loader.hc::xdg_candidate` — used to nest `match
     xdg { … match home { … } }`. Extracted a shared `opt_path(dir,
     suffix)` combinator built on `map_maybe` + `unwrap_maybe_or`.
   - `src/hilisp_host.hc::host_bind` — used to nest `match
     parse_chord { … match string_to_action { … } }`. Rewrote as a
     tuple-match on `(parse_chord(...), string_to_action(...))`,
     plus a small `bind_ok(env, chord_str, action_name)` helper.

7. **`hica build` blocker (M4b defer).** Rewrote `src/main.hc` to
   call `load_user_config` before `event_loop`. `hica check` clean,
   but `hica build` fails with:

   ```
   (1, 0): build error: could not find module: lisp
     search path: /Users/claes.adamsson/cladam/code/hedit,…
   ```

   `hica.hml`'s `@koka { include: "./lib/hilisp/src" }` reaches
   `hica test` (all HiLisp modules resolve from the test binary)
   but not `hica build`. Reverted `main.hc` to its M3 shape and
   documented the deferral inline. All other tests + code remain
   green; the wiring is a one-liner change when the include path
   propagates.

**Final green surface (2026-08-18):**

- `hica check` clean on every module (main [<console>], runtime
  [<fsys, Terminal, Clipboard>], hilisp_host [pure], config_loader
  [<fsys, io>], everything else pure).
- `hica build` succeeds; `hica run src/main.hc` prints the M3 stub
  transcript.
- `hica fmt --check` + `hica analyse` 100/100 across all 8 `src/*.hc`
  files.
- 19 actions + 4 render + 8 runtime + 19 hilisp_host = **50/50 tests
  green** under `/Users/claes.adamsson/cladam/code/hica-ecosystem/hica/hica`
  (hica 0.49.4 + local HiLisp submodule with the eval.hc carve-out).

**Session 3 — 2026-08-18 (M4b closeout).** Two upstream fixes shipped
between sessions cleared both deferrals:

1. **hica gained a `hica build` include-path fix.** `@koka { include:
   "./lib/hilisp/src" }` in `hica.hml` now propagates through `hica
   build` the same way it always has through `hica test`. Filed as
   `docs/hica-issues.md` Issue #7 (RESOLVED). Wired
   `load_user_config(default_config())` into `src/main.hc` before the
   handler stack; if the loader returns `Some(msg)` we prime it onto
   `EditorState.status_message` via `set_status_message`. `hica
   check src/main.hc` clean at `[<console>]`, `hica build` green,
   `hica run` still prints the M3 stub transcript.
2. **HiLisp v0.9.2 fixed the closure-staleness bug in `apply`.** The
   v0.9.1 carve-out only merged outbound (callee → caller). Two-form
   configs like `(bind "Ctrl-x" 'quit) (bind "Ctrl-q" 'ignore)` broke
   because the `LFun` for `bind` captured its `closure_env` at
   `(def bind (fn (k a) (host/bind k a)))` time, so the second call
   read stale `__hedit_bindings`, added its own key on top, and
   overwrote the first call's writes. Repro'd with a probe test that
   inspected the `LFun`'s captured env directly:

   ```
   env1 __hedit_bindings:        { … "Ctrl-x" "quit" }   ✅ good
   closure_env __hedit_bindings: { …                 }   ❌ stale
   ```

   Reported to HiLisp, fixed same day as **v0.9.2** (submodule
   pointer bumped). The fix makes `apply` symmetric: pre-merge
   caller's `__`-prefixed keys into the callee's env before eval,
   then merge outbound as before. Filed as `docs/hica-issues.md`
   Issue #8 (RESOLVED).

3. **Added the M4b integration test.** `tests/runtime_test.hc` test 9:
   `HiLisp (bind Ctrl-x 'quit) rewires the quit chord end-to-end`.
   Uses `load_config` (not `load_user_config`, so no filesystem
   touched) with the same two-form config that broke on v0.9.1,
   seeds `init_editor_with_config(None, cfg)`, scripts a single
   Ctrl-x event through the Terminal handler, asserts
   `should_quit == true`. Green under v0.9.2 + the hica include-path
   fix.

**Post-M4b green surface (2026-08-18):**

- `hica check src/main.hc` → `[<console>]` (M4b wiring in place).
- `hica check src/runtime.hc` → `[<fsys, Terminal, Clipboard>]`.
- `hica build` → succeeds.
- `hica run src/main.hc` → M3 stub transcript, exit 0.
- 19 actions + 4 render + 9 runtime + 19 hilisp_host = **51/51 tests
  green**.
- `hica fmt --check` + `hica analyse` 100/100 across all touched
  files.

**Exit criteria (final, all green):**

- ✅ `Config.values` alist + helpers landed in `src/model.hc`.
- ✅ `pub fun make_hedit_env` + `load_config` + `parse_chord` in
  `src/hilisp_host.hc`.
- ✅ `src/config_loader.hc` with `candidate_paths`, `read_first`,
  `load_user_config`.
- ✅ `src/main.hc` integration — `load_user_config` runs at startup,
  status message primed onto `EditorState.status_message` when the
  loader has something to say.
- ✅ 10 new tests in `tests/hilisp_host_test.hc`, all green.
- ✅ `tests/runtime_test.hc` integration test 9 (HiLisp-rebound
  Ctrl-x → Quit).
- ✅ `docs/hedit-design.md` §7 aligned with the shipped surface.
- ✅ `docs/hica-issues.md` Issues #6, #7, #8 filed and marked
  resolved.
- ✅ `README.md` Status line — M4 flipped to ✅.

**HiLisp submodule note.** `lib/hilisp/` points at tag **v0.9.2** —
the symmetric `apply` carve-out ships upstream. hedit builds outside
this workspace from a fresh clone; no local patches required beyond
`git submodule update --init --recursive`.

### Reflection

**What changed vs the plan.** The plan called for a straight
"install builtins → call them → extract mutated env" pipeline; three
things needed unexpected work:

1. **hica compiler fix mid-milestone.** The `map_set` totality gap
   blocked the initial hilisp_host code entirely. Upstream shipped a
   fix (`map operations → foldr`) that unblocked the string-keyed
   storage path; the KeyChord-keyed variant we tried first was still
   `<div>` even after the fix. Rewrote storage to be string-keyed
   inside the env (chord serialised as `"Modifier-c"`) so
   everything routes through HiLisp's own `env_set`, which was
   already total. Ships as: `__hedit_bindings` / `__hedit_values`
   are `LHash` values, keyed by strings, populated via `map_set`.
2. **HiLisp Lisp-scope semantics vs host mutation.** The natural
   preamble `(def set (fn (k v) (host/set k v)))` puts the host
   call inside a function body, whose env is normally discarded by
   HiLisp's `apply` (correct Lisp scope). Added a targeted
   carve-out to `lib/hilisp/src/eval.hc::apply`: `body_touches_host`
   detects `host/…` calls in the body shape, and
   `merge_host_bindings` copies the callee's `__`-prefixed bindings
   into the caller's env after the call returns. Non-`__` bindings
   still get discarded, preserving `def` scoping for user code.
3. **`hica build` include-path.** Test surface reaches lib/hilisp
   fine; production build doesn't. Downstream integration
   (`main.hc` calling `load_user_config`) waits on that.

**What to carry forward:**

- **Storage-shape choice matters for totality.** When embedding a
  Lisp-shaped host callback, always keep host-side state alist-keyed
  by strings and mutate via the Lisp's own `env_set` / `map_set`.
  User-defined keys (structs, enums) trip Koka's totality inference
  through their auto-derived `==`. This is the "why LHash of strings"
  pattern that ended up in `src/hilisp_host.hc`.
- **The `__` prefix as host-namespace convention.** hedit's config
  lives under `__hedit_bindings` / `__hedit_values`; the HiLisp
  carve-out in `apply` only propagates keys with `__` prefix, so
  users can't accidentally leak `def`s into host state.
  Documented at the top of `src/hilisp_host.hc`.
- **`hica analyse` HIGH severities on nested `match`.** Three
  modules hit "nested match on maybe" — always refactor by
  extracting a helper (`parse_or`, `opt_path`, `bind_ok`) or
  using `map_maybe` / `and_then` / `unwrap_maybe_or`. Even without
  the analyse hint, the tuple-match refactor of `host_bind` reads
  materially clearer than nested `Some(_) => Some(_) => …`.
- **Debug prints inside HiLisp's `apply` are cheap and worth it.**
  When the wrapped `(set …)` mysteriously didn't persist, adding
  three `println` calls to `apply` (inner env value before + after
  merge, caller env value before merge) diagnosed the "whole-chain
  walk overwrites fresh values" bug in one minute. Pattern:
  `println("[HL] " + lval_show(env_get(…, key)))`.
- **`hica build` vs `hica test` include-path discrepancy is real.**
  Anything that uses `@koka { include }` in `hica.hml` works under
  `hica test` (each test binary gets the include prepended) but
  not under `hica build` (main entry doesn't). File as an upstream
  wishlist item; workaround for hedit is to keep HiLisp-touching
  code in test-only test files until the discrepancy is fixed.

**What to change in the design doc:**

- §7.5 example unchanged — the `(set "tabsize" 4)` / `(bind
  "Ctrl-s" 'save)` syntax works exactly as shown.
- §7.6 API surface: add a note that (set)/(get)/(bind) are hedit
  aliases for `(host/set)/(host/get)/(host/bind)`. Small
  clarification, not a shape change.
- §7.7 Load Sequence: the current wording ("initialise
  ConfigState with defaults, locate config file, if found: create
  HiLisp Env, register built-ins, eval file contents") matches the
  shipped `load_user_config` flow. No change needed.

**Ready for M5.** All M4 exit criteria (including M4b) are green,
Issues #6/#7/#8 are all filed and resolved upstream, and the
config → bindings → action → event_loop chain is exercised
end-to-end. The named-effect experiment can start.

---

## Milestone M5 (stretch, narrow scope) — Named effects for per-buffer state

### Goal

**Prove** `spawn Buffer { … } as buf_ref` as the container for
per-buffer state. The concrete payload we use to justify moving state
out of `EditorState.buffer` into a spawned handler is a **per-buffer
undo/redo stack** — a feature that has nowhere clean to live in the
current single-`TextBuffer` shape and that we've deferred since M1.

**Narrow scope (decided during planning, Option B):** single active
buffer, no multi-buffer navigation. We're proving the mechanism scales
(there's *one* test that spawns two `Buffer` handlers and asserts
their state is isolated), not shipping multi-buffer UX. Multi-buffer
navigation (`NextBuffer`, `OpenFile`, `CloseBuffer`) is deferred to a
follow-on **M5.5** — the `Action` enum and `spawn Buffer` shape
established in M5 will carry it without churn.

**Non-goals for M5:**

- Multi-buffer navigation UX (Ctrl-tab / Ctrl-o / Ctrl-w).
- Native ANSI positioning in the `render_frame` handler (still a
  line-by-line `println` dump).
- Real OS clipboard handler (still in-memory).
- Any async story; `spawn` is used for state, not concurrency.
- Plugin loading, HiLisp hooks on buffer events.

**Exit criteria (draft, refined after Plan step 1):**

- `src/runtime.hc` declares `pub effect Buffer { … }` with an op set
  finalised after reading `hica-ecosystem/hica/examples/effects/
  two-counters.hc` and `counter-pool.hc`. Working draft:
  `get() : TextBuffer`, `put(b: TextBuffer)`, `snapshot()`,
  `undo() : bool`, `redo() : bool`. `snapshot()` pushes the current
  buffer onto the undo stack; `undo/redo` return `true` if they
  actually moved.
- `src/model.hc` grows two `Action` variants (`Undo`, `Redo`) and
  their default chord bindings (`Ctrl-z`, `Ctrl-y`). HiLisp
  `(bind …)` picks them up for free via `string_to_action` — one
  two-line edit in `hilisp_host.hc`.
- **(Superseded — see Log.)** `EditorState.buffer` stays a plain
  `TextBuffer`; `apply_action` stays 100% pure. `event_loop` alone
  spawns a `ref<Buffer>` per call and threads it through a new
  tail-recursive `event_loop_step`, calling `snapshot`/`undo`/`redo`
  with the current `TextBuffer` passed explicitly (no handler-local
  mirror of `state.buffer` to drift out of sync).
- `tests/spawn_test.hc` (new): at least
  1. type → snapshot → type → Undo → assert buffer restored;
  2. type → Undo → Redo → assert forward again;
  3. spawn two `Buffer` handlers in one test, mutate one, prove the
     other is unchanged — this is the "does spawn scale" evidence.
- Every existing test (19 actions + 4 render + 9 runtime + 19
  hilisp_host) still green under the `BufferRef` indirection.
- `hica run src/main.hc` demonstrates a type → Undo → Redo round-trip
  in the stub transcript.
- `docs/hedit-design.md` gains a new §8 "Per-buffer state via
  `spawn Buffer`"; `docs/notes.md` grows Undo/Redo defaults; README
  Status flips M5 to 🚧 (or ✅ if fully green in-milestone).

### Plan

- [x] **Read the shape.** Read `hica-ecosystem/hica/documentation/
  named-effects-design.md`, then the `two-counters.hc` and
  `counter-pool.hc` examples. Write a one-paragraph "shape we're
  adopting" note at the top of the M5 Log — especially: how the
  `spawn` expression binds its ref, how ops are called on that ref,
  how the ref's lifetime scopes. Do NOT read hica compiler
  internals.
- [x] **Add `Action::Undo` / `Action::Redo` + defaults.** Same shape
  as pre-M3 Copy/Paste addition. Extend `action_to_string` /
  `string_to_action` in `src/hilisp_host.hc` so `(bind "Ctrl-z"
  'undo)` works. `apply_action` in `src/actions.hc` grows two arms
  (no-op-in-pure, real work in `event_loop`).
- [x] **Declare `pub effect Buffer` in `src/runtime.hc`.** Shipped as
  `snapshot(b: TextBuffer)`, `undo(current: TextBuffer) :
  maybe<TextBuffer>`, `redo(current: TextBuffer) : maybe<TextBuffer>`
  — the buffer is passed explicitly on every op instead of mirrored
  in handler-local state (see Log for rationale). Handler state is
  just the two stacks: `with var undo_stack = [], var redo_stack = []`.
- [x] **`EditorState` migration — superseded.** Kept `buffer:
  TextBuffer` as a plain field; no `BufferRef` migration, no churn in
  `render.hc` / `actions.hc`. Only `event_loop` speaks `ref<Buffer>`.
  See Log for the design-fork rationale (spawn is a statement, not a
  pure expression, so migrating the field would have made every pure
  helper effectful).
- [x] **`event_loop` snapshots before every mutating action.** Split
  into `event_loop` (spawns the `ref<Buffer>` once) + recursive
  `event_loop_step(state, buf_ref)`. `Insert`/`Paste` call
  `buf_ref.snapshot(sized.buffer)` before delegating; `Undo`/`Redo`
  call `buf_ref.undo(...)`/`redo(...)` and restore via a new
  `apply_history` helper (mirrors `apply_write_result`'s shape).
- [x] **`src/main.hc`.** No change needed — `event_loop` owns the
  `spawn Buffer` internally now, so the existing call site
  (`event_loop(s1)`) picks it up for free.
- [x] **Tests.** `tests/spawn_test.hc` (new) with 4 tests: undo
  restores snapshot, undo-then-redo returns forward, undo on empty
  history is `None`, two spawned instances stay isolated (the "does
  spawn scale" evidence). `tests/runtime_test.hc`'s existing 9 tests
  needed no changes — `EditorState.buffer` semantics are unchanged.
- [x] **Docs.** Design doc §8 (new), notes.md Undo/Redo, README
  Status M5 line, this journal's Log/Reflection.
- [x] **`hica fmt --check` + `hica analyse` 100/100 on every
  touched file.** Clean (see Log for the one `fmt` fixup needed on
  `spawn_test.hc`).

### Log

**Session 1 — 2026-08-19.** Shape-reading pass (Plan step 1).

**Shape we're adopting.** Read `named-effects-design.md` §1-2 plus
`examples/effects/two-counters.hc`, `counter-pool.hc`, and re-skimmed
`buffer.hc` (stateful handler shape, pre-dates spawn). The mechanism:

```hica
spawn Counter {
  incr() => count = count + 1,
  get() => count
} with var count = 0 as c1
```

`spawn Name { arms } (with var …)? as ref` declares the arms *and*
installs the handler in one statement — no `handle … in { … }` block,
no lexical nesting. The bound name (`c1`) is a first-class value of
type `ref<Name>` you call ops on directly: `c1.incr()`, `c1.get()`.
Multiple `spawn`s of the same effect coexist with fully isolated state
(`counter-pool.hc` spawns three `Counter`s in one `fun main()`, no
lexical nesting required). `ref<Name>` is passable to ordinary
functions as a typed parameter (`fun bump(c: ref<Counter>, n: int)`),
confirmed by both examples. Probed both example files directly against
our installed `hica 0.49.6` (copied into `tests_probe/`, ran, deleted)
— both compile and run unchanged, confirming named effects are
production-ready in the version hedit already builds with. No new
hica issue anticipated for the mechanism itself.

**Implication for hedit's shape:** `EditorState.buffer: TextBuffer`
becomes `EditorState.buffer: ref<Buffer>`. `spawn Buffer { … } as
buf_ref` replaces the `new_buffer(...)` call at `init_editor_with_config`
time — but `spawn` is a *statement*, not a pure expression, so
`init_editor_with_config` (currently pure, used by all 19 actions_test
cases) cannot remain pure once it spawns. Likely resolution: keep
`init_editor_with_config` constructing a *plain* `TextBuffer` value as
today (pure, for tests that don't touch the effect), and have
`src/main.hc` / the integration tests do the `spawn Buffer { … } with
var current = new_buffer(...) as buf_ref` step separately, writing the
ref into state right before `event_loop`. This keeps the pure test
surface (`apply_action`, `resolve_action`, `insert_char`, etc.)
completely unchanged — they keep operating on a plain `TextBuffer` —
while only `event_loop` and its handler-stack callers speak `ref<Buffer>`.
Revisit this split once the effect ops are drafted in the next session
(this may mean `EditorState` keeps `buffer: TextBuffer` and undo/redo
state rides alongside it via a *separate* `ref<Buffer>` threaded
through `event_loop` only — smaller blast radius than rewriting every
pure helper's signature. Decide in Plan step 3-4.)

**Chunk 1 — `Action::Undo`/`Redo` (2026-08-19).** Added `Undo`/`Redo`
variants to `Action` in `model.hc`, default bindings `Ctrl-z`/`Ctrl-y`,
no-op arms in `apply_action` (same shape as Copy/Paste — real work
waits for the `Buffer` effect), and `action_to_string`/
`string_to_action` entries in `hilisp_host.hc` so `(bind "Ctrl-z"
'undo)` round-trips. Added 4 pure tests to `actions_test.hc`
(resolve_action → Undo/Redo, apply_action no-op on both) and 1 to
`hilisp_host_test.hc` (HiLisp rebind of Ctrl-z → Undo). All green:
**56/56** (23 actions + 20 hilisp_host + 4 render + 9 runtime).
`hica fmt --check` + `hica analyse` 100/100 on every touched file. No
surprises — purely additive, same shape as the pre-M3 Copy/Paste
cleanup.

**Chunk 2 — `pub effect Buffer` + `tests/spawn_test.hc` (2026-08-19).**
First cut declared `Buffer` with a mirrored-state shape (`get()`,
`put(b)`, `snapshot()`, `undo() : bool`, `redo() : bool`, matching the
exit-criteria draft) — but that requires the handler to hold its own
`current: TextBuffer` in `with var current = …`, which can drift out
of sync with `EditorState.buffer` (two sources of truth for the same
data). Switched to the design sketched in the M5 Log's "Implication
for hedit's shape" note: `snapshot(b: TextBuffer)`,
`undo(current: TextBuffer) : maybe<TextBuffer>`, `redo(current:
TextBuffer) : maybe<TextBuffer>` — the caller always passes
`EditorState.buffer` explicitly, the handler only ever owns the two
stacks, and there is no second copy of the buffer anywhere. Wrote
`tests/spawn_test.hc` standalone (imports `runtime`, never touches
`event_loop`) with 4 tests exercising the spawned effect directly —
this is Plan's "does spawn scale" evidence, confirmed by test 4
(two `spawn Buffer { … } as buf1` / `as buf2` in one test, mutating
only `buf1`, asserting `buf2`'s history stays empty).

**The wall — hica Issue #9 (transitive named-effect compile
failure).** `spawn` inside a `test { … }` body compiled and ran fine
for `spawn_test.hc`'s 4 tests. But wiring `Buffer` into `event_loop`
(Chunk 3, same session) broke `tests/runtime_test.hc` — a file that
never spawns directly, only calls `event_loop` (which does the
`spawn` internally, one module over in `runtime.hc`). Failure:

```
tests/runtime_test.kk(...): type error: identifier hc_snapshot cannot be found
```

Root cause (confirmed with a minimal 2-file repro, `probe_named_lib.hc`
+ `probe_named_test.hc`, kept for provenance in
`docs/hica-issues.md`): hica's test-mode auto-panic-handler generator
(the Issue #5 fix) emits a plain unnamed-handler guard
(`with handler ctl hc_snapshot(...) -> throw(...)`) for *every*
user-defined effect visible in the program — but `spawn` promotes an
effect to a Koka *named effect* (ops compile to
`hc_<effect>_<op>` behind `with c <- named handler`, not
`with handler`), so the guard references an identifier that was never
generated. Confirmed the failure is specifically about *transitive*
spawns: the repro's test file never spawns `Counter` itself, only
calls a library function that does — exactly hedit's `event_loop`
shape. Filed as `docs/hica-issues.md` Issue #9.

**Same-day fix.** The user (hica's maintainer) diagnosed and fixed
the actual root cause on the local hica build
(`hica-ecosystem/hica/hica`, 0.49.8): imported function bodies —
including ones containing a `spawn` — weren't being collected into
`user-prog.decls`, so the promoted-named-effect detection never saw
the transitive `spawn` when it lived in a different module than the
test file. Re-ran everything under the local 0.49.8 binary with zero
hedit-side workaround code: `tests/runtime_test.hc` 9/9,
`tests/spawn_test.hc` 4/4, both green on the exact code drafted before
the wall was hit. Updated Issue #9 to RESOLVED.

**Chunk 3 — wire `event_loop` (2026-08-19, same session).** Split
`event_loop` into two functions: `pub fun event_loop(state)` spawns
one `ref<Buffer>` (fresh undo/redo stacks) and delegates to a new
tail-recursive `event_loop_step(state, buf_ref)`, which is the actual
loop body (previously all of `event_loop`). `Insert`/`Paste` arms call
`buf_ref.snapshot(sized.buffer)` before mutating; `Undo`/`Redo` arms
call `buf_ref.undo(...)`/`redo(...)` and route the `maybe<TextBuffer>`
result through a new `apply_history(state, result, verb)` helper
(same two-arm shape as `apply_write_result`: `Some(b)` restores the
buffer + sets a status message, `None` sets a "Nothing to
undo"/"redo" message — empty history is a no-op, not an error).
`src/main.hc` needed **no changes** — it just calls `event_loop(s1)`
as before; the `spawn` is fully internal to `runtime.hc`.

One `hica fmt --check` fixup needed: `tests/spawn_test.hc`'s
first draft had inconsistent indentation on the four near-identical
`spawn Buffer { … }` blocks — `hica fmt` reformatted it once, then
`--check` was clean.

**Final green surface (2026-08-19, local hica 0.49.8):**

- `hica check src/main.hc` → ok, `[<console>]`.
- `hica check src/runtime.hc` → ok.
- `hica build` → succeeds; `hica run src/main.hc` → M4b stub
  transcript, exit 0.
- 23 actions + 20 hilisp_host + 4 render + 9 runtime + 4 spawn =
  **60/60 tests green.**
- `hica fmt --check` clean on every touched file (`model.hc`,
  `actions.hc`, `hilisp_host.hc`, `runtime.hc`, `main.hc`,
  `spawn_test.hc`, `actions_test.hc`, `hilisp_host_test.hc`).
- `hica analyse` 100/100 on `runtime.hc` and `main.hc` (0
  Critical/High/Medium).
- `docs/hica-issues.md` Issue #9 filed and marked RESOLVED same day.

Docs (design doc §9, notes.md Undo/Redo section, README status line)
landed in the same session — see Reflection below for the closing
notes.

### Reflection

**What changed vs the plan.** The exit-criteria draft assumed
`EditorState.buffer` would migrate to `BufferRef`/`ref<Buffer>` and
`apply_action` would become effectful in `<Buffer>`. That didn't
survive contact with the language: `spawn` is a statement, not a pure
expression, so the migration would have forced every pure helper
(`apply_action`, `insert_char`, `current_line`, `paste_text`, all of
`actions_test.hc`) to carry `<Buffer>` — directly undoing the M2/M3
"handle_action stays pure" invariant. Caught this during the Plan
step-1 shape-reading pass, before writing any migration code, and
routed around it: `EditorState.buffer` stayed a plain `TextBuffer`;
only `event_loop` spawns and talks to `ref<Buffer>`. Op shape also
changed mid-implementation (Chunk 2): the exit-criteria draft's
`get()`/`put(b)`/stateless `snapshot()` would have mirrored the buffer
inside the handler as a second source of truth; shipped
`snapshot(b)`/`undo(current)`/`redo(current)` instead, passing the
buffer explicitly on every call so the handler only ever owns the two
stacks.

**What changed vs the plan (the compiler wall).** Wiring the spawned
effect into `event_loop` (a different module than the test file that
exercises it) tripped a real hica gap: the test-mode auto-panic-handler
generator didn't know a *transitively* spawned effect had been
promoted to a named effect, so it emitted a guard referencing an
identifier (`hc_snapshot`) that plain-effect codegen never produces.
Filed as Issue #9 with a 2-file minimal repro; the user (hica's
maintainer) traced it to a broader gap — imported function bodies
weren't collected into `user-prog.decls` at all, so cross-module
named-effect detection silently failed — and fixed it the same
session on a local build. No hedit-side workaround code was needed;
the originally-drafted `event_loop`/`spawn Buffer` shape just started
working once the compiler fix landed.

**What to carry forward:**

- **`spawn` is a statement — plan around it *before* writing
  migration code.** Any milestone that considers moving a
  `EditorState` field to a spawned ref should first ask "does this
  field get read/written from a currently-pure function?" If yes,
  keep the field plain and give the effect a narrower, single-caller
  scope (exactly the `event_loop`-only `Buffer` pattern here) instead
  of chasing the effect through every pure helper.
- **Passing state explicitly beats mirroring it in handler-local
  vars.** `snapshot(b: TextBuffer)` / `undo(current: TextBuffer)`
  has no way to drift out of sync with `EditorState.buffer`, because
  there's only one copy of the buffer, ever. Prefer this shape any
  time a spawned handler's job is to *react to* state owned
  elsewhere, rather than *own* the state itself.
- **Transitive named-effect promotion is a real cross-module gap
  class.** Same shape as Issue #6 (map totality) and Issue #5 (test-mode
  panic handlers) before it — a hica compiler invariant that holds for
  single-file examples silently breaks once the `spawn` and the test
  file live in different modules. Any new named-effect adoption in
  hedit should get a quick "does a test only *call* the spawning
  function, never spawn directly itself" check before assuming the
  single-file examples generalise.
- **Small 2-file repros keep paying off.** `probe_named_lib.hc` +
  `probe_named_test.hc`, copied into `tests_probe/`, run, then
  deleted — same pattern as M3's Issue #5 probe. Isolating "library
module spawns, test module only calls" from hedit's much larger
  `runtime.hc`/`runtime_test.hc` pair made the repro actionable in
  minutes instead of hours.
- **Local hica builds move faster than the published/PATH binary.**
  `~/.local/bin/hica` was still on 0.49.7 when the fix shipped as a
  local 0.49.8 build at
  `/Users/claes.adamsson/cladam/code/hica-ecosystem/hica/hica`. Noted
  in repo memory: check both versions before assuming a just-fixed
  bug is available generally.

**What to change in the design doc.**

- New §9 written to match the shipped shape exactly (explicit-buffer
  ops, `EditorState.buffer` unchanged, `event_loop`-only spawn). No
  further changes needed — the section was drafted *from* the final
  code, not the original exit-criteria draft.

**Ready for M5.5** (deferred, scope-guarded below) once there's an
actual need for multi-buffer navigation — the `Action` enum and
`spawn Buffer` shape established here should carry it without churn,
per the milestone map's original framing.

---

## Milestone M5.5 — Multi-buffer navigation

### Goal

Prove that hedit can hold more than one open buffer and navigate
between them, without disturbing the pure single-buffer surface every
earlier milestone (and its ~65 tests) was written against.

**Narrow scope (decided during planning):**

- `EditorState.buffer` stays the *active* buffer field — every
  pre-M5.5 pure helper (`insert_char`, `current_line`, `paste_text`,
  `render_editor_to_buffer`, all of `actions_test.hc`/`render_test.hc`)
  keeps working unchanged. A new `background_buffers: list<TextBuffer>`
  field holds the rest of the open buffers as a **rotation ring**:
  `NextBuffer`/`PrevBuffer` rotate the ring (no separate active-index
  to drift out of sync with which buffer is actually active);
  `NewBuffer`/`CloseBuffer` push/pop the front.
- `Action::NewBuffer` (open a fresh in-memory scratch buffer) replaces
  the originally-sketched `Action::OpenFile(path)`. There's no
  command-line/path-prompt input widget yet, and `(bind chord 'action)`
  only resolves *bare* action symbols (see `string_to_action`) — there
  is no way for a keybinding to carry an arbitrary path argument today.
  `OpenFile(path)` is deferred until a prompt widget exists to supply
  one.
- Default bindings are `Ctrl-o` (new), `Ctrl-n` / `Ctrl-p` (cycle),
  `Ctrl-w` (close) — not the originally-sketched `Ctrl-tab`, because
  `KeyChord` is `{ m: Modifier, c: char }` and Tab isn't a `char` in
  hedit's key model (it's `SpecialKey::Tab`, routed through `KSpecial`,
  which `resolve_action` doesn't consult for bindings). Reusing the
  existing chord shape avoids adding a new binding-table dimension for
  one milestone.
- All four new actions are **pure** — no per-buffer `spawn Buffer`
  pool. `event_loop`'s single spawned `Buffer` handler (M5) keeps
  tracking undo/redo for whatever `state.buffer` currently is; see
  Non-goals below.

**Non-goals for M5.5:**

- Opening existing files from disk (`OpenFile(path)`) — needs a
  command/path-prompt input widget. Deferred.
- **Per-buffer isolated undo/redo.** Switching buffers does *not*
  swap in a separate undo/redo history for the newly-active buffer —
  the M5 `Buffer` effect instance is still one shared stack per
  `event_loop` call. This is a known, called-out limitation (typing in
  buffer A, switching to B, hitting Ctrl-z, will try to undo against
  A's snapshots even though B is now active). Fixing this properly
  needs a `spawn`-per-buffer pool (the "counter-pool.hc" pattern) —
  its own follow-on once there's real demand for it.
- Split panes / windows (`PaneNode` in `docs/hedit-design.md` §3) —
  still on the original design doc's roadmap, untouched here.
- A tabline that preserves a stable left-to-right visual order
  independent of ring rotation — `render.hc`'s tabline always lists
  the active buffer first (`open_buffers` = `[buffer] + background_buffers`),
  so cycling visibly reshuffles tab order instead of just moving a
  highlight. Cosmetic; fine for a plain-text row.

### Plan

- [x] **`src/model.hc`.** `EditorState` grows `background_buffers:
  list<TextBuffer>` + `next_bid: int`; `buffer` unchanged. New
  `open_buffers(s)` helper returns the full ring, active first (used
  by the tabline). Four new `Action` variants + default bindings
  (`Ctrl-o`/`Ctrl-n`/`Ctrl-p`/`Ctrl-w`).
- [x] **`src/actions.hc`.** Pure helpers `new_buffer_action`,
  `cycle_next_buffer`, `cycle_prev_buffer`, `close_buffer_action` —
  see Log for the ring-rotation trick (`cycle_prev_buffer` is
  `cycle_next_buffer` run against `reverse(background_buffers)`, so
  there's only one piece of traversal logic to get right). Wired into
  `apply_action`; no `event_loop` changes needed since all four are
  pure.
- [x] **`src/hilisp_host.hc`.** `action_to_string`/`string_to_action`
  grow the four new symbol names (`new-buffer`, `next-buffer`,
  `prev-buffer`, `close-buffer`) — same one-line-per-action shape as
  M5's `undo`/`redo` addition.
- [x] **`src/render.hc`.** New `build_tabline`/`buffer_tab_name`
  helpers; `render_editor_to_buffer` gains a tabline row (row 0),
  shrinking `n_content` from `h - 1` to `h - 2`. Active tab is
  bracketed (`[scratch]`), others plain, joined with `|`.
- [x] **Tests.** `actions_test.hc` (+7): default-binding resolution,
  `NewBuffer` opens+backgrounds, `NextBuffer`/`PrevBuffer` cycle and
  wrap (including the single-buffer no-op case), `CloseBuffer`
  promotes the next buffer and refuses to close the last one.
  `render_test.hc` (+2, 1 updated): tabline row assertions; the
  pre-existing "typed content" test updated for the new row offset.
  `hilisp_host_test.hc` (+2): `(bind … 'new-buffer)` etc. round-trip.
  `runtime_test.hc` (+2): `Ctrl-o`/`Ctrl-n`/`Ctrl-w` reach
  `apply_action` end-to-end through the real `event_loop`/Terminal
  handler pipeline, same shape as the M4b HiLisp-rebind test.
  **72/72 tests green**: 29 actions + 6 render + 11 runtime + 22
  hilisp_host + 4 spawn.
- [x] **`hica fmt --check` + `hica analyse` 100/100** on every touched
  file (`fmt` needed one alignment pass on `hilisp_host.hc` and
  `runtime_test.hc` after the new match arms/tests were added).
- [x] **Docs.** This Goal/Plan/Log/Reflection; `docs/hedit-design.md`
  gains a multi-buffer section; README Status M5.5 line.

### Log

**Session 1 — 2026-08-19.**

Read the M5.5 sketch left in the "Follow-on" note (the section this
replaced) against the actual `KeyChord`/`Action`/`string_to_action`
shapes before writing any code — caught two mismatches early instead
of mid-implementation:

1. `Ctrl-tab` isn't representable — `KeyChord` is `Modifier + char`,
   and Tab is a `SpecialKey` delivered via `KSpecial`, which
   `resolve_action` never routes through the binding table. Swapped to
   `Ctrl-n`/`Ctrl-p` (free chords, unused by any existing binding).
2. `OpenFile(path)` can't be reached from a keybinding at all —
   `(bind chord 'symbol)` only ever produces zero-argument `Action`
   variants (`string_to_action : string -> maybe<Action>`), so there's
   no HiLisp-side way to supply a path even if we added the variant.
   Rather than add dead code, scoped the milestone down to `NewBuffer`
   (an in-memory scratch buffer, no path needed) and explicitly
   deferred `OpenFile` as a non-goal.

**The ring-instead-of-map decision.** The original sketch called for
`EditorState.buffers: list<BufferRef>` + `active: int` — a full
migration away from the `buffer: TextBuffer` field every pure helper
since M1 has depended on. Prototyping that shape on paper first: every
call site of `state.buffer` (and there are ~30 across `actions.hc`,
`render.hc`, `runtime.hc`, and every test file) would need to become
`active_buffer(state)` / `set_active_buffer(state, b)`, plus an
`active: int` that can point at a missing/stale id if not threaded
carefully. That's the same shape of risk M5's Reflection flagged for
`ref<Buffer>` migration — "does this field get read/written from a
currently-pure function? If yes, keep the field plain." `buffer`
*is* read/written everywhere. So instead: keep `buffer` as the sole
active-buffer field, and represent "the other open buffers" as a
`background_buffers` ring. `NextBuffer`/`PrevBuffer` just rotate the
ring (`cycle_next_buffer`/`cycle_prev_buffer` in `actions.hc`) — no
index to keep in sync, and zero changes needed to any pre-M5.5 pure
helper or test.

**hica gotcha (repeat of a known one).** `map(s2.background_buffers,
(b: TextBuffer) => b.lines)` in a test failed twice for two different
reasons: first the *unannotated* lambda `(b) => b.lines` hit the
known `hc_lines` prelude collision (repo memory notes this); adding
the type annotation `(b: TextBuffer) => ...` inline then hit a hard
parse error — hica's lambda-parameter syntax doesn't accept inline
type annotations at all (`(x: T) => …` parses as a tuple pattern, not
a typed parameter). Fixed by extracting a named top-level helper
(`fun buf_lines(b: TextBuffer) : list<string> => b.lines`) and passing
it point-free to `map` — the established workaround already used
elsewhere in this codebase (`binding_to_entry` in `hilisp_host.hc`).

**Stale `.kk` cache bit twice more.** Editing `model.hc`'s
`EditorState` shape without touching `runtime.hc` left a stale
`src/runtime.kk` around from a prior build, so `hica test
tests/runtime_test.hc` failed with a Koka arity error pointing at a
`.kk` file whose source (`runtime.hc`) hadn't even been edited this
session. Same fix as previous sessions: delete the stale generated
`.kk` next to its `.hc` and re-run — `hica` regenerates it against the
new `model.kk` automatically. Filed nowhere new; this is the same
known gap from repo memory (`hedit-hica-build.md`), just triggered by
a cross-module field change instead of a direct edit.

### Reflection

**What changed vs the plan.** The Follow-on sketch that kicked this
milestone off assumed a `buffers: list<BufferRef>` + `active: int`
migration and `Ctrl-tab`/`OpenFile(path)` bindings. Neither survived
contact with the actual `KeyChord`/`Action` shapes (see Log) — caught
during a pre-implementation read of the existing types, before writing
migration code, exactly the discipline M5's Reflection called out as
worth repeating. The ring-based `background_buffers` design shipped
instead, and required zero changes to any pure helper or test file
written before this milestone.

**What to carry forward:**

- **Before extending an enum-backed keybinding system, check whether
  the new action can actually be *reached* through it.** `OpenFile
  (path)` looked like a natural `Action` variant from the design doc's
  framing, but `string_to_action`'s zero-arg-symbol shape meant it was
  unreachable from any keybinding without a much bigger change (a
  prompt/argument-passing mechanism). Scope the milestone to what the
  *existing* dispatch mechanism can carry, and defer the rest
  explicitly rather than shipping a keybinding-less enum variant.
- **A rotation ring beats a list+index when "index" would otherwise
  need to be kept in sync with a separately-migrated field.** Same
  lesson as M5's `ref<Buffer>` fork, generalised: if a field is
  read/written pervasively by pure code, don't migrate it — wrap the
  *other* state around it instead.
- **The `hc_lines` collision needs a type annotation to fix, but hica
  lambdas don't support inline type annotations** — `(x: T) => …` is a
  parse error, not a type-checker error. The fix is always "extract a
  named top-level function", not "annotate the lambda parameter".
  Worth remembering as the *first* thing to try, not the second.

**What to change in the design doc:** `docs/hedit-design.md` §3's
`EditorState`/`TextBuffer` sketch (`buffers: Map<BufferId, TextBuffer>`,
`active_buffer_id`) predates this milestone's ring-based shape — a new
section documents what actually shipped, alongside a note that the
§3 sketch was aspirational, not binding, same as M5's `spawn Buffer`
sketch vs. what shipped.

**Ready for a further follow-on** once there's real demand for
per-buffer isolated undo/redo (the `spawn`-per-buffer pool) or a
path-prompt input widget for `OpenFile`. Both are scope-guarded above,
not started.

---

## Follow-on: further multi-buffer work (deferred)

Once there's real demand:

- **Per-buffer isolated undo/redo** — a `spawn Buffer` pool keyed by
  buffer id (the "counter-pool.hc" pattern), grown on `NewBuffer` and
  shrunk on `CloseBuffer`, replacing the current single shared
  `Buffer` instance in `event_loop`.
- **`Action::OpenFile(path)`** — needs a command-line/path-prompt
  input widget first; `(bind …)` can't carry an argument today.
- **Stable tabline ordering** independent of ring rotation.
- Split panes / windows (`PaneNode`).

---

## Milestone M6 — CLI arg parsing + real file loading

### Goal

hedit gains a real command-line surface via the `std/cli` prelude
(`cli-prelude.hc` / `cli_spec.hc` pattern already used in `hicurl`),
and — the part that actually matters — a file path passed on the
command line stops being metadata-only. Today `new_buffer(bid, path)`
stores `path` but never reads the file (see `model.hc`'s own comment:
"a real file-open step will come with the `fs` effect later"); this
milestone closes that gap.

**This milestone alone does NOT make hedit usable interactively** —
`main.hc`'s `Terminal` handler is still the M1 stub (hardcoded
canned `Ctrl-q`, `render_frame` just dumps lines via `println`). That
flip happens in M7. M6 is the CLI-parsing + real-content-load
foundation M7 builds on.

**Scope:**

- Single `[FILE]` positional (optional). Opening *multiple* files from
  argv into `background_buffers` is a non-goal here — no evidence yet
  that `std/cli`'s positional handling supports a repeatable arg
  cleanly, and a single file covers the exit criteria below. Revisit
  as a follow-on once real demand shows up.
- `--help` / `--version` — free from `cli()` / `cli_help` /
  `cli_version_str`, no hedit-side code needed beyond wiring
  `cli_parse`'s `Help`/`Version` arms in `main.hc`.
- Missing/unreadable file → status message (mirrors the existing
  `load_user_config` error-surfacing pattern), never a crash.
- **Non-goals (deferred to M8):** `--config`/`--no-config` override,
  `--tabsize`, `--readonly`, `+LINE:COL`. Keeping M6 to "parse argv,
  load one real file" keeps it small and independently testable.

### Plan

- [x] **`src/cli_spec.hc` (new).** `make_spec()` — `cli("hedit",
  "0.2.0", "a terminal text editor in hica") |> arg("file", "file
  to open", false)`. No flags yet (those land in M8) — this file's job
  is just the positional + free `--help`/`--version`.
- [x] **`src/model.hc`.** New `pub fun load_buffer(new_bid: int, path:
  maybe<string>)` that calls `read_file` when `path` is `Some(p)` and
  splits into `lines` (dropping one trailing-newline artifact so it
  round-trips with `save_buffer`'s `join(lines, "\n") + "\n"`); falls
  back to today's empty-scratch-buffer shape on `None` or a read error
  (with the error surfaced as a status message, same pattern as
  `config_loader.hc::load_user_config`). `new_buffer` itself is
  untouched — a new `init_editor_with_buffer` constructor lets
  `main.hc` assemble `EditorState` from an already-loaded buffer
  without touching the pure `init_editor`/`init_editor_with_config`
  surface every earlier test depends on.
- [x] **`src/main.hc`.** `argv` now goes through `cli_parse(spec)`;
  `Help`/`Version`/`CliError` print and exit before any editor state
  is built; `Parsed(r)` hands `get_positional(r, 0)` to `load_buffer`,
  merges its status message with the config-load status
  (`combine_status`), and feeds the loaded buffer into
  `init_editor_with_buffer`.
- [x] **Tests.** New `tests/cli_test.hc` (4 tests): `--help` → `Help`,
  `--version` → `Version`, a file argument resolves the `[FILE]`
  positional, no arguments leaves it `None`. New `tests/model_test.hc`
  (4 tests): real file content loads into `lines`, a file with no
  trailing newline keeps its last line, a missing path falls back to
  an empty buffer *and* sets a status message, `None` path returns the
  plain empty scratch buffer.
- [x] **`hica fmt --check` + `hica analyse` 100/100** on every new/edited
  file — required two rounds of rework, see Log.
- [x] **Docs.** This Goal/Plan/Log/Reflection; `docs/hedit-design.md`
  gains §11; README Status gains an M6 line.

### Exit criteria

- [x] `hica check src/main.hc` clean.
- [x] `hica build src/main.hc -o hedit` succeeds.
- [x] All existing suites stay green; new `tests/cli_test.hc` +
  `tests/model_test.hc` pass. **80/80 tests green**: 29 actions + 6
  render + 11 runtime + 22 hilisp_host + 4 spawn + 4 cli + 4 model.
- [x] `./hedit --help` prints usage and exits 0; `./hedit --version`
  prints the version and exits 0.
- [x] `./hedit <file>` ends its single stub-handler tick showing the
  *real* file content in the dumped lines, not an empty buffer —
  provable without a real tty, which is exactly why this is split out
  from M7.

### Log

**Session 1 — 2026-08-20.**

Followed the plan closely — `cli_spec.hc` mirrors `lib/hilisp/src/main.hc`'s
already-shipped `std/cli` usage almost verbatim (same `cli()` \|>
`arg()` shape, same `Help`/`Version`/`CliError`/`Parsed` dispatch in
`main`). `load_buffer` mirrors `config_loader.hc::load_user_config`'s
shape: `(value, maybe<string>)` so a load failure never crashes, it
just surfaces a status message. Confirmed `read_file`/`write_file`/
`get_env` are effectively global builtins in this hica build — none of
`config_loader.hc`/`runtime.hc` import `std/io` yet call them directly,
so `model.hc` doesn't need the import either.

Three hica rough edges surfaced, all fixed within this session (now in
repo memory):

1. **Tuple-of-`maybe` match infers a spurious `exn` effect.**
   `combine_status`'s first draft matched `(a, b)` as a pair covering
   all four `(None\|Some) × (None\|Some)` combinations — exhaustive, and
   `hica check` agreed. `hica build`'s real koka compile disagreed:
   "effects do not match, inferred `<exn\|_e>`, expected `total`" on an
   otherwise pure string-concat function. Rewriting as nested single
   matches (`match a { None => …, Some(x) => match b { … } }`) made the
   spurious effect disappear. Filed as a build gotcha, not a hica
   issue — no minimal repro isolated yet, and this is the kind of
   thing better reported with one once it recurs somewhere less
   time-pressured.
2. **`hica analyse` flags any nested `match` on maybe/result as HIGH,**
   dropping both `combine_status` and `load_buffer` to 92/100 even
   after fix #1 (a 2-level match, not a real debt smell). Extracted
   the inner match into its own named helper in both cases
   (`combine_with`, `load_existing_buffer`) — same shape
   `config_loader.hc`'s `read_first`/`load_user_config` split already
   uses. Back to 100/100 without changing behaviour.
3. **Fixing #2 by extracting `load_existing_buffer` broke the build
   again**, and not for the reason expected. `load_buffer` kept its
   explicit `: (TextBuffer, maybe<string>)` return-type annotation,
   and now that its body was *only* a match dispatching to the
   extracted helper (rather than calling `read_file` directly), Koka
   misinferred "expected effect: total" again — regardless of whether
   the helper itself carried an annotation. This is the same class of
   bug repo memory already had a note for ("functions that
   transitively call IO effects must NOT have explicit return type
   annotations"), just one call-level further removed than the
   existing note covered. Dropping `load_buffer`'s return-type
   annotation fixed the build — but immediately reintroduced the
   `hc_lines` prelude collision at every call site that destructures
   the tuple and then reads `.lines` (the receiver type is no longer
   pinned). Fixed *there* instead, per the existing `hc_lines` note:
   annotate the `let` binding, not a tuple-destructuring pattern —
   `let result : (TextBuffer, maybe<string>) = load_buffer(...); let
   buf = result.0`. `tests/model_test.hc` was the only caller that
   reads `.lines`, so `main.hc`'s call site didn't need the same
   treatment.

`.koka`'s cached `std/cli` module (`cli.kki`) also kept corrupting
itself mid-session — not once but twice more after a clean, on builds
that touched `model.hc`. `hica clean --cache && rm -rf .koka` resolved
it every time; just needed re-running after the second and third
recurrence instead of assuming the first clean should have been
enough.

### Reflection

**What changed vs the plan.** The shape shipped is almost exactly what
was planned — the only structural addition not in the original plan is
`init_editor_with_buffer`, needed once it became clear `main.hc` has to
assemble `EditorState` from an *already-loaded* `TextBuffer` rather than
a bare path, without disturbing `init_editor_with_config`'s existing
contract. Everything else (file layout, function names, test shape)
matched the plan; the friction was entirely in getting `hica build` and
`hica analyse` to agree on the same code, not in the design.

**What to carry forward:**

- **`hica check` passing is not sufficient evidence a shape will
  `hica build`.** Two of this session's three gotchas (#1 and #3) only
  showed up in the real koka compile, after `hica check` had already
  said the file was clean. Budget a real `hica build` (or `hica test`)
  pass before considering a milestone's Plan checkbox done, not just
  `hica check`.
- **De-nesting a `match` to satisfy `hica analyse` is not a free
  refactor — verify the build still passes afterward.** Extracting
  `load_existing_buffer` fixed the analyse score but broke the build
  for an unrelated reason (the effect-annotation gotcha); the two
  tools' feedback loops don't compose for free, re-run both after every
  change chasing either one.
- **The `hc_lines`-collision fix (annotate the binding) generalises to
  any call site consuming a tuple whose return type isn't pinned on
  the function itself** — not just the single-value case the existing
  note described. `let result : (T, U) = f(...); let x = result.0` is
  the general form; tuple-destructuring `let (a, b) = ...` doesn't take
  an inline annotation.
- **Cache corruption on `std/cli` needs repeated cleaning, not just
  one.** Don't stop at the first `hica clean --cache && rm -rf .koka`
  if the exact same parse error reappears — it did, twice more, on
  builds that only touched `model.hc` (a file that doesn't even import
  `std/cli`).

**What to change in the design doc.** New §11 written to match the
shipped shape (CLI spec file, `load_buffer`/`init_editor_with_buffer`
split, status-message merge in `main.hc`).

**Ready for M7** — the native `Terminal` handler is the next milestone,
unblocked by this one's real file-loading foundation.

---

## Milestone M7 — Native `Terminal` handler (raw mode)

### Goal

Replace `main.hc`'s M1 stub `Terminal` handler with a real POSIX
handler: raw-mode tty, byte-at-a-time keyboard decode into hedit's
existing `Event`/`Key` types (`keys.hc` — unchanged), a real window
size query, and a real ANSI render (clear + redraw). **This is the
milestone whose exit criteria is "usable by an end user"** — everything
before it (M1-M6) built a pure, well-tested core with a synthetic
front door.

**Scope:**

- Raw mode on/off via a C FFI wrapper around `tcgetattr`/`tcsetattr`
  (termios) — following the project's established Koka C FFI
  conventions (no `ctx` parameter; call `kk_get_context()` inside the
  C body; see repo memory `hedit-hica-build.md` equivalents in the
  hica repo). Raw mode **must** be restored on every exit path
  (`Ctrl-q`, and ideally a crash/signal — best-effort for v1, a
  `SIGINT`/`SIGTERM` handler is a stretch item, not a blocker).
- `poll_event()`: blocking read of one byte from stdin; decode
  `Ctrl-<letter>` (control bytes 0x01-0x1a), plain printable bytes
  (`KChar`), and the small set of ANSI escape sequences needed for
  `SpecialKey` values that already exist in `keys.hc` (`Enter`,
  `Backspace`, `Tab`, `Esc`, arrow keys). **Non-goal:** wiring arrow
  keys to an actual editing `Action` — `model.hc`'s `Action` enum has
  no `MoveUp`/`MoveLeft`/etc. variants yet, so decoding the escape
  sequence into `KSpecial(ArrowUp)` is as far as this milestone goes;
  making the cursor actually move is its own follow-on.
- `get_dimensions()`: real terminal size via `ioctl(TIOCGWINSZ)` (C
  FFI) with a `COLUMNS`/`LINES` env-var fallback if the ioctl fails
  (e.g. piped output).
- `render_frame(buf)`: full-redraw ANSI (`\x1b[2J\x1b[H` then print
  each line) — no diffing/partial-redraw optimization in this pass.
- `set_cursor_style`: can stay a no-op if the ANSI cursor-shape escape
  isn't a priority; note it explicitly as deferred rather than
  silently skipping it.

### Plan

- [x] **New C FFI module** (`src/term_ffi.kk` + `src/term_ffi_inline.c`)
  — shape changed from the original proposal once a working precedent
  was found (see Log): `read_key() : io int`, `term_cols() : io int`,
  `term_rows() : io int`, `flush_stdout() : io ()`. No
  `enable_raw_mode`/`disable_raw_mode`/`read_byte`/`term_size` — raw
  mode is `stty` via `exec`, and escape-sequence assembly happens
  inside the C FFI itself rather than as a separate pure decode step.
- [x] **`src/main.hc`.** Stub `handle Terminal { … }` arms swapped for
  native ones; `enable_raw_mode()`/`disable_raw_mode()` wrap the
  `event_loop` call (both are thin `exec("stty …")` wrappers, not FFI).
- [x] **Escape-sequence decode helper** — shipped as
  `src/keys.hc::decode_key(code: int) : Event`, not `list<int> -> Key`
  (see Log for why the signature changed). Pure, unit tested against
  every code class (printable, control, synthetic arrow, EOF) without
  needing a real tty.
- [x] **Tests.** `tests/keys_test.hc` — 6 unit tests for `decode_key`.
  Manual QA checklist (can't be automated away):
  - [x] `./hedit` with no args opens an empty scratch buffer, typing
    inserts characters, `Ctrl-q` quits cleanly. *(verified non-
    interactively: `printf 'hix\021' | ./hedit` → buffer shows `hix`,
    exit code 0.)*
  - [x] `./hedit somefile.txt` shows real file content / creates it on
    save. *(verified: `./hedit /tmp/hedit_smoke.txt` then `hi` +
    Ctrl-S + Ctrl-Q → file contains `hi`, status line showed
    "Saved".)*
  - [x] `Ctrl-s` saves and the status line shows "Saved". *(verified,
    same run as above.)*
  - [ ] `Ctrl-c`/`Ctrl-v`, `Ctrl-z`/`Ctrl-y`, `Ctrl-o`/`n`/`p`/`w` all
    work as documented in `docs/notes.md`. *(covered end-to-end
    against the **scripted** Terminal handler in `runtime_test.hc`;
    not yet re-verified against the native one in a real interactive
    session — this tool has no way to send raw control bytes to an
    interactive tty. Needs a human pass.)*
  - [x] After quitting, the shell prompt / terminal echo is back to
    normal (raw mode was restored). *(verified: `stty -a` after exit
    shows `icanon isig … echo` — sane, not raw.)*
  - [ ] Resizing the terminal window doesn't crash the editor (picked
    up on the next `get_dimensions()` tick). *(not exercised — needs a
    human pass with a real terminal resize.)*
- [x] **`hica fmt --check` + `hica analyse`** on every new/edited `.hc`
  file — all clean, 100/100 (the `.kk`/`.c` FFI files are hand-written
  and out of scope for `hica fmt`/`analyse`).
- [x] **Docs.** Log + Reflection below; `docs/hedit-design.md` §4.1's
  "M1 stub / M2 real" comment now documents the real M7 handler;
  README quick-start flips from "synthetic run" to real usage.

### Exit criteria

- `hica build -o hedit` produces a binary.
- Running `./hedit [file]` in a real terminal: a person can open a
  file (or start scratch), type, save, copy/paste, undo/redo, switch
  buffers, and quit — and the terminal is left in a sane state
  afterward. **This is the "usable by an end user" bar.**
- The manual QA checklist above is fully checked off by whoever ships
  this (can't be automated away — call it out plainly rather than
  skipping it).
- All pre-existing automated suites (`actions_test`, `render_test`,
  `runtime_test`, `hilisp_host_test`, `spawn_test`, `cli_test`) stay
  green — the headless test harness is untouched; only `main.hc`'s
  handler wiring changes.

### Log

1. **A working precedent existed and reshaped the whole plan.** Before
   writing any FFI by hand, the user pointed at
   `hicurl/src/http_exec.hc` (a sibling project) as an FFI example.
   Reading `hicurl/src/http_ffi.kk` + `http_ffi_inline.c` confirmed the
   exact hica-side syntax (`extern import "modname"` pulling in a
   hand-written `.kk` + `c file "shim.c"`) and the kklib conventions
   (`kk_get_context()`, `kk_integer_from_int`, `kk_std_core_types__new_TupleN`
   for multi-value returns). That in turn led to searching
   hica-ecosystem for a terminal-specific precedent, which turned up
   `programs/myeon/term_raw.kk` + `term_raw_ffi.c` — **the same
   author's own prior solution to this exact problem** (a hica TUI
   program needing raw-mode single-key reads + terminal size). Adopting
   that shape wholesale (renamed `hedit_*`) meant:
   - No `enable_raw_mode`/`disable_raw_mode`/`read_byte`/`term_size` C
     FFI at all — `myeon.hc` toggles raw mode with a plain `exec("stty
     raw -echo icrnl 2>/dev/null")` / `exec("stty sane 2>/dev/null")`,
     which is already effect-total (`<exec>`) via hica's own
     `exec` builtin. Zero termios save/restore C to write, test, or
     get wrong.
   - Escape-sequence assembly (the 100ms `select()` window to
     distinguish a lone `Esc` from `ESC [ A`) lives **inside the C FFI**,
     which returns synthetic int codes `1001..1004` for the arrows
     directly. So the "pure decode" seam collapsed from the planned
     `list<int> -> Key` (fed by a separate impure byte-gathering loop)
     down to a single `decode_key(code: int) : Event` — simpler, and
     the C code + the codes it returns are literally copy-pasted from
     a file that's already known to work.
   - `hica`'s own `src/emit/codegen.kk` has a `rawterm` entry in its
     `effectful-prims` list containing exactly `read_key`, `term_cols`,
     `term_rows`, `flush_stdout` — i.e. the compiler already
     special-cases these four names for effect-annotation inference.
     Naming the FFI wrappers in `term_ffi.kk` identically (rather than
     `hedit_read_key` etc. on the Koka side) means any future hedit
     `.hc` code calling them transitively gets the same "don't
     annotate the return type" treatment documented elsewhere in repo
     memory, for free.
2. **First real build hit the known `cli.kki` cache corruption twice.**
   Both times: `hica clean --cache && rm -rf .koka` then `hica
   --version` (to re-extract the stdlib) before rebuilding. Matches
   the existing repo-memory note that this can recur more than once
   per session even on builds that don't touch `std/cli` directly.
3. **Raw-mode CRLF staircase.** First interactive smoke test showed
   every rendered line indented one column further right than the
   last. Root cause: `stty raw` disables output post-processing
   (`OPOST`), so a bare `"\n"` from `println` doesn't imply a carriage
   return the way it does in cooked mode. Fixed by building the whole
   frame as one string joined with `"\r\n"` (`join(buf.lines, "\r\n")`)
   and a single `print` + `flush_stdout()`, instead of `foreach(buf.lines,
   println)`.
4. **No way to send raw control bytes (Ctrl-q, Ctrl-s, …) through this
   tool's interactive terminal.** `send_to_terminal` types literal
   characters + Enter; there's no mechanism here to inject a bare
   `0x11`/`0x13` byte into a live pty. Worked around it by piping
   scripted bytes on stdin instead (`printf 'hi\023\021' | ./hedit`),
   which still exercises the real native handler (raw mode off a
   non-tty stdin is a harmless no-op for `stty`, and `read(0, …)` works
   identically on a pipe) — confirmed typing, Ctrl-s save-to-disk, and
   Ctrl-q quit-with-exit-0 this way, plus `stty -a` showing sane flags
   restored afterward. Ctrl-c/v/z/y/o/n/p/w interactive confirmation
   and terminal-resize handling are left for a human pass (see the
   Plan checklist above) — they're already covered end-to-end against
   the *scripted* handler in `runtime_test.hc`, so the remaining risk
   is narrowly "does the native FFI decode the same way", which
   `decode_key`'s unit tests plus the piped smoke tests already cover.

### Reflection

**What changed vs the plan.** The C FFI surface shrank a lot: 4
functions instead of the originally-scoped `enable_raw_mode` /
`disable_raw_mode` / `read_byte` / `term_size`, because a working
precedent (`programs/myeon` in hica-ecosystem) proved `stty` via
`exec` is enough for raw-mode toggling and that escape-sequence
assembly is simpler to do inside the C FFI than as a separate pure
`list<int> -> Key` layer. The pure/testable seam ended up being
`decode_key(code: int) : Event` rather than the planned `list<int> ->
Key` — narrower in scope but exactly as testable, and it matches an
already-proven contract instead of inventing a new one.

**What to carry forward:**

- **Before hand-writing any hica C FFI, check for a sibling project or
  hica-ecosystem program that already solved the same problem.** Two
  precedents existed for this milestone (`hicurl` for general FFI
  syntax/kklib conventions, `programs/myeon` for the terminal-specific
  problem) and reading both first turned an estimated ~150-line
  termios implementation into a ~70-line adaptation of code that was
  already known to work, with a smaller test surface.
- **`hica`'s own `effectful-prims` list in `codegen.kk` is worth
  grepping when naming a hand-written FFI wrapper** — reusing an
  already-special-cased name (`read_key`, `term_cols`, `term_rows`,
  `flush_stdout`) means the compiler's own effect-annotation inference
  treats calls to it consistently with its built-in rawterm ops, for
  free.
- **Raw mode (`OPOST` off) breaking bare `"\n"` line endings is a
  real, easy-to-miss gotcha** — worth a permanent repo-memory note:
  any full-frame redraw under `stty raw` must join lines with `"\r\n"`
  explicitly.
- **This tool's terminal integration cannot send raw control bytes to
  an interactive pty.** Piping scripted bytes via stdin
  (`printf '...' | ./program`) is the workaround for smoke-testing
  Ctrl-chord handling non-interactively — worth remembering for future
  milestones that need to exercise raw keyboard input without a human
  at a real terminal.

**What to change in the design doc.** `docs/hedit-design.md` §4.1 now
documents the M7 shape (FFI module, `decode_key`, `stty`-based raw
mode, the CRLF gotcha) in place of the old "M1 stub, M2 real" text
that was already stale (M2 didn't actually ship a real Terminal
handler — that slipped to M7 as this journal's own milestone map
shows).

**Ready for M8** — CLI polish for end users is the next (and, per the
milestone map, final currently-planned) milestone.

---

## M7 revisit — fixing the basics (2026-08)

### Goal

M7 was committed and the manual QA checklist was mostly checked off,
but real end-user usage surfaced three basics that didn't actually
work: typed non-ASCII input (`åäö`), terminal resize, and editing an
existing file (inserting/deleting anywhere but the end of a line).
This is a bugfix pass over the M7 handler, not a new milestone.

### What was actually broken

- **`åäö` didn't work.** `hedit_read_key` read stdin one raw byte at a
  time. A UTF-8 character like `å` (`0xC3 0xA5`) came through as two
  separate out-of-range bytes, each decoded by `decode_key` as a stray
  `Esc` (its catch-all fallback).
- **Resize didn't work.** `event_loop_step` already recomputed
  `get_dimensions()` every tick, but the loop only ticks on a
  *blocking* `read()` in `hedit_read_key`. A `SIGWINCH` with no signal
  handler installed doesn't interrupt that blocking read, so nothing
  redrew until the next real keystroke — resizing the window did
  nothing visible until you typed something.
- **Editing an existing file didn't work.** Two compounding bugs:
  `insert_char` always appended at the *end* of the current line
  regardless of the cursor's column (a documented M1 simplification
  that was never revisited), and `resolve_action` mapped every
  `KSpecial` (Enter, Backspace, all four arrows) to `Ignore` — so
  there was no way to move the cursor, start a new line, or delete a
  character. On top of that, `render_frame` never positioned the real
  terminal cursor, so it visually sat wherever the last full-redraw's
  `ESC[H` left it, with no relationship to the logical edit position.

### Fixes

- `src/term_ffi_inline.c`: `hedit_read_key` now detects a UTF-8 leader
  byte (`>= 0xC0`) and reads the right number of continuation bytes,
  decoding the whole sequence into a single Unicode codepoint (hica's
  `char`/`string` are codepoint-based, not byte-based — confirmed via
  `chr(229)` → `"å"` and `length` counting chars, not bytes). Also adds
  a `select()` with a 200ms timeout ahead of the blocking `read()`,
  returning sentinel `-2` on timeout so the caller gets a periodic
  wake-up (and therefore a fresh `get_dimensions()` + redraw) even
  with no keyboard input.
- `src/keys.hc`: `decode_key` maps `-2` to `Tick` and any
  `code >= 128` to `KChar(chr(code))` (the decoded UTF-8 codepoint).
- `src/actions.hc`: `insert_char` is now cursor-column-aware (splices
  at `cur.pos.col` instead of appending). New `insert_newline`
  (splits the line, cursor moves to col 0 of the new line),
  `delete_backward` (deletes before the cursor, or merges into the
  previous line at column 0 — a no-op at the very start of the
  buffer), and `move_left`/`move_right`/`move_up`/`move_down` (left/
  right wrap at line boundaries, up/down clamp the column to the
  target line's length). `resolve_action` now maps
  `KSpecial(Enter/Backspace/ArrowUp/Down/Left/Right)` to these instead
  of falling through to `Ignore`.
- `src/model.hc`: new `Action` variants `NewLine`, `DeleteBackward`,
  `MoveUp`/`MoveDown`/`MoveLeft`/`MoveRight`; `ScreenBuffer` gained
  `cursor_row`/`cursor_col` (1-indexed).
- `src/render.hc`: `render_editor_to_buffer` computes the head
  cursor's screen position, clamped to the visible viewport (no
  scroll-offset tracking yet — a cursor past the fold pins to the
  last visible row/col rather than scrolling; that's a separate
  follow-up).
- `src/main.hc`: `render_native` appends a trailing `ESC[{row};{col}H`
  after the frame so the real terminal cursor visibly tracks the edit
  position.
- `src/runtime.hc`: `NewLine`/`DeleteBackward` snapshot the buffer for
  undo, same as `Insert`.
- `src/hilisp_host.hc`: `action_to_string` grew match arms for the new
  `Action` variants (Koka's exhaustiveness check caught this
  immediately at build time).

### Log

1. **Naming collision between two different types' constructors.**
   The first attempt named the new backspace `Action` variant
   `Backspace` — colliding with the pre-existing `SpecialKey.Backspace`
   constructor from `keys.hc`. This didn't fail where the ambiguous
   name was defined; it failed in a *different* file
   (`hilisp_host.hc`'s `action_to_string`, matching on `a : Action`)
   with "expected Action, got SpecialKey" — hica/Koka resolved the
   bare constructor name against the wrong type globally rather than
   scoping it to the match's target type. Fixed by renaming to
   `DeleteBackward`. Worth remembering: hica type constructor names
   appear to need to be unique across the whole program, not just
   within their own `type` block — a collision surfaces as a
   confusing type error at an unrelated call site, not at the
   declaration.
2. **The recurring `cli.kki` stale-cache parse error showed up again**
   mid-session, on a build that only touched `.hc` files far from
   `std/cli`. `hica clean --cache && rm -rf .koka` (twice) cleared it,
   consistent with the existing repo-memory note that one clean isn't
   always enough.
3. **Verification without a real terminal.** Confirmed all three
   fixes end-to-end via piped scripted bytes (this tool can't send
   raw control bytes to an interactive pty — see the M7 Log above):
   `printf 'h\xc3\xa5i\021' | ./hedit` rendered `håi` correctly
   (proving the UTF-8 decode + re-encode round-trip); `printf
   'ab\ncd\177\177\177\021' | ./hedit` walked Enter-then-triple-
   Backspace back down to a merged `ab` line at the correct cursor
   position; `printf 'hi\033[DX\021' | ./hedit` (arrow-left, insert)
   produced `hXi`, confirming column-aware insertion against a real
   ANSI arrow-key escape sequence, not just the synthetic decode_key
   unit tests.

### Reflection

**What to carry forward:**

- M7's own manual QA checklist explicitly flagged terminal-resize and
  several Ctrl-chords as "needs a human pass" — but it didn't flag
  "type in the middle of an existing file" or "non-ASCII input" as
  open risks at all, because the *scripted* test harness in
  `runtime_test.hc` only ever fed single-cursor, end-of-line,
  ASCII-only `KeyEvent`s. The pure/scripted test suite proved the
  dispatch pipeline works; it never exercised whether the pipeline
  covered the actions a real editing session needs. Lesson: a green
  test suite over a narrow event vocabulary can hide "the feature
  doesn't exist yet" as effectively as it hides "the feature is
  buggy" — worth explicitly listing the *action* coverage (not just
  the effect-handler coverage) a milestone's exit criteria implies.
- hica's compile-time exhaustiveness check on `action_to_string`'s
  `match` immediately caught every new `Action` variant that needed a
  string mapping — a good example of leaning on the type checker
  instead of a manual "search all call sites" pass when growing a
  closed sum type.

**Ready for M8** — same as before this revisit; CLI polish is still
the next planned milestone.

---

## Milestone M8 — CLI polish for end users

### Goal

Round out the flag set sketched during planning (micro-inspired,
trimmed to what hedit can actually act on): config overrides, a
tabsize override, read-only mode, and `+LINE:COL` startup
positioning. By the end of this milestone the flags explored at the
start of the M6-M8 arc are all real, and the docs describe a genuine
end-user quick-start (not just "run the synthetic stub").

**Scope:**

- `--config <path>` / `-c` — bypass `candidate_paths`'s XDG/HOME
  search in `config_loader.hc`, load this file instead.
- `--no-config` — skip `load_user_config` entirely (reproduce bugs
  without a user's `init.hl` in the loop).
- `--tabsize <n>` — inserts/overrides a `("tabsize", n)` entry in
  `Config.values` *after* `init.hl` is loaded (CLI wins over config
  file, matching micro's session-override precedence).
- `--readonly` / `-R` — gates the `Save` action (in `runtime.hc`'s
  `save_buffer` or `apply_action`) with a "read-only — not saved"
  status message instead of writing.
- `+LINE[:COL]` — a second, special-shaped positional (not a
  `flag`/`option` — matches micro's own syntax) parsed before
  `cli_parse` sees the rest, or as a pre-pass over `get_args()`; sets
  the initial cursor `Position` on the opened buffer (clamped to
  valid line/col bounds — out-of-range values shouldn't crash).

### Plan

- [x] **`src/cli_spec.hc`.** Add `flag("readonly", "R", …)`,
  `flag("no-config", "", …)`, `option("config", "c", …)`,
  `option("tabsize", "", …)`.
- [x] **`src/config_loader.hc`.** `load_user_config` grows an
  optional explicit-path parameter and a skip bool (or a small wrapper
  function so the existing signature/tests stay intact).
- [x] **`src/main.hc`.** Thread the new flags: build `cfg0` from
  `default_config()`, conditionally skip/override the HiLisp load,
  then apply `--tabsize` as a post-load `Config.values` override
  before `init_editor_with_config`.
- [x] **`src/model.hc` / `src/actions.hc`.** `readonly: bool` on
  `Config` (or `EditorState`); `Save` action checks it first.
  `+LINE:COL` parsing feeds directly into `Cursor.pos` at buffer
  construction.
- [x] **Tests.** One test per new flag's plumbing in `cli_test.hc` +
  a `config_loader_test`/`actions_test` case each for the readonly
  gate, the tabsize override precedence, and `+LINE:COL` clamping
  (negative/out-of-bounds values don't crash).
- [x] **`hica fmt --check` + `hica analyse` 100/100** on every touched
  file.
- [x] **Docs.** `docs/notes.md` gains a "Command-line usage" section
  (paste real `hedit --help` output); README quick-start becomes
  `hedit path/to/file.txt`; this section's Log + Reflection.

### Exit criteria

- All four new flags exercised by a green test each.
- `hica run src/main.hc -- --help` output is accurate and complete
  for every flag shipped across M6-M8.
- `docs/notes.md` and `README.md` describe a real end-user quick-start
  (install → `hedit somefile.txt` → edit → `Ctrl-s` → `Ctrl-q`) with no
  caveats about synthetic/stub behavior remaining.

### Log

- Went with a plain `readonly: bool` field on `Config` rather than
  `EditorState` — every other CLI-derived setting already lives on
  `Config`, and it meant `save_buffer`'s existing `state.config.…`
  access pattern needed no new plumbing. Adding the field meant
  updating all 3 `Config { … }` construction sites in the codebase
  (`model.hc::default_config`, `hilisp_host.hc::config_from_env`,
  `tests/actions_test.hc`) — a quick `grep` for `Config \{` up front
  found all of them in one pass.
- `load_user_config_opts` deliberately does *not* replace
  `load_user_config` — it's a thin wrapper that dispatches to either
  the existing (untouched, still independently tested) XDG/HOME
  search or a new `load_config_from_path` helper, sharing the
  Ok/Err→status-message shaping via an extracted `apply_config_src`
  helper. Kept `load_user_config`'s own tests passing unmodified.
- `+LINE:COL` parsing (`cli_spec.hc::parse_position_arg`) isn't part
  of the `std/cli` spec at all — `std/cli` has no notion of a
  `+`-prefixed positional, and trying to shoehorn it in as a regular
  `arg()` would've meant `+42` and a real filename fighting over the
  same `[file]` positional slot. Instead `extract_position_arg` pulls
  the first `+…` token out of `get_args()` by hand *before*
  `cli_parse_args` ever sees the rest — order-independent (`hedit +10
  f.txt` and `hedit f.txt +10` both work), pure, and easy to unit-test
  without touching `CliSpec` at all.
- Hit the `hica analyse` "nested match on maybe/result" HIGH-severity
  rule again on the first draft of `parse_line_col` (parsing
  `LINE:COL`'s two `parse_int` calls as one nested match) — same fix
  as every previous time (see repo memory / M6 note): extract the
  inner match into its own single-match helper
  (`with_parsed_line`). Back to 100/100 immediately.
- Found a new Koka reserved-word collision: a test-local variable
  named `exists` fails with a parse error ("unexpected exists") —
  add to the running list alongside `val`/`raw`/`prefix`/`now`.
  Renamed to `was_written`.
- Verified all four flags end-to-end against the real `./hedit`
  binary (not just the pure `cli_test.hc` plumbing tests), since
  `std/cli` parsing being correct doesn't guarantee the CLI→Config→
  EditorState wiring in `main.hc` is: `--readonly` + scripted
  `Ctrl-s` bytes confirmed the target file was never created;
  `+2 file.txt` + a scripted insert-then-save confirmed the char
  landed on line 2 of the saved file; `--config <path>` and
  `--config <path> --tabsize <n>` both surfaced the expected
  `"Loaded config from …"` status text in the rendered frame;
  `--no-config` confirmed no status text appears at all. Same
  scripted-stdin-bytes technique as M7 (this tool can't send raw
  control bytes to an interactive pty).
- No stale-`cli.kki` cache corruption this session, but did the
  precautionary `hica clean --cache && rm -rf .koka` before the first
  build anyway per the recurring repo-memory note — worth doing
  reflexively whenever a build touches `main.hc`/`cli_spec.hc`.

### Reflection

**What went well:**

- Splitting `load_user_config_opts` out as a thin dispatcher over the
  *existing* `load_user_config` (rather than growing its parameter
  list) meant zero risk to already-green tests — the diff to
  `config_loader.hc` is purely additive.
- The `+LINE:COL` "not part of the CLI spec, hand-parsed out of argv
  first" design avoided a whole class of `std/cli` positional-arity
  conflicts and made the parsing itself trivially pure/testable in
  isolation — no `CliResult` plumbing needed for it at all.
- Smoke-testing all four flags against the compiled binary (not just
  `cli_test.hc`'s pure parsing tests) caught the class of bug that
  parsing-only tests structurally can't: whether `main.hc` actually
  *does* anything with the parsed value. Worth keeping as a standard
  last step for any CLI-surfaced milestone, not just this one.

**What to carry forward:**

- The "extract to a helper to satisfy `hica analyse`'s nested-match
  rule" fix is now common enough (M6, M7 revisit, M8) that it's
  basically reflexive — reach for it on sight rather than debugging
  the rule each time.
- New reserved word discovered this session: `exists`. Keep growing
  this list (`val`, `raw`, `prefix`, `now`, `exists` so far) — it's
  cheap insurance against a confusing "unexpected X" parse error deep
  in a generated `.kk` file.

**Ready for M9** — "Save As" / `OpenFile` prompt is next.

---

## Handy commands

```sh
# Type-check + effect row
hica check src/main.hc

# Build the editor binary
hica build -o hedit

# Run the (currently synthetic) editor
hica run src/main.hc

# Test suites
hica test tests/actions_test.hc
hica test tests/hilisp_host_test.hc
hica test tests/runtime_test.hc      # created in M1

# Formatting + linting (must pass on any file we touch)
hica fmt --check src/runtime.hc
hica analyse src/runtime.hc

# Cleanup
hica clean          # Remove .kk files and binaries in src folder
hica clean --cache  # remove ~/.hica/stdlib.
hica clean --full.  # Remove generated files, ~/.hica/stdlib. and the .koka directory
```

---

## Milestone M9 — "Save As" / `OpenFile` prompt

### Goal

Today `Ctrl-s` on a scratch buffer (`buffer.path == None` — the
default when hedit is started with no `[FILE]` argument, or via
`Ctrl-o`'s `NewBuffer`) just sets the status message to `"No file —
save not possible"` (see `docs/notes.md`'s Save semantics section)
and there is no way to open an existing file once hedit is already
running (`OpenFile(path)` has been a called-out non-goal since M5.5).
Both gaps have the same root cause: hedit has no way to ask the user
for a filename mid-session. This milestone adds the smallest widget
that closes both gaps — a single-line text-input prompt — without
growing into a full command palette.

**Scope:**

- A minimal `Prompt` state on `EditorState` (e.g.
  `pub type Prompt { NoPrompt, SaveAsPrompt(text: string), OpenPrompt(text: string) }`)
  and a small set of new `Action`s (`PromptChar(c)`, `PromptBackspace`,
  `PromptSubmit`, `PromptCancel`) that only apply while a prompt is
  active — `resolve_action` checks `state.prompt` before falling back
  to the normal Insert/Enter/Backspace dispatch.
- `Ctrl-s` on a pathless buffer opens `SaveAsPrompt("")` instead of
  the "not possible" status message; `Enter` submits and writes the
  file (`<fsys>`, same `write_file` path `save_buffer` already uses),
  setting `buffer.path = Some(entered_path)` on success.
- A new chord (not yet bound in `default_bindings` — pick one that
  doesn't collide, e.g. `Ctrl-e`) opens `OpenPrompt("")`; `Enter`
  loads the path via the existing `load_buffer` (M6) into a *new*
  buffer, backgrounding the current one (same shape as `NewBuffer`).
- `Esc` cancels either prompt, discarding the typed text and
  returning to normal editing with no state change.
- `render_editor_to_buffer` draws the prompt (e.g. `"Save as: " +
  text`) on the status row while active, replacing the normal
  path/dirty or status-message line.
- **Non-goals:** filename tab-completion, directory browsing/listing,
  overwrite confirmation on an existing path — plain text entry only,
  matching the "smallest widget that closes the gap" framing above.

### Plan

- [x] **`src/model.hc`.** Add the `Prompt` type + `prompt: Prompt`
  field on `EditorState`; add `PromptChar`/`PromptBackspace`/
  `PromptSubmit`/`PromptCancel` to `Action`.
- [x] **`src/actions.hc`.** `resolve_action` branches on
  `state.prompt` first (prompt active → route every `KeyEvent` to the
  four prompt actions; otherwise unchanged). Pure prompt-text editing
  helpers (append/backspace on `Prompt`'s `text` field) live here,
  mirroring `insert_char`/`delete_backward`'s shape.
- [x] **`src/runtime.hc`.** `event_loop_step` handles `PromptSubmit`
  for `SaveAsPrompt`/`OpenPrompt` inline (needs `<fsys>`, same as
  `save_buffer`); `PromptCancel` just clears `state.prompt` via
  `apply_action`.
- [x] **`src/render.hc`.** Prompt row rendering on the status line.
- [x] **`src/model.hc`.** Bind a new chord for `OpenPrompt` in
  `default_bindings` (rebindable via HiLisp `(bind …)` like every
  other chord).
- [x] **Tests.** `actions_test.hc` for prompt state transitions
  (char/backspace/cancel) and the `resolve_action` routing gate;
  `runtime_test.hc` for the end-to-end `Ctrl-s` → type a name → Enter
  → file written, and `OpenPrompt` → type a path → Enter → new buffer
  with real content, using the scripted `Terminal` handler.
- [x] **`hica fmt --check` + `hica analyse` 100/100** on every touched
  file.
- [x] **Docs.** `docs/notes.md` Save semantics section updated (no
  more "not possible" dead end); this section's Log + Reflection.

### Exit criteria

- Starting `hedit` with no file, typing content, `Ctrl-s`, entering a
  filename, and `Ctrl-q` leaves that content saved on disk under the
  entered name — closing the exact gap this milestone was scoped for.
- Opening a second, different existing file from inside a running
  hedit session works without restarting the process.
- All pre-existing automated suites stay green; new prompt-specific
  tests are added alongside them.

### Log

- `resolve_action` is now split into `resolve_normal_action` (the
  pre-M9 body, unchanged) and `resolve_prompt_action`, with a 2-line
  dispatcher on `state.prompt` picking between them. Kept the two
  bodies fully separate rather than threading a prompt-active bool
  through the old function — every prompt keystroke only ever needs to
  produce one of five `Action`s, so a dedicated match is both clearer
  and impossible to accidentally fall through to `Insert`.
- `Action`/`Prompt` share the same "text so far" shape (`SaveAsPrompt`
  and `OpenPrompt` both carry a bare `text: string`) but the pure
  editing helpers (`prompt_insert_char`/`prompt_backspace`) go through
  a small `prompt_text`/`with_prompt_text` get/set pair instead of
  matching on the variant at every call site — adding a third prompt
  kind later only touches those two functions.
- `save_buffer` (already effectful, already had the readonly check)
  was the natural place to grow the "no path → open the prompt"
  branch — no new dispatch needed in `event_loop_step` beyond a single
  `PromptSubmit` arm that fans out to `submit_save_as`/
  `submit_open_file` based on which `Prompt` variant is active.
  `submit_open_file` mirrors `new_buffer_action`'s backgrounding shape
  exactly (`background_buffers: state.background_buffers +
  [state.buffer]`), so a loaded file behaves identically to `Ctrl-o`'s
  scratch buffer once it's open.
- **Found via `hica analyse`/build, not `hica test`:** adding four new
  `Action` variants (`OpenFile`, `PromptChar`, `PromptBackspace`,
  `PromptSubmit`, `PromptCancel`) broke `src/hilisp_host.hc`'s
  `action_to_string`/`string_to_action` — that match was already
  non-exhaustive by construction (no catch-all arm), so Koka inferred
  `<exn|_e>` instead of `total` on a function whole-program inference
  reaches through, and the failure surfaced in an *unrelated* test
  file (`runtime_test.hc`, which imports `hilisp_host`) rather than
  at the `model.hc` edit site. `model_test.hc`/`actions_test.hc`
  (which don't import `hilisp_host`) stayed green throughout, which
  is what made this easy to miss on a partial test run. **Lesson:**
  after adding an `Action` variant, grep for `match a { ... }` /
  `match action { ... }` across the whole `src/` tree before trusting
  a single test file's pass — `hilisp_host.hc`'s Action↔symbol table
  is the one place outside `actions.hc` that has to stay exhaustive.
- **Real bug, not a test artifact:** the first working build
  segfaulted under scripted-stdin smoke testing whenever `Ctrl-q` was
  sent while a prompt was open. Root cause: `resolve_prompt_action`'s
  catch-all (`_ => Ignore`) also swallowed the synthetic
  `KShortcut(Ctrl, 'q')` that `keys.hc::decode_key` emits for an
  EOF/closed-stdin read (`code == -1`) — with a prompt open and stdin
  already closed, `event_loop_step` re-read EOF, got `Ignore`, and
  looped again indefinitely, blowing the C stack (Koka's recursive
  `event_loop_step` isn't a hard guarantee of TCO through an effect
  handler resumption). Fixed by adding an explicit
  `KeyEvent(KShortcut(Ctrl, 'q')) => Quit` arm to
  `resolve_prompt_action` — Ctrl-q now force-quits even mid-prompt,
  which both fixes the EOF spin *and* is arguably better UX (no
  editor-wide "confirm quit" exists yet, so this matches the
  no-confirmation philosophy everywhere else). Caught by the same
  scripted-stdin-bytes technique as M7/M8, not by the pure unit tests
  — this class of bug (infinite loop / stack blowout on an
  edge-case Event) is structurally invisible to `hica test`, which
  never has enter/exit-condition timing like a live event loop does.
- Confirmed end-to-end against the compiled `./hedit` binary via
  scripted stdin bytes (same technique as M7/M8): `Ctrl-s` on a
  pathless buffer + a typed path + `Enter` produced the exact file
  content on disk and flipped the tabline/status to the new path;
  `Ctrl-e` + an existing 2-line file's path + `Enter` loaded real
  content into a new buffer and backgrounded the scratch one. Note:
  a piped (non-tty) stdin needs a literal `\n` (LF, code 10) to submit
  a prompt, not `\r` (CR) — a real terminal's `stty icrnl` translates
  CR→LF before hedit ever sees the byte, but that translation is a
  no-op on a non-tty pipe (same caveat as M7's raw-mode notes).
- `hica fmt` reformatted two pre-existing single-argument slice
  expressions in `actions.hc` (`[col:]` → `[col: ]`) and trimmed a
  trailing blank line in `render.hc` — unrelated to this milestone's
  logic, just picked up incidentally by running `fmt --check` on every
  touched file.
- Recurring `cli.kki` stale-cache parse error again (twice this
  session) — same `hica clean --cache && rm -rf .koka` fix as every
  prior milestone.

### Reflection

**What went well:**

- Splitting `resolve_action` into `resolve_normal_action` +
  `resolve_prompt_action` behind a one-line `match state.prompt`
  dispatcher kept the diff to the existing dispatch function at zero
  — no risk of subtly changing normal-mode keystroke behavior while
  adding the prompt path.
- The `prompt_text`/`with_prompt_text` get/set pair over the `Prompt`
  ADT paid for itself immediately: `prompt_insert_char` and
  `prompt_backspace` are both one-liners that don't know or care which
  prompt variant is active.

**What to carry forward:**

- **New standing check for any future `Action` variant:** grep
  `action_to_string`/`string_to_action` in `hilisp_host.hc` (and any
  other exhaustive `match action { ... }`) *before* running tests —
  a non-exhaustive match there fails via a confusing effect-inference
  error in an unrelated test file, not a clean "missing case" message
  at the edit site.
- **New standing check for any new `Action` reachable while another
  input-consuming mode is active** (prompts today, maybe a future
  command palette): make sure the synthetic EOF-quit event
  (`KShortcut(Ctrl, 'q')` from `decode_key(-1)`) can still reach
  `Quit` from every such mode, or a closed stdin will spin the event
  loop instead of exiting. Caught by scripted-stdin smoke testing,
  not unit tests — keep that step mandatory for any milestone that
  touches `event_loop`/`resolve_action`.
- Piped-stdin smoke tests need `\n` for Enter, not `\r` — add this to
  the running "scripted stdin bytes" cheat sheet alongside the
  Ctrl-chord octal codes from M7/M8.

**Ready for M10** — usability polish: help overlay + theming is next.

---



## Milestone M10 — Usability polish: help overlay + theming

### Goal

Everything through M7 makes hedit *functional*; nothing so far makes
it *discoverable* or *pleasant to look at*. A first-time user has no
in-editor way to learn the keybindings (they'd have to read
`docs/notes.md`), and the whole UI renders in the terminal's default
foreground/background — no visual distinction between the tabline,
status line, and content. This milestone closes both gaps with the
smallest reasonable widgets: a static help overlay and a small
configurable color theme for hedit's own chrome (tabline/status
line/cursor line) — **not** a syntax-highlighting engine, which is a
much bigger, separate feature.

**Scope:**

- **Help overlay.** A chord (e.g. `Ctrl-g`, or `F1` if `term_ffi`'s
  key decode grows function-key support) toggles a full-screen
  overlay listing every chord in `state.config.bindings` next to its
  action name — generated from the live bindings table, not a
  hardcoded string, so a user's HiLisp `(bind …)` remaps show up
  correctly. Any key closes the overlay and returns to the buffer
  underneath unchanged.
- **Theming.** A `Theme` struct (tabline fg/bg, status-line fg/bg,
  active-tab fg/bg, cursor-line bg) with a built-in default, applied
  in `render_native` (`main.hc`) via `std/term`'s existing
  `term_ansi`/`term_rgb` helpers when building the frame string.
  Configurable from HiLisp via `(set "theme.status-fg" "...")`-style
  keys read through the existing `Config.values` alist — no new
  config-loading machinery, just new well-known keys.
- One or two built-in named presets (e.g. `"default"`, `"ilseon"` —
  reusing the palette already defined in `std/term`) selectable via
  `(set "theme" "ilseon")`, resolved to concrete colors before
  `render_native` needs them.
- **Non-goals:** per-token syntax highlighting (needs a lexer per
  filetype — a separate, much larger milestone), a live theme editor/
  picker UI, true-color detection/fallback (assume the terminal
  supports what the user's theme requests, same trust level as
  `std/term`'s existing `term_rgb`).

### Plan

- [ ] **`src/model.hc`.** Add `Theme` struct + `default_theme()`;
  add `HelpOverlay` to a small UI-mode enum on `EditorState` (or a
  bare `bool show_help`, whichever stays simpler); add a `ToggleHelp`
  `Action`.
- [ ] **`src/actions.hc`.** `resolve_action`/`apply_action` wiring for
  `ToggleHelp`; while help is showing, route every other key back to
  `ToggleHelp`-off ("any key closes it") ahead of normal dispatch,
  same pattern M9's prompt-mode gate would use.
- [ ] **`src/render.hc`.** `render_help_buffer(state) : ScreenBuffer`
  — one row per binding, generated from `state.config.bindings` +
  the existing `action_to_string`/`chord_to_str` naming helpers in
  `hilisp_host.hc` (may need to make those `pub` if reused across
  modules). `render_editor_to_buffer` gains theme-aware coloring for
  the tabline/status rows.
- [ ] **`src/main.hc`.** `render_native` applies the active `Theme`'s
  ANSI codes when emitting the tabline/status rows.
- [ ] **`src/config_loader.hc` / `src/hilisp_host.hc`.** Recognise
  `theme.*` and `theme` keys from `(set …)`, resolving named presets
  to a concrete `Theme` after `init.hl` loads.
- [ ] **Tests.** `render_test.hc` cases for help-overlay content
  (reflects custom bindings, not just defaults) and theme color
  codes appearing in the rendered tabline/status rows;
  `hilisp_host_test.hc` cases for `(set "theme" …)` resolution.
- [ ] **`hica fmt --check` + `hica analyse` 100/100** on every touched
  file.
- [ ] **Docs.** `docs/notes.md` gains "Help overlay" and "Theming"
  sections; this section's Log + Reflection.

### Exit criteria

- A new user can press the help chord, see every currently-bound
  chord (including any custom `(bind …)` from their `init.hl`), and
  return to editing without losing buffer state.
- `(set "theme" "ilseon")` in `init.hl` visibly recolors the
  tabline/status line on the next render, with no crash on an unknown
  theme name (falls back to the default theme with a status message).
- All pre-existing automated suites stay green; new help/theme tests
  are added alongside them.

