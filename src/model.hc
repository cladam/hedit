// model.hc — core editor state (pure data + constructors).
//
// This is a deliberately reduced slice of section 3 of docs/hedit-design.md:
// single buffer, single cursor, no panes, no undo stack, no buffer map. We'll
// grow these back in later steps once the minimum shell type-checks and runs.

// A caret position inside a `TextBuffer`.
pub struct Position {
  line: int,
  col: int
}

// One cursor. `cid` is the cursor identifier (avoids clashing with the
// `TextBuffer.id` accessor that Koka generates).
pub struct Cursor {
  cid: int,
  pos: Position
}

// A buffer of text lines plus its cursors and dirty flag.
// `bid` is the buffer identifier (same reason we don't reuse `id`).
// `lines` is a `list<string>` for now; a piece table / rope can slot in later
// without changing this file's public surface.
pub struct TextBuffer {
  bid: int,
  path: maybe<string>,
  lines: list<string>,
  cursors: list<Cursor>,
  is_dirty: bool
}

// Full editor state.  Single-buffer for step 1.
pub struct EditorState {
  buffer: TextBuffer,
  status_message: maybe<string>,
  screen_size: (int, int),
  should_quit: bool
}

// --- constructors ---------------------------------------------------------

// A fresh buffer with one empty line and one cursor at (0, 0).
pub fun new_buffer(bid: int, path: maybe<string>) : TextBuffer =>
  TextBuffer {
    bid: bid,
    path: path,
    lines: [""],
    cursors: [Cursor { cid: 0, pos: Position { line: 0, col: 0 } }],
    is_dirty: false
  }

// Initial editor state. `path` is optional — `None` means an unnamed scratch
// buffer. A real file-open step will come with the `fs` effect later.
pub fun init_editor(path: maybe<string>) : EditorState =>
  EditorState {
    buffer: new_buffer(0, path),
    status_message: None,
    screen_size: (80, 24),
    should_quit: false
  }

// --- small pure helpers ---------------------------------------------------

pub fun set_status_message(s: EditorState, msg: string) : EditorState =>
  EditorState { ...s, status_message: Some(msg) }

pub fun clear_status_message(s: EditorState) : EditorState =>
  EditorState { ...s, status_message: None }
