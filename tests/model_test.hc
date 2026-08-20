// model_test.hc — tests for src/model.hc's real file-loading (M6).
//
// The `path == None` fallback shape is already exercised indirectly by
// every `init_editor(None)` call across the other test files; these
// tests focus on `load_buffer`'s new file-reading behaviour: a real
// file, and a missing one.

import "../src/model"

test "load_buffer reads real file content into lines" {
  let tmp_path = "/tmp/hedit_test_m6_load.txt"
  write_file(tmp_path, "hello\nworld\n")
  let (buf, status) = load_buffer(0, Some(tmp_path))
  assert(buf.lines == ["hello", "world"])
  assert(buf.path == Some(tmp_path))
  assert(status == None)
}

test "load_buffer without a trailing newline keeps the last line" {
  let tmp_path = "/tmp/hedit_test_m6_load_no_newline.txt"
  write_file(tmp_path, "hello\nworld")
  let (buf, _status) = load_buffer(0, Some(tmp_path))
  assert(buf.lines == ["hello", "world"])
}

test "load_buffer falls back to an empty buffer on a missing file" {
  let path = "/tmp/hedit_test_m6_missing_does_not_exist.txt"
  let (buf, status) = load_buffer(0, Some(path))
  assert(buf.lines == [""])
  assert(buf.path == Some(path))
  let has_status = match status {
    Some(_) => true,
    None    => false
  }
  assert(has_status)
}

test "load_buffer with no path returns an empty scratch buffer" {
  let (buf, status) = load_buffer(0, None)
  assert(buf.lines == [""])
  assert(buf.path == None)
  assert(status == None)
}
