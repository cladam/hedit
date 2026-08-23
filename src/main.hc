// main.hc — hedit entry point.
//
// M1: native stub Terminal handler + event_loop.
// M2: render_frame arm now flushes the ScreenBuffer lines to stdout
//     (simple line-by-line dump — full ANSI diffing lands in a later pass).
//     event_loop gains <fsys> from handle_action's Ctrl-s save path.
// M3: adds an in-memory Clipboard handler stacked outside the Terminal
//     handler. Ctrl-c / Ctrl-v round-trip through a `with var clip = ""`
//     slot; a native pbcopy/wl-copy/xclip handler can replace this arm
//     without touching event_loop or the M4 HiLisp bridge.
// M4b: calls `load_user_config(default_config())` before installing
//      handlers. If a user's `init.hl` sits under $XDG_CONFIG_HOME or
//      $HOME its (set …) / (bind …) forms feed into the initial
//      `EditorState.config`. Any status message from the loader
//      (successful path, or an error string) is primed onto
//      `EditorState.status_message` so the first render tick surfaces
//      the load result — mirroring vim/emacs on .vimrc/init.el.
//      Unblocked by the hica `hica build` include-path fix (see
//      docs/hica-issues.md Issue #7) + HiLisp v0.9.1 with the
//      apply-carve-out shipped upstream.
// M6: argv now goes through `std/cli` (spec in `src/cli_spec.hc`).
//     `--help`/`--version` print and exit before any editor state is
//     built. The optional `[FILE]` positional is loaded for real via
//     `load_buffer` (model.hc) instead of the old path-only stub.
// M7: the stub Terminal handler is replaced with a real one backed by
//     `term_ffi` (raw-mode key reads + terminal size, C FFI — see
//     src/term_ffi.kk) and `std/term` (ANSI escape helpers). Raw mode
//     itself is toggled via `stty` through hica's built-in `exec`
//     (no termios FFI needed) — the same approach hica-ecosystem's
//     `programs/myeon` reference program uses for the same problem.
// M8: CLI polish — `--config`/`--no-config` (config_loader.hc's
//     load_user_config_opts), `--tabsize` (a post-load Config.values
//     override, CLI wins over init.hl), `--readonly` (gates Save in
//     runtime.hc), and `+LINE:COL` (a hand-parsed positional, stripped
//     out of argv before `cli_parse_args` ever sees it — `std/cli` has
//     no concept of a `+`-prefixed arg).
// M10: theming. `resolve_theme_with_status` (model.hc) turns `Config.values`
//     into a concrete `Theme` once at startup (a session never changes it
//     live — HiLisp only runs once, before the event loop starts), which
//     `render_native` then applies as true-color ANSI codes to the
//     tabline/status/cursor-line rows of every rendered frame.

import "keys"
import "model"
import "runtime"
import "hilisp_host"
import "config_loader"
import "cli_spec"
import "std/cli"
import "std/term"

extern import "term_ffi"

// Combine the config-load and file-load status messages (either, both,
// or neither may be present) into the single message that gets primed
// onto `EditorState.status_message` for the first render tick.
fun combine_with(x: string, b: maybe<string>) : maybe<string> =>
  match b {
    None => Some(x),
    Some(y) => {
      let combined = x + " | " + y
      Some(combined)
    }
  }

fun combine_status(a: maybe<string>, b: maybe<string>) : maybe<string> =>
  match a {
    None => b,
    Some(x) => combine_with(x, b)
  }

// Raw mode via `stty` (through hica's built-in `exec`) rather than a
// hand-written termios FFI — `stty sane` on the way out covers the
// normal-quit path; a crash/SIGINT leaving the shell in raw mode is a
// known, documented limitation (see M7 exit criteria / manual QA list).
fun enable_raw_mode() {
  let _ = exec("stty raw -echo icrnl 2>/dev/null")
}

fun disable_raw_mode() {
  let _ = exec("stty sane 2>/dev/null")
}

// ------------------- Theming (M10) ----------------------------------------
//
// `Theme` (model.hc) holds true-color (r, g, b) triples; these helpers turn
// one into raw ANSI SGR codes wrapping a single already-width-fitted row.
// Applied here (not in render.hc) so `render.hc`'s ScreenBuffer stays plain
// text — the existing render tests assert on exact row content, and the
// real terminal is the only place that needs to see escape sequences.
fun rgb_fg_code(c: (int, int, int)) : string =>
  "38;2;" + show(c.0) + ";" + show(c.1) + ";" + show(c.2)

fun rgb_bg_code(c: (int, int, int)) : string =>
  "48;2;" + show(c.0) + ";" + show(c.1) + ";" + show(c.2)

fun wrap_fg_bg(fg: (int, int, int), bg: (int, int, int), s: string) : string =>
  term_esc() + "[" + rgb_fg_code(fg) + ";" + rgb_bg_code(bg) + "m" + s + term_esc() + "[0m"

fun wrap_bg(bg: (int, int, int), s: string) : string =>
  term_esc() + "[" + rgb_bg_code(bg) + "m" + s + term_esc() + "[0m"

// The tabline's active tab is the leading "[name]" segment (see
// `render.hc::build_tabline`) — split on the first "]" so it gets
// `active_tab_fg`/`active_tab_bg` while the rest of the row (other open
// buffers) gets the plain `tabline_fg`/`tabline_bg` pair.
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

fun colorize_status_row(theme: Theme, row: string) : string =>
  wrap_fg_bg(theme.status_fg, theme.status_bg, row)

fun colorize_cursor_row(theme: Theme, row: string) : string =>
  wrap_bg(theme.cursor_line_bg, row)

// Style the tabline (first row), status line (last row), and the row the
// cursor currently sits on (everything else, plain). `cursor_row` is
// 1-indexed and already clamped to the visible viewport by render.hc.
fun style_frame_lines(theme: Theme, lines: list<string>, cursor_row: int) : list<string> {
  let total = length(lines)
  style_frame_lines_go(theme, lines, 0, total, cursor_row)
}

fun style_frame_lines_go(theme: Theme, lines: list<string>, idx: int, total: int, cursor_row: int) : list<string> =>
  match lines {
    [] => [],
    [x, ..rest] => {
      let styled =
        if idx == 0 { colorize_tabline_row(theme, x) }
        else if idx == total - 1 { colorize_status_row(theme, x) }
        else if idx + 1 == cursor_row { colorize_cursor_row(theme, x) }
        else { x }
      [styled] + style_frame_lines_go(theme, rest, idx + 1, total, cursor_row)
    }
  }

// Full-redraw ANSI: home, then the rendered lines (each followed by an
// erase-to-end-of-line), then an erase-to-end-of-screen (handles a frame
// with fewer rows than the last one, e.g. after a resize) and a final
// escape moving the real terminal cursor to `buf.cursor_row`/
// `buf.cursor_col` (1-indexed) so it visibly tracks the edit position.
// No diffing/partial-redraw optimization in this pass (see M7 scope).
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
  let styled     = style_frame_lines(theme, buf.lines, buf.cursor_row)
  let cleared    = map(styled, (l) => l + term_esc() + "[K")
  let cursor_esc = term_esc() + "[" + show(buf.cursor_row) + ";" + show(buf.cursor_col) + "H"
  let frame = term_esc() + "[H" + join(cleared, "\r\n") + term_esc() + "[J" + cursor_esc
  print(frame)
  flush_stdout()
}

// `--tabsize <n>` (M8): applied to Config.values *after* init.hl has
// loaded, so it always wins over a config-file setting.
fun apply_tabsize_override(cfg: Config, tabsize: maybe<string>) : Config =>
  match tabsize {
    None    => cfg,
    Some(v) => set_config_value(cfg, "tabsize", v)
  }

// `--readonly` (M8): can only turn the flag on (there's no "un-readonly"
// CLI flag — omit it and the default `false` stands).
fun apply_readonly_override(cfg: Config, ro: bool) : Config =>
  if ro { Config { ...cfg, readonly: true } } else { cfg }

fun run_editor(r: CliResult, pos_arg: maybe<string>) {
  let cfg0             = default_config()
  let (cfg1, cfg_status) = load_user_config_opts(cfg0, get_opt(r, "config"), has_flag(r, "no-config"))
  let cfg2             = apply_tabsize_override(cfg1, get_opt(r, "tabsize"))
  let cfg              = apply_readonly_override(cfg2, has_flag(r, "readonly"))
  let (theme, theme_status) = resolve_theme_with_status(cfg)
  let (loaded_buf0, load_status) = load_buffer(0, get_positional(r, 0))
  let start_pos        = match pos_arg {
    None    => None,
    Some(a) => parse_position_arg(a)
  }
  let loaded_buf = set_initial_position(loaded_buf0, start_pos)
  let s0 = init_editor_with_buffer(loaded_buf, cfg)
  let s1 = match combine_status(combine_status(cfg_status, load_status), theme_status) {
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
      event_loop(s1)
    }
  }
  disable_raw_mode()
}

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
