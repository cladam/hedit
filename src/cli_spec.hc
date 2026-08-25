// cli_spec.hc — hedit's command-line surface (M6, flags in M8).
//
// A single optional [FILE] positional. --help/--version come free from
// `std/cli` (cli_help / cli_version_str) — no hedit-side code needed
// beyond wiring the Help/Version arms in main.hc.
//
// M8 adds --config/--no-config, --tabsize, --readonly (all plain
// `std/cli` flags/options) plus a `+LINE[:COL]` positional, which isn't
// part of the `std/cli` spec at all — it's stripped out of argv by hand
// (`extract_position_arg`) before the rest is handed to `cli_parse_args`,
// since `std/cli` has no concept of a `+`-prefixed positional.

import "std/cli"
import "model"

pub fun make_spec() : CliSpec =>
  cli("hedit", "0.10.0", "a terminal text editor in hica")
    |> arg("file", "file to open", false)
    |> option("config", "c", "load config from this path instead of the default search")
    |> flag("no-config", "", "skip loading the user's init.hl entirely")
    |> option("tabsize", "", "override the tabsize config value")
    |> flag("readonly", "R", "open the file in read-only mode (Save is disabled)")

// Parse a `+LINE[:COL]` token into a 1-indexed `Position` (converted to
// hedit's 0-indexed `Position` here). Malformed tokens (non-numeric,
// too many `:` parts) resolve to `None` rather than erroring — an
// unusable `+foo` just leaves the cursor at its default (0, 0).
// Split into two single-match helpers (rather than one nested match)
// per `hica analyse`'s "nested match on maybe" HIGH-severity rule.
fun with_parsed_line(n: int, col_str: string) : maybe<Position> =>
  match parse_int(col_str) {
    None    => None,
    Some(m) => Some(Position { line: max(n - 1, 0), col: max(m - 1, 0) })
  }

fun parse_line_col(line_str: string, col_str: string) : maybe<Position> =>
  match parse_int(line_str) {
    None    => None,
    Some(n) => with_parsed_line(n, col_str)
  }

pub fun parse_position_arg(a: string) : maybe<Position> =>
  if !starts_with(a, "+") { None }
  else {
    let body = removeprefix(a, "+")
    match split(body, ":") {
      [line_str] => match parse_int(line_str) {
        Some(n) => Some(Position { line: max(n - 1, 0), col: 0 }),
        None    => None
      },
      [line_str, col_str] => parse_line_col(line_str, col_str),
      _ => None
    }
  }

// Pull the first `+`-prefixed token out of argv (order-independent —
// `hedit +10 file.txt` and `hedit file.txt +10` both work), leaving
// everything else untouched for `cli_parse_args`. Only the first `+…`
// token is treated specially; a second one is left as a positional
// (and will fail `std/cli`'s single-[FILE] arg check, same as any
// other stray extra positional).
pub fun extract_position_arg(args: list<string>) : (maybe<string>, list<string>) =>
  match args {
    [] => (None, []),
    [a, ..rest] =>
      if starts_with(a, "+") { (Some(a), rest) }
      else {
        let (found, kept) = extract_position_arg(rest)
        (found, [a] + kept)
      }
  }
