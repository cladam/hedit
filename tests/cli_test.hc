// cli_test.hc — tests for src/cli_spec.hc's argv surface (M6).
//
// Uses `cli_parse_args` directly (not `cli_parse`, which reads real
// `get_args()`) so these stay pure and deterministic.

import "../src/cli_spec"
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
