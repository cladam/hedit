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
// M4: HiLisp `(set …)` / `(bind …)` bridge lands in
//     `src/hilisp_host.hc` + `src/config_loader.hc` (tested end-to-end
//     via `tests/hilisp_host_test.hc`, 19/19 green). `main.hc` does
//     *not* yet call `load_user_config` at startup — pulling
//     `lib/hilisp/src/*.kk` into a `hica build` currently fails with
//     "could not find module: lisp" because hica.hml's
//     `@koka { include }` block doesn't propagate through the build
//     path. `hica test` handles the include correctly, which is why
//     the M4 test surface is green. Wiring the loader into `main.hc`
//     lands as M4b once the build-path issue is resolved (either a
//     hica CLI fix or a manifest-key discovery on our end).

import "keys"
import "model"
import "runtime"

fun main() {
  let s0 = init_editor(None)
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
      event_loop(s0)
    }
  }

  println("---")
  println("hedit m4 stub run complete.")
}
