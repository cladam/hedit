// model_test.hc — tests for src/model.hc's real file-loading (M6).
//
// The `path == None` fallback shape is already exercised indirectly by
// every `init_editor(None)` call across the other test files; these
// tests focus on `load_buffer`'s new file-reading behaviour: a real
// file, and a missing one.
//
// Each result is bound through an annotated `let` so `buf.lines` below
// resolves to the struct accessor, not the prelude's `hc_lines(string)`
// (the receiver type is otherwise unresolved at this call site — see
// repo memory notes on the `hc_lines` collision).

import "../src/model"

test "load_buffer reads real file content into lines" {
  let tmp_path = "/tmp/hedit_test_m6_load.txt"
  write_file(tmp_path, "hello\nworld\n")
  let result: (TextBuffer, maybe<string>) = load_buffer(0, Some(tmp_path))
  let buf = result.0
  let status = result.1
  assert(buf.lines == ["hello", "world"])
  assert(buf.path == Some(tmp_path))
  assert(status == None)
}

test "load_buffer without a trailing newline keeps the last line" {
  let tmp_path = "/tmp/hedit_test_m6_load_no_newline.txt"
  write_file(tmp_path, "hello\nworld")
  let result: (TextBuffer, maybe<string>) = load_buffer(0, Some(tmp_path))
  let buf = result.0
  assert(buf.lines == ["hello", "world"])
}

test "load_buffer falls back to an empty buffer on a missing file" {
  let path = "/tmp/hedit_test_m6_missing_does_not_exist.txt"
  let result: (TextBuffer, maybe<string>) = load_buffer(0, Some(path))
  let buf = result.0
  let status = result.1
  assert(buf.lines == [""])
  assert(buf.path == Some(path))
  let has_status = match status {
    Some(_) => true,
    None    => false
  }
  assert(has_status)
}

test "load_buffer with no path returns an empty scratch buffer" {
  let result: (TextBuffer, maybe<string>) = load_buffer(0, None)
  let buf = result.0
  let status = result.1
  assert(buf.lines == [""])
  assert(buf.path == None)
  assert(status == None)
}

// ------------------- M8: --tabsize override precedence -------------------

test "set_config_value overrides a value already present" {
  let cfg0 = default_config()
  let cfg1 = set_config_value(cfg0, "tabsize", "4")
  let cfg2 = set_config_value(cfg1, "tabsize", "2")
  assert(get_config(cfg2, "tabsize", "8") == "2")
}

test "set_config_value adds a value when none was present" {
  let cfg0 = default_config()
  let cfg1 = set_config_value(cfg0, "tabsize", "2")
  assert(get_config_int(cfg1, "tabsize", 8) == 2)
}

// ------------------- M8: +LINE:COL clamping -------------------------------

test "clamp_position keeps an in-range position unchanged" {
  let lines = ["hello", "world"]
  let pos = clamp_position(lines, Position { line: 1, col: 3 })
  assert(pos == Position { line: 1, col: 3 })
}

test "clamp_position clamps a line past EOF to the last line" {
  let lines = ["hello", "world"]
  let pos = clamp_position(lines, Position { line: 99, col: 0 })
  assert(pos == Position { line: 1, col: 0 })
}

test "clamp_position clamps a negative line to 0" {
  let lines = ["hello", "world"]
  let pos = clamp_position(lines, Position { line: -5, col: 0 })
  assert(pos == Position { line: 0, col: 0 })
}

test "clamp_position clamps a column past end-of-line to the line length" {
  let lines = ["hi", "world"]
  let pos = clamp_position(lines, Position { line: 0, col: 99 })
  assert(pos == Position { line: 0, col: 2 })
}

test "set_initial_position moves every cursor to the clamped position" {
  let tmp_path = "/tmp/hedit_test_m8_position.txt"
  write_file(tmp_path, "hello\nworld\n")
  let result: (TextBuffer, maybe<string>) = load_buffer(0, Some(tmp_path))
  let buf = set_initial_position(result.0, Some(Position { line: 1, col: 3 }))
  let cur = head_or_default(buf.cursors)
  assert(cur.pos == Position { line: 1, col: 3 })
}

test "set_initial_position clamps a position past EOF instead of crashing" {
  let tmp_path = "/tmp/hedit_test_m8_position_clamp.txt"
  write_file(tmp_path, "hello\nworld\n")
  let result: (TextBuffer, maybe<string>) = load_buffer(0, Some(tmp_path))
  let buf = set_initial_position(result.0, Some(Position { line: 99, col: 99 }))
  let cur = head_or_default(buf.cursors)
  assert(cur.pos == Position { line: 1, col: 5 })
}

test "set_initial_position with None leaves the buffer's cursors untouched" {
  let result: (TextBuffer, maybe<string>) = load_buffer(0, None)
  let buf = set_initial_position(result.0, None)
  let cur = head_or_default(buf.cursors)
  assert(cur.pos == Position { line: 0, col: 0 })
}

fun head_or_default(cursors: list<Cursor>) : Cursor =>
  match cursors {
    [x, .._] => x,
    []       => Cursor { cid: 0, pos: Position { line: 0, col: 0 } }
  }
