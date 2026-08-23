# hedit Cheatsheet

What hedit offers today, a companion to the full reference in 
[hedit-defaultkeys.md](hedit-defaultkeys.md) (every binding, plus gaps/roadmap) and [hedit-design.md](hedit-design.md)
(the "why"). 

This is a living document and will be extended as new features are implemented. Anything marked **not yet** is a known gap.

## Starting hedit

```sh
hedit                 # empty scratch buffer
hedit file.txt         # open a file
hedit +42 file.txt      # open at line 42
hedit +42:8 file.txt    # open at line 42, column 8
hedit --readonly file.txt   # -R — open read-only (Save disabled)
hedit --tabsize 2 file.txt  # override tabsize for this run
hedit --config path/to/init.hl file.txt  # load config from elsewhere
hedit --no-config file.txt  # skip init.hl entirely
hedit --help / --version
```

## Basic navigation

| Key         | Does                              |
|------------ |----------------------------------- |
| Arrow keys  | Move up/down/left/right (wraps at line ends) |

**Not yet:** Page Up/Down, Home/End, word-wise movement (`Ctrl-Left/Right`),
jump-to-line. See [hedit-defaultkeys.md § What's not there yet](hedit-defaultkeys.md#whats-not-there-yet).

## Basic editing

| Key      | Does                                                |
|--------- |----------------------------------------------------- |
| Any char | Insert at the cursor                                 |
| Enter    | Split the line at the cursor                         |
| Backspace| Delete before the cursor (merges into previous line at column 0) |
| Ctrl-c   | Copy the current line                                |
| Ctrl-v   | Paste                                                |
| Ctrl-z   | Undo                                                 |
| Ctrl-y   | Redo                                                 |

**Not yet:** selections (so cut/copy is whole-line only, not
arbitrary ranges), search, replace, cut-to-end-of-line, delete-line
(`dd`-style).

## File operations

| Key    | Does                                                                 |
|------- |----------------------------------------------------------------------|
| Ctrl-s | Save. On a pathless (scratch) buffer, opens the Save-As prompt instead |
| Ctrl-e | Open the "open file" prompt                                          |
| Ctrl-q | Quit                                                                 |

Prompt controls (Save-As / Open): type to edit the path, **Enter**
submits, **Esc** cancels, **Backspace** edits.

## Buffers

hedit keeps open buffers in a ring:

| Key    | Does                                                        |
|------- |--------------------------------------------------------------|
| Ctrl-o | New scratch buffer (pushes the current one onto the ring)    |
| Ctrl-n | Next buffer in the ring                                      |
| Ctrl-p | Previous buffer in the ring                                  |
| Ctrl-w | Close the active buffer (refuses on the last one)            |

The tabline (row 0) lists every open buffer, active one bracketed —
e.g. `[scratch] | notes.txt`.

**Not yet:** split panes/windows, multiple cursors.

## Help

| Key    | Does                                                              |
|------- |--------------------------------------------------------------------|
| Ctrl-g | Toggle a full-screen keybindings overlay, generated live from the current bindings (any key closes it) |

## Customization — `init.hl`

`init.hl` is a HiLisp file that is loaded from (first hit wins): `$XDG_CONFIG_HOME/hedit/init.hl`
(or `$HOME/.config/hedit/init.hl`), then `$HOME/.hedit.hl`, or an
explicit `--config path`. 
A copy-pasteable reference with every current option lives at [../examples/init.hl](../examples/init.hl).

Settings — `(set key value)`, read back with `(get key)`:

```hilisp
(set "tabsize" 4)
(set "theme" "default")   ; or "ilseon"
(set "theme.tabline-fg" "255,255,255")   ; per-slot true-color overrides
(set "theme.status-bg"  "200,200,200")
```

Rebinding — `(bind "Ctrl-x" 'action-name)`, `'ignore` to disable a
default without replacing it:

```hilisp
(bind "Ctrl-s" 'save)
(bind "Ctrl-q" 'quit)
(bind "Ctrl-w" 'ignore)   ; silence the default close-buffer binding
```

A broken form in `init.hl` doesn't lock you out: hedit evaluates top
to bottom, stops at the first error, surfaces it in the status line,
and keeps whatever loaded before that point.

**Not yet:** a plugin system, `set`/`bind` from a running "command
prompt" (there's no colon/command-line mode — only the Save-As/Open
path prompt), theme presets beyond `default`/`ilseon`.

## Where hedit differentiate

- One file (`init.hl`, HiLisp) for both settings and keybindings.
- Buffers are a rotation ring, not a tab bar.
- No split panes yet.
- No plugin system yet. HiLisp is meant to grow into that role later
  rather than bolting on a separate mechanism.
