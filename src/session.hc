/// Session and crash recovery (M23): serialization and deserialization of
/// EditorState (panes, buffers, cursors, scroll lines, and unsaved scratch
/// content) to and from HiLisp s-expressions.

import "keys"
import "model"
import "../lib/hilisp/src/lisp"

// ------------------- String escaping & formatting -------------------------

/// Escape a raw string for HiLisp s-expression representation using display.hc.
fun escape_str_val(s: string) : string =>
  escape_string(s)

/// Format a boolean as a HiLisp literal.
fun bool_to_str(b: bool) : string =>
  if b { "true" } else { "false" }

/// Format an optional string path as an s-expression atom.
fun path_to_sexpr(p: maybe<string>) : string =>
  match p {
    None    => "nil",
    Some(s) => "\"" + escape_str_val(s) + "\""
  }

/// Format an optional anchor position as an s-expression atom.
fun anchor_to_sexpr(a: maybe<Position>) : string =>
  match a {
    None    => "nil",
    Some(pos) => "(anchor " + show(pos.line) + " " + show(pos.col) + ")"
  }

// ------------------- Serialization ----------------------------------------

/// Format a single cursor as `(cursor cid line col anchor sticky)`.
fun serialize_cursor(c: Cursor) : string =>
  "(cursor " + show(c.cid) + " " + show(c.pos.line) + " " + show(c.pos.col) + " " +
    anchor_to_sexpr(c.anchor) + " " + bool_to_str(c.anchor_sticky) + ")"

/// Format a list of cursors into an s-expression.
fun serialize_cursors(cs: list<Cursor>) : string =>
  "(cursors " + join(map(cs, serialize_cursor), " ") + ")"

/// Format buffer lines into `(lines "..." "...")`.
fun serialize_lines(ls: list<string>) : string =>
  "(lines " + join(map(ls, (l) => "\"" + escape_str_val(l) + "\""), " ") + ")"

/// Serialize a TextBuffer to an s-expression. Lines are embedded if the buffer
/// has no path (scratch) or if is_dirty is true, preserving unsaved work.
fun serialize_buffer(buf: TextBuffer) : string {
  let should_embed_lines = buf.is_dirty || match buf.path { None => true, Some(_) => false }
  let lines_sexpr = if should_embed_lines { " " + serialize_lines(buf.lines) } else { "" }
  "(buffer (bid " + show(buf.bid) + ") (path " + path_to_sexpr(buf.path) + ") " +
    "(is-dirty " + bool_to_str(buf.is_dirty) + ") (scroll-line " + show(buf.scroll_line) + ") " +
    serialize_cursors(buf.cursors) + lines_sexpr + ")"
}

/// Serialize a PaneNode layout tree.
// Ratios are stored as integers multiplied by 1000 to avoid float precision issues.
fun serialize_pane_node(node: PaneNode) : string =>
  match node {
    Leaf(leaf_bid) => "(leaf " + show(leaf_bid) + ")",
    Split(axis, ratio, left_child, right_child) => {
      let axis_str = match axis {
        Horizontal => "horizontal",
        Vertical   => "vertical"
      }
      let ratio_int = round(ratio * 1000.0)
      "(split " + axis_str + " " + show(ratio_int) + " " +
        serialize_pane_node(left_child) + " " + serialize_pane_node(right_child) + ")"
    }
  }

/// Serialize the entire editor session state into a readable HiLisp s-expression.
pub fun serialize_session(state: EditorState) : string {
  let all_buffers = [state.buffer] + state.background_buffers
  let buf_sexprs = join(map(all_buffers, serialize_buffer), "\n    ")
  "(session\n" +
    "  (version 1)\n" +
    "  (active-bid " + show(state.buffer.bid) + ")\n" +
    "  (next-bid " + show(state.next_bid) + ")\n" +
    "  (panes " + serialize_pane_node(state.panes) + ")\n" +
    "  (buffers\n    " + buf_sexprs + "))\n"
}

// ------------------- Deserialization helpers ------------------------------

/// Check whether an LVal is an LSym with the given name.
fun is_sym(v: LVal, expected: string) : bool =>
  match v {
    LSym(s, _) => s == expected,
    _          => false
  }

/// Find a tagged sublist `(tag ...)` in a list of LVals and return the rest of that sublist.
fun find_tag_args(items: list<LVal>, tag: string) : maybe<list<LVal>> =>
  match items {
    [] => None,
    [head_val, ..rest] =>
      match head_val {
        LList([sym_val, ..args]) =>
          if is_sym(sym_val, tag) { Some(args) }
          else { find_tag_args(rest, tag) },
        _ => find_tag_args(rest, tag)
      }
  }

/// Extract an integer value from a tagged sublist `(tag <int>)`.
fun find_tag_int(items: list<LVal>, tag: string) : maybe<int> =>
  match find_tag_args(items, tag) {
    Some([LNum(n)]) => Some(n),
    _               => None
  }

/// Extract a boolean value from a tagged sublist `(tag <bool>)`.
fun find_tag_bool(items: list<LVal>, tag: string) : maybe<bool> =>
  match find_tag_args(items, tag) {
    Some([LBool(b)]) => Some(b),
    _                => None
  }

/// Result of parsing an optional path tag.
type PathField {
  PathMissing,
  PathNone,
  PathSome(path_str: string)
}

/// Extract an optional string path from a tagged sublist `(path "..." | nil)`.
fun find_tag_path(items: list<LVal>, tag: string) : PathField =>
  match find_tag_args(items, tag) {
    Some([LStr(s)])    => PathSome(s),
    Some([LNil])       => PathNone,
    Some([LSym(s, _)]) => if s == "nil" { PathNone } else { PathMissing },
    _                  => PathMissing
  }

/// Extract string lines from a tagged sublist `(lines "..." ...)`.
fun parse_lines_list(items: list<LVal>) : list<string> =>
  match items {
    [] => [],
    [LStr(s), ..rest] => [s] + parse_lines_list(rest),
    [_, ..rest]       => parse_lines_list(rest)
  }

/// Parse an anchor expression `(anchor line col)` or `nil`.
fun parse_anchor_val(v: LVal) : maybe<Position> =>
  match v {
    LList([LSym(s, _), LNum(l), LNum(c)]) =>
      if s == "anchor" { Some(Position { line: l, col: c }) } else { None },
    _ => None
  }

/// Parse a single cursor expression `(cursor cid line col anchor sticky)`.
fun parse_one_cursor(v: LVal) : maybe<Cursor> =>
  match v {
    LList([LSym(tag, _), LNum(cid), LNum(l), LNum(c), anchor_val, LBool(sticky)]) =>
      if tag == "cursor" {
        Some(Cursor {
          cid: cid,
          pos: Position { line: l, col: c },
          anchor: parse_anchor_val(anchor_val),
          anchor_sticky: sticky
        })
      } else { None },
    _ => None
  }

/// Parse a list of cursor expressions.
fun parse_cursor_list(items: list<LVal>) : list<Cursor> =>
  match items {
    [] => [],
    [c_val, ..rest] =>
      match parse_one_cursor(c_val) {
        Some(cur) => [cur] + parse_cursor_list(rest),
        None      => parse_cursor_list(rest)
      }
  }

/// Parse a PaneNode from an LVal expression.
fun parse_pane_expr(v: LVal) : maybe<PaneNode> =>
  match v {
    LList([LSym(tag, _), LNum(target_bid)]) =>
      if tag == "leaf" { Some(Leaf(target_bid)) } else { None },
    LList([LSym(tag, _), LSym(axis_sym, _), LNum(ratio_int), left_expr, right_expr]) =>
      if tag == "split" {
        let axis_res = if axis_sym == "horizontal" { Some(Horizontal) }
          else if axis_sym == "vertical" { Some(Vertical) }
          else { None }
        match axis_res {
          None => None,
          Some(ax) => {
            let raw_ratio = to_float(ratio_int) / 1000.0
            let ratio_flt = if raw_ratio < 0.05 { 0.05 } else if raw_ratio > 0.95 { 0.95 } else { raw_ratio }
            match (parse_pane_expr(left_expr), parse_pane_expr(right_expr)) {
              (Some(l_node), Some(r_node)) => Some(Split(ax, ratio_flt, l_node, r_node)),
              _ => None
            }
          }
        }
      } else { None },
    _ => None
  }

/// Parse a single buffer expression `(buffer (bid N) (path ...) ...)`.
fun parse_one_buffer(v: LVal) : maybe<TextBuffer> =>
  match v {
    LList([LSym(tag, _), ..fields]) =>
      if tag == "buffer" {
        let bid_res = find_tag_int(fields, "bid")
        let path_res = find_tag_path(fields, "path")
        let dirty_res = find_tag_bool(fields, "is-dirty")
        let scroll_res = find_tag_int(fields, "scroll-line")
        let cursors_res = match find_tag_args(fields, "cursors") {
          Some(c_items) => {
            let parsed = parse_cursor_list(c_items)
            if length(parsed) > 0 { Some(parsed) } else { None }
          },
          None => None
        }
        let lines_val = match find_tag_args(fields, "lines") {
          Some(l_items) => parse_lines_list(l_items),
          None          => []
        }
        let opt_path = match path_res {
          PathSome(p) => Some(Some(p)),
          PathNone    => Some(None),
          PathMissing => None
        }
        match (bid_res, opt_path, dirty_res, scroll_res, cursors_res) {
          (Some(b_id), Some(b_path), Some(b_dirty), Some(b_scroll), Some(b_cursors)) => {
            let fallback_lines = if length(lines_val) > 0 { lines_val } else { [""] }
            Some(TextBuffer {
              bid: b_id,
              path: b_path,
              lines: fallback_lines,
              cursors: b_cursors,
              is_dirty: b_dirty,
              scroll_line: b_scroll
            })
          },
          _ => None
        }
      } else { None },
    _ => None
  }

/// Parse a list of buffer expressions.
fun parse_buffers_list(items: list<LVal>) : list<TextBuffer> =>
  match items {
    [] => [],
    [buf_val, ..rest] =>
      match parse_one_buffer(buf_val) {
        Some(buf) => [buf] + parse_buffers_list(rest),
        None      => parse_buffers_list(rest)
      }
  }

/// Split buffers into active buffer and background buffers based on active_bid.
fun partition_active_buffer(bufs: list<TextBuffer>, target_bid: int) : (TextBuffer, list<TextBuffer>) =>
  match bufs {
    [] => (new_buffer(0, None), []),
    [first_buf, ..rest] =>
      if first_buf.bid == target_bid {
        (first_buf, rest)
      } else {
        let (found_act, remaining) = partition_active_buffer(rest, target_bid)
        if found_act.bid == target_bid {
          (found_act, [first_buf] + remaining)
        } else {
          (first_buf, rest)
        }
      }
  }

/// Check if a PaneNode references at least one of the restored buffer IDs.
fun pane_has_bid(node: PaneNode, target_bid: int) : bool =>
  match node {
    Leaf(bid) => bid == target_bid,
    Split(_, _, left_node, right_node) =>
      pane_has_bid(left_node, target_bid) || pane_has_bid(right_node, target_bid)
  }

/// Reconstruct the EditorState from parsed components.
fun assemble_editor_state(active_bid: int, next_bid: int, panes_node: PaneNode, bufs: list<TextBuffer>, cfg: Config) : maybe<EditorState> {
  if length(bufs) == 0 { None }
  else {
    let (act_buf, bg_bufs) = partition_active_buffer(bufs, active_bid)
    let validated_panes = if pane_has_bid(panes_node, act_buf.bid) { panes_node } else { Leaf(act_buf.bid) }
    Some(EditorState {
      buffer: act_buf,
      background_buffers: bg_bufs,
      next_bid: max(next_bid, act_buf.bid + 1),
      status_message: None,
      screen_size: (80, 24),
      should_quit: false,
      config: cfg,
      prompt: NoPrompt,
      show_help: false,
      search: NoSearch,
      panes: validated_panes,
      resizing_divider: None,
      undo_tree: None,
      shell_output: None
    })
  }
}
/// Deserialize a HiLisp s-expression string back into an EditorState.
/// Degrades to None on any syntax error, malformed AST, or missing required fields.
pub fun deserialize_session(src: string, cfg: Config) : maybe<EditorState> {
  let tokens = tokenise(src)
  let (ast, _) = parse_tokens(tokens)
  match ast {
    LList([LSym(tag, _), ..entries]) =>
      if tag == "session" {
        let active_bid_res = find_tag_int(entries, "active-bid")
        let next_bid_res = find_tag_int(entries, "next-bid")
        let panes_res = match find_tag_args(entries, "panes") {
          Some([pane_expr]) => parse_pane_expr(pane_expr),
          _                 => None
        }
        let bufs_res = match find_tag_args(entries, "buffers") {
          Some(buf_exprs) => {
            let parsed_bufs = parse_buffers_list(buf_exprs)
            if length(parsed_bufs) > 0 { Some(parsed_bufs) } else { None }
          },
          _ => None
        }
        match (active_bid_res, next_bid_res, panes_res, bufs_res) {
          (Some(act_id), Some(nxt_id), Some(p_tree), Some(b_list)) =>
            assemble_editor_state(act_id, nxt_id, p_tree, b_list, cfg),
          _ => None
        }
      } else { None },
    _ => None
  }
}

// ------------------- Session candidate paths (XDG compliant) -------------

/// Candidate filesystem paths for the session file, in priority order:
/// 1. `$XDG_STATE_HOME/hedit/session.hl`
/// 2. `$HOME/.local/state/hedit/session.hl`
/// 3. `$HOME/.hedit_session.hl`
pub fun session_candidate_paths(state_home: maybe<string>, home: maybe<string>) : list<string> {
  let state_cand = match state_home {
    Some(d) => [d + "/hedit/session.hl"],
    None    => []
  }
  let home_cands = match home {
    Some(h) => [h + "/.local/state/hedit/session.hl", h + "/.hedit_session.hl"],
    None    => []
  }
  state_cand + home_cands
}

/// The default path to write the session file to.
pub fun default_session_path() : maybe<string> {
  let state_home = get_env("XDG_STATE_HOME")
  let home = get_env("HOME")
  match session_candidate_paths(state_home, home) {
    []           => None,
    [p, .._rest] => Some(p)
  }
}

/// Helper to test candidate paths for read access.
fun find_first_readable_session(paths: list<string>) : (maybe<string>, maybe<string>) =>
  match paths {
    [] => (None, None),
    [p, ..rest] =>
      match read_file(p) {
        Ok(content) => (Some(p), Some(content)),
        Err(_)      => find_first_readable_session(rest)
      }
  }

/// Find the first readable session file among candidates.
pub fun find_session_file() : (maybe<string>, maybe<string>) {
  let state_home = get_env("XDG_STATE_HOME")
  let home = get_env("HOME")
  let paths = session_candidate_paths(state_home, home)
  find_first_readable_session(paths)
}

/// Check if an editor session is trivial (single pathless clean buffer with no edits).
pub fun is_trivial_session(state: EditorState) : bool {
  if length(state.background_buffers) > 0 { false }
  else if state.buffer.is_dirty { false }
  else {
    let pane_ok = match state.panes { Leaf(_) => true, _ => false }
    let path_ok = match state.buffer.path { None => true, _ => false }
    let lines_ok = state.buffer.lines == [""] || length(state.buffer.lines) == 0
    pane_ok && path_ok && lines_ok
  }
}

/// Read file content and split into lines, falling back to existing lines on read error.
fun read_named_lines(p: string, fallback: list<string>) {
  match read_file(p) {
    Ok(content) => split_lines(content),
    Err(_)      => fallback
  }
}

/// Populate a restored buffer's lines from disk if it has a path and is not dirty.
fun refresh_restored_buffer(buf: TextBuffer) {
  if buf.is_dirty { buf }
  else {
    match buf.path {
      None    => buf,
      Some(p) => TextBuffer { ...buf, lines: read_named_lines(p, buf.lines) }
    }
  }
}

/// Populate all restored buffers from disk where appropriate.
pub fun refresh_restored_state(state: EditorState) {
  EditorState {
    ...state,
    buffer: refresh_restored_buffer(state.buffer),
    background_buffers: map(state.background_buffers, refresh_restored_buffer)
  }
}

/// Remove the session file from disk if it exists.
pub fun remove_session_file() {
  match default_session_path() {
    None => (),
    Some(p) => {
      let _ = exec("rm -f " + p + " 2>/dev/null")
      ()
    }
  }
}

/// Save session snapshot to the default session path if not trivial.
/// If trivial, removes the session file so subsequent launches start clean.
pub fun save_session_if_needed(state: EditorState) {
  match default_session_path() {
    None => (),
    Some(p) =>
      if is_trivial_session(state) {
        remove_session_file()
      } else {
        let sexpr = serialize_session(state)
        let _ = write_file(p, sexpr)
        ()
      }
  }
}
