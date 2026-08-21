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

// Full-redraw ANSI: clear + home, then the rendered lines, then a final
// escape moving the real terminal cursor to `buf.cursor_row`/`cursor_col`
// (1-indexed) so it visibly tracks the edit position instead of sitting
// wherever the last redraw happened to leave it. No diffing/partial-redraw
// optimization in this pass (see M7 scope).
// Raw mode (`stty raw`) disables output post-processing, so a bare
// "\n" doesn't return the cursor to column 0 — join with "\r\n"
// instead of relying on `println`, or every line staircases rightward.
fun render_native(buf: ScreenBuffer) {
  let cursor_esc = term_esc() + "[" + show(buf.cursor_row) + ";" + show(buf.cursor_col) + "H"
  let frame = term_esc() + "[2J" + term_esc() + "[H" + join(buf.lines, "\r\n") + cursor_esc
  print(frame)
  flush_stdout()
}

fun run_editor(r: CliResult) {
  let (cfg, cfg_status) = load_user_config(default_config())
  let (loaded_buf, load_status) = load_buffer(0, get_positional(r, 0))
  let s0 = init_editor_with_buffer(loaded_buf, cfg)
  let s1 = match combine_status(cfg_status, load_status) {
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
      render_frame(buf)    => render_native(buf),
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
  match cli_parse(spec) {
    Help          => println(cli_help(spec)),
    Version       => println(cli_version_str(spec)),
    CliError(msg) => eprintln("error: {msg}"),
    Parsed(r)     => run_editor(r)
  }
}
