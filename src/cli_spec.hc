// cli_spec.hc — hedit's command-line surface (M6).
//
// A single optional [FILE] positional. --help/--version come free from
// `std/cli` (cli_help / cli_version_str) — no hedit-side code needed
// beyond wiring the Help/Version arms in main.hc.
//
// Non-goals (deferred to M8): --config/--no-config, --tabsize,
// --readonly, +LINE:COL.

import "std/cli"

pub fun make_spec() : CliSpec =>
  cli("hedit", "0.2.0", "a terminal text editor in hica")
    |> arg("file", "file to open", false)
