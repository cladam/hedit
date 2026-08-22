// cli_test.hc — tests for src/cli_spec.hc's argv surface (M6, M8).
//
// Uses `cli_parse_args` directly (not `cli_parse`, which reads real
// `get_args()`) so these stay pure and deterministic.

import "../src/cli_spec"
import "../src/model"
import "std/cli"

test "--help resolves to Help" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, ["--help"])
  let is_help = match outcome {
    Help => true,
    _    => false
  }
  assert(is_help)
}

test "--version resolves to Version" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, ["--version"])
  let is_version = match outcome {
    Version => true,
    _       => false
  }
  assert(is_version)
}

test "a file argument resolves to the [FILE] positional" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, ["notes.txt"])
  let path = match outcome {
    Parsed(r) => get_positional(r, 0),
    _         => None
  }
  assert(path == Some("notes.txt"))
}

test "no arguments leaves the [FILE] positional unset" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, [])
  let path = match outcome {
    Parsed(r) => get_positional(r, 0),
    _         => Some("unexpected")
  }
  assert(path == None)
}

// ------------------- M8: --config / --no-config / --tabsize / --readonly

test "--config <path> is available as an option" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, ["--config", "/tmp/init.hl"])
  let cfg_path = match outcome {
    Parsed(r) => get_opt(r, "config"),
    _         => None
  }
  assert(cfg_path == Some("/tmp/init.hl"))
}

test "-c is the short form of --config" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, ["-c", "/tmp/init.hl"])
  let cfg_path = match outcome {
    Parsed(r) => get_opt(r, "config"),
    _         => None
  }
  assert(cfg_path == Some("/tmp/init.hl"))
}

test "--no-config is a flag" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, ["--no-config"])
  let is_set = match outcome {
    Parsed(r) => has_flag(r, "no-config"),
    _         => false
  }
  assert(is_set)
}

test "--tabsize <n> is available as an option" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, ["--tabsize", "2"])
  let tabsize = match outcome {
    Parsed(r) => get_opt_int(r, "tabsize"),
    _         => None
  }
  assert(tabsize == Some(2))
}

test "--readonly is a flag" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, ["--readonly"])
  let is_set = match outcome {
    Parsed(r) => has_flag(r, "readonly"),
    _         => false
  }
  assert(is_set)
}

test "-R is the short form of --readonly" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, ["-R"])
  let is_set = match outcome {
    Parsed(r) => has_flag(r, "readonly"),
    _         => false
  }
  assert(is_set)
}

test "flags and the [FILE] positional coexist" {
  let spec = make_spec()
  let outcome = cli_parse_args(spec, ["--readonly", "notes.txt"])
  let (is_ro, path) = match outcome {
    Parsed(r) => (has_flag(r, "readonly"), get_positional(r, 0)),
    _         => (false, None)
  }
  assert(is_ro)
  assert(path == Some("notes.txt"))
}

// ------------------- M8: +LINE:COL positional --------------------------

test "extract_position_arg pulls a +LINE token out of argv" {
  let result: (maybe<string>, list<string>) = extract_position_arg(["+10", "notes.txt"])
  assert(result.0 == Some("+10"))
  assert(result.1 == ["notes.txt"])
}

test "extract_position_arg works when the +LINE token comes after the file" {
  let result: (maybe<string>, list<string>) = extract_position_arg(["notes.txt", "+10:5"])
  assert(result.0 == Some("+10:5"))
  assert(result.1 == ["notes.txt"])
}

test "extract_position_arg leaves argv untouched with no +LINE token" {
  let result: (maybe<string>, list<string>) = extract_position_arg(["notes.txt"])
  assert(result.0 == None)
  assert(result.1 == ["notes.txt"])
}

test "parse_position_arg decodes a bare +LINE as 0-indexed line, col 0" {
  let pos = parse_position_arg("+10")
  assert(pos == Some(Position { line: 9, col: 0 }))
}

test "parse_position_arg decodes +LINE:COL as 0-indexed line and col" {
  let pos = parse_position_arg("+10:5")
  assert(pos == Some(Position { line: 9, col: 4 }))
}

test "parse_position_arg clamps +1:1 to line 0, col 0 (never negative)" {
  let pos = parse_position_arg("+1:1")
  assert(pos == Some(Position { line: 0, col: 0 }))
}

test "parse_position_arg rejects a non-numeric token" {
  let pos = parse_position_arg("+abc")
  assert(pos == None)
}

test "parse_position_arg rejects a token without a leading +" {
  let pos = parse_position_arg("10:5")
  assert(pos == None)
}
