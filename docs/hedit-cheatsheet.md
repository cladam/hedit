# hedit Cheatsheet

What hedit offers today.

This is a living document and will be extended as new features are implemented. Anything marked **not yet** is a known gap.

## Starting hedit

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

## Basic navigation

| Key         | Does                              |
|------------ |----------------------------------- |
| Arrow keys  | Move up/down/left/right (wraps at line ends) |
| Ctrl-b / Ctrl-f | Move left/right (same as ArrowLeft/ArrowRight) |
| Ctrl-a / Ctrl-e | Move to start/end of the current line |
| Meta-f / Meta-b | Move forward/back one word |

**Not yet:** Page Up/Down, Home/End, jump-to-line. See
[hedit-defaultkeys.md § What's not there yet](hedit-defaultkeys.md#whats-not-there-yet).

## Basic editing

| Key      | Does                                                |
|--------- |----------------------------------------------------- |
| Any char | Insert at the cursor                                 |
| Enter    | Split the line at the cursor                         |
| Backspace| Delete before the cursor (merges into previous line at column 0) |
| Ctrl-d   | Delete the char under the cursor (forward-delete)    |
| Ctrl-k   | Kill from the cursor to the end of the line, into the clipboard |
| Ctrl-w   | Kill the word before the cursor, into the clipboard  |
| Meta-d   | Kill the word after the cursor, into the clipboard   |
| Meta-l   | Kill the entire current line, into the clipboard     |
| Ctrl-c   | Copy the current line                                |
| Ctrl-v   | Paste                                                |
| Ctrl-y   | Yank — same as Ctrl-v (one shared clipboard slot)    |
| Ctrl-z   | Undo                                                 |
| Ctrl-r   | Redo                                                 |

**Not yet:** selections (so cut/copy is whole-line only, not
arbitrary ranges), search, replace, delete-line (`dd`-style).

## File operations

| Key    | Does                                                                 |
|------- |----------------------------------------------------------------------|
| Ctrl-s | Save. On a pathless (scratch) buffer, opens the Save-As prompt instead |
| Ctrl-o | Open the "open file" prompt                                          |
| Ctrl-q | Quit                                                                 |

Prompt controls (Save-As / Open): type to edit the path (inserts at
the cursor, not just append), **Enter** submits, **Esc** cancels. The
same readline chords as the main buffer also work here: **Ctrl-a/e**
(start/end), **Ctrl-b/f** (left/right), **Ctrl-d** (delete forward),
**Ctrl-k** (kill to end), **Backspace**.

## Buffers

hedit keeps open buffers in a ring:

| Key    | Does                                                        |
|------- |--------------------------------------------------------------|
| Meta-o | New scratch buffer (pushes the current one onto the ring)    |
| Meta-n | Next buffer in the ring                                      |
| Meta-p | Previous buffer in the ring                                  |
| Meta-w | Close the active buffer (refuses on the last one)            |

The tabline (row 0) lists every open buffer, active one bracketed —
e.g. `[scratch] | notes.txt`.

**Not yet:** split panes/windows, multiple cursors.

## Help

| Key    | Does                                                              |
|------- |--------------------------------------------------------------------|
| Ctrl-g | Toggle a full-screen keybindings overlay, generated live from the current bindings (any key closes it) |
| Meta-h | Same as Ctrl-g                                                     |

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
(bind "Meta-w" 'ignore)   ; silence the default close-buffer binding
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
