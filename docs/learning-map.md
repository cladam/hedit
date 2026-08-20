# hedit — Learning Map

A personal study guide, not a spec. The goal isn't to re-read every line
of generated code — it's to be able to explain *why* each layer looks the
way it does, and to change any of it yourself without asking an assistant
first. Check items off as you go; this file is yours to edit.

Order matters: each layer assumes the previous one. Skipping ahead to
effects before the pure core clicks is the most common way to get lost.

---

## Layer 0 — hica fundamentals (if any of this feels shaky, start here)

You don't need the whole language reference — just enough to read
`src/*.hc` fluently.

- [ ] **ADTs + exhaustive `match`.** `src/keys.hc` (`Modifier`, `Key`,
      `Event`) is the smallest possible example. Read it, then find
      every place it's destructured (`grep_search` for `match evt`).
- [ ] **Structs vs enums, `==`/`show` auto-derive.** `src/model.hc`'s
      `Position`/`Cursor`/`TextBuffer`. Why do `actions_test.hc`'s
      asserts like `s2.buffer.lines == ["hi"]` just work with no
      hand-written `Eq` instance? → `docs/hica-issues.md` Issue 2.
- [ ] **Purity by construction.** `apply_action` in `src/actions.hc` has
      no effect row in its type. Ask: which functions in this file
      *could* be effectful but aren't, and why does that matter for
      testing? (Hint: `tests/actions_test.hc`'s header comment.)
- [ ] **Perceus / FBIP.** `docs/hedit-design.md` §3 + §6 table. You
      don't need the GC theory — just the practical claim: unique
      references let `insert_char` mutate in place without violating
      purity semantics. Say it back in your own words before moving on.
- [ ] **The gotchas you'll hit immediately when writing new code.**
      Skim `/memories/repo/hedit-hica-build.md` (Hica Syntax Reminders
      section) once, don't try to memorise it — you'll come back to it.

**Self-check:** pick any `fun` in `src/actions.hc` and explain its full
type signature (params, return, effect row) without looking it up.

---

## Layer 1 — hedit's pure core

This is the part of hedit that has *no* I/O, ever. If you understand
this layer cold, everything else is "just" plumbing around it.

- [ ] `src/model.hc` — the data: `TextBuffer`, `Cursor`, `EditorState`,
      `Action`, `Config`. Note what's *not* here yet: selections,
      multi-cursor column tracking, a rope/piece-table (still
      `list<string>`). These are deliberate simplifications — find the
      comment that admits each one.
- [ ] `src/actions.hc` — the pipeline:
      `Event --resolve_action--> Action --apply_action--> EditorState`.
      Trace one full keystroke by hand: `KeyEvent(KChar('h'))` from
      `resolve_action` through `insert_char`. Then trace a bound
      shortcut: `KeyEvent(KShortcut(Ctrl, 'z'))` through
      `lookup_binding` → `Undo` → (dead end — why? see Layer 2).
- [ ] `src/render.hc` — `render_editor_to_buffer`. Pure function from
      `EditorState` to `ScreenBuffer`. No handler needed to unit-test
      it (`tests/render_test.hc` never installs `Terminal`).
- [ ] **Multi-buffer ring (M5.5).** `background_buffers` in
      `src/model.hc` + `cycle_next_buffer`/`cycle_prev_buffer` in
      `src/actions.hc`. Convince yourself the rotation trick is
      correct: draw 3 buffers on paper, cycle forward twice, backward
      once, check it matches `tests/actions_test.hc`'s wrap-around
      test.

**Exercise (do this yourself, don't ask for the diff):** add a new pure
`Action` — e.g. `Action::DuplicateLine` — end to end: variant in
`model.hc`, default binding, `apply_action` arm, a test in
`actions_test.hc`. If you can do this without opening `runtime.hc` at
all, Layer 1 has clicked.

---

## Layer 2 — the effect boundary

Where the pure core meets the outside world. This is the part of hica
that's genuinely novel (most languages don't have user-facing algebraic
effects), so it's worth the most study time.

- [ ] **`handle E { arms } in { body }`.** `src/runtime.hc`'s
      `pub effect Terminal` / `pub effect Clipboard`, handled in
      `src/main.hc` (native) and `tests/runtime_test.hc` (scripted).
      Key question: why can the *same* `event_loop` run against two
      completely different handler implementations with zero code
      change? (This is the whole point of the design — see
      `docs/hedit-design.md` §4 and §6's validation-matrix row on
      "Handler scoping".)
- [ ] **`with var … in { … }` handler-local state.** Find it in
      `tests/runtime_test.hc` (`var events`, `var render_count`).
      Note it *cannot* leak past the `in { }` block — that's enforced
      by the type system, not convention.
- [ ] **Named/spawned effects — `spawn Name { … } as ref`.**
      `pub effect Buffer` in `src/runtime.hc`. This is different from
      `handle … in { }`: it's a *statement*, the ref outlives the
      spawn call for the rest of the block, and you call ops on it
      directly (`buf_ref.snapshot(...)`) instead of through lexical
      handler scope. `docs/hedit-design.md` §9.3 is the "why" doc —
      read it *before* the code, it explains a real design fork
      (migrating `EditorState.buffer` to `ref<Buffer>` was tried on
      paper and rejected).
- [ ] **Isolation proof.** `tests/spawn_test.hc`'s last test spawns two
      `Buffer` instances and asserts they don't cross-talk. This is
      the single test that justifies "named effects scale to more than
      one instance" — know it well enough to explain what would break
      if hica's `spawn` implementation had a shared-state bug.

**Exercise:** without changing behaviour, add a **third** spawned
`Buffer` instance in a scratch test file and prove three-way isolation
(extend spawn_test.hc's pattern). This forces you to actually write
`spawn` syntax yourself instead of reading it.

**Self-check:** explain, out loud, why `EditorState.buffer` is still a
plain `TextBuffer` and not a `ref<Buffer>`. If you can't, re-read
`docs/effects-journal.md`'s M5 Reflection section — this is the single
most important design decision in the codebase so far.

---

## Layer 3 — the HiLisp bridge

hedit's config/plugin language. This layer teaches you a *second*
codebase (`lib/hilisp/`) that you also helped build — worth treating as
its own mini-syllabus.

- [ ] **HiLisp itself, 20 minutes.** `lib/hilisp/docs/lisp-primer.md`
      top to bottom — it's written to be read in one sitting.
- [ ] **HiLisp's own architecture.** `lib/hilisp/src/`:
      `tokeniser.hc` → `parser.hc` → `ast.hc` → `eval.hc` →
      `builtins.hc`. Read them in that pipeline order once, just
      skimming signatures — you're building a mental map, not
      memorising.
- [ ] **The host-dispatch mechanism.** How does a *pure, total* HiLisp
      callback (`register_host_dispatch` demands totality) mutate
      hedit-side config? Read `src/hilisp_host.hc`'s top comment block
      first (the "storage shape" explanation), then trace one call:
      `(bind "Ctrl-x" 'quit)` → `host/bind` → `env_set` → …
      → `config_from_env`.
- [ ] **Why actions round-trip through strings.** `action_to_string` /
      `string_to_action` in `src/hilisp_host.hc`. Note the constraint
      this creates — re-read the M5.5 journal Log's point about
      `OpenFile(path)` being unreachable from a keybinding *because of
      this exact mechanism*. That's a real architectural limit you
      discovered, not a bug — know how to explain it to someone else.
- [ ] **Config discovery + load order.** `src/config_loader.hc` +
      `docs/hedit-design.md` §7.7.

**Exercise:** add a new HiLisp built-in, e.g. `(current-tab-count)`
that reads `length(open_buffers(state))`. This touches
`make_hedit_env`, the host-dispatch plumbing, and forces you to
understand the total-callback constraint first-hand.

---

## Layer 4 — the compiler bugs you already found (this is your edge)

This is the layer most engineers *never* get to: you've been the first
person to hit real gaps in a young compiler and traced them to root
cause. `docs/hica-issues.md` is effectively a second design document —
for the compiler itself, from a user's perspective.

- [ ] Read all 9 issues in `docs/hica-issues.md` **in order** — they
      escalate in subtlety (parser hang → missing `pub` → totality
      gaps → cross-module named-effect promotion). Issue 9 in
      particular is genuinely hard compiler-engineering territory
      (transitive effect promotion across module boundaries).
- [ ] For each *resolved* issue, without re-reading the fix: guess what
      you think the fix was, then check. This is the fastest way to
      internalise *why* each bug existed, not just that it did.
- [ ] Issue 4 is still **OPEN** (`hc_lines` collision) — you hit it
      again this session (`tests/actions_test.hc`'s `buf_lines`
      helper). Know the workaround cold: named top-level function
      instead of an inline lambda, because it pins the receiver type.
      This will bite you again in any future file with a `lines` (or
      similarly prelude-shadowed) field name.

**Self-check:** could you write a *new* minimal repro for a
hypothetical 10th hica bug, in the same two-file style as Issue 9's
`probe_named_lib.hc`/`probe_named_test.hc`? That skill (isolating a
bug from a large codebase into an actionable minimal case) is the
single highest-leverage thing you've practiced in this project.

---

## Layer 5 — the milestones as case studies in *process*, not just code

`docs/effects-journal.md` is long, but it's a record of real decisions,
not a changelog. Read it milestone-by-milestone, and for each one, find
the moment where the plan changed and ask *why* before reading the
journal's own answer:

- [ ] **M1–M4**: `pub effect`, cross-module effects, HiLisp bridge
      landing. Skim — mostly plumbing, but note the Issue #3/#5/#6/#7
      cross-references (this is where those hica bugs surfaced).
- [ ] **M5**: the `ref<Buffer>` migration that got rejected on paper
      (see Layer 2). This is the best-written Reflection in the file —
      re-read it after you've done the Layer 2 exercise.
- [ ] **M5.5**: the ring-vs-map decision, and the two mismatches caught
      *before* writing code (`Ctrl-tab` unrepresentable,
      `OpenFile(path)` unreachable). This is the template for how to
      run your own milestones going forward: read the sketch against
      the actual types *first*, write the Log entry for what you find,
      *then* write code.

**Exercise:** before starting the next milestone (per the "Follow-on"
notes at the end of M5.5 — per-buffer isolated undo, or an `OpenFile`
path-prompt widget), write your own Goal/Plan section *first*, in your
own words, before asking for implementation help. Compare it against
what actually ships.

---

## How you'll know you own it

A rough bar, not a checklist to game:

1. You can explain any single file in `src/` to someone else without
   opening it while talking.
2. You can predict which hica gotcha (Layer 0's list, `hc_lines`,
   stale `.kk` cache, lambda type-annotation parse errors, …) a given
   new feature is most likely to trip, before you hit it.
3. You can read a `docs/effects-journal.md` Plan section and guess the
   Log's "what changed" before reading it.
4. You'd notice if a generated diff quietly reintroduced something a
   past Reflection explicitly ruled out (e.g. mirroring
   `EditorState.buffer` in handler-local state).

If 1–4 feel true, you don't need this file anymore — delete it or fold
what's left into `docs/notes.md`.
