// render.hc — pure ScreenBuffer builder.
//
// M2: real render pass replacing the trivial `build_screen` stub from M1.
// Layout: rows 0..(h-2) are editor content (buffer lines + "~" fill for
// empty rows); row (h-1) is the status line (path + dirty flag, or an
// explicit status_message). Pure: no effects.

import "keys"
import "model"

// Truncate `s` to at most `w` characters (no-op if already shorter).
fun fit_to_width(s: string, w: int) : string =>
  if length(s) > w { s[0:w] } else { s }

// First `n` elements of `xs`, padding with `pad` when `xs` is exhausted.
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

// Display name for a buffer's tab: its path, or "scratch" for an unnamed
// in-memory buffer (M5.5 `NewBuffer` — see actions.hc).
fun buffer_tab_name(buf: TextBuffer) : string =>
  match buf.path { None => "scratch", Some(p) => p }

// One tabline entry per open buffer (active buffer first — see
// `open_buffers` in model.hc), joined with "|". The active tab is
// bracketed (`[scratch]`) so it's visually distinct from the rest.
fun build_tabline(state: EditorState) : string {
  let active_name = buffer_tab_name(state.buffer)
  let bg_names    = map(state.background_buffers, buffer_tab_name)
  join(["[" + active_name + "]"] + bg_names, "|")
}

// Build a ScreenBuffer from `state`. Reads `state.screen_size` for dimensions.
// `cursor_row`/`cursor_col` are the head cursor's position clamped to the
// visible viewport (1-indexed, tabline occupies row 1) — there's no
// scroll-offset tracking yet, so a cursor past the bottom/right edge just
// renders pinned to the last visible row/column instead of scrolling.
pub fun render_editor_to_buffer(state: EditorState) : ScreenBuffer {
  let (w, h)    = state.screen_size
  let buf       = state.buffer
  let n_content = h - 2

  // Each content line truncated to screen width; empty rows filled with "~".
  let text_rows    = map(buf.lines, (l) => fit_to_width(l, w))
  let content_rows = take_or_pad(text_rows, n_content, "~")

  let tabline_row = fit_to_width(build_tabline(state), w)

  // Status line: explicit message wins; fallback is path + dirty flag.
  let path_part   = match buf.path { None => "[No Name]", Some(p) => p }
  let dirty_str   = if buf.is_dirty { " [+]" } else { "" }
  let default_msg = path_part + dirty_str
  let status_msg  = match state.status_message { None => default_msg, Some(m) => m }
  let status_row  = fit_to_width(status_msg, w)

  let cur          = match buf.cursors { [] => Position { line: 0, col: 0 }, [x, .._] => x.pos }
  let visible_line = max(min(cur.line, max(n_content - 1, 0)), 0)
  let visible_col  = max(min(cur.col, max(w - 1, 0)), 0)

  ScreenBuffer {
    width: w,
    height: h,
    lines: [tabline_row] + content_rows + [status_row],
    cursor_row: visible_line + 2,
    cursor_col: visible_col + 1
  }
}

