// config_loader_test.hc — tests for load_user_config_opts.
//
// `--no-config` and `--config <path>` are exercised here directly
// against the filesystem (real temp files) rather than mocked, mirroring
// model_test.hc's approach for load_buffer.

import "../src/model"
import "../src/keys"
import "../src/config_loader"
import "../src/hilisp_host"
import "../lib/hilisp/src/lisp"

test "load_user_config_opts with skip=true returns cfg0 unchanged and no status" {
  let cfg0 = default_config()
  let result: (Config, Env, maybe<string>) = load_user_config_opts(cfg0, None, true)
  assert(result.2 == None)
  assert(result.0.values == [])
}

test "load_user_config_opts with an explicit path loads that file" {
  let tmp_path = "/tmp/hedit_test_m8_config.hl"
  write_file(tmp_path, "(set \"tabsize\" \"2\")")
  let cfg0 = default_config()
  let result: (Config, Env, maybe<string>) = load_user_config_opts(cfg0, Some(tmp_path), false)
  assert(get_config(result.0, "tabsize", "4") == "2")
  // A clean load is silent (M13.2) — no "Loaded config from …" noise.
  assert(result.2 == None)
}

test "load_user_config_opts with a missing explicit path surfaces an error status" {
  let path = "/tmp/hedit_test_m8_missing_config_does_not_exist.hl"
  let cfg0 = default_config()
  let result: (Config, Env, maybe<string>) = load_user_config_opts(cfg0, Some(path), false)
  assert(result.0.values == [])
  let has_status = match result.2 {
    Some(_) => true,
    None    => false
  }
  assert(has_status)
}

test "skip=true wins even when an explicit path is also given" {
  let tmp_path = "/tmp/hedit_test_m8_config_skip.hl"
  write_file(tmp_path, "(set \"tabsize\" \"2\")")
  let cfg0 = default_config()
  let result: (Config, Env, maybe<string>) = load_user_config_opts(cfg0, Some(tmp_path), true)
  assert(result.2 == None)
  assert(result.0.values == [])
}

// ------------------- plugin resolution & loading (M11) -----------------

test "load_user_config_opts: a (plugin ...) opt-in loads plugins/<name>/plugin.hl into the same env" {
  let init_path = "/tmp/hedit_test_m11_plugins_ok/init.hl"
  write_file(init_path, "(plugin \"greeter\")")
  write_file("/tmp/hedit_test_m11_plugins_ok/plugins/greeter/plugin.hl",
             "(on 'buffer-open (fn (path) \"Welcome to hedit!\"))")
  let cfg0 = default_config()
  let (_, env, status) = load_user_config_opts(cfg0, Some(init_path), false)
  // A clean config + a clean plugin load is silent (M13.2).
  assert(status == None)
  let (results, _) = fire_hook(env, "buffer-open", [LStr("foo.txt")])
  match results {
    [LStr(s)] => assert_eq(s, "Welcome to hedit!"),
    _         => assert(false)
  }
}

test "load_user_config_opts: a missing plugin name surfaces a status message, not a crash" {
  let init_path = "/tmp/hedit_test_m11_plugins_missing/init.hl"
  write_file(init_path, "(plugin \"does-not-exist\")")
  let cfg0 = default_config()
  let (_, _, status) = load_user_config_opts(cfg0, Some(init_path), false)
  let mentions_plugin = match status {
    Some(msg) => index_of(msg, "plugin does-not-exist") != None,
    None      => false
  }
  assert(mentions_plugin)
}

test "load_user_config_opts: a broken plugin doesn't block a good one loaded after it" {
  let init_path = "/tmp/hedit_test_m11_plugins_mixed/init.hl"
  write_file(init_path, "(plugin \"broken\") (plugin \"greeter\")")
  write_file("/tmp/hedit_test_m11_plugins_mixed/plugins/broken/plugin.hl", "(this-is-not-defined)")
  write_file("/tmp/hedit_test_m11_plugins_mixed/plugins/greeter/plugin.hl",
             "(on 'buffer-open (fn (path) \"Welcome to hedit!\"))")
  let cfg0 = default_config()
  let (_, env, status) = load_user_config_opts(cfg0, Some(init_path), false)
  let mentions_broken = match status {
    Some(msg) => index_of(msg, "plugin broken") != None,
    None      => false
  }
  assert(mentions_broken)
  let (results, _) = fire_hook(env, "buffer-open", [LStr("foo.txt")])
  match results {
    [LStr(s)] => assert_eq(s, "Welcome to hedit!"),
    _         => assert(false)
  }
}

// ------------------- live config reload (M19) --------------------------

test "reload_config: valid change updates config and sets status message" {
  let init_path = "/tmp/hedit_test_m19_reload/init.hl"
  write_file(init_path, "(bind \"Ctrl-x\" 'quit)")
  let cfg0 = Config { ...default_config(), custom_config_path: Some(init_path) }
  let s0 = init_editor_with_config(None, cfg0)
  let s1 = reload_config(s0)
  assert(lookup_binding(s1.config.bindings, KeyChord { m: Ctrl, c: 'x' }) == Quit)
  assert(s1.status_message == Some("Config reloaded"))

  // Now update the file with a different binding and reload again
  write_file(init_path, "(bind \"Ctrl-x\" 'save)")
  let s2 = reload_config(s1)
  assert(lookup_binding(s2.config.bindings, KeyChord { m: Ctrl, c: 'x' }) == Save)
  assert(s2.status_message == Some("Config reloaded"))
}

test "reload_config: syntax error preserves existing config and surfaces error status" {
  let init_path = "/tmp/hedit_test_m19_err/init.hl"
  write_file(init_path, "(bind \"Ctrl-x\" 'quit)")
  let cfg0 = Config { ...default_config(), custom_config_path: Some(init_path) }
  let s0 = init_editor_with_config(None, cfg0)
  let s1 = reload_config(s0)
  assert(lookup_binding(s1.config.bindings, KeyChord { m: Ctrl, c: 'x' }) == Quit)

  // Now update the file with a syntax error
  write_file(init_path, "(this is an unclosed (expression")
  let s2 = reload_config(s1)
  // Old binding is preserved (never apply a partially-parsed config)
  assert(lookup_binding(s2.config.bindings, KeyChord { m: Ctrl, c: 'x' }) == Quit)
  let mentions_error = match s2.status_message {
    Some(msg) => index_of(msg, "Config error") != None,
    None      => false
  }
  assert(mentions_error)
}

test "reload_config_with_env: updates env hooks on reload" {
  let init_path = "/tmp/hedit_test_m19_hooks/init.hl"
  write_file(init_path, "(on 'buffer-open (fn (path) \"v1\"))")
  let cfg0 = Config { ...default_config(), custom_config_path: Some(init_path) }
  let s0 = init_editor_with_config(None, cfg0)
  let (s1, env1) = reload_config_with_env(s0, make_hedit_env(s0.config))
  let (res1, _) = fire_hook(env1, "buffer-open", [LStr("test.txt")])
  assert(res1 == [LStr("v1")])

  // Update hook definition and reload
  write_file(init_path, "(on 'buffer-open (fn (path) \"v2\"))")
  let (s2, env2) = reload_config_with_env(s1, env1)
  let (res2, _) = fire_hook(env2, "buffer-open", [LStr("test.txt")])
  assert(res2 == [LStr("v2")])
  assert(s2.status_message == Some("Config reloaded"))
}
