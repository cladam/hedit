# Default Keys

Below are the hotkeys hedit actually binds today, sourced from
`src/model.hc::default_bindings()` and `src/actions.hc`'s fixed
(non-rebindable) key handling — not aspirational. This list is also
generated live inside the editor: press `Ctrl-g` to open the
keybindings overlay, which renders straight from `state.config.bindings`
so it never drifts out of sync with what's actually installed.

All chords below except arrows/Enter/Backspace/Esc are rebindable from
`init.hl` with `(bind "Ctrl-x" 'action-name)` — see
[../examples/init.hl](../examples/init.hl) for every bindable action
name and a commented-out copy of each default. `'ignore` is a valid
target if you want to silence a default without replacing it.

hedit is modelled after [micro](https://github.com/micro-editor/micro)'s
"everything is a rebindable named action" philosophy (see
[micro-defaultkeys.md](micro-defaultkeys.md) for micro's own chart), but
today only implements a small, deliberately narrow subset — see
[What's not there yet](#whats-not-there-yet) below.

### File operations

| Key     | Action        | Description                                                                                     |
|-------- |-------------- |------------------------------------------------------------------------------------------------ |
| Ctrl-s  | `save`        | Save the current buffer. If it has no path yet (a new/scratch buffer), opens the Save-As prompt. |
| Ctrl-o  | `open-file`   | Open the "open file" prompt (type a path, Enter to load it into a new buffer).                   |
| Ctrl-q  | `quit`        | Quit hedit.                                                                                       |

### Cursor & line editing (readline-style)

Bash/readline-style chords for moving and editing without leaving the
home row — the same bindings work inside the Save-As/Open prompt too
(routed to `Prompt*` actions, see below).

| Key     | Action           | Description                                                          |
|-------- |----------------- |------------------------------------------------------------------------ |
| Ctrl-a  | `move-line-start`| Move to the start of the current line.                              |
| Ctrl-e  | `move-line-end`  | Move to the end of the current line.                                |
| Ctrl-b  | `move-left`      | Move left one char (same action as ArrowLeft).                      |
| Ctrl-f  | `move-right`     | Move right one char (same action as ArrowRight).                    |
| Ctrl-d  | `delete-forward`| Delete the char under the cursor (or merge the next line up at end of line). |
| Ctrl-k  | `kill-line`      | Kill from the cursor to the end of the line, into the clipboard.     |
| Ctrl-w  | `kill-word-back` | Kill the whitespace-delimited word before the cursor, into the clipboard. |
| Meta-f  | `move-word-forward` | Move forward one word.                                           |
| Meta-b  | `move-word-back`    | Move back one word.                                              |
| Meta-d  | `kill-word-forward` | Kill the word after the cursor, into the clipboard.              |
| Meta-l  | `kill-whole-line`   | Kill the entire current line, into the clipboard.                |

### Buffers

hedit has no tabs in the GUI sense — open buffers form a ring; `next`/
`prev` rotate it. There's no "close tab, keep others" gap: closing the
last buffer is refused with a status message instead of exiting.

`new-buffer`/`next-buffer`/`prev-buffer`/`close-buffer` are bound to
`Meta-o`/`Meta-n`/`Meta-p`/`Meta-w` by default — `term_ffi_inline.c`
decodes a bare `ESC` + printable char as `KShortcut(Meta, _)` (most
terminals' "metaSendsEscape" behaviour for Alt), so these are reachable
from a real terminal.

| Key     | Action         | Description                                                    |
|-------- |--------------- |----------------------------------------------------------------|
| Meta-o  | `new-buffer`   | Push the current buffer to the ring and open a fresh scratch buffer. |
| Meta-n  | `next-buffer`  | Cycle to the next buffer in the ring.                          |
| Meta-p  | `prev-buffer`  | Cycle to the previous buffer in the ring.                      |
| Meta-w  | `close-buffer` | Close the active buffer, promoting the next one in the ring.   |

### Clipboard & history

hedit has a single clipboard slot shared by `copy`/`paste` and the
kill commands above — `Ctrl-y` (yank) is bound to the same `paste`
action as `Ctrl-v`, not a separate kill-ring.

| Key     | Action   | Description                                  |
|-------- |--------- |---------------------------------------------- |
| Ctrl-c  | `copy`   | Copy the current line to the clipboard.       |
| Ctrl-v  | `paste`  | Paste clipboard contents at the cursor.       |
| Ctrl-y  | `paste`  | Yank — same as Ctrl-v (see above).            |
| Ctrl-z  | `undo`   | Undo the last edit.                           |
| Ctrl-r  | `redo`   | Redo the last undone edit.                    |

### Navigation & editing (fixed, not user-remappable)

These have no `char` payload to key a rebinding on, so they're handled
directly in `resolve_normal_action` rather than going through
`state.config.bindings`.

| Key         | Description                                             |
|------------ |--------------------------------------------------------- |
| Arrow keys  | Move the cursor up/down/left/right (wraps at line ends). |
| Enter       | Split the line at the cursor.                             |
| Backspace   | Delete the char before the cursor, or merge with the previous line at column 0. |
| Any printable char | Insert at the cursor.                              |

### Other

| Key     | Action        | Description                                                        |
|-------- |-------------- |--------------------------------------------------------------------- |
| Ctrl-g  | `toggle-help` | Open/close the keybindings overlay (any key closes it once it's up). |
| Meta-h  | `toggle-help` | Same as Ctrl-g — mnemonic "help".                                  |

### Save-As / Open prompts

Active when `Ctrl-s` triggers a save on a pathless buffer, or after
`Ctrl-o`. Not user-remappable (fixed like navigation above), and
`Ctrl-q` still quits even mid-prompt. The same readline chords as the
main buffer work here too, editing/killing the typed path instead of
buffer text.

| Key       | Description                                    |
|---------- |------------------------------------------------- |
| Any char  | Insert at the cursor (not just append).          |
| Backspace | Delete the char before the cursor.               |
| Ctrl-a    | Move to the start of the typed text.             |
| Ctrl-e    | Move to the end of the typed text.               |
| Ctrl-b    | Move left one column.                            |
| Ctrl-f    | Move right one column.                           |
| Ctrl-d    | Delete the char under the cursor.                |
| Ctrl-k    | Kill from the cursor to the end, into the clipboard. |
| Enter     | Submit (save-as / open the path).                |
| Esc       | Cancel, returning to the buffer.                 |

---

## What's not there yet

Compare this chart against [micro-defaultkeys.md](micro-defaultkeys.md)
— everything below is a gap, not a design decision. Recording it here
because it's the natural next milestone (a candidate "M11 — extended
key input" in `docs/effects-journal.md`'s numbering) rather than a
separate speculative document.

- **No further Alt/Meta chords beyond a single modified char.**
  `term_ffi_inline.c` now decodes a bare `ESC` + printable char as
  `KShortcut(Meta, _)` (most terminals' "metaSendsEscape" for Alt), and
  `default_bindings()` wires up `Meta-o/n/p/w/h/f/b/d/l`. Still
  missing: `Shift`-modified chords (`Modifier.Shift` exists but nothing
  produces it) and `Meta`/`Alt` combined with a special key like
  `Alt-Backspace` — only `Meta-<letter>` round-trips today.
- **No Home/End/PageUp/PageDown/Delete/F-keys.** `SpecialKey` only has
  `Enter`, `Backspace`, `Tab`, `Esc`, and the four arrows. The C FFI's
  escape-sequence decoder only recognizes plain `ESC [ A/B/C/D`; it
  doesn't try `~`-terminated sequences (`ESC[5~` PageUp, `ESC[3~`
  Delete, ...) or SS3 sequences (`ESC O P` = F1).
  Tab (code 9) is decoded but currently unused by `resolve_normal_action`.
- **No modifier-parameterised arrows** (`Ctrl-Right`, `Shift-Left`,
  `Ctrl-Shift-Down`, ...). Terminals encode these as `ESC[1;<n>C`
  where `<n>` is a modifier bitmask (2=Shift, 3=Alt, 4=Alt+Shift,
  5=Ctrl, 6=Ctrl+Shift, 7=Ctrl+Alt, 8=Ctrl+Alt+Shift) — the FFI's
  fixed 3-byte lookahead (`ESC [ X`) can't see the extra `;<n>`
  parameter at all.
- **No mouse.** `Event.MouseEvent` already exists as a variant, but
  nothing enables mouse reporting mode or parses `ESC[M...`/SGR mouse
  sequences — it's dead code waiting for a producer.
- **No multi-cursor, macros, splits, or find/replace.** These aren't
  input-decoding gaps — they're whole features `Action`/`EditorState`
  don't model yet (no selection range, no macro recording state, no
  pane tree, no search state).
- **`KeyChord` only models one modifier + one char.** Even once the
  decoder above exists, `KeyChord { m: Modifier, c: char }`
  (`src/model.hc`) can't represent `Ctrl-Shift-Right` (two modifiers,
  a special key, not a char) — the struct itself needs to grow before
  a binding table entry could exist for it.

### A sketch of the work, in order

1. **Widen `SpecialKey`** (`src/keys.hc`) with `Home`, `End`,
   `PageUp`, `PageDown`, `Delete`, `F1`..`F12`.
2. **Teach the C FFI** (`term_ffi_inline.c`) to parse `~`-terminated
   and SS3 escape sequences into new synthetic codes (following the
   existing 1001-1004 arrow convention, e.g. 1005=Home, 1006=End, ...),
   and to parse the `;<n>` modifier parameter on both arrow and `~`
   sequences into a separate return value (or a packed code) rather
   than throwing it away.
3. **Detect bare Alt.** ✅ Done — most terminals send `Alt-x` as `ESC`
   followed immediately by `x` (no `[`); `term_ffi_inline.c` special-cases
   a non-`[` byte after `ESC` as a Meta-modified char (codes 2032-2126)
   instead of falling through to plain `Esc`.
4. **Generalize `KeyChord`** to carry a *set* of modifiers plus either
   a `char` or a `SpecialKey` payload, e.g.
   `KeyChord { mods: list<Modifier>, key: KeyPayload }` with
   `KeyPayload = PChar(char) | PSpecial(SpecialKey)`. This is the
   breaking change everything else hangs off — `default_bindings()`,
   `lookup_binding`, and the HiLisp `parse_chord`/`chord_to_str` round
   trip in `src/hilisp_host.hc` all need updating together, ideally
   keeping today's `"Ctrl-s"` strings valid (single modifier + char is
   just the one-element case of the new shape).
5. **Extend the HiLisp chord grammar** so `.hl` files can spell
   `"Alt-Left"`, `"Ctrl-Shift-Right"`, `"Alt-Backspace"` — parse on
   `-`, treat all-but-the-last segment as modifiers, the last as either
   a single char or a `SpecialKey` name.
6. **Mouse** is a separate track: enable reporting (`ESC[?1000h` or
   SGR `ESC[?1006h`) once on startup/raw-mode-enter, parse the report
   sequences in the FFI or `keys.hc`, and populate the already-defined
   `MouseEvent`.
7. **Multi-key sequences** (a pending-prefix chord, vim/emacs-style)
   would need a small state machine — a `pending_chord` field on
   `EditorState` that `resolve_action` checks before consulting
   `state.config.bindings` — but nothing today requires this, so it's
   lowest priority.

None of this needs new hica language features — it's ordinary ADT
growth plus more C FFI parsing, so it can land incrementally (e.g.
Home/End/PageUp first, modifiers later) rather than as one big-bang
milestone.