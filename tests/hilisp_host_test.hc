// hilisp_host_test.hc — smoke tests for the HiLisp embed.
//
// M0 tests: proves hedit can talk to HiLisp through the tiny host wrapper
// and that the four upstream v0.8.0 features we care about (arithmetic,
// hash-maps, string escapes, quoted symbols) all round-trip.
//
// M4 tests: end-to-end coverage of the `(set …)` / `(get …)` / `(bind …)`
// bridge is *drafted* below but commented out — they exercise the code
// path in `src/hilisp_host.hc::load_config` that currently trips the
// `<div>` totality gap documented in `docs/hica-issues.md` Issue #6.
// The `parse_chord` tests are safe to run today because they only
// exercise the pure helper, not the host-callback machinery.

import "../src/keys"
import "../src/model"
import "../src/hilisp_host"
import "../lib/hilisp/src/lisp"

// Sanity: arithmetic and let bindings

test "eval_source: arithmetic returns the last value" {
  assert_eq(eval_source("(+ 1 2)"), "3")
}

test "eval_source: multiple top-level forms - last one wins" {
  assert_eq(eval_source("(def x 10) (+ x 32)"), "42")
}

test "eval_source: nested let bindings" {
  assert_eq(eval_source("(let (x 1 y 2) (+ x y))"), "3")
}

// Hash-maps (design doc section 8.2, shipped in HiLisp 0.7.0)

test "eval_source: hash-map reader literal + hash-get" {
  assert_eq(eval_source("(hash-get \{\"theme\" \"gruvbox\"\} \"theme\")"),
            "gruvbox")
}

test "eval_source: hash-get default for missing key" {
  assert_eq(eval_source("(hash-get \{\"a\" 1\} \"missing\" 99)"), "99")
}

// String escapes (design doc section 8.1, shipped in HiLisp 0.7.0)

test "eval_source: backslash-n is decoded inside string literals" {
  // Peel the string out of the LVal so equality goes through the built-in
  // string/(==), avoiding the ambiguous default/cmp/(==) that fires when
  // Koka has to pick an eq instance for LVal itself.
  let out = match eval_source_val("\"hi\\nthere\"") {
    LStr(s) => s,
    _       => ""
  }
  assert_eq(out, "hi\nthere")
}

// Symbols (design doc section 8.3, shipped in HiLisp 0.7.0)

test "eval_source: quoted symbol round-trips through symbol-name" {
  assert_eq(eval_source("(symbol-name 'save)"), "save")
}

test "eval_source: symbol? distinguishes symbol from string" {
  assert_eq(eval_source("(symbol? 'save)"), "true")
  assert_eq(eval_source("(symbol? \"save\")"), "false")
}

// Error surface (design doc section 8.4, shipped in HiLisp 0.7.0)

test "eval_source_val: undefined symbol returns LError with a span" {
  let v = eval_source_val("(+ 1 undefined-var)")
  match v {
    LError(id, _, _, Span(_, _)) => assert_eq(id, "eval/undefined-symbol"),
    _ => assert(false)  // we expected an error with a real span
  }
}

// ------------------- M4: parse_chord (pure, always safe) -----------------

test "parse_chord: Ctrl-s → KeyChord(Ctrl, 's')" {
  match parse_chord("Ctrl-s") {
    Some(kc) => {
      assert((kc.m == Ctrl) == true)
      assert((kc.c == 's') == true)
    },
    None => assert(false)
  }
}

test "parse_chord: Alt-x → KeyChord(Alt, 'x')" {
  match parse_chord("Alt-x") {
    Some(kc) => {
      assert((kc.m == Alt) == true)
      assert((kc.c == 'x') == true)
    },
    None => assert(false)
  }
}

test "parse_chord: rejects garbage" {
  assert(parse_chord("nope") == None)
  assert(parse_chord("Ctrl-longer") == None)
  assert(parse_chord("BadMod-s") == None)
  assert(parse_chord("Ctrl-") == None)
}

// ------------------- M4: (set)/(bind) end-to-end -------------------------
//
// These tests are the real M4 exit criterion: a HiLisp config string
// materialises into a hedit-side `Config`. They exercise
// `register_host_dispatch` + `hedit_host_dispatch` + `load_config` in
// one go. The pattern intentionally mirrors the design doc §7.5 example.

test "load_config: (set) records values into the config" {
  let (cfg, err) = load_config("(set \"tabsize\" 4)", default_config())
  assert(err == None)
  assert(get_config(cfg, "tabsize", "?") == "4")
  assert(get_config_int(cfg, "tabsize", 99) == 4)
}

test "load_config: (set) with a string value" {
  let (cfg, err) = load_config("(set \"theme\" \"gruvbox\")", default_config())
  assert(err == None)
  assert(get_config(cfg, "theme", "?") == "gruvbox")
}

test "load_config: (bind) rewires Ctrl-x to quit" {
  let (cfg, err) = load_config("(bind \"Ctrl-x\" 'quit)", default_config())
  assert(err == None)
  let chord = KeyChord { m: Ctrl, c: 'x' }
  assert(lookup_binding(cfg.bindings, chord) == Quit)
}

test "load_config: (bind) preserves defaults not shadowed" {
  // The user only rebinds Ctrl-x; Ctrl-s → Save should survive.
  let (cfg, err) = load_config("(bind \"Ctrl-x\" 'save)", default_config())
  assert(err == None)
  let ctrl_s = KeyChord { m: Ctrl, c: 's' }
  assert(lookup_binding(cfg.bindings, ctrl_s) == Save)
}

test "load_config: (bind) rewires Ctrl-z to undo" {
  let (cfg, err) = load_config("(bind \"Ctrl-z\" 'undo)", default_config())
  assert(err == None)
  let chord = KeyChord { m: Ctrl, c: 'z' }
  assert(lookup_binding(cfg.bindings, chord) == Undo)
}

test "load_config: (bind) rewires Ctrl-o to new-buffer (M5.5)" {
  let (cfg, err) = load_config("(bind \"Alt-b\" 'new-buffer)", default_config())
  assert(err == None)
  let chord = KeyChord { m: Alt, c: 'b' }
  assert(lookup_binding(cfg.bindings, chord) == NewBuffer)
}

test "load_config: next-buffer/prev-buffer/close-buffer symbols all resolve" {
  let src = "(bind \"Alt-1\" 'next-buffer) (bind \"Alt-2\" 'prev-buffer) (bind \"Alt-3\" 'close-buffer)"
  let (cfg, err) = load_config(src, default_config())
  assert(err == None)
  assert(lookup_binding(cfg.bindings, KeyChord { m: Alt, c: '1' }) == NextBuffer)
  assert(lookup_binding(cfg.bindings, KeyChord { m: Alt, c: '2' }) == PrevBuffer)
  assert(lookup_binding(cfg.bindings, KeyChord { m: Alt, c: '3' }) == CloseBuffer)
}

test "load_config: multiple forms compose (set + bind)" {
  let src = "(set \"tabsize\" 2) (bind \"Alt-w\" 'save)"
  let (cfg, err) = load_config(src, default_config())
  assert(err == None)
  assert(get_config_int(cfg, "tabsize", 99) == 2)
  let alt_w = KeyChord { m: Alt, c: 'w' }
  assert(lookup_binding(cfg.bindings, alt_w) == Save)
}

test "load_config: bad chord surfaces as status message" {
  let (_, err) = load_config("(bind \"nope\" 'quit)", default_config())
  match err {
    Some(msg) => assert(str_length(msg) > 0),
    None      => assert(false)
  }
}

test "load_config: unknown action surfaces as status message" {
  let (_, err) = load_config("(bind \"Ctrl-x\" 'nonsense)", default_config())
  match err {
    Some(msg) => assert(str_length(msg) > 0),
    None      => assert(false)
  }
}
