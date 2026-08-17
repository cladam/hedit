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
(bind "Ctrl-w" 'close-buffer)
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
hica build   # compile to binary
hica run     # compile and run
hica fmt     # format according to hica style guide
hica check   # type-check without emitting
hica clean   # remove generated files
```

## Status

- ✅ Design document drafted (`docs/hedit-design.md`)
- ✅ HiLisp submodule wired into the build
- 🚧 Scripting bridge (`src/script/hilisp_host.hc`) — in progress
- 🚧 Core editor / event loop / effects — **M3 green**:
      `src/runtime.hc` now declares two `pub effect`s — `Terminal`
      (poll/render/dimensions/cursor-style) and `Clipboard` (get/set
      selection) — and `event_loop` dispatches Save via built-in
      `write_file`, Copy/Paste through the `Clipboard` effect. All
      keybindings still flow through the config-driven `Action`
      pipeline (Ctrl-c → Copy, Ctrl-v → Paste added to
      `default_bindings()` — micro-style, HiLisp-remappable in M4).
      `src/main.hc` stacks an in-memory Clipboard handler outside the
      Terminal stub. 40/40 tests green: 19 actions (6 new
      Copy/Paste unit tests), 9 HiLisp host, 4 render, 8 runtime
      (3 new nested-handler integration tests for Ctrl-c/Ctrl-v /
      round-trip). Requires **hica ≥ 0.49.4** for the test-mode
      panic-handler fix (see `docs/hica-issues.md` Issue #5). Real
      ANSI positioning + real OS clipboard land in a later pass.
- ⏳ Native terminal handler — not yet started



## License

MIT — see [LICENSE](LICENSE).
