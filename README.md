# hedit

`hedit` is a lightweight, terminal-based text editor written in [`hica`](https://www.hica.dev/). 
It aims to pair modern editor UX (standard keybindings, mouse, multiple cursors, split views) with `hica`'s
algebraic effects and Perceus-based memory management (FBIP).

## Configuration & plugins: HiLisp

`hedit` uses **[HiLisp](https://github.com/cladam/hica-lisp)** (a small Lisp
interpreter written in `hica`) as its **configuration and plugin language**.
There is no second scripting runtime planned: settings, keybindings, and
(later) plugins are all authored as `.hl` files evaluated by the same embedded
HiLisp interpreter.

HiLisp lives as a git submodule under `lib/hilisp/` and is compiled together
with `hedit` (see `hica.hml`).

### Example `init.hl`

```lisp
;; ~/.config/hedit/init.hl

(set "tabsize"     4)
(set "auto-indent" true)
(set "theme"       "ilseon")

(bind "Ctrl-s" 'save)
(bind "Ctrl-q" 'quit)
(bind "Meta-w" 'close-buffer)
```

Config discovery order (first hit wins):

1. `$XDG_CONFIG_HOME/hedit/init.hl` (or `$HOME/.config/hedit/init.hl`)
2. `$HOME/.hedit.hl`

If neither exists, `hedit` runs with hard-coded defaults.

See [`examples/init.hl`](examples/init.hl) for all available options

### API surface

| Built-in | Purpose |
|---|---|
| `(set key value)` | Set a configuration value |
| `(get key)` | Read a configuration value |
| `(bind keystroke action)` | Map a keystroke to a named built-in action |

Upcoming plugin discovery, event hooks (`on 'buffer-open`, `on 'save`, ...), buffer introspection/mutation (`current-buffer`,
`insert-text`, ...), will also be written in HiLisp, as additional built-ins on the same interpreter.

## Quick Install

Using standard `curl`:
```sh
curl -fsSL https://github.com/cladam/hedit/releases/latest/download/install.sh | sh
```

Or install hedit using `hicurl`:

```sh
hicurl https://github.com/cladam/hedit/releases/latest/download/install.sh | sh
```

Installs binary (`macos-arm64`, `linux-arm64`, `linux-x86_64`) to `~/.local/bin`. Override target location with `HEDIT_INSTALL_DIR=/usr/local/bin`.

```sh
HEDIT_INSTALL_DIR=/usr/local/bin curl -fsSL https://github.com/cladam/hedit/releases/latest/download/install.sh | sh
# Or with hicurl
HEDIT_INSTALL_DIR=/usr/local/bin hicurl https://github.com/cladam/hedit/releases/latest/download/install.sh | sh
```

**Note:** _No Windows support!_

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

### Usage

```sh
hica build -o hedit           # compile to ./hedit
./hedit                       # open an empty scratch buffer
./hedit somefile.txt          # open a real file
```

Default keybindings (overridable from `init.hl`). 
Full reference with every chord: [`docs/hedit-cheatsheets.md`](docs/hedit-cheatsheet.md)
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

### Command-line flags

```sh
hedit                                   # empty scratch buffer
hedit file.txt                          # open a file
hedit +42 file.txt                      # open at line 42
hedit +42:8 file.txt                    # open at line 42, column 8
hedit --readonly file.txt               # -R — open read-only (Save disabled)
hedit --tabsize 2 file.txt              # override tabsize for this run
hedit --config init.hl file.txt         # load config from elsewhere
hedit --no-config file.txt              # skip init.hl entirely
hedit --help / --version
```

CLI flags always win over `init.hl`, e.g. `--tabsize` overrides a `(set "tabsize" ...)` in the loaded config.


## License

MIT – see [LICENSE](LICENSE).
