/// Unit tests for session serialization, deserialization, and recovery.

import "../src/keys"
import "../src/model"
import "../src/session"

test "serialize and deserialize single scratch buffer with content" {
  let cfg = default_config()
  let buf = TextBuffer {
    bid: 0,
    path: None,
    lines: ["hello", "world"],
    cursors: [Cursor { cid: 0, pos: Position { line: 1, col: 2 }, anchor: None, anchor_sticky: false }],
    is_dirty: true,
    scroll_line: 0
  }
  let s0 = init_editor_with_buffer(buf, cfg)
  let sexpr = serialize_session(s0)
  assert(starts_with(sexpr, "(session"))

  let res = deserialize_session(sexpr, cfg)
  let is_some = match res { Some(_) => true, None => false }
  assert(is_some)

  let s1:EditorState = match res { Some(s) => s, None => s0 }
  let b: TextBuffer = s1.buffer
  assert_eq(b.bid, 0)
  assert(b.path == None)
  assert(b.is_dirty == true)
  assert(b.lines == ["hello", "world"])
  let ok_cur = match b.cursors {
    [c, ..] => c.pos.line == 1 && c.pos.col == 2,
    _       => false
  }
  assert(ok_cur)
}

test "serialize and deserialize multi-buffer and split panes" {
  let cfg = default_config()
  let buf0 = TextBuffer {
    bid: 0,
    path: Some("/tmp/file_a.txt"),
    lines: ["aaa", "bbb"],
    cursors: [Cursor { cid: 0, pos: Position { line: 0, col: 1 }, anchor: Some(Position { line: 0, col: 3 }), anchor_sticky: true }],
    is_dirty: false,
    scroll_line: 5
  }
  let buf1 = TextBuffer {
    bid: 1,
    path: Some("/tmp/file_b.txt"),
    lines: ["ccc"],
    cursors: [Cursor { cid: 1, pos: Position { line: 0, col: 0 }, anchor: None, anchor_sticky: false }],
    is_dirty: true,
    scroll_line: 0
  }
  let test_panes = Split(Vertical, 0.6, Leaf(0), Leaf(1))
  let s0 = EditorState {
    ...init_editor_with_buffer(buf0, cfg),
    background_buffers: [buf1],
    panes: test_panes,
    next_bid: 5
  }
  let sexpr = serialize_session(s0)
  let res = deserialize_session(sexpr, cfg)
  let is_some = match res { Some(_) => true, None => false }
  assert(is_some)

  let s1 = match res { Some(s) => s, None => s0 }
  assert_eq(s1.buffer.bid, 0)
  assert_eq(s1.next_bid, 5)
  assert_eq(length(s1.background_buffers), 1)

  let ok_bg = match s1.background_buffers {
    [bg, ..] => bg.bid == 1 && bg.is_dirty == true,
    _        => false
  }
  assert(ok_bg)
  assert_eq(s1.buffer.scroll_line, 5)

  // Validate panes
  let ok_panes = match s1.panes {
    Split(ax, r, l_node, r_node) => {
      let ok_ax = match ax { Vertical => true, _ => false }
      let ok_r = r > 0.59 && r < 0.61
      let ok_l = match l_node { Leaf(bid) => bid == 0, _ => false }
      let ok_r_node = match r_node { Leaf(bid) => bid == 1, _ => false }
      ok_ax && ok_r && ok_l && ok_r_node
    },
    _ => false
  }
  assert(ok_panes)

  // Validate anchor
  let ok_anchor = match s1.buffer.cursors {
    [c, ..] => {
      let sticky_ok = c.anchor_sticky
      let anchor_pos_ok = match c.anchor {
        Some(pos) => pos.line == 0 && pos.col == 3,
        None      => false
      }
      sticky_ok && anchor_pos_ok
    },
    _ => false
  }
  assert(ok_anchor)
}

test "deserialize malformed strings degrades to None" {
  let cfg = default_config()
  let r1 = match deserialize_session("", cfg) { None => true, Some(_) => false }
  assert(r1)
  let r2 = match deserialize_session("not a lisp sexpr ((((", cfg) { None => true, Some(_) => false }
  assert(r2)
  let r3 = match deserialize_session("(other-tag (foo 1))", cfg) { None => true, Some(_) => false }
  assert(r3)
  let r4 = match deserialize_session("(session (version 1) (active-bid 0))", cfg) { None => true, Some(_) => false }
  assert(r4)
}

test "session candidate paths follow XDG and HOME specification" {
  let c1 = session_candidate_paths(Some("/custom/state"), Some("/custom/home"))
  assert_eq(c1, ["/custom/state/hedit/session.hl", "/custom/home/.local/state/hedit/session.hl", "/custom/home/.hedit_session.hl"])

  let c2 = session_candidate_paths(None, Some("/custom/home"))
  assert_eq(c2, ["/custom/home/.local/state/hedit/session.hl", "/custom/home/.hedit_session.hl"])

  let c3 = session_candidate_paths(None, None)
  assert_eq(c3, [])
}

test "serialize and deserialize special characters and multiple cursors" {
  let cfg = default_config()
  let buf = TextBuffer {
    bid: 2,
    path: None,
    lines: ["\"quoted text\"", "line\\with\\backslash", "line\twith\ttab"],
    cursors: [
      Cursor { cid: 0, pos: Position { line: 0, col: 5 }, anchor: None, anchor_sticky: false },
      Cursor { cid: 1, pos: Position { line: 1, col: 4 }, anchor: Some(Position { line: 1, col: 8 }), anchor_sticky: true }
    ],
    is_dirty: true,
    scroll_line: 2
  }
  let s0 = init_editor_with_buffer(buf, cfg)
  let sexpr = serialize_session(s0)
  let res = deserialize_session(sexpr, cfg)
  let is_some = match res { Some(_) => true, None => false }
  assert(is_some)

  let s1:EditorState = match res { Some(s) => s, None => s0 }
  let b: TextBuffer = s1.buffer
  assert_eq(b.bid, 2)
  assert_eq(b.lines, ["\"quoted text\"", "line\\with\\backslash", "line\twith\ttab"])
  assert_eq(length(b.cursors), 2)
}

test "is_trivial_session detects untouched scratch buffer" {
  let cfg = default_config()
  let s_clean = init_editor(None)
  assert(is_trivial_session(s_clean))

  let s_dirty = init_editor_with_buffer(TextBuffer { ...s_clean.buffer, is_dirty: true }, cfg)
  assert(!is_trivial_session(s_dirty))

  let s_named = init_editor_with_buffer(TextBuffer { ...s_clean.buffer, path: Some("/tmp/f.txt") }, cfg)
  assert(!is_trivial_session(s_named))

  let s_multi = EditorState { ...s_clean, background_buffers: [s_clean.buffer] }
  assert(!is_trivial_session(s_multi))
}
