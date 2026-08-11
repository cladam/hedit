// hilisp_host_test.hc — smoke tests for the HiLisp embed (Step 1).
//
// These aren't testing HiLisp itself (its own suite lives in lib/hilisp) --
// they're proving that hedit can talk to HiLisp through the tiny host wrapper
// and that the four upstream v0.8.0 features we care about (arithmetic,
// hash-maps, string escapes, quoted symbols) all round-trip.

import "../src/script/hilisp_host"
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
