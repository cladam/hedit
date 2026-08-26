/// Locate & load the user's HiLisp init.hl. Resolution order): 
/// `$XDG_CONFIG_HOME/hedit/init.hl` (or `$HOME/.config/hedit/init.hl` when XDG isn't set), 
/// then `$HOME/.hedit.hl`. Neither existing is a supported silent no-op,
/// this module only decides *which* source string to feed to
/// `hilisp_host.hc::load_config`, which does the actual eval/merge.

import "model"
import "hilisp_host"

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

/// Evaluate `src` (already read from `p`) through
/// `hilisp_host::load_config` and shape the resulting status message.
// Shared by both the XDG/HOME search and `--config`'s explicit path.
fun apply_config_src(cfg0:Config, src: string, p: string) : (Config, maybe<string>) {
  let (cfg, err) = load_config(src, cfg0)
  match err {
    None      => (cfg, Some("Loaded config from " + p)),
    Some(msg) => (cfg, Some("Config error (" + p + "): " + msg))
  }
}

/// Resolve `$XDG_CONFIG_HOME`/`$HOME`, walk the candidate paths, and
/// evaluate the first one found through `hilisp_host::load_config`.
/// Returns `cfg0` unchanged with `None` status if neither candidate exists.
pub fun load_user_config(cfg0:Config) : (Config, maybe<string>) {
  let xdg    = get_env("XDG_CONFIG_HOME")
  let home   = get_env("HOME")
  let paths  = candidate_paths(xdg, home)
  let (src, path) = read_first(paths)
  match path {
    None    => (cfg0, None),
    Some(p) => apply_config_src(cfg0, src, p)
  }
}

/// `--config <path>`: load exactly that file instead of walking
/// `candidate_paths`. A missing/unreadable path surfaces as a status
/// message rather than a silent fallback.
pub fun load_config_from_path(cfg0:Config, p: string) : (Config, maybe<string>) =>
  match read_file(p) {
    Ok(content) => apply_config_src(cfg0, content, p),
    Err(msg)    => (cfg0, Some("Could not open " + p + ": " + msg))
  }

/// CLI-aware entry point used by `main.hc`: `--no-config` skips
/// loading entirely, `--config <path>` loads exactly that file, and
/// absent both, falls back to the normal XDG/HOME search.
pub fun load_user_config_opts(cfg0:Config, explicit_path: maybe<string>, skip: bool) : (Config, maybe<string>) {
  if skip { (cfg0, None) }
  else {
    match explicit_path {
      Some(p) => load_config_from_path(cfg0, p),
      None    => load_user_config(cfg0)
    }
  }
}
