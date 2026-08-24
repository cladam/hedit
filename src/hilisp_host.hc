// hilisp_host.hc — HiLisp bridge into hedit.
//
// M4 turns this from a "spin up a fresh env and eval a string" wrapper into
// the *real* configuration bridge described in docs/hedit-design.md §7:
//
//   1. `make_hedit_env()` seeds a HiLisp environment with hedit-specific
//      builtins (`(set …)`, `(get …)`, `(bind …)`) that route through
//      HiLisp's host-dispatch (`host/…`) plumbing. A one-line preamble
//      re-aliases the `host/set` name to plain `set` so users write
//      idiomatic Lisp in `init.hl`.
//   2. Host state lives *inside* the HiLisp Env under three well-known
//      string keys — hedit has no other way to keep mutable state across
//      a pure callback that HiLisp calls back into, and HiLisp's
//      `register_host_dispatch` demands a **total** callback. Building
//      on top of HiLisp's own `env_set` / `map_set` on `list<(string,
//      LVal)>` inherits its totality for free.
//   3. `load_config(source, cfg0)` is the one call the rest of hedit
//      makes: parse + eval + return the merged Config. If a form
//      produces an LError we still return the config accumulated so
//      far, with a status message consumers can surface — a broken
//      binding shouldn't lock you out of your editor.
//
// Storage shape inside the env (why it looks this way):
//
//   __hedit_bindings  →  LHash of  "Ctrl-x" → LStr("save")
//   __hedit_values    →  LHash of  "tabsize" → LStr("4")
//
// Both are string-keyed alists (wrapped in `LHash` so HiLisp's own
// `map_set` handles them). We serialise chords to the same
// `"Modifier-c"` syntax users type in `(bind …)`, and actions to their
// symbol names, then decode on the way out via `config_from_env`. That
// keeps every mutation the callback performs a chain of stdlib
// functions HiLisp already proved to be total, satisfying
// `register_host_dispatch`'s type without patching upstream.
//
// See tests/hilisp_host_test.hc for end-to-end coverage of every
// public entry point below.

import "keys"
import "model"
import "../lib/hilisp/src/lisp"

// ------------------- eval loop -----------------------------------------

// Evaluate every top-level form in `tokens` against `env`, threading env
// through. Returns the *final* value + the updated env. Short-circuits
// on the first `LError` so `load_config` can surface a diagnostic and
// still hand back the partial config it accumulated up to that point.
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

// Compatibility helpers kept from the M0 stub — used by the smoke tests
// in `tests/hilisp_host_test.hc` and by any caller that doesn't need
// the full ConfigState round-trip.

pub fun eval_source(src: string) : string {
  let env    = make_env()
  let tokens = tokenise(src)
  let (result, _) = eval_all(tokens, env, LNil)
  lval_display(result)
}

pub fun eval_source_val(src: string) : LVal {
  let env    = make_env()
  let tokens = tokenise(src)
  let (result, _) = eval_all(tokens, env, LNil)
  result
}

// ------------------- Modifier <-> string helpers -----------------------

fun mod_to_string(m: Modifier) : string =>
  match m {
    Ctrl  => "Ctrl",
    Alt   => "Alt",
    Meta  => "Meta",
    Shift => "Shift"
  }

fun parse_mod(s: string) : maybe<Modifier> =>
  match s {
    "Ctrl"  => Some(Ctrl),
    "Alt"   => Some(Alt),
    "Meta"  => Some(Meta),
    "Shift" => Some(Shift),
    _       => None
  }

// Pull the single char out of a 1-char string. hica's stdlib exposes
// `chars(s) : list<char>` — total, so this function stays total.
fun single_char_of(s: string) : maybe<char> =>
  match chars(s) {
    [ch] => Some(ch),
    _    => None
  }

// Parse `"Ctrl-s"` style chord strings into a KeyChord. Matches the
// syntax used in the design doc §7.5 example (`(bind "Ctrl-s" 'save)`).
// The single-char rule keeps this focused on shortcut chords — special
// keys (Enter, Backspace, …) get their own binding path later.
pub fun parse_chord(s: string) : maybe<KeyChord> {
  let parts = split(s, "-")
  match parts {
    [m_str, c_str] =>
      match (parse_mod(m_str), single_char_of(c_str)) {
        (Some(m), Some(ch)) => Some(KeyChord { m: m, c: ch }),
        _                   => None
      },
    _ => None
  }
}

// Inverse of `parse_chord`. Used when we seed defaults into the env
// (so a user's `(bind …)` can either replace or coexist with them) and
// when the round-tripped Config picks bindings back out for hedit.
// `pub` (M10): reused by `render.hc`'s help overlay to label each row.
pub fun chord_to_str(chord: KeyChord) : string =>
  mod_to_string(chord.m) + "-" + char_to_string(chord.c)

// ------------------- Action <-> symbol name ----------------------------

// `pub` (M10): reused by `render.hc`'s help overlay to label each row.
pub fun action_to_string(a: Action) : string =>
  match a {
    Quit        => "quit",
    Save        => "save",
    Copy        => "copy",
    Paste       => "paste",
    Undo        => "undo",
    Redo        => "redo",
    NewBuffer   => "new-buffer",
    NextBuffer  => "next-buffer",
    PrevBuffer  => "prev-buffer",
    CloseBuffer => "close-buffer",
    OpenFile    => "open-file",
    Ignore      => "ignore",
    Insert(_)   => "insert",
    NewLine        => "new-line",
    DeleteBackward => "backspace",
    DeleteForward  => "delete-forward",
    MoveUp         => "move-up",
    MoveDown    => "move-down",
    MoveLeft    => "move-left",
    MoveRight   => "move-right",
    MoveLineStart => "move-line-start",
    MoveLineEnd   => "move-line-end",
    MoveWordForward => "move-word-forward",
    MoveWordBack    => "move-word-back",
    KillLine       => "kill-line",
    KillWordBack   => "kill-word-back",
    KillWordForward => "kill-word-forward",
    KillWholeLine   => "kill-whole-line",
    Resize(_, _) => "resize",
    PromptChar(_)   => "prompt-char",
    PromptBackspace => "prompt-backspace",
    PromptSubmit    => "prompt-submit",
    PromptCancel    => "prompt-cancel",
    PromptMoveStart     => "prompt-move-start",
    PromptMoveEnd       => "prompt-move-end",
    PromptMoveLeft      => "prompt-move-left",
    PromptMoveRight     => "prompt-move-right",
    PromptDeleteForward => "prompt-delete-forward",
    PromptKillLine      => "prompt-kill-line",
    ToggleHelp      => "toggle-help"
  }

fun string_to_action(s: string) : maybe<Action> =>
  match s {
    "quit"         => Some(Quit),
    "save"         => Some(Save),
    "copy"         => Some(Copy),
    "paste"        => Some(Paste),
    "undo"         => Some(Undo),
    "redo"         => Some(Redo),
    "new-buffer"   => Some(NewBuffer),
    "next-buffer"  => Some(NextBuffer),
    "prev-buffer"  => Some(PrevBuffer),
    "close-buffer" => Some(CloseBuffer),
    "open-file"    => Some(OpenFile),
    "toggle-help"  => Some(ToggleHelp),
    "move-left"       => Some(MoveLeft),
    "move-right"      => Some(MoveRight),
    "move-line-start" => Some(MoveLineStart),
    "move-line-end"   => Some(MoveLineEnd),
    "move-word-forward" => Some(MoveWordForward),
    "move-word-back"    => Some(MoveWordBack),
    "delete-forward"  => Some(DeleteForward),
    "kill-line"       => Some(KillLine),
    "kill-word-back"  => Some(KillWordBack),
    "kill-word-forward" => Some(KillWordForward),
    "kill-whole-line"   => Some(KillWholeLine),
    "ignore"       => Some(Ignore),
    _              => None
  }

// ------------------- Env <-> Config shuttling --------------------------
//
// State lives inside the HiLisp Env under two well-known keys. Both
// are stored as `LHash` (whose backing store HiLisp guarantees to be
// total under `map_get` / `map_set`) so the host callback stays total
// no matter how many times a user calls `(set …)` or `(bind …)`.

// Well-known env keys. `__hedit_` prefix keeps them out of any name a
// user might reasonably `(def …)`.
fun bindings_key() : string => "__hedit_bindings"

fun values_key() : string   => "__hedit_values"

// Serialise a hedit-side `Config.bindings` alist into an `LHash` keyed
// by `"Modifier-c"` chord strings, values = LStr(action-name).
fun bindings_to_hash(kb: list<(KeyChord, Action)>) : LVal =>
  LHash(map(kb, binding_to_entry))

fun binding_to_entry(pair: (KeyChord, Action)) : (string, LVal) =>
  match pair {
    (chord, act) => (chord_to_str(chord), LStr(action_to_string(act)))
  }

// Same shape for the `(set k v)` values alist. Every LVal is
// stringified at the boundary so downstream consumers only see plain
// strings.
fun values_to_hash(kv: list<(string, string)>) : LVal =>
  LHash(map(kv, value_to_entry))

fun value_to_entry(pair: (string, string)) : (string, LVal) =>
  match pair {
    (k, v) => (k, LStr(v))
  }

// Extract the hash entries back into hedit-side data. Malformed entries
// (chord that doesn't parse, action symbol we don't recognise) are
// silently dropped — the `(bind …)` call that produced them already had
// a chance to fail loudly via `host_bind`'s LError arm.
pub fun config_from_env(env: Env, fallback: Config) : Config {
  let kb = match env_get(env, bindings_key()) {
    LHash(entries) => entries_to_bindings(entries),
    _              => fallback.bindings
  }
  let vs = match env_get(env, values_key()) {
    LHash(entries) => entries_to_values(entries),
    _              => fallback.values
  }
  Config { bindings: kb, values: vs, readonly: fallback.readonly }
}

fun entries_to_bindings(entries: list<(string, LVal)>) : list<(KeyChord, Action)> =>
  match entries {
    [] => [],
    [(k, LStr(act_name)), ..rest] =>
      match (parse_chord(k), string_to_action(act_name)) {
        (Some(chord), Some(act)) => [(chord, act)] + entries_to_bindings(rest),
        _                        => entries_to_bindings(rest)
      },
    [_, ..rest] => entries_to_bindings(rest)
  }

fun entries_to_values(entries: list<(string, LVal)>) : list<(string, string)> =>
  match entries {
    [] => [],
    [(k, LStr(v)), ..rest] => [(k, v)] + entries_to_values(rest),
    [_, ..rest]            => entries_to_values(rest)
  }

// Seed the env with a Config value so the next host callback starts
// from a known baseline (typically `default_config()` from model.hc).
pub fun env_with_config(env: Env, cfg: Config) : Env {
  let env1 = env_set(env, bindings_key(), bindings_to_hash(cfg.bindings))
  env_set(env1, values_key(), values_to_hash(cfg.values))
}

// ------------------- Value <-> string coercion -------------------------
//
// HiLisp values arrive as `LVal`s; we stringify booleans/numbers so the
// `Config.values` alist stays a plain `list<(string, string)>`. Callers
// on the hedit side decode back into ints/bools via `get_config_int` in
// model.hc.
//
// Totality note: this function must stay **total** — it's called from
// `hedit_host_dispatch`, whose signature is `(string, list<LVal>, Env)
// -> (LVal, Env)` (i.e. total) as demanded by HiLisp's
// `register_host_dispatch`. We deliberately do NOT delegate to
// `lval_show`, because `lval_show` recurses into `LList`/`LHash`
// payloads via `map(items, lval_show).join(" ")` — a genuinely
// divergent shape that Koka correctly infers as `<div>`. Anything a
// user might reasonably store in a config value round-trips through
// the four total-safe variants below; for anything richer they should
// serialise on the HiLisp side first (e.g. `(set "k" (str v))`).
//
// See hica-issues.md Issue 6 → "Resolution" section.
fun value_to_string(v: LVal) : string =>
  match v {
    LStr(s)   => s,
    LNum(n)   => show(n),
    LBool(b)  => if b { "true" } else { "false" },
    LNil      => "nil",
    // Fallback: unsupported richer shapes serialise to a placeholder
    // rather than the recursive `lval_show`. Keeps the callback total.
    _         => "<unsupported>"
  }

// ------------------- host callback -------------------------------------
//
// Wired into HiLisp's host-dispatch. Routes `host/set`, `host/get`,
// `host/bind` to hedit-side config mutations. Everything else falls
// through to an LError so a typo in `init.hl` fails loud.
//
// The callback stays *total* because every mutation is expressed as
// stdlib `map_set`/`map_get` on `list<(string, LVal)>` — no direct
// recursion on user-defined key types. HiLisp's
// `register_host_dispatch` requires this.

pub fun hedit_host_dispatch(name: string, args: list<LVal>, env: Env) : (LVal, Env) =>
  match name {
    "host/set"  => host_set(args, env),
    "host/get"  => host_get(args, env),
    "host/bind" => host_bind(args, env),
    _           => (lerror("host/unknown", "unknown hedit host op: " + name), env)
  }

// `(set key value)` — record a string-typed value.
fun host_set(args: list<LVal>, env: Env) : (LVal, Env) =>
  match args {
    [LStr(k), v] => {
      let cur = match env_get(env, values_key()) {
        LHash(entries) => entries,
        _              => []
      }
      let updated = map_set(cur, k, LStr(value_to_string(v)))
      (LNil, env_set(env, values_key(), LHash(updated)))
    },
    _ => (lerror("host/bad-args", "set expects (key value)"), env)
  }

// `(get key)` — look up a value; returns nil when missing so
// `(if (get "foo") …)` reads naturally.
fun host_get(args: list<LVal>, env: Env) : (LVal, Env) =>
  match args {
    [LStr(k)] => {
      let cur = match env_get(env, values_key()) {
        LHash(entries) => entries,
        _              => []
      }
      match map_get(cur, k) {
        Some(v) => (v, env),
        None    => (LNil, env)
      }
    },
    _ => (lerror("host/bad-args", "get expects (key)"), env)
  }

// Once chord & action have both parsed, record the binding using the
// same canonical chord string the user typed. Split out from
// `host_bind` so the outer function doesn't nest `match` on maybe —
// `hica analyse` flags depth-3 nesting as HIGH severity, and having
// this in its own combinator reads clearer regardless.
fun bind_ok(env: Env, chord_str: string, action_name: string) : (LVal, Env) {
  let cur = match env_get(env, bindings_key()) {
    LHash(entries) => entries,
    _              => []
  }
  let updated = map_set(cur, chord_str, LStr(action_name))
  (LNil, env_set(env, bindings_key(), LHash(updated)))
}

// `(bind "Ctrl-x" 'save)` — replace (or add) a binding.
// Malformed chord strings or unknown action symbols surface as LErrors
// with hedit-specific ids so `load_config`'s status can be helpful.
fun host_bind(args: list<LVal>, env: Env) : (LVal, Env) =>
  match args {
    [LStr(chord_str), LSym(action_name, _)] =>
      match (parse_chord(chord_str), string_to_action(action_name)) {
        (None, _)    => (lerror("host/bad-chord", "unrecognised chord: " + chord_str), env),
        (_, None)    => (lerror("host/bad-action", "unknown action: " + action_name), env),
        (Some(_), Some(_)) => bind_ok(env, chord_str, action_name)
      },
    _ => (lerror("host/bad-args", "bind expects (chord-string 'action)"), env)
  }

// ------------------- HiLisp preamble -----------------------------------
//
// Registered on the env before evaluating user code. Aliases the raw
// `host/set` name to plain `set` (and friends) so authors write the
// idiomatic form documented in the README.

fun preamble() : string =>
  "(def set  (fn (k v) (host/set k v))) " +
  "(def get  (fn (k)   (host/get k)))   " +
  "(def bind (fn (k a) (host/bind k a)))"

// Build a HiLisp env seeded with:
//   * all core HiLisp builtins (via `make_env`),
//   * the hedit host-dispatch callback,
//   * the initial Config snapshot under the well-known env keys,
//   * the `set` / `get` / `bind` aliases so callers write idiomatic
//     `(bind "Ctrl-s" 'save)` instead of `(host/bind …)`.
pub fun make_hedit_env(cfg0:Config) : Env {
  let base       = make_env()
  let dispatched = register_host_dispatch(base, hedit_host_dispatch)
  let seeded     = env_with_config(dispatched, cfg0)
  let tokens     = tokenise(preamble())
  let (_, e2)    = eval_all(tokens, seeded, LNil)
  e2
}

// ------------------- public load entry point ---------------------------
//
// Evaluate a HiLisp source string as a hedit config file. Returns the
// merged Config plus a status message: `None` on clean load, `Some(msg)`
// when the eval hit an `LError` (so callers can drop it onto
// `EditorState.status_message`). Even on error we return whatever
// Config accumulated up to that point — a broken (bind …) at line 40
// shouldn't lose the 39 preceding lines' worth of config.
pub fun load_config(src: string, cfg0:Config) : (Config, maybe<string>) {
  let env0    = make_hedit_env(cfg0)
  let tokens  = tokenise(src)
  let (result, env1) = eval_all(tokens, env0, LNil)
  let cfg2    = config_from_env(env1, cfg0)
  match result {
    LError(_, _, _, _) => (cfg2, Some(lval_display(result))),
    _                  => (cfg2, None)
  }
}
