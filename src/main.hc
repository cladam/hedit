// main.hc — hedit entry point.
//
// Until we wire real terminal I/O through effect handlers, `main` just drives
// a tiny synthetic event sequence to prove the core pipeline compiles and
// behaves. Once the `terminal` effect exists this file will replace the
// canned events with `poll_event()` inside an `event_loop`.

import "types"
import "model"
import "actions"

fun main() {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  let s3 = handle_action(s2, KeyEvent(KShortcut(Ctrl, 'q')))

  println("hedit synthetic run:")
  println("  lines:       {s3.buffer.lines}")
  println("  is_dirty:    {s3.buffer.is_dirty}")
  println("  should_quit: {s3.should_quit}")
}
