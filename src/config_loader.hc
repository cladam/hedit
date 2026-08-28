/// Locate & load the user's HiLisp init.hl. Resolution order):
/// `$XDG_CONFIG_HOME/hedit/init.hl` (or `$HOME/.config/hedit/init.hl` when XDG isn't set),
/// then `$HOME/.hedit.hl`. Neither existing is a supported silent no-op,
/// this module only decides *which* source string to feed to
/// `hilisp_host.hc::load_config_with_env`, which does the actual eval/merge.
//
// Also resolves & loads `(plugin "name")` opt-ins recorded by `init.hl`:
// each name maps to `<config-root>/plug/<name>/plugin.hl`, evaluated into
// the *same* `Env` init.hl populated (so plugins see prior `(set ...)`/
// `(bind ...)` calls, and later plugins see earlier ones). A broken or
// missing plugin file surfaces as a status message, not a crash, and
// never blocks the rest of the plugin list (M11 error isolation).

import "model"
import "hilisp_host"
import "../lib/hilisp/src/lisp"

/// Wrap `dir + suffix` in a singleton list, or `[]` if `dir` is `None`.
fun opt_path(dir: maybe<string>, suffix: string) : list<string> =>
  unwrap_maybe_or(map_maybe(dir, (d) => [d + suffix]), [])

/// The XDG candidate path: `$XDG_CONFIG_HOME/hedit/init.hl` if set,
/// else `$HOME/.config/hedit/init.hl`, else `[]`.
fun xdg_candidate(xdg: maybe<string>, home: maybe<string>) : list<string> =>
  match xdg {
    Some(_) => opt_path(xdg, "/hedit/init.hl"),
    None    => opt_path(home, "/.config/hedit/init.hl")
  }

/// The `$HOME/.hedit.hl` candidate path, or `[]` if `$HOME` is unset.
fun home_candidate(home: maybe<string>) : list<string> =>
  opt_path(home, "/.hedit.hl")

/// Compose the two candidate config paths in priority order.
// Kept pure so it's unit-testable independently of the filesystem —
// callers supply whatever `$XDG_CONFIG_HOME`/`$HOME` resolve to.
pub fun candidate_paths(xdg: maybe<string>, home: maybe<string>) : list<string> =>
  xdg_candidate(xdg, home) + home_candidate(home)

/// Try each candidate path in order; the first readable file wins,
/// returned as `(content, Some(path))`. `("", None)` on total miss.
pub fun read_first(paths: list<string>) : (string, maybe<string>) =>
  match paths {
    [] => ("", None),
    [p, ..rest] => match read_file(p) {
      Ok(content) => (content, Some(p)),
      Err(_)      => read_first(rest)
    }
  }

// ------------------- plugin resolution & loading (M11) -------------------

/// The directory a config path lives in (everything before the last
/// `/`), or `""` if `path` has no `/` at all.
fun config_dir_of(path: string) : string {
  let parts = split(path, "/")
  match reverse(parts) {
    []          => "",
    [_, ..rest] => join(reverse(rest), "/")
  }
}

/// `<base_dir>/plug/<name>/plugin.hl` — the fixed layout every
/// `(plugin "name")` opt-in resolves to.
fun plugin_path(base_dir: string, name: string) : string =>
  base_dir + "/plug/" + name + "/plugin.hl"

/// Evaluate one already-read plugin source into `env0`, prefixing any
/// `LError` status with the plugin's name.
fun plugin_loaded(cfg0:Config, env0:Env, name: string, src: string) : (Config, Env, maybe<string>) {
  let (cfg1, env1, status) = load_config_env(src, cfg0, env0)
  match status {
    None      => (cfg1, env1, None),
    Some(msg) => (cfg1, env1, Some("plugin " + name + ": " + msg))
  }
}

/// Resolve + read one plugin's `plugin.hl`; a missing/unreadable file
/// surfaces the same "plugin <name>: <error>" status shape as a broken
/// one, rather than crashing.
fun load_one_plugin(cfg0:Config, env0:Env, base_dir: string, name: string) : (Config, Env, maybe<string>) =>
  match read_file(plugin_path(base_dir, name)) {
    Err(msg) => (cfg0, env0, Some("plugin " + name + ": " + msg)),
    Ok(src)  => plugin_loaded(cfg0, env0, name, src)
  }

/// Fold `load_one_plugin` over every opt-in name, threading `Config`/
/// `Env` and accumulating one status message per failure — a single
/// broken plugin never stops the rest of the list from loading.
fun load_plugins_go(cfg0:Config, env0:Env, base_dir: string, names: list<string>, acc: list<string>) : (Config, Env, list<string>) =>
  match names {
    [] => (cfg0, env0, acc),
    [name, ..rest] => {
      let (cfg1, env1, status) = load_one_plugin(cfg0, env0, base_dir, name)
      let acc2 = match status {
        None      => acc,
        Some(msg) => acc + [msg]
      }
      load_plugins_go(cfg1, env1, base_dir, rest, acc2)
    }
  }

/// Load every `(plugin "name")` opt-in recorded on `env0` from
/// `<base_dir>/plug/<name>/plugin.hl`, in declaration order.
pub fun load_plugins(cfg0:Config, env0:Env, base_dir: string, names: list<string>) : (Config, Env, list<string>) =>
  load_plugins_go(cfg0, env0, base_dir, names, [])

/// Append `extra` plugin-error messages onto an existing status,
/// joined with " | " (matching `main.hc::combine_status`'s style).
fun join_status(base: maybe<string>, extra: list<string>) : maybe<string> =>
  match extra {
    [] => base,
    _  => {
      let joined = join(extra, " | ")
      match base {
        None      => Some(joined),
        Some(msg) => Some(msg + " | " + joined)
      }
    }
  }

/// Evaluate `src` (already read from `p`) through
/// `hilisp_host::load_config_with_env`, then resolve & load any
/// `(plugin ...)` opt-ins it recorded, from `p`'s own directory.
// Shared by both the XDG/HOME search and `--config`'s explicit path.
fun apply_config_src(cfg0:Config, src: string, p: string) : (Config, Env, maybe<string>) {
  let (cfg1, env1, err) = load_config_with_env(src, cfg0)
  let status1 = match err {
    None      => Some("Loaded config from " + p),
    Some(msg) => Some("Config error (" + p + "): " + msg)
  }
  let (cfg2, env2, plugin_errs) = load_plugins(cfg1, env1, config_dir_of(p), plugin_names_from_env(env1))
  (cfg2, env2, join_status(status1, plugin_errs))
}

/// Resolve `$XDG_CONFIG_HOME`/`$HOME`, walk the candidate paths, and
/// evaluate the first one found through `hilisp_host::load_config_with_env`.
/// Returns `cfg0` unchanged (with a fresh, plugin-free `Env`) and `None`
/// status if neither candidate exists.
pub fun load_user_config(cfg0:Config) : (Config, Env, maybe<string>) {
  let xdg    = get_env("XDG_CONFIG_HOME")
  let home   = get_env("HOME")
  let paths  = candidate_paths(xdg, home)
  let (src, path) = read_first(paths)
  match path {
    None    => (cfg0, make_hedit_env(cfg0), None),
    Some(p) => apply_config_src(cfg0, src, p)
  }
}

/// `--config <path>`: load exactly that file instead of walking
/// `candidate_paths`. A missing/unreadable path surfaces as a status
/// message rather than a silent fallback.
pub fun load_config_from_path(cfg0:Config, p: string) : (Config, Env, maybe<string>) =>
  match read_file(p) {
    Ok(content) => apply_config_src(cfg0, content, p),
    Err(msg)    => (cfg0, make_hedit_env(cfg0), Some("Could not open " + p + ": " + msg))
  }

/// CLI-aware entry point used by `main.hc`: `--no-config` skips
/// loading entirely, `--config <path>` loads exactly that file, and
/// absent both, falls back to the normal XDG/HOME search. The returned
/// `Env` is what `main.hc` stashes on `EditorState.hilisp_env` for
/// `runtime.hc::fire_hook`.
pub fun load_user_config_opts(cfg0:Config, explicit_path: maybe<string>, skip: bool) : (Config, Env, maybe<string>) {
  if skip { (cfg0, make_hedit_env(cfg0), None) }
  else {
    match explicit_path {
      Some(p) => load_config_from_path(cfg0, p),
      None    => load_user_config(cfg0)
    }
  }
}
