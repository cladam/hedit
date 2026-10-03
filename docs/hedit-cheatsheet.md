# hedit Cheatsheet

This reference covers hedit's default bindings and context-specific controls.
Bindings changed in `init.hl` appear in the live `Ctrl-g` overlay.

`Meta` is usually the Alt or Option key, depending on the terminal.

## Starting hedit

```sh
hedit                         # restore the previous session, or open a scratch buffer
hedit --no-recover            # skip session recovery
hedit file.txt                # open a file without restoring the previous session
hedit +42 file.txt            # open at line 42
hedit +42:8 file.txt          # open at line 42, column 8
hedit --readonly file.txt     # open read-only
hedit --tabsize 2 file.txt    # override the configured tab size
hedit --config init.hl        # load a specific configuration file
hedit --no-config             # skip configuration
hedit --help                  # show all command-line options
hedit --version
```

Command-line options override settings loaded from `init.hl`.

## Navigation

| Key | Action |
| --- | --- |
| Arrow keys | Move up, down, left, or right; horizontal movement wraps at line ends |
| PageUp / PageDown | Move one visible page up or down |
| `Ctrl-a` / `Ctrl-e` | Move to the start / end of the current line |
| `Meta-f` / `Meta-b` | Move forward / backward by one word |

## Editing

| Key | Action |
| --- | --- |
| Any printable character | Insert at every active cursor |
| Enter | Split the line at every active cursor |
| Backspace | Delete backward, joining lines when necessary |
| `Ctrl-d` | Delete forward, joining the next line at end of line |
| `Ctrl-k` | Cut from the cursor to the end of the line |
| `Ctrl-w` | Cut the word before the cursor |
| `Meta-d` | Cut the word after the cursor |
| `Meta-l` | Cut the entire current line |
| `Ctrl-c` | Copy active selections, or the current line when nothing is selected |
| `Ctrl-v` / `Ctrl-y` | Paste from the system clipboard |

Kill, copy, and paste commands share the system clipboard. hedit uses
`pbcopy`/`pbpaste` on macOS, `wl-copy`/`wl-paste` on Wayland, and `xclip` or
`xsel` on X11, with an in-memory fallback when no complete tool pair is
available.

## Selections and multiple cursors

| Key or gesture | Action |
| --- | --- |
| `Ctrl-Space` | Set the selection mark; press again to clear it |
| Movement with a mark set | Extend the selection |
| `Meta-a` | Select the entire buffer |
| Mouse drag | Select text |
| `Meta-c` | Select the word under the cursor, then add a cursor at each subsequent match |
| Meta-click | Add a cursor at the clicked position |
| Esc | Return to one cursor and clear selections |

Typing, deleting, and pasting apply at every active cursor. hedit adjusts later
cursor positions as earlier edits change the buffer.

## Undo and revision history

| Key | Action |
| --- | --- |
| `Ctrl-z` | Undo to the parent revision |
| `Ctrl-r` | Redo along the active branch |
| `Meta-u` | Cycle sibling branches |
| `Meta-t` | Open the visual undo tree |

Inside the undo tree, use Up/Down or `k`/`j` to preview revisions. Enter
restores the selected revision. Esc or `Meta-t` closes the tree without
restoring it.

## Find

| Key | Action |
| --- | --- |
| `Ctrl-f` | Open the find prompt; matches update as you type |
| `Ctrl-Right` | Move to the next match, wrapping at the end |
| `Ctrl-Left` | Move to the previous match, wrapping at the beginning |
| Enter | Closes the prompt and moves to the next match; highlighting remains active |
| Esc | Cancel the search and clear its highlights |

Search is case-sensitive, uses plain substrings, and covers the whole buffer.
`Ctrl-Right` and `Ctrl-Left` continue to work after the prompt closes.

## Files and buffers

| Key | Action |
| --- | --- |
| `Ctrl-s` | Save; opens Save As when the buffer has no path |
| `Ctrl-o` | Open the file prompt |
| `Ctrl-q` | Quit, or close the active pane when more than one pane is open |
| `Meta-o` | Open a new scratch buffer |
| `Meta-n` / `Meta-p` | Move to the next / previous buffer in the ring |
| `Meta-w` | Close the active buffer; the last buffer cannot be closed |

The tabline lists open buffers and brackets the active one, for example
`[scratch] | notes.txt`.

## Split panes

| Key or gesture | Action |
| --- | --- |
| `Meta-v` | Open a vertical split prompt |
| `Meta-h` | Open a horizontal split prompt |
| `Meta-Arrows` | Focus the nearest pane in that direction |
| `Meta-Tab` | Cycle focus through the panes |
| Click in a pane | Focus the pane and place the cursor |
| Drag a divider | Resize the adjacent panes |
| Mouse wheel | Scroll the pane under the pointer without changing focus |

In a split prompt, enter a path to open that file in the new pane. Submit an
empty prompt to duplicate the current buffer into the new pane. Esc cancels.

## Command palette and shell

| Key | Action |
| --- | --- |
| `Meta-x` | Open the command palette |
| Tab / Down | Select the next matching command |
| Up | Select the previous matching command |
| Enter | Run the selected or typed command |
| Esc | Close the palette |

Type `!` followed by a command, such as `!git status`, or select `shell` to
open a shell-command prompt. hedit displays captured output in an overlay.

| Shell output key | Action |
| --- | --- |
| Up/Down or `k`/`j` | Scroll one line |
| PageUp / PageDown | Scroll one page |
| Mouse wheel | Scroll one line |
| Esc, Enter, or `q` | Close the output |

## Prompt editing

Save As, Open, Find, split, command, and shell prompts share these controls:

| Key | Action |
| --- | --- |
| Any printable character | Insert at the prompt cursor |
| Backspace / `Ctrl-d` | Delete backward / forward |
| `Ctrl-a` / `Ctrl-e` | Move to the start / end |
| `Ctrl-b` / `Ctrl-f` | Move left / right |
| `Ctrl-k` | Cut from the cursor to the end |
| Enter | Submit |
| Esc | Cancel |

Tab, Down, and Up cycle suggestions in the command palette. `Ctrl-q` retains
its normal quit or close-pane behavior while a prompt is open.

## Help and configuration

| Key | Action |
| --- | --- |
| `Ctrl-g` | Show the active keybindings; any key closes the overlay |
| `Meta-r` | Reload `init.hl` and plugins without restarting |

hedit loads the first applicable configuration file:

1. `$XDG_CONFIG_HOME/hedit/init.hl`, when `$XDG_CONFIG_HOME` is set
2. `$HOME/.config/hedit/init.hl`
3. `$HOME/.hedit.hl`

Use `--config` to load another file. See
[`examples/init.hl`](../examples/init.hl) for all settings and bindable action
names.

```lisp
(set "tabsize" 4)
(set "theme" "ilseon")

(bind "Ctrl-s" 'save)
(bind "Meta-w" 'close-buffer)
(bind "Ctrl-w" 'ignore) ; disable a default binding
```

Only modifier-plus-character shortcuts are rebindable. Navigation keys,
PageUp/PageDown, Enter, Backspace, Esc, pane-focus keys, and mouse gestures are
handled directly by the editor.
