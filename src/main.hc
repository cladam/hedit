/// hedit's entry point: parses argv, loads config + the target file,
/// resolves the theme, installs the native Terminal/Clipboard handlers
/// (raw-mode key reads via `term_ffi`, ANSI rendering via `std/term`),
/// and hands off to `runtime.hc::event_loop`.

import "keys"
import "model"
import "runtime"
import "hilisp_host"
import "config_loader"
import "cli_spec"
import "std/cli"
import "std/term"
import "../lib/hilisp/src/lisp"

extern import "term_ffi"

/// Combine a status message `x` (config/file load result) with an
/// optional second one `b` (e.g. the theme resolver's warning).
fun combine_with(x: string, b: maybe<string>) : maybe<string> =>
  match b {
    None => Some(x),
    Some(y) => {
      let combined = x + " | " + y
      Some(combined)
    }
  }

/// Combine two optional status messages (either, both, or neither may
/// be present) into the single message primed onto
/// `EditorState.status_message` for the first render tick.
fun combine_status(a: maybe<string>, b: maybe<string>) : maybe<string> =>
  match a {
    None => b,
    Some(x) => combine_with(x, b)
  }

/// Put the terminal into raw mode via `stty` (through hica's built-in
/// `exec`) rather than a hand-written termios FFI.
// `stty sane` on the way out covers the normal-quit path; a
// crash/SIGINT leaving the shell in raw mode is a known, documented
// limitation (see M7 exit criteria / manual QA list).
fun enable_raw_mode() {
  let _ = exec("stty raw -echo icrnl 2>/dev/null")
}

/// Restore normal terminal mode (`stty sane`).
fun disable_raw_mode() {
  let _ = exec("stty sane 2>/dev/null")
}

// -------------------------- Theming ----------------------------------------
//
// `Theme` (model.hc) holds true-color (r, g, b) triples; these helpers turn
// one into raw ANSI SGR codes wrapping a single already-width-fitted row.
// Applied here (not in render.hc) so `render.hc`'s ScreenBuffer stays plain
// text — the existing render tests assert on exact row content, and the
// real terminal is the only place that needs to see escape sequences.

/// The ANSI SGR foreground true-color code for `c`.
fun rgb_fg_code(c: (int, int, int)) : string =>
  "38;2;" + show(c.0) + ";" + show(c.1) + ";" + show(c.2)

/// The ANSI SGR background true-color code for `c`.
fun rgb_bg_code(c: (int, int, int)) : string =>
  "48;2;" + show(c.0) + ";" + show(c.1) + ";" + show(c.2)

/// Wrap `s` in an ANSI SGR foreground+background pair, reset afterward.
fun wrap_fg_bg(fg: (int, int, int), bg: (int, int, int), s: string) : string =>
  term_esc() + "[" + rgb_fg_code(fg) + ";" + rgb_bg_code(bg) + "m" + s + term_esc() + "[0m"

/// Wrap `s` in an ANSI SGR background-only code, reset afterward.
fun wrap_bg(bg: (int, int, int), s: string) : string =>
  term_esc() + "[" + rgb_bg_code(bg) + "m" + s + term_esc() + "[0m"

/// Colorize a rendered tabline row: the active tab (leading "[name]"
/// segment) gets `active_tab_fg`/`active_tab_bg`, the rest of the row
/// gets the plain `tabline_fg`/`tabline_bg` pair.
fun colorize_tabline_row(theme: Theme, row: string) : string =>
  match index_of(row, "]") {
    Some(i) => {
      let active_part = row[0:i + 1]
      let rest_part   = row[i + 1:]
      wrap_fg_bg(theme.active_tab_fg, theme.active_tab_bg, active_part) +
        wrap_fg_bg(theme.tabline_fg, theme.tabline_bg, rest_part)
    },
    None => wrap_fg_bg(theme.tabline_fg, theme.tabline_bg, row)
  }

/// Colorize a rendered status-line row.
fun colorize_status_row(theme: Theme, row: string) : string =>
  wrap_fg_bg(theme.status_fg, theme.status_bg, row)

/// Colorize a rendered content row that the cursor currently sits on.
fun colorize_cursor_row(theme: Theme, row: string) : string =>
  wrap_bg(theme.cursor_line_bg, row)

// ------------------- Search-match highlighting -----------------------
// A row with an active search match gets its match span(s) painted with
// `theme.search_match_bg` instead of the tabline/status/cursor-line
// treatment above — simpler and safer than nesting a second background
// inside an already-wrapped row (no shared SGR reset to reason about),
// at the cost of the cursor-line tint not showing through on a row that
// also has a match.

/// `(start, end)` column spans (0-indexed, `end` exclusive) for `row`
/// (1-indexed) out of every `ScreenBuffer.highlights` triple.
fun spans_for_row(highlights: list<(int, int, int)>, row: int) : list<(int, int)> =>
  match highlights {
    [] => [],
    [(r, s, e), ..rest] =>
      if r == row { [(s, e)] + spans_for_row(rest, row) } else { spans_for_row(rest, row) }
  }

/// Wrap every `(start, end)` span in `row` with `bg`, leaving the text
/// between/around spans untouched — spans must be in increasing,
/// non-overlapping order (guaranteed by `render.hc::matches_to_highlights`,
/// document order).
fun highlight_row_go(row: string, spans: list<(int, int)>, pos: int, bg: (int, int, int)) : string =>
  match spans {
    [] => row[pos: ],
    [(s, e), ..rest] => {
      let cs = max(s, pos)
      let ce = min(e, length(row))
      if cs >= ce { highlight_row_go(row, rest, pos, bg) }
      else { row[pos: cs] + wrap_bg(bg, row[cs: ce]) + highlight_row_go(row, rest, ce, bg) }
    }
  }

/// Style the tabline (first row), status line (last row), a row with an
/// active search match (match spans only), or the row the cursor
/// currently sits on (everything else, plain).
// `cursor_row` is 1-indexed and already clamped to the visible viewport
// by render.hc.
fun style_frame_lines(theme: Theme, lines: list<string>, cursor_row: int, highlights: list<(int, int, int)>) : list<string> {
  let total = length(lines)
  style_frame_lines_go(theme, lines, 0, total, cursor_row, highlights)
}

/// Recursive worker for `style_frame_lines`, tracking the current row index.
fun style_frame_lines_go(theme: Theme, lines: list<string>, idx: int, total: int, cursor_row: int, highlights: list<(int, int, int)>) : list<string> =>
  match lines {
    [] => [],
    [x, ..rest] => {
      let row_spans = spans_for_row(highlights, idx + 1)
      let styled = match row_spans {
        [] =>
          if idx == 0 { colorize_tabline_row(theme, x) }
          else if idx == total - 1 { colorize_status_row(theme, x) }
          else if idx + 1 == cursor_row { colorize_cursor_row(theme, x) }
          else { x },
        _ => highlight_row_go(x, row_spans, 0, theme.search_match_bg)
      }
      [styled] + style_frame_lines_go(theme, rest, idx + 1, total, cursor_row, highlights)
    }
  }

/// Full-redraw a `ScreenBuffer` to the real terminal via ANSI escapes,
/// including moving the terminal's real cursor to `buf.cursor_row`/`buf.cursor_col`.
// Deliberately does NOT clear the whole screen (`ESC[2J`) before
// redrawing — that blanks the terminal for a frame before the new
// content lands, which reads as flicker on every keystroke. Overwriting
// in place from the home position is flicker-free, but every row must
// clear its own leftover tail (`ESC[K`): scrolling changes which buffer
// line lands on a given screen row, and a shorter new line only
// overwrites part of what a longer previous line left there — without
// the per-line erase the untouched trailing characters from the old
// frame stay on screen, reading as scrambled/overlapping text.
// Raw mode (`stty raw`) disables output post-processing, so a bare
// "\n" doesn't return the cursor to column 0 — join with "\r\n"
// instead of relying on `println`, or every line staircases rightward.
fun render_native(theme: Theme, buf: ScreenBuffer) {
  let styled     = style_frame_lines(theme, buf.lines, buf.cursor_row, buf.highlights)
  let cleared    = map(styled, (l) => l + term_esc() + "[K")
  let cursor_esc = term_esc() + "[" + show(buf.cursor_row) + ";" + show(buf.cursor_col) + "H"
  let frame = term_esc() + "[H" + join(cleared, "\r\n") + term_esc() + "[J" + cursor_esc
  print(frame)
  flush_stdout()
}

/// `--tabsize <n>`: applied to Config.values after init.hl has
/// loaded, so it always wins over a config-file setting.
fun apply_tabsize_override(cfg: Config, tabsize: maybe<string>) : Config =>
  match tabsize {
    None    => cfg,
    Some(v) => set_config_value(cfg, "tabsize", v)
  }

/// `--readonly`: can only turn the flag on (there's no
/// "un-readonly" CLI flag — omit it and the default `false` stands).
fun apply_readonly_override(cfg: Config, ro: bool) : Config =>
  if ro { Config { ...cfg, readonly: true } } else { cfg }

/// Build the initial `EditorState` from parsed CLI args (config, theme,
/// target file, `+LINE:COL` start position), then install the native
/// Terminal/Clipboard handlers and run `event_loop`.
fun run_editor(r: CliResult, pos_arg: maybe<string>) {
  let cfg0             = default_config()
  let (cfg1, hl_env, cfg_status) = load_user_config_opts(cfg0, get_opt(r, "config"), has_flag(r, "no-config"))
  let cfg2             = apply_tabsize_override(cfg1, get_opt(r, "tabsize"))
  let cfg              = apply_readonly_override(cfg2, has_flag(r, "readonly"))
  let (theme, theme_status) = resolve_theme_with_status(cfg)
  let (loaded_buf0, load_status) = load_buffer(0, get_positional(r, 0))
  let start_pos        = match pos_arg {
    None    => None,
    Some(a) => parse_position_arg(a)
  }
  let loaded_buf = set_initial_position(loaded_buf0, start_pos)
  let buf_path = match loaded_buf.path { Some(p) => p, None => "" }
  let (hook_results, hl_env2) = fire_hook(env_with_buffer_stats(hl_env, loaded_buf), "buffer-open", [LStr(buf_path)])
  let s0 = init_editor_with_buffer(loaded_buf, cfg)
  let all_status = combine_status(combine_status(combine_status(cfg_status, load_status), theme_status), hook_status(hook_results))
  let s1 = match all_status {
    None      => s0,
    Some(msg) => set_status_message(s0, msg)
  }
  enable_raw_mode()
  let final = handle Clipboard {
    get_selection()   => clip,
    set_selection(t)  => clip = t
  } with var clip = "" in {
    handle Terminal {
      poll_event()         => decode_key(read_key()),
      render_frame(buf)    => render_native(theme, buf),
      get_dimensions()     => (term_cols(), term_rows()),
      set_cursor_style(_s) => ()
    } in {
      event_loop_with_env(s1, hl_env2)
    }
  }
  disable_raw_mode()
}

/// hedit's entry point: parse argv, then dispatch to `--help`/`--version`
/// or `run_editor`.
fun main() {
  let spec = make_spec()
  let (pos_arg, args) = extract_position_arg(get_args())
  match cli_parse_args(spec, args) {
    Help          => println(cli_help(spec)),
    Version       => println(cli_version_str(spec)),
    CliError(msg) => eprintln("error: {msg}"),
    Parsed(r)     => run_editor(r, pos_arg)
  }
}
