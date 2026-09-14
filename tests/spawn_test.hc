// spawn_test.hc — `pub effect Buffer` isolation + undo/redo proof.
//
// These tests exercise the spawned `Buffer` effect directly (no
// `event_loop`, no Terminal/Clipboard handlers) — the "does spawn
// scale" evidence the M5 exit criteria calls for. `event_loop`'s real
// wiring (spawn once, dispatch Insert/Paste/Undo/Redo/branching) lives in
// `src/runtime.hc` and is covered by `tests/runtime_test.hc`.
//
// Op shape: `snapshot`/`undo`/`redo` take the *current* `TextBuffer`
// as an explicit argument. In M21, the linear undo/redo stacks were
// replaced by an immutable branching tree graph of `UndoNode`s.

import "../src/keys"
import "../src/model"
import "../src/runtime"

// Small helper: a TextBuffer with the given lines, no path, one cursor.
fun mk_buf(lines: list<string>) : TextBuffer =>
  TextBuffer { ...new_buffer(0, None), lines: lines }

fun make_test_buf() {
  let pair: (ref<Buffer>, ref<Buffer>) = spawn_buffer_handler()
  pair.0
}

// ------------------- undo restores prior snapshot ---------------

test "type, snapshot, type, undo restores the snapshot" {
  let buf: ref<Buffer> = make_test_buf()
  let after_type = mk_buf(["hi"])
  buf.snapshot(after_type)
  let after_more_typing = mk_buf(["hi there"])
  let restored = buf.undo(after_more_typing)
  assert(restored == Some(after_type))
}

// ------------------- redo moves forward again --------------------

test "undo then redo returns to the later state" {
  let buf: ref<Buffer> = make_test_buf()
  let snapshot_point = mk_buf(["hi"])
  buf.snapshot(snapshot_point)
  let later    = mk_buf(["hi there"])
  let _        = buf.undo(later)
  let restored = buf.redo(snapshot_point)
  assert(restored == Some(later))
}

// ------------------- undo on an empty history is a no-op ---------

test "undo on an empty history returns None" {
  let buf: ref<Buffer> = make_test_buf()
  let restored = buf.undo(mk_buf(["only state"]))
  assert(restored == None)
}

// ------------------- two spawned instances stay isolated --------

test "two spawned Buffer instances keep independent history" {
  let buf1:ref<Buffer> = make_test_buf()
  let buf2:ref<Buffer> = make_test_buf()

  // Only buf1 gets a snapshot — buf2's history must stay empty.
  buf1.snapshot(mk_buf(["a"]))
  let restored1 = buf1.undo(mk_buf(["a changed"]))
  let restored2 = buf2.undo(mk_buf(["b"]))
  assert(restored1 == Some(mk_buf(["a"])))
  assert(restored2 == None)
}

// ------------------- M21: branching undo graph (not lost) -------

test "undo then edit creates a branch that is not lost, reachable via next_branch" {
  let buf: ref<Buffer> = make_test_buf()
  let b0 = mk_buf(["root"])
  buf.snapshot(b0)
  let b_branch1 = mk_buf(["branch 1"])
  let _ = buf.undo(b_branch1) // now back at b0, branch 1 is child 2
  // Edit while undone: creates branch 2
  let b_branch2 = mk_buf(["branch 2"])
  buf.snapshot(b0)
  let _ = buf.undo(b_branch2) // branch 2 is child 3, back at b0

  // Next branch switches from branch 2 to branch 1!
  let switched = buf.next_branch(b0)
  assert(switched == Some(b_branch1))
  // Next branch switches from branch 1 back to branch 2!
  let switched2 = buf.next_branch(b_branch1)
  assert(switched2 == Some(b_branch2))
}

// ------------------- M21: snapshot_tree exports full graph ------

test "snapshot_tree captures branching history structure" {
  let buf: ref<Buffer> = make_test_buf()
  let b0 = mk_buf(["root"])
  buf.snapshot(b0)
  let b1 = mk_buf(["branch 1"])
  let _ = buf.undo(b1)
  let b2 = mk_buf(["branch 2"])
  buf.snapshot(b0)
  let _ = buf.undo(b2)
  let tree = buf.snapshot_tree()
  assert(tree.current_id == 1)
  assert(length(tree.nodes) == 3) // root (1), branch 1 (2), branch 2 (3)
}

// ------------------- M21: jump_to restores any historical node --

test "jump_to restores an arbitrary node in the undo tree" {
  let buf: ref<Buffer> = make_test_buf()
  let b0 = mk_buf(["root"])
  buf.snapshot(b0)
  let b1 = mk_buf(["branch 1"])
  let _ = buf.undo(b1)
  let b2 = mk_buf(["branch 2"])
  buf.snapshot(b0)
  let _ = buf.undo(b2)

  // Jump directly to branch 1 (id 2)
  let restored = buf.jump_to(2)
  assert(restored == Some(b1))
}
