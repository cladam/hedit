// hilisp_host.hc — a thin embedding of HiLisp inside hedit.
//
// Step 1 of the scripting bridge (see docs/hedit-design.md §7). This module
// owns nothing durable yet: each `eval_source` call spins up a fresh HiLisp
// environment (`make_env`), tokenises + parses + evaluates the given source,
// and returns the last value's display string.
//
// Later steps will:
//   - Keep one long-lived Env per hedit session.
//   - Register hedit-specific builtins (`set`, `get`, `bind`) on top of it.
//   - Thread a ConfigState through those builtins.
//
// Everything here uses only what HiLisp already exposes via its `lisp.hc`
// barrel re-export, so we don't leak internal module names into hedit.

import "../lib/hilisp/src/lisp"

// Evaluate every top-level form in `src` against `env`, threading the env
// through. Returns the *final* value produced (last form's result) plus the
// updated env. If a form yields an LError we short-circuit: the caller gets
// the error back so they can render it with `render_snippet` if they wish.
//
// This mirrors run_forms in HiLisp's own main.hc but stays pure: no printing,
// no side effects — hedit decides how to surface diagnostics.
pub fun eval_all(tokens: list<Token>, env: Env, last: LVal) : (LVal, Env) =>
  match tokens {
    [] => (last, env),
    _  => {
      let (expr, rest) = parse_tokens(tokens)
      let (result, env2) = eval(expr, env)
      match result {
        LError(_, _, _, _) => (result, env2),
        _                  => eval_all(rest, env2, result)
      }
    }
  }

// Public: evaluate a HiLisp source string, return the display of the last
// value (or the error's display, which lval_display renders as "error[…]: …").
// Uses a fresh env — every call is independent.
pub fun eval_source(src: string) : string {
  let env    = make_env()
  let tokens = tokenise(src)
  let (result, _) = eval_all(tokens, env, LNil)
  lval_display(result)
}

// Same as eval_source but returns the raw LVal so tests can pattern-match on
// LError, LHash, etc. Useful for structural assertions.
pub fun eval_source_val(src: string) : LVal {
  let env    = make_env()
  let tokens = tokenise(src)
  let (result, _) = eval_all(tokens, env, LNil)
  result
}
