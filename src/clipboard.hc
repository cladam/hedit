/// OS clipboard integration for the real editor handler.
///
/// Tool selection is kept pure so priority and incomplete command pairs can
/// be tested without depending on the host running the test suite.

/// Whether `name` occurs in the supplied executable list.
fun tool_available(tools: list<string>, name: string) : bool =>
  match tools {
    []          => false,
    [x, ..rest] => if x == name { true } else { tool_available(rest, name) }
  }

/// Select the highest-priority complete clipboard command pair.
pub fun choose_clipboard_tool(tools: list<string>) : maybe<(string, string)> {
  if tool_available(tools, "pbcopy") && tool_available(tools, "pbpaste") {
    Some(("pbcopy", "pbpaste"))
  } else if tool_available(tools, "wl-copy") && tool_available(tools, "wl-paste") {
    Some(("wl-copy", "wl-paste -n"))
  } else if tool_available(tools, "xclip") {
    Some(("xclip -selection clipboard -i", "xclip -selection clipboard -o"))
  } else if tool_available(tools, "xsel") {
    Some(("xsel -b -i", "xsel -b -o"))
  } else {
    None
  }
}

/// Whether an executable is available on PATH.
fun success_marker() : string =>
  "__HEDIT_CLIPBOARD_COMMAND_OK__"

/// Run a shell command and return its exact output only on exit status zero.
fun successful_output(cmd: string) =>
  match exec(cmd + " && printf '" + success_marker() + "'") {
    Err(_) => None,
    Ok(out) =>
      if ends_with(out, success_marker()) {
        Some(out[0:length(out) - length(success_marker())])
      } else {
        None
      }
  }

/// Whether an executable is available on PATH.
fun command_exists(name: string) =>
  match successful_output("command -v " + name + " >/dev/null 2>&1") {
    Some(_) => true,
    None    => false
  }

/// Keep the executable names that are currently available on PATH.
fun detected_tools(names: list<string>) =>
  match names {
    []          => [],
    [x, ..rest] =>
      if command_exists(x) { [x] + detected_tools(rest) }
      else { detected_tools(rest) }
  }

/// Detect the highest-priority complete clipboard command pair on this host.
pub fun detect_clipboard_tool() {
  let tools = detected_tools(["pbcopy", "pbpaste", "wl-copy", "wl-paste", "xclip", "xsel"])
  choose_clipboard_tool(tools)
}

/// Remove a temporary clipboard file.
fun remove_temp(path: string) {
  let _ = exec("rm -f '" + path + "' 2>/dev/null")
}

/// Feed a temporary file to the selected clipboard setter, then remove it.
fun set_from_temp(set_cmd: string, path: string) {
  let result = successful_output(set_cmd + " < '" + path + "'")
  remove_temp(path)
  match result {
    Some(_) => true,
    None    => false
  }
}

/// Finish a clipboard write after the temporary file creation attempt.
fun write_temp(set_cmd: string, path: string, text: string) =>
  match write_file(path, text) {
    Ok(_)  => set_from_temp(set_cmd, path),
    Err(_) => { remove_temp(path); false }
  }

/// Create and populate the temporary file used by a clipboard setter.
fun set_with_command(set_cmd: string, text: string) =>
  match successful_output("mktemp") {
    None           => false,
    Some(raw_path) => write_temp(set_cmd, trim(raw_path), text)
  }

/// Write text to the OS clipboard. Returns false when unavailable or failed.
pub fun os_clipboard_set(tool: maybe<(string, string)>, text: string) =>
  match tool {
    None               => false,
    Some((set_cmd, _)) => set_with_command(set_cmd, text)
  }

/// Read clipboard text with one concrete getter command.
fun get_with_command(get_cmd: string, fallback: string) =>
  match successful_output(get_cmd) {
    Some(out) => out,
    None      => fallback
  }

/// Read exact text from the OS clipboard, falling back on any failure.
pub fun os_clipboard_get(tool: maybe<(string, string)>, fallback: string) =>
  match tool {
    None                => fallback,
    Some((_, get_cmd)) => get_with_command(get_cmd, fallback)
  }
