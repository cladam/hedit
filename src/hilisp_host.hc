/// HiLisp bridge into hedit.
/// Builds a HiLisp `Env` seeded with hedit's `(set ...)`/`(get ...)`/`(bind ...)` host
/// builtins (routed through HiLisp's `host/...` dispatch, then aliased
/// to the plain names via a preamble), and evaluates `init.hl` source
/// against it via `load_config`.
//
// Host state lives *inside* the Env under two well-known string keys
// (`__hedit_bindings`, `__hedit_values`, both `LHash`) rather than as
// hedit-side mutable state, since HiLisp's `register_host_dispatch`
// demands a **total** callback — building on HiLisp's own `env_set`/
// `map_set` inherits its totality for free. Chords serialise to the
// `"Modifier-c"` syntax users type in `(bind ...)`; actions to their
// symbol names; both decode back via `config_from_env`.
//
// See tests/hilisp_host_test.hc for end-to-end coverage of every public
// entry point below.

import "keys"
import "model"
import "actions"
import "../lib/hilisp/src/lisp"

// ------------------- eval loop -----------------------------------------

/// Evaluate every top-level form in `tokens` against `env`, threading
/// env through, and return the final value + updated env.
// Short-circuits on the first `LError` so `load_config` can surface a
// diagnostic and still hand back the partial config accumulated so far.
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

/// Evaluate `src` in a fresh env and return the final value's display string.
pub fun eval_source(src: string) : string {
  let env    = make_env()
  let tokens = tokenise(src)
  let (result, _) = eval_all(tokens, env, LNil)
  lval_display(result)
}

/// Evaluate `src` in a fresh env and return the final `LVal`.
pub fun eval_source_val(src: string) : LVal {
  let env    = make_env()
  let tokens = tokenise(src)
  let (result, _) = eval_all(tokens, env, LNil)
  result
}

// ------------------- Modifier <-> string helpers -----------------------

/// Render a `Modifier` as its `(bind ...)` chord-string name.
fun mod_to_string(m: Modifier) : string =>
  match m {
    Ctrl  => "Ctrl",
    Alt   => "Alt",
    Meta  => "Meta",
    Shift => "Shift"
  }

/// Parse a `(bind ...)` chord-string modifier name back into a `Modifier`.
fun parse_mod(s: string) : maybe<Modifier> =>
  match s {
    "Ctrl"  => Some(Ctrl),
    "Alt"   => Some(Alt),
    "Meta"  => Some(Meta),
    "Shift" => Some(Shift),
    _       => None
  }

/// Pull the single char out of a 1-char string, or `None` otherwise.
fun single_char_of(s: string) : maybe<char> =>
  match chars(s) {
    [ch] => Some(ch),
    _    => None
  }

/// Parse `"Ctrl-s"`-style chord strings (docs/hedit-design.md §7.5)
/// into a `KeyChord`.
// The single-char rule keeps this focused on shortcut chords — special
// keys (Enter, Backspace, ...) get their own binding path later.
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

/// Inverse of `parse_chord`.
// Used when seeding defaults into the env (so a user's `(bind ...)` can
// replace or coexist with them) and when the round-tripped Config picks
// bindings back out. Also reused by render.hc's help overlay (M10) to
// label each row.
pub fun chord_to_str(chord: KeyChord) : string =>
  mod_to_string(chord.m) + "-" + char_to_string(chord.c)

// ------------------- Action <-> symbol name ----------------------------

/// Render an `Action` as its `(bind ...)`-facing symbol name.
// Also reused by render.hc's help overlay (M10) to label each row.
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
    ToggleHelp      => "toggle-help",
    StartFind       => "start-find",
    FindNext        => "find-next",
    FindPrev        => "find-prev"
  }

/// Inverse of `action_to_string`; unrecognised names resolve to `None`.
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
    "start-find"   => Some(StartFind),
    "find-next"    => Some(FindNext),
    "find-prev"    => Some(FindPrev),
    "ignore"       => Some(Ignore),
    _              => None
  }

// ------------------- Env <-> Config shuttling --------------------------
//
// State lives inside the HiLisp Env under two well-known keys. Both
// are stored as `LHash` (whose backing store HiLisp guarantees to be
// total under `map_get` / `map_set`) so the host callback stays total
// no matter how many times a user calls `(set ...)` or `(bind ...)`.

/// The env key under which the bindings alist is stored.
// `__hedit_` prefix keeps it out of any name a user might `(def ...)`.
fun bindings_key() : string => "__hedit_bindings"

/// The env key under which the `(set ...)` values alist is stored.
fun values_key() : string   => "__hedit_values"

/// The env key under which the `(on 'event (fn ...))` hook registry
/// (event-name -> `LList` of closures) is stored.
fun hooks_key() : string => "__hedit_hooks"

/// The env key under which the ordered `(plugin "name")` list is stored.
fun plugins_key() : string => "__hedit_plugins"

/// The env key under which the current buffer's line/word/char counts
/// are stashed as an `LHash`, refreshed before every hook firing (see
/// `env_with_buffer_stats`) so `(buffer-stats)` never sees stale data.
fun buffer_stats_key() : string => "__hedit_buffer_stats"

/// Serialise `buf`'s line/word/char counts into `env` under the
/// well-known stats key. Called from every `fire_hook` call site in
/// `runtime.hc`, right before firing, so `(buffer-stats)` always
/// reflects the buffer active at the moment a hook runs.
// Return-type annotation omitted: `line_count`/`word_count`/`char_count`
// are cross-file recursive helpers (actions.hc) and an explicit `: Env`
// here mis-infers "expected effect: total" (repo-memory div/effect
// annotation gotcha).
pub fun env_with_buffer_stats(env: Env, buf: TextBuffer) {
  let stats = LHash([
    ("lines", LNum(line_count(buf))),
    ("words", LNum(word_count(buf))),
    ("chars", LNum(char_count(buf)))
  ])
  env_set(env, buffer_stats_key(), stats)
}

/// Serialise a `Config.bindings` alist into an `LHash` keyed by
/// `"Modifier-c"` chord strings, values = LStr(action-name).
fun bindings_to_hash(kb: list<(KeyChord, Action)>) : LVal =>
  LHash(map(kb, binding_to_entry))

/// Serialise a single `(KeyChord, Action)` pair into a hash entry.
fun binding_to_entry(pair: (KeyChord, Action)) : (string, LVal) =>
  match pair {
    (chord, act) => (chord_to_str(chord), LStr(action_to_string(act)))
  }

/// Serialise the `(set k v)` values alist into an `LHash`.
// Every LVal is stringified at the boundary so downstream consumers
// only see plain strings.
fun values_to_hash(kv: list<(string, string)>) : LVal =>
  LHash(map(kv, value_to_entry))

/// Serialise a single `(key, value)` pair into a hash entry.
fun value_to_entry(pair: (string, string)) : (string, LVal) =>
  match pair {
    (k, v) => (k, LStr(v))
  }

/// Extract the env's hash entries back into a hedit-side `Config`.
// Malformed entries (chord that doesn't parse, action symbol we don't
// recognise) are silently dropped — the `(bind ...)` call that produced
// them already had a chance to fail loudly via `host_bind`'s LError arm.
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

/// Decode a hash's entries into a hedit-side bindings alist,
/// dropping any entry that doesn't parse as a chord + known action.
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

/// Decode a hash's entries into a hedit-side `(key, value)` alist.
fun entries_to_values(entries: list<(string, LVal)>) : list<(string, string)> =>
  match entries {
    [] => [],
    [(k, LStr(v)), ..rest] => [(k, v)] + entries_to_values(rest),
    [_, ..rest]            => entries_to_values(rest)
  }

/// Seed `env` with `cfg`'s bindings + values under the well-known keys.
// Typically called with `default_config()` from model.hc so the next
// host callback starts from a known baseline.
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

/// Stringify an `LVal` for storage in `Config.values`.
// Must stay total — called from `hedit_host_dispatch`, whose signature
// is total per HiLisp's `register_host_dispatch`. Deliberately does NOT
// delegate to `lval_show`, which recurses into `LList`/`LHash` payloads
// (a genuinely divergent shape Koka infers as `<div>`). Anything a user
// might reasonably store round-trips through the four variants below;
// richer values should be serialised on the HiLisp side first (e.g.
// `(set "k" (str v))`). See hica-issues.md Issue 6 → "Resolution".
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

/// Dispatch a `host/...` op name to its hedit-side handler.
pub fun hedit_host_dispatch(name: string, args: list<LVal>, env: Env) : (LVal, Env) =>
  match name {
    "host/set"           => host_set(args, env),
    "host/get"           => host_get(args, env),
    "host/bind"          => host_bind(args, env),
    "host/on"            => host_on(args, env),
    "host/plugin"        => host_plugin(args, env),
    "host/buffer-stats"  => host_buffer_stats(args, env),
    _                    => (lerror("host/unknown", "unknown hedit host op: " + name), env)
  }

/// `(set key value)` — record a string-typed value.
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

/// `(get key)` — look up a value; returns nil when missing so
/// `(if (get "foo") ...)` reads naturally.
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

/// Record a binding once chord & action have both parsed, using the
/// same canonical chord string the user typed.
// Split out from `host_bind` so the outer function doesn't nest `match`
// on maybe — `hica analyse` flags depth-3 nesting as HIGH severity.
fun bind_ok(env: Env, chord_str: string, action_name: string) : (LVal, Env) {
  let cur = match env_get(env, bindings_key()) {
    LHash(entries) => entries,
    _              => []
  }
  let updated = map_set(cur, chord_str, LStr(action_name))
  (LNil, env_set(env, bindings_key(), LHash(updated)))
}

/// `(bind "Ctrl-x" 'save)` — replace (or add) a binding.
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

// ------------------- Buffer stats (M13, read-only) ----------------------

/// An all-zero stats hash — the `(buffer-stats)` fallback before
/// anything has stashed real counts on `env` (e.g. the very first hook
/// of a run, if one ever fires before `event_loop_step`'s first tick).
fun zero_buffer_stats() : LVal =>
  LHash([("lines", LNum(0)), ("words", LNum(0)), ("chars", LNum(0))])

/// `(buffer-stats)` — a read-only lookup of the current buffer's
/// line/word/char counts. Pure lookup of `env`, same shape as
/// `host_get`, so the host callback stays total.
fun host_buffer_stats(args: list<LVal>, env: Env) : (LVal, Env) =>
  match args {
    [] => match env_get(env, buffer_stats_key()) {
      LHash(entries) => (LHash(entries), env),
      _              => (zero_buffer_stats(), env)
    },
    _ => (lerror("host/bad-args", "buffer-stats expects no args"), env)
  }

// ------------------- Plugin / hook registry (M11) -----------------------
//
// `(plugin "name")` records an opt-in plugin name (an ordered `LList` of
// `LStr`s, since load order matters and there's no dedup need). `(on
// 'event (fn ...))` appends a closure to `__hedit_hooks[event-name]` — an
// `LHash` whose values are themselves `LList`s of closures, so more than
// one plugin can hook the same event. `fire_hook` (called from
// `runtime.hc::event_loop`) looks up and calls every closure registered
// for an event, in registration order, threading `env` through each call
// via HiLisp's own `apply`.

/// `(plugin "name")` — append a plugin name to the ordered load list.
fun host_plugin(args: list<LVal>, env: Env) : (LVal, Env) =>
  match args {
    [LStr(name)] => {
      let cur = match env_get(env, plugins_key()) {
        LList(items) => items,
        _            => []
      }
      (LNil, env_set(env, plugins_key(), LList(cur + [LStr(name)])))
    },
    _ => (lerror("host/bad-args", "plugin expects (name)"), env)
  }

/// Decode the plugin-name `LList` back into a plain `list<string>`,
/// dropping any malformed (non-`LStr`) entry rather than failing.
fun lvals_to_names(items: list<LVal>) : list<string> =>
  match items {
    [] => [],
    [LStr(s), ..rest] => [s] + lvals_to_names(rest),
    [_, ..rest]       => lvals_to_names(rest)
  }

/// Extract the ordered `(plugin "name")` list recorded on `env`.
pub fun plugin_names_from_env(env: Env) : list<string> =>
  match env_get(env, plugins_key()) {
    LList(items) => lvals_to_names(items),
    _            => []
  }

/// `(on 'event (fn (...) ...))` — append a closure to the hook list
/// registered for `event`.
fun host_on(args: list<LVal>, env: Env) : (LVal, Env) =>
  match args {
    [LSym(event_name, _), closure] => {
      let cur = match env_get(env, hooks_key()) {
        LHash(entries) => entries,
        _              => []
      }
      let existing = match map_get(cur, event_name) {
        Some(LList(items)) => items,
        _                  => []
      }
      let updated = map_set(cur, event_name, LList(existing + [closure]))
      (LNil, env_set(env, hooks_key(), LHash(updated)))
    },
    _ => (lerror("host/bad-args", "on expects ('event-name (fn ...))"), env)
  }

/// Call every hook registered for `event`, in registration order,
/// threading `env` through each call. Returns every closure's return
/// value (see `hook_cancels`/`hook_status` for the conventions built on
/// top of that list) alongside the final `Env`.
pub fun fire_hook(env: Env, event: string, args: list<LVal>) : (list<LVal>, Env) {
  let hooks = match env_get(env, hooks_key()) {
    LHash(entries) => entries,
    _              => []
  }
  let closures = match map_get(hooks, event) {
    Some(LList(items)) => items,
    _                   => []
  }
  call_hooks(closures, args, env)
}

/// Recursive worker for `fire_hook`: apply each closure in turn,
/// threading `env` and collecting every return value in order.
fun call_hooks(closures: list<LVal>, args: list<LVal>, env: Env) : (list<LVal>, Env) =>
  match closures {
    [] => ([], env),
    [f, ..rest] => {
      let (result, env2)  = apply(f, args, env)
      let (results, env3) = call_hooks(rest, args, env2)
      ([result] + results, env3)
    }
  }

/// The `pre-save`/`pre-action` cancel convention: `true` iff any hook
/// result is `LBool(False)`.
pub fun hook_cancels(results: list<LVal>) : bool =>
  match results {
    [] => false,
    [LBool(false), ..rest] => true,
    [_, ..rest]            => hook_cancels(rest)
  }

/// The status-bar convention: every hook's `LStr` return, joined in
/// registration order with `" | "` — so two plugins hooking the same
/// event (e.g. `greeter` and `filetype-tips` both on `buffer-open`)
/// each get to say something instead of one silently overwriting the
/// other. `None` if no hook returned a string.
pub fun hook_status(results: list<LVal>) : maybe<string> {
  let strs = collect_str_results(results)
  match strs {
    [] => None,
    _  => Some(join(strs, " | "))
  }
}

/// Pull every `LStr` payload out of a hook-results list, preserving order.
fun collect_str_results(results: list<LVal>) : list<string> =>
  match results {
    []                 => [],
    [LStr(s), ..rest]  => [s] + collect_str_results(rest),
    [_, ..rest]        => collect_str_results(rest)
  }

// ------------------- HiLisp preamble -----------------------------------
//
// Registered on the env before evaluating user code. Aliases the raw
// `host/set` name to plain `set` (and friends) so authors write the
// idiomatic form documented in the README.

/// The HiLisp preamble that aliases `host/set`/`host/get`/`host/bind`/
/// `host/on`/`host/plugin`/`host/buffer-stats` to the idiomatic
/// `set`/`get`/`bind`/`on`/`plugin`/`buffer-stats` names.
fun preamble() : string =>
  "(def set    (fn (k v) (host/set k v)))    " +
  "(def get    (fn (k)   (host/get k)))      " +
  "(def bind   (fn (k a) (host/bind k a)))   " +
  "(def on     (fn (e f) (host/on e f)))     " +
  "(def plugin (fn (n)   (host/plugin n)))   " +
  "(def buffer-stats (fn () (host/buffer-stats)))"

/// Build a HiLisp env seeded with core HiLisp builtins, the hedit
/// host-dispatch callback, the initial `Config` snapshot, and the
/// `set`/`get`/`bind` aliases.
pub fun make_hedit_env(cfg0:Config) : Env {
  let base       = make_env()
  let dispatched = register_host_dispatch(base, hedit_host_dispatch)
  let seeded     = env_with_config(dispatched, cfg0)
  let tokens     = tokenise(preamble())
  let (_, e2)    = eval_all(tokens, seeded, LNil)
  e2
}

// ------------------- public load entry point ---------------------------

/// Evaluate a HiLisp source string as a hedit config file, returning
/// the merged `Config` plus a status message (`None` on clean load,
/// `Some(msg)` on an `LError`).
// Even on error we return whatever Config accumulated up to that point
// — a broken (bind ...) at line 40 shouldn't lose the 39 preceding
// lines' worth of config.
pub fun load_config(src: string, cfg0:Config) : (Config, maybe<string>) {
  let (cfg, _, status) = load_config_with_env(src, cfg0)
  (cfg, status)
}

/// Evaluate `src` against an already-built `env0` (typically a prior
/// `load_config_env`'s output `Env`, so `init.hl` and each `plugin.hl`
/// accumulate into the *same* env), returning the merged `Config`, the
/// resulting `Env` (carrying any newly-registered `(on ...)` hooks), and
/// a status message.
// Split out of `load_config_with_env` so `config_loader.hc` can fold this
/// over a list of plugin sources without rebuilding a fresh env each time.
pub fun load_config_env(src: string, cfg0:Config, env0:Env) : (Config, Env, maybe<string>) {
  let tokens  = tokenise(src)
  let (result, env1) = eval_all(tokens, env0, LNil)
  let cfg2    = config_from_env(env1, cfg0)
  match result {
    LError(_, _, _, _) => (cfg2, env1, Some(lval_display(result))),
    _                  => (cfg2, env1, None)
  }
}

/// Same as `load_config`, but also returns the resulting `Env` so a
/// caller (`config_loader.hc`) can keep loading `(plugin "name")`
/// files into it, and later thread it into `EditorState.hilisp_env`
/// for `runtime.hc::fire_hook`.
pub fun load_config_with_env(src: string, cfg0:Config) : (Config, Env, maybe<string>) {
  let env0 = make_hedit_env(cfg0)
  load_config_env(src, cfg0, env0)
}
