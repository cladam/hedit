// hilisp_host_test.hc — smoke tests for the HiLisp embed.
//
// These tests proves hedit can talk to HiLisp through the tiny host wrapper
// and that the four upstream v0.8.0 features we care about (arithmetic,
// hash-maps, string escapes, quoted symbols) all round-trip.
//
// End-to-end coverage of the `(set …)` / `(get …)` / `(bind …)`

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

// Hash-maps

test "eval_source: hash-map reader literal + hash-get" {
  assert_eq(eval_source("(hash-get \{\"theme\" \"gruvbox\"\} \"theme\")"),
            "gruvbox")
}

test "eval_source: hash-get default for missing key" {
  assert_eq(eval_source("(hash-get \{\"a\" 1\} \"missing\" 99)"), "99")
}

// String escapes

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

// Symbols

test "eval_source: quoted symbol round-trips through symbol-name" {
  assert_eq(eval_source("(symbol-name 'save)"), "save")
}

test "eval_source: symbol? distinguishes symbol from string" {
  assert_eq(eval_source("(symbol? 'save)"), "true")
  assert_eq(eval_source("(symbol? \"save\")"), "false")
}

// Error surface

test "eval_source_val: undefined symbol returns LError with a span" {
  let v = eval_source_val("(+ 1 undefined-var)")
  match v {
    LError(id, _, _, Span(_, _)) => assert_eq(id, "eval/undefined-symbol"),
    _ => assert(false)  // we expected an error with a real span
  }
}

// ------------------- parse_chord (pure, always safe) -----------------

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

// ------------------- (set)/(bind) end-to-end -------------------------
//
// A HiLisp config string materialises into a hedit-side `Config`.
// The tests exercise `register_host_dispatch` + `hedit_host_dispatch` + `load_config` in one go.

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

test "load_config: start-find/find-next/find-prev symbols round-trip (M12)" {
  let src = "(bind \"Alt-1\" 'start-find) (bind \"Alt-2\" 'find-next) (bind \"Alt-3\" 'find-prev)"
  let (cfg, err) = load_config(src, default_config())
  assert(err == None)
  assert(lookup_binding(cfg.bindings, KeyChord { m: Alt, c: '1' }) == StartFind)
  assert(lookup_binding(cfg.bindings, KeyChord { m: Alt, c: '2' }) == FindNext)
  assert(lookup_binding(cfg.bindings, KeyChord { m: Alt, c: '3' }) == FindPrev)
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

// ------------------- (plugin)/(on)/fire_hook (M11) --------------------

test "load_config_with_env: (plugin) records an ordered name list" {
  let src = "(plugin \"greeter\") (plugin \"word-count\")"
  let (_, env, err) = load_config_with_env(src, default_config())
  assert(err == None)
  assert(plugin_names_from_env(env) == ["greeter", "word-count"])
}

test "fire_hook: no hooks registered is a no-op returning []" {
  let (_, env, _) = load_config_with_env("(plugin \"greeter\")", default_config())
  let (results, _) = fire_hook(env, "buffer-open", [LStr("")])
  assert(results == [])
}

test "fire_hook: a single hook receives its args and returns a value" {
  let src = "(on 'buffer-open (fn (path) (str \"opened \" path)))"
  let (_, env, err) = load_config_with_env(src, default_config())
  assert(err == None)
  let (results, _) = fire_hook(env, "buffer-open", [LStr("foo.txt")])
  match results {
    [LStr(s)] => assert_eq(s, "opened foo.txt"),
    _         => assert(false)
  }
}

test "fire_hook: multiple hooks on the same event all fire in order" {
  let src = "(on 'post-save (fn (p) \"first\")) (on 'post-save (fn (p) \"second\"))"
  let (_, env, err) = load_config_with_env(src, default_config())
  assert(err == None)
  let (results, _) = fire_hook(env, "post-save", [LStr("f.txt")])
  match results {
    [LStr(a), LStr(b)] => {
      assert_eq(a, "first")
      assert_eq(b, "second")
    },
    _ => assert(false)
  }
}

test "hook_cancels: true iff any hook result is (false)" {
  assert(hook_cancels([LStr("ok"), LBool(false)]) == true)
  assert(hook_cancels([LStr("ok"), LBool(true)]) == false)
  assert(hook_cancels([]) == false)
}

test "hook_status: last LStr result wins" {
  assert(hook_status([LBool(true), LStr("first"), LStr("second")]) == Some("second"))
  assert(hook_status([LBool(true)]) == None)
  assert(hook_status([]) == None)
}

test "fire_hook: pre-action hook returning false trips hook_cancels" {
  let src = "(on 'pre-action (fn (name) false))"
  let (_, env, _) = load_config_with_env(src, default_config())
  let (results, _) = fire_hook(env, "pre-action", [LStr("save")])
  assert(hook_cancels(results))
}

// ------------------- (buffer-stats) (M13) ------------------------------

test "buffer-stats: falls back to zero counts before anything seeds it" {
  let (_, env, _) = load_config_with_env("(plugin \"greeter\")", default_config())
  let (result, _) = eval_all(tokenise("(hash-get (buffer-stats) \"lines\")"), env, LNil)
  assert_eq(lval_show(result), "0")
}

test "buffer-stats: reflects a seeded buffer's line/word/char counts" {
  let (_, env0, _) = load_config_with_env("(plugin \"greeter\")", default_config())
  let buf  = TextBuffer { ...new_buffer(0, None), lines: ["one two", "three"] }
  let env1 = env_with_buffer_stats(env0, buf)
  let (lines_v, _) = eval_all(tokenise("(hash-get (buffer-stats) \"lines\")"), env1, LNil)
  let (words_v, _) = eval_all(tokenise("(hash-get (buffer-stats) \"words\")"), env1, LNil)
  let (chars_v, _) = eval_all(tokenise("(hash-get (buffer-stats) \"chars\")"), env1, LNil)
  assert_eq(lval_show(lines_v), "2")
  assert_eq(lval_show(words_v), "3")
  assert_eq(lval_show(chars_v), "12")
}

test "buffer-stats: re-seeding overwrites the previous buffer's counts" {
  let (_, env0, _) = load_config_with_env("(plugin \"greeter\")", default_config())
  let buf1 = TextBuffer { ...new_buffer(0, None), lines: ["a"] }
  let buf2 = TextBuffer { ...new_buffer(0, None), lines: ["a", "b", "c"] }
  let env1 = env_with_buffer_stats(env0, buf1)
  let env2 = env_with_buffer_stats(env1, buf2)
  let (lines_v, _) = eval_all(tokenise("(hash-get (buffer-stats) \"lines\")"), env2, LNil)
  assert_eq(lval_show(lines_v), "3")
}

// ------------------- example plugins (M13) ------------------------------
//
// Each test loads the *exact* HiLisp source shipped in
// `examples/plugins/<name>/plugin.hl`, so a passing test proves the
// real file works — not a simplified stand-in.

test "protected-paths: blocks .env/id_rsa/etc paths, allows everything else" {
  let src =
    "(defn protected? (path) (or (ends-with path \".env\") (or (ends-with path \"id_rsa\") (starts-with path \"/etc/\")))) " +
    "(on 'pre-save (fn (path) (if (protected? path) false true)))"
  let (_, env, err) = load_config_with_env(src, default_config())
  assert(err == None)
  let (r1, _) = fire_hook(env, "pre-save", [LStr("secrets.env")])
  let (r2, _) = fire_hook(env, "pre-save", [LStr("/home/me/.ssh/id_rsa")])
  let (r3, _) = fire_hook(env, "pre-save", [LStr("/etc/hosts")])
  let (r4, _) = fire_hook(env, "pre-save", [LStr("notes.txt")])
  assert(hook_cancels(r1))
  assert(hook_cancels(r2))
  assert(hook_cancels(r3))
  assert(!hook_cancels(r4))
}

test "confirm-close: requires close-buffer twice in a row, other actions reset it" {
  let src =
    "(on 'pre-action (fn (name) (if (= name \"close-buffer\") (if (= (get \"close-armed\") \"true\") (do (set \"close-armed\" \"false\") true) (do (set \"close-armed\" \"true\") false)) (do (set \"close-armed\" \"false\") true)))) " +
    "(on 'pre-action (fn (name) (if (and (= name \"close-buffer\") (= (get \"close-armed\") \"true\")) \"press again to close\" nil)))"
  let (_, env0, err) = load_config_with_env(src, default_config())
  assert(err == None)
  // First press: cancelled, with a nudge.
  let (r1, env1) = fire_hook(env0, "pre-action", [LStr("close-buffer")])
  assert(hook_cancels(r1))
  assert(hook_status(r1) == Some("press again to close"))
  // Immediate second press: goes through.
  let (r2, _) = fire_hook(env1, "pre-action", [LStr("close-buffer")])
  assert(!hook_cancels(r2))
  // A different action in between resets the arm — next close-buffer
  // is treated as a fresh first press.
  let (r3, env3) = fire_hook(env0, "pre-action", [LStr("close-buffer")])
  let (_, env4)  = fire_hook(env3, "pre-action", [LStr("save")])
  let (r5, _)    = fire_hook(env4, "pre-action", [LStr("close-buffer")])
  assert(hook_cancels(r3))
  assert(hook_cancels(r5))
}

test "filetype-tips: a different buffer-open message per extension" {
  let src =
    "(defn tip-for (path) (cond (= path \"\") \"New scratch buffer — Ctrl-s to save it somewhere.\" " +
    "(ends-with path \".hl\") \"HiLisp source.\" (ends-with path \".kk\") \"Koka source.\" " +
    "(ends-with path \".hc\") \"hica source — Ctrl-g for the keybinding overlay.\" " +
    "(ends-with path \".md\") \"Markdown — Ctrl-f to search headings.\" true \"Ready to edit.\")) " +
    "(on 'buffer-open (fn (path) (tip-for path)))"
  let (_, env, err) = load_config_with_env(src, default_config())
  assert(err == None)
  let (r1, _) = fire_hook(env, "buffer-open", [LStr("")])
  let (r2, _) = fire_hook(env, "buffer-open", [LStr("README.md")])
  let (r3, _) = fire_hook(env, "buffer-open", [LStr("notes.txt")])
  assert(hook_status(r1) == Some("New scratch buffer — Ctrl-s to save it somewhere."))
  assert(hook_status(r2) == Some("Markdown — Ctrl-f to search headings."))
  assert(hook_status(r3) == Some("Ready to edit."))
}

test "session-stats: save-count increments across consecutive saves" {
  let src =
    "(defn save-count () (if (get \"save-count\") (parse-int (get \"save-count\")) 0)) " +
    "(on 'post-save (fn (path) (do (set \"save-count\" (+ 1 (save-count))) (str \"saved \" (get \"save-count\") \"x this session\"))))"
  let (_, env0, err) = load_config_with_env(src, default_config())
  assert(err == None)
  let (r1, env1) = fire_hook(env0, "post-save", [LStr("a.txt")])
  let (r2, env2) = fire_hook(env1, "post-save", [LStr("a.txt")])
  let (r3, _)    = fire_hook(env2, "post-save", [LStr("a.txt")])
  assert(hook_status(r1) == Some("saved 1x this session"))
  assert(hook_status(r2) == Some("saved 2x this session"))
  assert(hook_status(r3) == Some("saved 3x this session"))
}

// Fire the commit-nag `post-save` hook `n` times in a row, returning
// the last firing's results.
fun fire_n_saves(env: Env, n: int) : (list<LVal>, Env) =>
  if n <= 1 { fire_hook(env, "post-save", [LStr("x.txt")]) }
  else {
    let (_, env2) = fire_hook(env, "post-save", [LStr("x.txt")])
    fire_n_saves(env2, n - 1)
  }

test "commit-nag: overrides the status only on the 5th save, not the 1st-4th" {
  let src =
    "(defn nag-count () (if (get \"commit-nag-count\") (parse-int (get \"commit-nag-count\")) 0)) " +
    "(defn divisible-by-5? (n) (if (< n 5) (= n 0) (divisible-by-5? (- n 5)))) " +
    "(on 'post-save (fn (path) (do (set \"commit-nag-count\" (+ 1 (nag-count))) " +
    "(if (divisible-by-5? (parse-int (get \"commit-nag-count\"))) \"maybe commit to git?\" (str \"saved \" path)))))"
  let (_, env0, err) = load_config_with_env(src, default_config())
  assert(err == None)
  let (r1, _) = fire_n_saves(env0, 1)
  let (r4, _) = fire_n_saves(env0, 4)
  let (r5, _) = fire_n_saves(env0, 5)
  assert(hook_status(r1) == Some("saved x.txt"))
  assert(hook_status(r4) == Some("saved x.txt"))
  assert(hook_status(r5) == Some("maybe commit to git?"))
}

test "recent-files: accumulates opened paths into one status line" {
  let src =
    "(on 'buffer-open (fn (path) (if (= path \"\") nil " +
    "(do (set \"recent-files\" (if (get \"recent-files\") (str (get \"recent-files\") \", \" path) path)) " +
    "(str \"recently opened: \" (get \"recent-files\"))))))"
  let (_, env0, err) = load_config_with_env(src, default_config())
  assert(err == None)
  let (r0, env0b) = fire_hook(env0, "buffer-open", [LStr("")])
  assert(hook_status(r0) == None)
  let (r1, env1) = fire_hook(env0b, "buffer-open", [LStr("a.txt")])
  let (r2, _)    = fire_hook(env1, "buffer-open", [LStr("b.txt")])
  assert(hook_status(r1) == Some("recently opened: a.txt"))
  assert(hook_status(r2) == Some("recently opened: a.txt, b.txt"))
}
