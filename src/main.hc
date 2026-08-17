// main.hc — hedit entry point.
//
// M1: native stub Terminal handler + event_loop.
// M2: render_frame arm now flushes the ScreenBuffer lines to stdout
//     (simple line-by-line dump — full ANSI diffing lands in a later pass).
//     event_loop gains <fsys> from handle_action's Ctrl-s save path.

import "keys"
import "model"
import "runtime"

fun main() {
  let s0 = init_editor(None)
  let final = handle Terminal {
    poll_event()         => KeyEvent(KShortcut(Ctrl, 'q')),
    render_frame(buf)    => foreach(buf.lines, (l) => println(l)),
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } in {
    event_loop(s0)
  }

  println("---")
  println("hedit m2 stub run complete.")
}
