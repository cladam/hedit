/// Pure ScreenBuffer builder. Layout: rows 0..(h-2) are editor content
/// (buffer lines + "~" fill for empty rows); row (h-1) is the status
/// line (path + dirty flag, or an explicit status_message).

import "keys"
import "model"
import "hilisp_host"

/// Truncate `s` to at most `w` characters (no-op if already shorter).
fun fit_to_width(s: string, w: int) : string =>
  if length(s) > w { s[0:w] } else { s }

/// First `n` elements of `xs`, padding with `pad` when `xs` is exhausted.
fun take_or_pad(xs: list<string>, n: int, pad: string) : list<string> {
  if n <= 0 {
    []
  } else {
    match xs {
      []          => [pad] + take_or_pad([], n - 1, pad),
      [x, ..rest] => [x]   + take_or_pad(rest, n - 1, pad)
    }
  }
}

/// Drop the first `n` elements of `xs` (no-op past the end).
fun drop_n(xs: list<string>, n: int) : list<string> =>
  if n <= 0 { xs } else {
    match xs {
      []          => [],
      [_, ..rest] => drop_n(rest, n - 1)
    }
  }

/// The vertical scroll offset (first visible buffer line).
// A pure function of the cursor line + viewport height with no extra
// `EditorState` field to keep in sync: once the cursor moves past the
// last row of the first page, the offset grows one line at a time so
// the cursor's line is always the last visible row — smooth per-line
// scrolling rather than a jump to the next full page.
fun scroll_offset(n_content: int, line: int) : int =>
  if n_content <= 0 { 0 } else { max(0, line - n_content + 1) }

/// Display name for a buffer's tab: its path, or "scratch" for an
/// unnamed in-memory buffer.
fun buffer_tab_name(buf: TextBuffer) : string =>
  match buf.path { None => "scratch", Some(p) => p }

/// One tabline entry per open buffer (active buffer first), joined
/// with "|". The active tab is bracketed (`[scratch]`).
fun build_tabline(state: EditorState) : string {
  let active_name = buffer_tab_name(state.buffer)
  let bg_names    = map(state.background_buffers, buffer_tab_name)
  join(["[" + active_name + "]"] + bg_names, "|")
}

/// Status-row label for an active Save-As/Open/Find prompt (M9/M12),
/// replacing the normal path/dirty-flag or status-message row while typing.
fun prompt_label(p: Prompt) : string =>
  match p {
    NoPrompt           => "",
    SaveAsPrompt(t, _) => "Save as: " + t,
    OpenPrompt(t, _)   => "Open: " + t,
    FindPrompt(t, _)   => "Find: " + t,
    VSplitPrompt(t, _) => "VSplit: " + t,
    HSplitPrompt(t, _) => "HSplit: " + t
  }

/// Length of the fixed label prefix in front of the typed text —
/// needed to place the real cursor at the right screen column.
fun prompt_prefix_len(p: Prompt) : int =>
  match p {
    NoPrompt           => 0,
    SaveAsPrompt(_, _) => length("Save as: "),
    OpenPrompt(_, _)   => length("Open: "),
    FindPrompt(_, _)   => length("Find: "),
    VSplitPrompt(_, _) => length("VSplit: "),
    HSplitPrompt(_, _) => length("HSplit: ")
  }

/// The prompt's own cursor column within its typed text.
fun prompt_cursor_col(p: Prompt) : int =>
  match p {
    NoPrompt           => 0,
    SaveAsPrompt(_, c) => c,
    OpenPrompt(_, c)   => c,
    FindPrompt(_, c)   => c,
    VSplitPrompt(_, c) => c,
    HSplitPrompt(_, c) => c
  }

// ------------------- Find match highlighting (M12) -------------------------
// `ScreenBuffer.highlights` carries `(row, start_col, end_col)` triples for
// every search match currently visible in the viewport — `main.hc`'s
/// `render_native` paints each span with `theme.search_match_bg`. Kept as
// plain (row, col) data here (not ANSI) so `ScreenBuffer` stays plain text,
// matching the existing tabline/status/cursor-line styling split.

/// Matches carried by `state.search`, or `[]` outside an active search.
fun active_matches(state: EditorState) : list<SearchMatch> =>
  match state.search {
    NoSearch                  => [],
    ActiveSearch(_, matches, _) => matches
  }

/// The active query's length, or 0 outside an active search.
fun active_query_len(state: EditorState) : int =>
  match state.search {
    NoSearch               => 0,
    ActiveSearch(q, _, _) => length(q)
  }

/// Translate one buffer-space `SearchMatch` into a screen-space
/// `(row, start_col, end_col)` highlight, or `None` if it falls outside
/// the visible viewport (scrolled off, or past the right edge).
fun match_to_highlight(m: SearchMatch, offset: int, n_content: int, w: int, qlen: int) : maybe<(int, int, int)> {
  let row_idx = m.line - offset
  if row_idx < 0 || row_idx >= n_content || m.col >= w { None }
  else { Some((row_idx + 2, m.col, min(m.col + qlen, w))) }
}

/// Every visible match's highlight span, dropping ones scrolled out of view.
fun matches_to_highlights(matches: list<SearchMatch>, offset: int, n_content: int, w: int, qlen: int) : list<(int, int, int)> =>
  match matches {
    [] => [],
    [m, ..rest] =>
      match match_to_highlight(m, offset, n_content, w, qlen) {
        None    => matches_to_highlights(rest, offset, n_content, w, qlen),
        Some(h) => [h] + matches_to_highlights(rest, offset, n_content, w, qlen)
      }
  }

/// The full set of highlight spans for the current frame — `[]` outside
/// an active search or once every match has scrolled out of view.
fun search_highlights(state: EditorState, offset: int, n_content: int, w: int) : list<(int, int, int)> =>
  matches_to_highlights(active_matches(state), offset, n_content, w, active_query_len(state))

/// Build a ScreenBuffer from `state`'s normal (non-help) editing view.
// `cursor_row`/`cursor_col` are the head cursor's position clamped to the
// visible viewport (1-indexed, tabline occupies row 1). Vertical scrolling
// (see `scroll_offset`) follows the cursor line by line once it goes past
// the first page, computed fresh each frame from the cursor position alone
// (no persisted scroll state). A cursor past the right edge still pins to
// the last visible column rather than scrolling horizontally. While a
// Save-As/Open prompt (M9) is active, the status row shows the prompt
// label instead and the real cursor tracks the end of the typed text.
fun render_normal_buffer(state: EditorState) : ScreenBuffer {
  let (w, h)    = state.screen_size
  let buf       = state.buffer
  let n_content = h - 2

  let cur    = match buf.cursors { [] => Position { line: 0, col: 0 }, [x, .._] => x.pos }
  let offset = scroll_offset(n_content, cur.line)

  // Each content line truncated to screen width; empty rows filled with "~".
  let text_rows    = map(drop_n(buf.lines, offset), (l) => fit_to_width(l, w))
  let content_rows = take_or_pad(text_rows, n_content, "~")

  let tabline_row = fit_to_width(build_tabline(state), w)

  // Status line: an active prompt wins; otherwise an explicit message,
  // falling back to path + dirty flag.
  let path_part   = match buf.path { None => "[No Name]", Some(p) => p }
  let dirty_str   = if buf.is_dirty { " [+]" } else { "" }
  let default_msg = path_part + dirty_str
  let status_msg  = match state.status_message { None => default_msg, Some(m) => m }
  let status_row  = match state.prompt {
    NoPrompt => fit_to_width(status_msg, w),
    _        => fit_to_width(prompt_label(state.prompt), w)
  }

  let visible_line = max(min(cur.line - offset, max(n_content - 1, 0)), 0)
  let visible_col  = max(min(cur.col, max(w - 1, 0)), 0)

  let (crow, ccol) = match state.prompt {
    NoPrompt => (visible_line + 2, visible_col + 1)
    _        => (h, min(prompt_prefix_len(state.prompt) + prompt_cursor_col(state.prompt) + 1, w))
  }

  ScreenBuffer {
    width: w,
    height: h,
    lines: [tabline_row] + content_rows + [status_row],
    cursor_row: crow,
    cursor_col: ccol,
    highlights: search_highlights(state, offset, n_content, w)
  }
}

// ------------------- Help overlay (M10) -----------------------------------
//
// A full-screen listing of every currently-bound chord, generated from the
// live `state.config.bindings` (not a hardcoded string) so a user's HiLisp
// `(bind ...)` remaps show up correctly. Any key closes it — see
// `actions.hc::resolve_help_action`.

/// One row: "Ctrl-s  ->  save".
// Reuses hilisp_host.hc's chord/action name helpers so the label matches
// exactly what `(bind ...)`/`(get ...)` see.
fun format_binding(b: (KeyChord, Action)) : string =>
  chord_to_str(b.0) + "  ->  " + action_to_string(b.1)

/// Build the full-screen help overlay ScreenBuffer listing every
/// currently-bound chord.
pub fun render_help_buffer(state: EditorState) : ScreenBuffer {
  let (w, h)       = state.screen_size
  let n_content    = h - 2
  let title_row    = fit_to_width("Keybindings — press any key to close", w)
  let binding_rows = map(state.config.bindings, (b) => fit_to_width(format_binding(b), w))
  let content_rows = take_or_pad(binding_rows, n_content, "")
  let footer_row   = fit_to_width("hedit", w)
  ScreenBuffer {
    width: w,
    height: h,
    lines: [title_row] + content_rows + [footer_row],
    cursor_row: 1,
    cursor_col: 1,
    highlights: []
  }
}

/// Build the ScreenBuffer for the current frame, dispatching on
/// `state.show_help` ahead of the normal render pass.
pub fun render_editor_to_buffer(state: EditorState) : ScreenBuffer =>
  if state.show_help { render_help_buffer(state) } else { render_normal_buffer(state) }
