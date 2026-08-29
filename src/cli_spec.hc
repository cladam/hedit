/// hedit's command-line surface: a single optional [FILE] positional
/// plus `--config`/`--no-config`/`--tabsize`/`--readonly` flags, and a
/// hand-parsed `+LINE[:COL]` positional that isn't part of `std/cli`'s
/// spec at all.

import "std/cli"
import "model"

/// Build hedit's `std/cli` spec.
pub fun make_spec() : CliSpec =>
  cli("hedit", "0.12.0", "a terminal text editor in hica")
    |> arg("file", "file to open", false)
    |> option("config", "c", "load config from this path instead of the default search")
    |> flag("no-config", "", "skip loading the user's init.hl entirely")
    |> option("tabsize", "", "override the tabsize config value")
    |> flag("readonly", "R", "open the file in read-only mode (Save is disabled)")

/// Parse the `:COL` part of a `+LINE:COL` token, given the already-parsed
/// 1-indexed line number `n`.
// Split into two single-match helpers (rather than one nested match)
// per `hica analyse`'s "nested match on maybe" HIGH-severity rule.
fun with_parsed_line(n: int, col_str: string) : maybe<Position> =>
  match parse_int(col_str) {
    None    => None,
    Some(m) => Some(Position { line: max(n - 1, 0), col: max(m - 1, 0) })
  }

/// Parse a `+LINE:COL` token's two numeric parts into a `Position`.
fun parse_line_col(line_str: string, col_str: string) : maybe<Position> =>
  match parse_int(line_str) {
    None    => None,
    Some(n) => with_parsed_line(n, col_str)
  }

/// Parse a `+LINE[:COL]` token into a 0-indexed `Position`. Malformed
/// tokens (non-numeric, too many `:` parts) resolve to `None` rather
/// than erroring.
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

/// Pull the first `+`-prefixed token out of argv, leaving everything
/// else untouched for `cli_parse_args`.
// Order-independent (`hedit +10 file.txt` and `hedit file.txt +10` both
// work). Only the first `+…` token is treated specially; a second one is
// left as a positional (and will fail `std/cli`'s single-[FILE] arg
// check, same as any other stray extra positional).
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
