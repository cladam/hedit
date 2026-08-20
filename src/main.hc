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

import "keys"
import "model"
import "runtime"
import "hilisp_host"
import "config_loader"
import "cli_spec"
import "std/cli"

// Combine the config-load and file-load status messages (either, both,
// or neither may be present) into the single message that gets primed
// onto `EditorState.status_message` for the first render tick.
fun combine_status(a: maybe<string>, b: maybe<string>) : maybe<string> =>
  match a {
    None => b,
    Some(x) => match b {
      None => Some(x),
      Some(y) => {
        let combined = x + " | " + y
        Some(combined)
      }
    }
  }

fun run_editor(r: CliResult) {
  let (cfg, cfg_status) = load_user_config(default_config())
  let (loaded_buf, load_status) = load_buffer(0, get_positional(r, 0))
  let s0 = init_editor_with_buffer(loaded_buf, cfg)
  let s1 = match combine_status(cfg_status, load_status) {
    None      => s0,
    Some(msg) => set_status_message(s0, msg)
  }
  let final = handle Clipboard {
    get_selection()   => clip,
    set_selection(t)  => clip = t
  } with var clip = "" in {
    handle Terminal {
      poll_event()         => KeyEvent(KShortcut(Ctrl, 'q')),
      render_frame(buf)    => foreach(buf.lines, println),
      get_dimensions()     => (80, 24),
      set_cursor_style(_s) => ()
    } in {
      event_loop(s1)
    }
  }

  println("---")
  println("hedit m4b stub run complete.")
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
