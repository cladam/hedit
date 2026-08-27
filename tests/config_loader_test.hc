// config_loader_test.hc — tests for load_user_config_opts.
//
// `--no-config` and `--config <path>` are exercised here directly
// against the filesystem (real temp files) rather than mocked, mirroring
// model_test.hc's approach for load_buffer.

import "../src/model"
import "../src/config_loader"

test "load_user_config_opts with skip=true returns cfg0 unchanged and no status" {
  let cfg0 = default_config()
  let result: (Config, maybe<string>) = load_user_config_opts(cfg0, None, true)
  assert(result.1 == None)
  assert(result.0.values == [])
}

test "load_user_config_opts with an explicit path loads that file" {
  let tmp_path = "/tmp/hedit_test_m8_config.hl"
  write_file(tmp_path, "(set \"tabsize\" \"2\")")
  let cfg0 = default_config()
  let result: (Config, maybe<string>) = load_user_config_opts(cfg0, Some(tmp_path), false)
  assert(get_config(result.0, "tabsize", "4") == "2")
  let has_status = match result.1 {
    Some(_) => true,
    None    => false
  }
  assert(has_status)
}

test "load_user_config_opts with a missing explicit path surfaces an error status" {
  let path = "/tmp/hedit_test_m8_missing_config_does_not_exist.hl"
  let cfg0 = default_config()
  let result: (Config, maybe<string>) = load_user_config_opts(cfg0, Some(path), false)
  assert(result.0.values == [])
  let has_status = match result.1 {
    Some(_) => true,
    None    => false
  }
  assert(has_status)
}

test "skip=true wins even when an explicit path is also given" {
  let tmp_path = "/tmp/hedit_test_m8_config_skip.hl"
  write_file(tmp_path, "(set \"tabsize\" \"2\")")
  let cfg0 = default_config()
  let result: (Config, maybe<string>) = load_user_config_opts(cfg0, Some(tmp_path), true)
  assert(result.1 == None)
  assert(result.0.values == [])
}
