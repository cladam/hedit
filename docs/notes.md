# hedit — Usage Notes, Tips & Tricks

Small living document — grows with the milestones. For the design see
`docs/hedit-design.md`; for the running "how did we build this" log see
`docs/effects-journal.md`.

---

## Keybindings

hedit follows [micro's model](https://github.com/micro-editor/micro/blob/master/runtime/help/keybindings.md):
every editor operation is a **named action** (`quit`, `save`, `insert`, …),
and every keystroke resolves through a **binding table** to one of those
actions. Nothing is hard-coded in the dispatcher — the defaults live in
`src/model.hc::default_bindings()` and can be replaced from HiLisp (M4)
via `(bind "Ctrl-x" 'save)`.

### Current default bindings (M10.6 — readline-style remap)

| Chord    | Action | Notes |
|----------|--------|-------|
| `Ctrl-q` | `quit`  | Sets `should_quit`; event loop terminates. |
| `Ctrl-s` | `save`  | Writes buffer to disk, or opens a Save-As prompt for a pathless buffer (M9). |
| `Ctrl-o` | `open-file`    | Opens a prompt to load an existing file into a new buffer (M9). Moved here from `new-buffer` in M10.6 — see note below. |
| `Ctrl-c` | `copy`  | Copies the head cursor's current line into the clipboard. |
| `Ctrl-v` | `paste` | Appends the clipboard content at the end of the head cursor's line. |
| `Ctrl-y` | `paste` | Yank — same clipboard slot as `Ctrl-v` (M10.6). |
| `Ctrl-z` | `undo`  | Restores the buffer to its last snapshot. |
| `Ctrl-r` | `redo`  | Re-applies the most recently undone snapshot. Moved here from `Ctrl-y` in M10.6. |
| `Ctrl-a` | `move-line-start` | Readline-style motion (M10.6). |
| `Ctrl-e` | `move-line-end`   | Readline-style motion (M10.6). Was `open-file` before M10.6 — see note below. |
| `Ctrl-b` / `Ctrl-f` | `move-left` / `move-right` | Duplicates of the arrow keys (M10.6). |
| `Ctrl-d` | `delete-forward` | Delete the char under the cursor (M10.6). |
| `Ctrl-k` | `kill-line` | Kill from the cursor to end of line (M10.6). |
| `Ctrl-w` | `kill-word-back` | Kill the word before the cursor (M10.6). Was `close-buffer` before M10.6 — see note below. |
| `Ctrl-g` | `toggle-help`  | Shows/hides the full-screen keybindings overlay (M10). |
| `Meta-o` | `new-buffer`   | Opens a fresh in-memory scratch buffer and makes it active. Moved here from `Ctrl-o` in M10.6. |
| `Meta-n` | `next-buffer`  | Cycles to the next open buffer (wraps around). |
| `Meta-p` | `prev-buffer`  | Cycles to the previous open buffer (wraps around). |
| `Meta-w` | `close-buffer` | Closes the active buffer; refuses to close the last one. Moved here from `Ctrl-w` in M10.6. |
| `Meta-h` | `toggle-help`  | Same action as `Ctrl-g`. |
| `Meta-f` / `Meta-b` | `move-word-forward` / `move-word-back` | Word motion (M10.6). |
| `Meta-d` | `kill-word-forward` | Kill the word after the cursor (M10.6). |
| `Meta-l` | `kill-whole-line` | Kill the entire current line (M10.6). |

**Binding remap note (M10.6):** if your `init.hl` has a custom
`(bind "Ctrl-o" …)`, `(bind "Ctrl-e" …)`, `(bind "Ctrl-w" …)`, or
`(bind "Ctrl-y" …)` from before M10.6, it now shadows a *different*
default action than it used to (the table above shows the new
defaults) — worth double-checking after upgrading.

Typing any printable character routes to `insert` automatically — you
don't (and can't) bind `a`, `b`, `c`, … Those aren't chord bindings.

Unbound shortcuts resolve to the `Ignore` action — they are silently
no-ops rather than errors, so a stale binding in your `init.hl` won't
wedge the editor.

`Meta-*` chords require the terminal to send a bare `ESC` immediately
followed by the character (most terminals' "metaSendsEscape" mode,
on by default) — see `src/term_ffi_inline.c` / `src/keys.hc::decode_key`.


### M4 (landed): HiLisp `(set …)` / `(bind …)` in `init.hl`

The HiLisp bridge in `src/hilisp_host.hc` + `src/config_loader.hc`
is complete. On startup (once M4b wires it into `main.hc`), hedit
walks `$XDG_CONFIG_HOME/hedit/init.hl` → `$HOME/.hedit.hl` and
evaluates the first hit against a HiLisp env seeded with your
current `Config`. Three built-ins are exposed:

| Form | Effect |
|------|--------|
| `(set "key" value)` | Records a string-typed value; retrieve with `get_config` / `get_config_int` from hedit code. |
| `(get "key")` | Reads a previously-set value (returns nil when absent, so `(if (get "auto-indent") …)` reads naturally). |
| `(bind "Ctrl-x" 'action)` | Rebinds a chord to a named action. Modifier prefixes: `Ctrl-`, `Alt-`, `Meta-`, `Shift-`. Supported action symbols: `'quit`, `'save`, `'copy`, `'paste`, `'undo`, `'redo`, `'new-buffer`, `'next-buffer`, `'prev-buffer`, `'close-buffer`, `'ignore`. |

Bad chord strings or unknown action symbols produce an `LError`
that surfaces on `EditorState.status_message` as `Config error
(…): error[host/bad-chord]: …` — so a typo in `init.hl` won't
lock you out of the editor, and you can see what tripped the
loader on the first render tick.

Anything you `(set …)` earlier in the file survives even if a
later form errors — `load_config` returns the *partial* Config
alongside the error message.

Example (from `tests/hilisp_host_test.hc`, all green):

```lisp
;; ~/.config/hedit/init.hl
(set "tabsize" 4)
(bind "Ctrl-x" 'quit)     ; new chord
(bind "Ctrl-s" 'save)     ; same as default, harmless
```

**Note on the `hica build` follow-up.** `hica test` handles the
HiLisp submodule include-path correctly, but `hica build` doesn't
yet — `@koka { include: "./lib/hilisp/src" }` in `hica.hml`
doesn't reach the production entry point. Until that lands
(tracked in the M4 journal), `main.hc` runs with hard-coded
defaults; the bridge is exercised through tests only. Nothing
changes for the config-file format itself.

---

## Copy / Paste (Ctrl-c / Ctrl-v) semantics

M3 v1 is deliberately small-scope so the effect scaffolding lands
without dragging in a full cursor-model rewrite. Behaviour:

- **Copy (Ctrl-c)** hands the head cursor's *current line* (no
  trailing newline) to `Clipboard.set_selection`, and sets the status
  line to `"Copied line"`. The buffer itself is unchanged and
  `is_dirty` doesn't flip.
- **Paste (Ctrl-v)** reads `Clipboard.get_selection` and appends the
  text verbatim to the end of the head cursor's line. Every cursor's
  column advances by `length(text)`. `is_dirty` flips true.
- **Handler swap.** `src/main.hc` installs an in-memory `Clipboard`
  handler (`with var clip = ""`). Tests install the same shape via
  the nested-handler pattern in `tests/runtime_test.hc`. A real OS
  clipboard (pbcopy / wl-copy / xclip) can slot in by swapping only
  the two arm bodies — `event_loop` doesn't change.

**Simplifications you'll notice:**

- No selection model yet — Copy always grabs the whole current line,
  not an anchor-to-head range.
- No `\n` splitting on Paste. A clipboard containing `"foo\nbar"` is
  pasted as a literal 7-char string; multi-line paste needs the
  buffer to grow a `split_line` op first (M5+).
- No system clipboard integration in the shipped stub — Copy/Paste
  round-trip only inside a single hedit session for now.

---

## Undo / Redo (Ctrl-z / Ctrl-y) semantics

M5 adds undo/redo via a `spawn`ed `Buffer` effect (see
`docs/hedit-design.md` §9) — one per `event_loop` call, holding two
stacks of `TextBuffer` snapshots. Behaviour:

- **Every keystroke is its own snapshot.** `Insert` and `Paste`
  each call `snapshot` on the buffer *before* mutating, so `Ctrl-z`
  undoes one character (or one paste) at a time — there's no
  coalescing of a typing run into a single undo step yet.
- **Undo (Ctrl-z)** restores the most recent snapshot and pushes the
  buffer you were on onto the redo stack. If there's no history,
  the status line shows `"Nothing to undo"` — not an error.
- **Redo (Ctrl-y)** re-applies the most recently undone snapshot.
  Any new snapshot (from typing after an undo) clears the redo
  stack, same as most editors — you can't redo past a fresh edit.
- **Save/Copy don't snapshot.** Only actions that mutate
  `TextBuffer` content push history.
- **Scope: single active buffer, per-buffer history not yet isolated.**
  The undo/redo mechanism is proven to scale to multiple independent
  instances (`tests/spawn_test.hc` spawns two and checks isolation),
  but `event_loop` still only ever spawns *one* `Buffer` instance per
  call. M5.5 added multi-buffer navigation (`Ctrl-o`/`Ctrl-n`/`Ctrl-p`/
  `Ctrl-w`) without giving each open buffer its own undo/redo stack —
  switching buffers doesn't swap in a separate history yet. See
  `docs/effects-journal.md` M5.5 non-goals.

---

## Multi-buffer navigation (Meta-o / Meta-n / Meta-p / Meta-w)

M5.5 lets hedit hold more than one open buffer. `EditorState.buffer` is
always the *active* buffer; `EditorState.background_buffers` holds the
rest as a rotation ring (see `docs/hedit-design.md` §10 for the shape).
These chords moved from `Ctrl-*` to `Meta-*` in M10.6 to make room for
the readline-style `Ctrl-*` motions below — see the Keybindings table.

- **`Meta-o` (new-buffer)** backgrounds the current buffer and opens a
  fresh, empty, unnamed scratch buffer as the new active one. This is
  an **in-memory** buffer only — use `Ctrl-o` (`open-file`, M9) to load
  an existing file from disk instead.
- **`Meta-n` / `Meta-p` (next-buffer / prev-buffer)** rotate through
  every open buffer, wrapping at both ends. With only one buffer open,
  both are no-ops.
- **`Meta-w` (close-buffer)** closes the active buffer and promotes the
  next one in the ring. Refuses (with a `"Can't close the last
  buffer"` status message) if it's the only buffer open — hedit always
  keeps at least one buffer open.
- **Tabline.** `render_editor_to_buffer` draws a tabline as the first
  screen row: every open buffer's name (its path, or `"scratch"` for
  an unnamed one), joined by `|`, with the active one bracketed —
  e.g. `[scratch]|notes.txt`.

---

## Save (Ctrl-s) semantics


- Writes `join(buffer.lines, "\n") + "\n"` — POSIX line-oriented tools
  (`wc -l`, `git diff`, most greps) expect a trailing newline, and files
  round-trip cleanly through common editors.
- Buffers with no path (a "scratch" buffer opened via `init_editor(None)`
  or `Ctrl-o`) open a **Save-As prompt** (M9, see below) instead of a
  dead-end status message.
- A session started with `--readonly`/`-R` (M8) sets status
  `"Read-only — not saved"` and never touches the filesystem, nor opens
  the Save-As prompt — checked before the no-path case, so it applies
  even to a scratch buffer.
- On success: `is_dirty` clears, status becomes `"Saved"`.
- On I/O error: status becomes `"Save failed: <message>"`; the buffer is
  left dirty.

---

## Save-As / Open prompt (M9)

`Ctrl-s` on a pathless buffer and the new `Ctrl-e` chord both open a
minimal single-line text-input widget on the status row instead of
growing hedit into a full command palette.

- **`Ctrl-s` on a scratch buffer** opens `Save as: ` — type a path and
  press `Enter` to write the buffer there; the buffer's `path` is set
  on success so subsequent `Ctrl-s` saves go straight to disk. `Esc`
  cancels, discarding the typed text and leaving the buffer exactly as
  it was (nothing is written).
- **`Ctrl-o` (`open-file`)** opens `Open: ` — type a path to an
  *existing* file and press `Enter` to load it into a **new** buffer,
  backgrounding the current one (same shape as `Meta-o`'s `new-buffer`).
  A missing/unreadable path surfaces the same `"Could not open …"`
  status `load_buffer` (M6) already produces for the CLI `[file]`
  positional. (`open-file` moved from `Ctrl-e` to `Ctrl-o` in M10.6 to
  free `Ctrl-e` for the readline `move-line-end` motion.)
- **While a prompt is active**, printable keys edit the prompt text
  instead of the buffer; `Ctrl-a/e/b/f` move within the prompt text and
  `Ctrl-k`/`Ctrl-d` kill-to-end/delete-forward inside it too (M10.6),
  mirroring the normal-mode readline motions. `Ctrl-q` is the one
  exception to "prompt steals every key": it still quits immediately
  even mid-prompt, matching the synthetic "stdin closed" event and
  avoiding a stuck prompt if the terminal session ends.
- **Rebindable.** `open-file` is a normal `Action` symbol, so
  `(bind "Ctrl-o" 'open-file)` in `init.hl` moves it like any other
  chord (see the Keybindings table above).
- **Non-goals:** filename tab-completion, directory browsing, and
  overwrite confirmation on an existing path are all deliberately out
  of scope — plain text entry only.

---

## Help overlay (M10)

`Ctrl-g` (`toggle-help`) shows a full-screen listing of every currently
bound chord — generated live from `state.config.bindings`
(`render.hc::render_help_buffer`), so a custom `(bind …)` remap from
your `init.hl` shows up correctly instead of a hardcoded cheat sheet.

- **Any key closes it** and returns to the buffer underneath, unchanged
  — the overlay never touches buffer state, it only flips
  `EditorState.show_help`.
- **`Ctrl-q` still quits** and a terminal resize still resizes even
  while the overlay is showing (same carve-outs as the M9 Save-As/Open
  prompt).
- The overlay ignores the periodic idle-poll `Tick` event (not a
  keypress) — otherwise it would close itself ~200ms after opening.

## Theming (M10)

hedit's own chrome (tabline, status line, the row the cursor is on) is
colored via a `Theme` (7 true-color `(r, g, b)` slots — tabline/status/
active-tab fg+bg, cursor-line bg), resolved once at startup in
`main.hc::run_editor` and applied as ANSI SGR codes when the frame is
printed (`render_native`). This is **not** syntax highlighting — buffer
content itself is never colored.

- **`(set "theme" "ilseon")`** in `init.hl` (or any `(set …)` call)
  switches the whole preset. Built-in presets: `"default"` and
  `"ilseon"` (a dark, low-sensory palette, same RGB values as
  `std/term`'s `ilseon_*` helpers). An unrecognised name falls back to
  `"default"` with a status message on the first render — it never
  crashes.
- **`(set "theme.<slot>" "R,G,B")`** overrides a single color on top of
  whichever preset is active. Slots: `theme.tabline-fg`,
  `theme.tabline-bg`, `theme.status-fg`, `theme.status-bg`,
  `theme.active-tab-fg`, `theme.active-tab-bg`, `theme.cursor-line-bg`.
- No new config-loading machinery was needed — `(set k v)` already
  wrote any string key/value into `Config.values`, so these are just
  new well-known keys read by `model.hc::resolve_theme_with_status`.
- **Non-goals:** per-token syntax highlighting, a live theme editor/
  picker UI, and true-color capability detection (hedit trusts the
  terminal supports 24-bit color, same as `std/term`'s `term_rgb`).

---

## Command-line usage (M8)

```
$ hedit --help
hedit 0.2.0 — a terminal text editor in hica


USAGE: hedit [OPTIONS] [file]

OPTIONS:
    --no-config         skip loading the user's init.hl entirely
  -R, --readonly        open the file in read-only mode (Save is disabled)
  -c, --config VALUE    load config from this path instead of the default search
    --tabsize VALUE     override the tabsize config value
  -h, --help            Show this help
      --version         Show version

ARGS:
  <file>                file to open
```

- **`hedit [file]`** — the only positional; a missing/unreadable path
  falls back to an empty scratch buffer with a status message (M6),
  never a crash.
- **`--config <path>` / `-c`** — bypasses the normal
  `$XDG_CONFIG_HOME`/`$HOME` search (`config_loader.hc::candidate_paths`)
  and loads exactly this file. A missing/unreadable explicit path is a
  status message (`"Could not open …"`), not a silent fallback — you
  asked for this file by name.
- **`--no-config`** — skips loading `init.hl` entirely (useful for
  reproducing a bug without a user's config in the loop). Wins over
  `--config` if both are given.
- **`--tabsize <n>`** — applied to `Config.values` *after* `init.hl`
  has loaded, so it always overrides a `(set "tabsize" …)` in the
  config file — CLI flags win, matching `micro`'s session-override
  precedence.
- **`--readonly` / `-R`** — gates `Save` (see above); nothing else about
  the session changes (you can still edit in-memory, just not write).
- **`+LINE[:COL]`** — a special positional (not a `std/cli`
  flag/option — matches `micro`'s own syntax), order-independent
  relative to `[file]`. 1-indexed on the command line, converted to
  hedit's internal 0-indexed `Position` and clamped into the opened
  buffer's actual bounds (`model.hc::clamp_position`) — an
  out-of-range line/column never crashes, it just lands on the nearest
  valid spot.

---

## Known limitations

Small stuff we've deliberately deferred; flagged here so no-one is
surprised. (Updated 2026-08-25, pre-M11 review — several M2/M3-era
entries below were stale and have been resolved or corrected.)

- **Render truncation is byte-oriented.** `render.hc::fit_to_width` uses
  `s[0:w]`, which slices by *byte* offset. Any multi-byte UTF-8 codepoint
  (é, →, 🙂, …) that straddles the width boundary will either corrupt or
  crash the render. hedit is ASCII-only in practice until we add a
  codepoint-safe slice (either in the hica stdlib or as a hedit helper).
  Still open.
- **No multi-cursor support.** Cursor-aware, mid-line editing (insert,
  delete, arrow motion) has been in since the M7 revisit; there is
  still only ever one cursor per buffer, not several. Still open, no
  milestone currently planned for it.
- **Per-buffer undo/redo isolation.** Switching buffers doesn't swap in
  a separate undo/redo history — see the Undo/Redo section above and
  `docs/effects-journal.md`'s M5.5 non-goals. Still open.
- **Tabline order isn't stable across cycling.** The active buffer is
  always listed first, so `Ctrl-n`/`Ctrl-p`/`Meta-n`/`Meta-p` visibly
  reshuffle tab order instead of just moving a highlight. Cosmetic,
  still open.
- **`set_cursor_style` is a no-op.** No ANSI cursor-shape escape is
  sent; the terminal's default cursor shape is used throughout. Still
  open, low priority.

**Resolved since this section was last written** (kept here briefly so
the history isn't lost): file loading from the CLI/a running session
(M6, M9), the native terminal handler (M7), and vertical scrolling for
buffers taller than the viewport (M10.5, a bottom-anchored formula in
`render.hc::scroll_offset`).
