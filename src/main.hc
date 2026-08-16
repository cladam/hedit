// main.hc — hedit entry point.
//
// M1 status: **BLOCKED on hica upstream — see docs/hica-issues.md
// Issue 3.** The intended M1 shape (documented in
// docs/effects-journal.md) installs a native-stub `Terminal` handler
// here and hands control to `event_loop` in `src/runtime.hc`. hica
// 0.49 doesn't yet propagate `effect` declarations across module
// imports, so the `handle Terminal { ... }` block below would fail
// with "unknown effect: 'Terminal'".
//
// Rather than duplicate the effect declaration (which the checker
// wouldn't unify anyway, per hica effects-design §12 Q1) or inline
// the loop and abandon the module split we planned, we leave main()
// in its pre-M1 synthetic shape until the upstream fix lands. At that
// point we swap this file for the handler-install shape sketched in
// hedit-design.md §4.1.

import "types"
import "model"
import "actions"
import "runtime"  // ScreenBuffer / build_screen / event_loop / effect Terminal

fun main() {
  let s0 = init_editor(None)
  let s1 = handle_action(s0, KeyEvent(KChar('h')))
  let s2 = handle_action(s1, KeyEvent(KChar('i')))
  let s3 = handle_action(s2, KeyEvent(KShortcut(Ctrl, 'q')))

  println("hedit synthetic run (M1 handler wiring pending — see docs/hica-issues.md #3):")
  println("  lines:       {s3.buffer.lines}")
  println("  is_dirty:    {s3.buffer.is_dirty}")
  println("  should_quit: {s3.should_quit}")
}
