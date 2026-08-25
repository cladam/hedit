# hedit

> ⚠️ **Very early days.** `hedit` is a work-in-progress terminal text editor
> written in [`hica`](https://github.com/cladam/hica). Almost nothing works yet
> — this repo currently exists to shape the design and to serve as an
> end-to-end integration workload for the `hica` compiler.

`hedit` is a lightweight, terminal-based text editor inspired by
[`micro`](https://micro-editor.github.io/). It aims to pair modern editor UX
(standard keybindings, mouse, multiple cursors, split views) with `hica`'s
algebraic effects and Perceus-based memory management (FBIP).

See [`docs/hedit-design.md`](docs/hedit-design.md) for the full design
document.

## Configuration & plugins: HiLisp

`hedit` uses **[HiLisp](https://github.com/cladam/hica-lisp)** — a small Lisp
interpreter written in `hica` — as its **configuration and plugin language**.
There is no second scripting runtime planned: settings, keybindings, and
(later) plugins are all authored as `.hl` files evaluated by the same embedded
HiLisp interpreter.

HiLisp lives as a git submodule under `lib/hilisp/` and is compiled together
with `hedit` (see `hica.hml`).

### Example `init.hl` (v1 target)

```lisp
;; ~/.config/hedit/init.hl

(set "tabsize"     4)
(set "auto-indent" true)
(set "theme"       "gruvbox")

(bind "Ctrl-s" 'save)
(bind "Ctrl-q" 'quit)
(bind "Meta-w" 'close-buffer)
```

Config discovery order (first hit wins):

1. `$XDG_CONFIG_HOME/hedit/init.hl` (or `$HOME/.config/hedit/init.hl`)
2. `$HOME/.hedit.hl`

If neither exists, `hedit` runs with hard-coded defaults.

### v1 API surface

| Built-in | Purpose |
|---|---|
| `(set key value)` | Set a configuration value |
| `(get key)` | Read a configuration value |
| `(bind keystroke action)` | Map a keystroke to a named built-in action |

Everything else — plugin discovery, event hooks (`on 'buffer-open`,
`on 'save`, …), buffer introspection/mutation (`current-buffer`,
`insert-text`, …), a runtime `:eval` command — is **planned for v2+** and will
also be written in HiLisp, as additional built-ins on the same interpreter.

## Cloning

Because HiLisp is a submodule:

```sh
git clone --recurse-submodules https://github.com/cladam/hedit.git
# or, if already cloned:
git submodule update --init --recursive
```

To bump the pinned HiLisp version:

```sh
git submodule update --remote lib/hilisp
```

## Usage

```sh
hica build            # compile to ./hedit
./hedit               # open an empty scratch buffer
./hedit somefile.txt  # open a real file
```

Default keybindings (overridable from `init.hl` — see above). Full
reference with every chord: [`docs/hedit-defaultkeys.md`](docs/hedit-defaultkeys.md)
(or press `Ctrl-g`/`Meta-h` inside hedit for a live overlay).

- File: `Ctrl-s` save, `Ctrl-o` open-file prompt, `Ctrl-q` quit
- Readline-style editing: `Ctrl-a`/`Ctrl-e` line start/end, `Ctrl-b`/`Ctrl-f`
  left/right, `Ctrl-d` delete-forward, `Ctrl-k` kill-line, `Ctrl-w`
  kill-word-back, `Meta-f`/`Meta-b` word forward/back, `Meta-d`
  kill-word-forward, `Meta-l` kill-whole-line
- Clipboard & history: `Ctrl-c`/`Ctrl-v` copy/paste, `Ctrl-y` yank
  (same clipboard slot as paste), `Ctrl-z` undo, `Ctrl-r` redo
- Buffers: `Meta-o`/`Meta-n`/`Meta-p`/`Meta-w` new/next/prev/close buffer
- Help: `Ctrl-g`/`Meta-h` toggle the keybindings overlay

### Command-line flags (M8)

```sh
./hedit somefile.txt              # open a file
./hedit +42 somefile.txt          # open at line 42
./hedit +42:8 somefile.txt        # open at line 42, column 8
./hedit --readonly somefile.txt   # open read-only (Ctrl-s is a no-op)
./hedit --tabsize 2 somefile.txt  # override tabsize for this session
./hedit --config ~/my-init.hl somefile.txt  # load a specific init.hl
./hedit --no-config somefile.txt  # skip init.hl entirely
./hedit --help                    # full flag reference
```

CLI flags always win over `init.hl` — e.g. `--tabsize` overrides a
`(set "tabsize" …)` in the loaded config, matching `micro`'s
session-override precedence.

```sh
hica fmt     # format according to hica style guide
hica check   # type-check without emitting
hica clean   # remove generated files
```

## Status

- ✅ Design document drafted (`docs/hedit-design.md`)
- ✅ HiLisp submodule wired into the build (pinned at
      **HiLisp v0.9.2** — the symmetric `apply` carve-out for
      wrapped `(host/…)` aliases)
- ✅ Scripting bridge (`src/hilisp_host.hc` + `src/config_loader.hc`)
      — HiLisp `(set …)` / `(get …)` / `(bind …)` mutate a
      hedit-side `Config` via HiLisp's host-dispatch (`host/set`,
      `host/get`, `host/bind`); config discovery walks
      `$XDG_CONFIG_HOME/hedit/init.hl` → `$HOME/.hedit.hl` (first
      hit wins) via `load_user_config`.
- ✅ Core editor / event loop / effects — **M4 green, M4b closed**.
      `src/main.hc` now calls `load_user_config(default_config())`
      at startup and primes any status message onto the first render
      tick. `pub effect Terminal` + `pub effect Clipboard` in
      `src/runtime.hc`; pure `handle_action` in `src/actions.hc`;
      pure `render_editor_to_buffer` in `src/render.hc`; save via
      built-in `write_file` on Ctrl-s. All action dispatch is
      config-driven (Ctrl-q → Quit etc. all live in
      `default_bindings()`, overridable from `init.hl`).
      **51/51 tests green**: 19 actions + 4 render + 9 runtime
      (incl. end-to-end HiLisp-rebound chord test) + 19 hilisp_host.
      Requires **hica ≥ 0.49.4** (test-mode panic-handler fix,
      `docs/hica-issues.md` Issue #5) + the `hica build` include-
      path fix (Issue #7) + the `map_set → foldr` totality fix
      (Issue #6) + HiLisp v0.9.2 (Issue #8: symmetric `apply`
      carve-out).
- ✅ **M5** — `pub effect Buffer` (named/spawned via `spawn Buffer { … }
      as ref`) provides per-buffer undo/redo history. `EditorState.buffer`
      stays a plain `TextBuffer` (pure core unchanged); only
      `event_loop` spawns and talks to the `ref<Buffer>`. `Ctrl-z` /
      `Ctrl-y` default bindings, overridable from `init.hl` like every
      other action. **60/60 tests green**: 23 actions + 4 render + 9
      runtime + 20 hilisp_host + 4 spawn (the new `tests/spawn_test.hc`,
      proving two spawned instances stay isolated). Requires a hica
      build with the transitive-named-effect fix (`docs/hica-issues.md`
      Issue #9 — landed same day as a local build, not yet in the
      published/PATH `hica`). Docs updated
      (`docs/hedit-design.md` §9, `docs/notes.md` Undo/Redo section);
      Reflection written in `docs/effects-journal.md`.
- ✅ **M5.5** — multi-buffer navigation. `EditorState.buffer` stays
      the active-buffer field; a new `background_buffers` ring holds
      the rest of the open buffers (`NextBuffer`/`PrevBuffer` rotate
      it, `NewBuffer`/`CloseBuffer` push/pop the front) — no
      `active`-index bookkeeping to drift out of sync. Default
      bindings `Ctrl-o` (new buffer), `Ctrl-n`/`Ctrl-p` (cycle),
      `Ctrl-w` (close), all pure and config-driven like every other
      action. `render_editor_to_buffer` gains a tabline row (active
      buffer bracketed). **72/72 tests green**: 29 actions + 6 render
      + 11 runtime + 22 hilisp_host + 4 spawn. Opening files from disk
      (`OpenFile(path)`) and per-buffer isolated undo/redo are
      deferred — see `docs/effects-journal.md` M5.5 non-goals.
- ✅ **M6** — CLI arg parsing (`std/cli`) + real file loading.
      `src/cli_spec.hc` parses a single optional `[file]` positional;
      `--help`/`--version` exit before any editor state is built.
      `src/model.hc::load_buffer` reads a real file from disk into
      `EditorState.buffer`, falling back to an empty scratch buffer
      with a status message on a missing/unreadable path — never a
      crash. **80/80 tests green**: 29 actions + 6 render + 11 runtime
      + 22 hilisp_host + 4 spawn + 4 cli + 4 model. This alone doesn't
      make hedit interactive yet — the `Terminal` handler is still the
      M1 stub; that flip is M7.
- ✅ **M7** — native `Terminal` handler. `src/term_ffi.kk` (+
      `src/term_ffi_inline.c`) is a hand-written C FFI module — raw
      key reads (`read_key`) that assemble arrow-key escape sequences
      into synthetic codes, and a real `term_cols`/`term_rows` via
      `ioctl(TIOCGWINSZ)` — following the same pattern as
      hica-ecosystem's `programs/myeon` reference program. Raw mode
      itself is toggled with `stty raw -echo icrnl` / `stty sane`
      through hica's built-in `exec`, no termios FFI needed.
      `src/keys.hc::decode_key` is the pure, unit-tested seam from a
      raw key code into hedit's `Event`/`Key` types. **hedit is now
      usable interactively** — `./hedit [file]` opens a real terminal
      session; type, save, copy/paste, undo/redo, switch buffers, and
      quit with the terminal left in a sane state. **86/86 tests
      green**: 29 actions + 6 render + 11 runtime + 22 hilisp_host + 4
      spawn + 4 cli + 4 model + 6 keys.
- ✅ **M8** — CLI polish for end users. `--config <path>`/`--no-config`
      (`src/config_loader.hc::load_user_config_opts`) override/skip
      `init.hl` discovery; `--tabsize <n>` overrides `Config.values`
      after `init.hl` loads (CLI wins, matching `micro`'s
      session-override precedence); `--readonly`/`-R` gates `Save` in
      `runtime.hc::save_buffer` with a status message instead of
      writing; `+LINE[:COL]` is hand-parsed out of argv (`std/cli` has
      no concept of a `+`-prefixed positional) and clamped into the
      opened buffer's bounds before the first render. **115/115 tests
      green**: 35 actions + 6 render + 12 runtime + 22 hilisp_host + 4
      spawn + 19 cli + 13 model + 4 config_loader.
- ⏳ Real OS clipboard handler (pbcopy / wl-copy / xclip) — not yet
      started
- ✅ **M9** — "Save As" / `OpenFile` prompt: a minimal single-line
      input widget so a scratch buffer can be saved for the first
      time, and an existing file opened without restarting hedit.
- ✅ **M10** — Usability polish. `Ctrl-g` (`toggle-help`) toggles a
      full-screen keybindings overlay generated live from
      `state.config.bindings` (custom `(bind …)` remaps show up
      correctly). A small `Theme` system colors hedit's own chrome
      (tabline/status line/cursor line, not syntax highlighting) —
      built-in `"default"`/`"ilseon"` presets and per-slot RGB
      overrides selectable from `init.hl` via `(set "theme" …)` /
      `(set "theme.<slot>" "R,G,B")`. **143/143 tests green**: 51
      actions + 6 render + 22 hilisp_host + 13 model + 16 runtime + 4
      config_loader + 8 keys + 19 cli + 4 spawn. See
      `docs/effects-journal.md`'s Milestone M10 section.
- ✅ **Readline/Meta keybinding rework** — remapped `open-file` to
      `Ctrl-o` and `redo` to `Ctrl-r`, freeing `Ctrl-e`/`Ctrl-y` for a
      full set of bash/readline-style chords (`Ctrl-a/e/b/f/d/k/w`),
      which also work inside the Save-As/Open prompt via cursor-aware
      `Prompt*` actions. `term_ffi_inline.c` now decodes a bare
      `ESC`+char as `KShortcut(Meta, _)` (most terminals'
      "metaSendsEscape" for Alt), so buffer-ring navigation moved to
      `Meta-o/n/p/w`, `Meta-h` mirrors `Ctrl-g`, and `Meta-f/b/d/l`
      add word-level motion/kill. Full chart:
      [`docs/hedit-defaultkeys.md`](docs/hedit-defaultkeys.md).



## License

MIT — see [LICENSE](LICENSE).
