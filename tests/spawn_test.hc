// spawn_test.hc — M5: `pub effect Buffer` isolation + undo/redo proof.
//
// These tests exercise the spawned `Buffer` effect directly (no
// `event_loop`, no Terminal/Clipboard handlers) — the "does spawn
// scale" evidence the M5 exit criteria calls for. `event_loop`'s real
// wiring (spawn once, dispatch Insert/Paste/Undo/Redo) lives in
// `src/runtime.hc` and is covered by `tests/runtime_test.hc`.
//
// `spawn Name { … } with var … as ref` is a *statement* (unlike
// `handle … in { … }`) — the bound ref stays live for the rest of the
// enclosing block, no `in { … }` wrapper and no escape restriction.
//
// Op shape: `snapshot`/`undo`/`redo` all take the *current* `TextBuffer`
// as an explicit argument rather than mirroring it in handler-local
// state (no `get`/`put`, no separate "current" var) — see
// `docs/effects-journal.md` M5 Log for the rationale.

import "../src/keys"
import "../src/model"
import "../src/runtime"

// Small helper: a TextBuffer with the given lines, no path, one cursor.
fun mk_buf(lines: list<string>) : TextBuffer =>
  TextBuffer { ...new_buffer(0, None), lines: lines }

// ------------------- test 1: undo restores prior snapshot ---------------

test "type, snapshot, type, undo restores the snapshot" {
  spawn Buffer {
    snapshot(b) => {
      undo_stack = [b] + undo_stack
      redo_stack = []
    },
    undo(current) => match undo_stack {
      [] => None,
      [top, ..rest] => {
        redo_stack = [current] + redo_stack
        undo_stack = rest
        Some(top)
      }
    },
    redo(current) => match redo_stack {
      [] => None,
      [top, ..rest] => {
        undo_stack = [current] + undo_stack
        redo_stack = rest
        Some(top)
      }
    }
  } with var undo_stack = [], var redo_stack = [] as buf

  let after_type = mk_buf(["hi"])
  buf.snapshot(after_type)
  let after_more_typing = mk_buf(["hi there"])
  let restored = buf.undo(after_more_typing)
  assert(restored == Some(after_type))
}

// ------------------- test 2: redo moves forward again --------------------

test "undo then redo returns to the later state" {
  spawn Buffer {
    snapshot(b) => {
      undo_stack = [b] + undo_stack
      redo_stack = []
    },
    undo(current) => match undo_stack {
      [] => None,
      [top, ..rest] => {
        redo_stack = [current] + redo_stack
        undo_stack = rest
        Some(top)
      }
    },
    redo(current) => match redo_stack {
      [] => None,
      [top, ..rest] => {
        undo_stack = [current] + undo_stack
        redo_stack = rest
        Some(top)
      }
    }
  } with var undo_stack = [], var redo_stack = [] as buf

  let snapshot_point = mk_buf(["hi"])
  buf.snapshot(snapshot_point)
  let later    = mk_buf(["hi there"])
  let _        = buf.undo(later)
  let restored = buf.redo(snapshot_point)
  assert(restored == Some(later))
}

// ------------------- test 3: undo on an empty stack is a no-op ----------

test "undo on an empty history returns None" {
  spawn Buffer {
    snapshot(b) => {
      undo_stack = [b] + undo_stack
      redo_stack = []
    },
    undo(current) => match undo_stack {
      [] => None,
      [top, ..rest] => {
        redo_stack = [current] + redo_stack
        undo_stack = rest
        Some(top)
      }
    },
    redo(current) => match redo_stack {
      [] => None,
      [top, ..rest] => {
        undo_stack = [current] + undo_stack
        redo_stack = rest
        Some(top)
      }
    }
  } with var undo_stack = [], var redo_stack = [] as buf

  let restored = buf.undo(mk_buf(["only state"]))
  assert(restored == None)
}

// ------------------- test 4: two spawned instances stay isolated --------

test "two spawned Buffer instances keep independent history" {
  spawn Buffer {
    snapshot(b) => {
      undo_stack = [b] + undo_stack
      redo_stack = []
    },
    undo(current) => match undo_stack {
      [] => None,
      [top, ..rest] => {
        redo_stack = [current] + redo_stack
        undo_stack = rest
        Some(top)
      }
    },
    redo(current) => match redo_stack {
      [] => None,
      [top, ..rest] => {
        undo_stack = [current] + undo_stack
        redo_stack = rest
        Some(top)
      }
    }
  } with var undo_stack = [], var redo_stack = [] as buf1

  spawn Buffer {
    snapshot(b) => {
      undo_stack = [b] + undo_stack
      redo_stack = []
    },
    undo(current) => match undo_stack {
      [] => None,
      [top, ..rest] => {
        redo_stack = [current] + redo_stack
        undo_stack = rest
        Some(top)
      }
    },
    redo(current) => match redo_stack {
      [] => None,
      [top, ..rest] => {
        undo_stack = [current] + undo_stack
        redo_stack = rest
        Some(top)
      }
    }
  } with var undo_stack = [], var redo_stack = [] as buf2

  // Only buf1 gets a snapshot — buf2's history must stay empty.
  buf1.snapshot(mk_buf(["a"]))
  let restored1 = buf1.undo(mk_buf(["a changed"]))
  let restored2 = buf2.undo(mk_buf(["b"]))
  assert(restored1 == Some(mk_buf(["a"])))
  assert(restored2 == None)
}
