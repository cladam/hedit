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
