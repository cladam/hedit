// main.hc — hedit entry point.
//
// M1: install the *native stub* Terminal handler and hand control to
// `event_loop` in `src/runtime.hc`. The stub returns a canned
// `Ctrl-q` from `poll_event`, sinks `render_frame`, and reports an
// 80x24 canvas — enough to make `hica run src/main.hc` exit cleanly
// and prove the effect-arm shape compiles under a real (non-test)
// backend. Real ANSI wiring lands in M2 alongside `write_file`-backed
// save.
//
// hica 0.49.2 finally propagates user-defined effects across module
// imports (`import "runtime"` brings `effect Terminal` into scope
// here), unblocking the M1 split we designed.

import "keys"
import "model"
import "runtime"

fun main() {
  let s0 = init_editor(None)
  let final = handle Terminal {
    poll_event()         => KeyEvent(KShortcut(Ctrl, 'q')),
    render_frame(_buf)   => (),
    get_dimensions()     => (80, 24),
    set_cursor_style(_s) => ()
  } in {
    event_loop(s0)
  }

  println("hedit m1 native-stub run:")
  println("  lines:       {final.buffer.lines}")
  println("  should_quit: {final.should_quit}")
}
