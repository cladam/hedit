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

### Current default bindings (M3)

| Chord    | Action | Notes |
|----------|--------|-------|
| `Ctrl-q` | `quit`  | Sets `should_quit`; event loop terminates. |
| `Ctrl-s` | `save`  | Writes buffer to disk (needs a named buffer). |
| `Ctrl-c` | `copy`  | Copies the head cursor's current line into the clipboard. |
| `Ctrl-v` | `paste` | Appends the clipboard content at the end of the head cursor's line. |

Typing any printable character routes to `insert` automatically — you
don't (and can't) bind `a`, `b`, `c`, … Those aren't chord bindings.

Unbound shortcuts (e.g. `Ctrl-x` today) resolve to the `Ignore` action —
they are silently no-ops rather than errors, so a stale binding in your
`init.hl` won't wedge the editor.


### Coming in M4

- `(bind "Ctrl-x" 'save)` — replace a default.
- `(bind "Alt-Enter" 'quit)` — add a new chord.
- `(unbind "Ctrl-q")` — TBD; may just drop from the alist.

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

## Save (Ctrl-s) semantics


- Writes `join(buffer.lines, "\n") + "\n"` — POSIX line-oriented tools
  (`wc -l`, `git diff`, most greps) expect a trailing newline, and files
  round-trip cleanly through common editors.
- Buffers with no path (a "scratch" buffer opened via `init_editor(None)`)
  set status `"No file — save not possible"` rather than throwing.
- On success: `is_dirty` clears, status becomes `"Saved"`.
- On I/O error: status becomes `"Save failed: <message>"`; the buffer is
  left dirty.

---

## Known limitations

Small stuff we've deliberately deferred; each one is fine for the M2/M3
scope but flagged here so no-one is surprised.

- **Render truncation is byte-oriented.** `render.hc::fit_to_width` uses
  `s[0:w]`, which slices by *byte* offset. Any multi-byte UTF-8 codepoint
  (é, →, 🙂, …) that straddles the width boundary will either corrupt or
  crash the render. hedit is ASCII-only in practice until we add a
  codepoint-safe slice (either in the hica stdlib or as a hedit helper).
- **Only one line + one cursor.** `insert_char` appends to the active
  line's end regardless of column. Multi-cursor and mid-line insertion
  are on the M5+ list.
- **No file open flow yet.** `write_file` on `Ctrl-s` works because the
  design lets you construct an `EditorState` with a path via
  `init_editor(Some(path))`. Opening a file from the command line / a
  key chord lands with M4 or M5.
- **Native handler is a stub.** `src/main.hc` runs one iteration and
  quits (canned `Ctrl-q`), and `render_frame` dumps `ScreenBuffer.lines`
  line-by-line with no ANSI positioning. A real terminal driver lands
  after the effect scaffolding stabilises.
