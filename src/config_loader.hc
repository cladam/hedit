// config_loader.hc — locate & load the user's HiLisp init.hl.
//
// Resolution order (docs/hedit-design.md §7.4, first hit wins):
//
//   1. $XDG_CONFIG_HOME/hedit/init.hl
//      (defaults to $HOME/.config/hedit/init.hl when XDG isn't set)
//   2. $HOME/.hedit.hl
//
// If neither file exists we hand back `default_config()` unchanged and
// a status of `None` — running with no init.hl is a supported, silent
// mode of operation.
//
// This module is deliberately thin. All the interesting work
// (mutating a hedit-side `Config` from user-supplied HiLisp) lives in
// `src/hilisp_host.hc::load_config`. This file just decides *which*
// source string to feed it.

import "model"
import "hilisp_host"

// Prepend `dir + "/hedit/init.hl"` (or the plain `.hedit.hl` variant)
// to a list. Kept as tiny helpers so the outer builder is a single
// pipeline with no nested `match` on maybe (which `hica analyse`
// treats as HIGH severity).
fun opt_path(dir: maybe<string>, suffix: string) : list<string> =>
  unwrap_maybe_or(map_maybe(dir, (d) => [d + suffix]), [])

// Compose the XDG candidate: `$XDG_CONFIG_HOME/hedit/init.hl` if the
// env var is set, otherwise `$HOME/.config/hedit/init.hl` when `$HOME`
// is set, or empty list on total miss.
fun xdg_candidate(xdg: maybe<string>, home: maybe<string>) : list<string> =>
  match xdg {
    Some(_) => opt_path(xdg, "/hedit/init.hl"),
    None    => opt_path(home, "/.config/hedit/init.hl")
  }

// `$HOME/.hedit.hl` if `$HOME` is set, empty otherwise.
fun home_candidate(home: maybe<string>) : list<string> =>
  opt_path(home, "/.hedit.hl")

// Compose the two candidate paths in priority order.
//
// Kept as a small pure helper so it can be unit-tested independently
// of the filesystem — the caller supplies whatever `$XDG_CONFIG_HOME`
// and `$HOME` resolve to at runtime, which keeps this function total
// and lets tests fabricate paths without exporting env vars.
pub fun candidate_paths(xdg: maybe<string>, home: maybe<string>) : list<string> =>
  xdg_candidate(xdg, home) + home_candidate(home)

// Try each candidate path in order; the first `Ok(_)` wins. On success
// we return `(source, Some(path_that_matched))`; on total miss we
// return `("", None)` so callers can distinguish "no config" from
// "config was empty".
pub fun read_first(paths: list<string>) : (string, maybe<string>) =>
  match paths {
    [] => ("", None),
    [p, ..rest] => match read_file(p) {
      Ok(content) => (content, Some(p)),
      Err(_)      => read_first(rest)
    }
  }

// Public entry point. Resolves $XDG_CONFIG_HOME / $HOME, walks the
// candidate paths, and — if a config is found — evaluates it through
// `hilisp_host::load_config` starting from `cfg0`.
//
// Returns:
//   * the final `Config` (merged when a file was loaded, or `cfg0`
//     unchanged when neither candidate existed),
//   * an optional status message: `Some("Loaded config from …")` on
//     success, `Some("<error>")` on eval failure, `None` when no
//     config file was present.
//
// The status message is designed to drop straight onto
// `EditorState.status_message` so the first render tick surfaces
// exactly one line of feedback about the config load — mirroring how
// vim/emacs behave on `.vimrc` / `init.el` errors.
pub fun load_user_config(cfg0:Config) : (Config, maybe<string>) {
  let xdg    = get_env("XDG_CONFIG_HOME")
  let home   = get_env("HOME")
  let paths  = candidate_paths(xdg, home)
  let (src, path) = read_first(paths)
  match path {
    None => (cfg0, None),
    Some(p) => {
      let (cfg, err) = load_config(src, cfg0)
      match err {
        None      => (cfg, Some("Loaded config from " + p)),
        Some(msg) => (cfg, Some("Config error (" + p + "): " + msg))
      }
    }
  }
}
