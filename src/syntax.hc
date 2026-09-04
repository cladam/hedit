/// M16: a small, single-grammar (hica/koka-flavored), line-by-line lexer.
/// Pure string-slicing, no `chars()`/list-indexing (see M16 journal note on
/// why: keeps this file free of the `items[index]` `exn`-effect pitfall).
/// Carries just enough state across lines — `in_string`/`in_comment` — to
/// span an unterminated string or `/* */` block comment onto the next line.
/// `//` line comments never carry over (they always end at the newline).

/// What a highlighted span represents. `Ident`/`Punct`/`Plain` exist for
/// completeness but are never emitted by `lex_line` today — nothing needs
/// coloring them, so skipping their spans keeps the span lists small.
pub type TokenKind {
  Keyword,
  StringLit,
  Comment,
  NumberLit,
  Ident,
  Punct,
  Plain
}

/// hica/koka reserved words worth coloring — not exhaustive, just the
/// common ones a source file actually uses often.
fun is_keyword(w: string) : bool =>
  w == "fun" || w == "pub" || w == "import" || w == "let" || w == "if" ||
  w == "else" || w == "match" || w == "struct" || w == "type" ||
  w == "return" || w == "spawn" || w == "with" || w == "handle" ||
  w == "var" || w == "in" || w == "extern" || w == "true" || w == "false" ||
  w == "for" || w == "while" || w == "break" || w == "continue" || w == "fn"

fun is_digit_str(s: string) : bool => s >= "0" && s <= "9"

fun is_alpha_str(s: string) : bool => (s >= "a" && s <= "z") || (s >= "A" && s <= "Z")

fun is_ident_start_str(s: string) : bool => is_alpha_str(s) || s == "_"

fun is_ident_str(s: string) : bool => is_ident_start_str(s) || is_digit_str(s)

/// First position `>= pos` where `pred` no longer holds for the single
/// character there, or `length(line)` if `pred` holds to the end.
fun scan_while(line: string, pos: int, pred: (string) -> bool) : int {
  let n = length(line)
  if pos >= n { n }
  else if pred(line[pos: pos + 1]) { scan_while(line, pos + 1, pred) }
  else { pos }
}

/// First unescaped `"` at or after `pos`, or `None` if the line ends
/// first (an unterminated string, carried to the next line).
fun find_string_end(line: string, pos: int) : maybe<int> {
  let n = length(line)
  if pos >= n { None }
  else {
    let c = line[pos: pos + 1]
    if c == "\\" && pos + 1 < n { find_string_end(line, pos + 2) }
    else if c == "\"" { Some(pos) }
    else { find_string_end(line, pos + 1) }
  }
}

/// First `*/` at or after `pos`, or `None` if the line ends first (an
/// unterminated block comment, carried to the next line).
fun find_comment_end(line: string, pos: int) : maybe<int> =>
  if pos > length(line) { None }
  else {
    match index_of(line[pos: ], "*/") {
      None      => None,
      Some(rel) => Some(pos + rel)
    }
  }

/// A `"…"` string starting at `span_start`, scanning for its closing
/// quote from `scan_pos` (after the opening quote, or 0 when the whole
/// line is a continuation of a string opened on a previous line).
fun lex_string(line: string, scan_pos: int, span_start: int) : (list<(int, int, TokenKind)>, bool, bool) =>
  match find_string_end(line, scan_pos) {
    None => ([(span_start, length(line), StringLit)], true, false),
    Some(j) => {
      let endp = j + 1
      let (tail_spans, ts, tc) = lex_normal(line, endp)
      ([(span_start, endp, StringLit)] + tail_spans, ts, tc)
    }
  }

/// A `/* … */` block comment starting at `span_start`, scanning for its
/// closing `*/` from `scan_pos`.
fun lex_block_comment(line: string, scan_pos: int, span_start: int) : (list<(int, int, TokenKind)>, bool, bool) =>
  match find_comment_end(line, scan_pos) {
    None => ([(span_start, length(line), Comment)], false, true),
    Some(j) => {
      let endp = j + 2
      let (tail_spans, ts, tc) = lex_normal(line, endp)
      ([(span_start, endp, Comment)] + tail_spans, ts, tc)
    }
  }

/// Lex `line` from `pos` onward, with no carried-over string/comment.
fun lex_normal(line: string, pos: int) : (list<(int, int, TokenKind)>, bool, bool) {
  let n = length(line)
  if pos >= n { ([], false, false) }
  else {
    let one = line[pos: pos + 1]
    let two = line[pos: min(pos + 2, n)]
    if two == "//" { ([(pos, n, Comment)], false, false) }
    else if two == "/*" { lex_block_comment(line, pos + 2, pos) }
    else if one == "\"" { lex_string(line, pos + 1, pos) }
    else if is_digit_str(one) {
      let endp = scan_while(line, pos + 1, is_digit_str)
      let (tail_spans, ts, tc) = lex_normal(line, endp)
      ([(pos, endp, NumberLit)] + tail_spans, ts, tc)
    }
    else if is_ident_start_str(one) {
      let endp = scan_while(line, pos + 1, is_ident_str)
      let word = line[pos: endp]
      let (tail_spans, ts, tc) = lex_normal(line, endp)
      if is_keyword(word) { ([(pos, endp, Keyword)] + tail_spans, ts, tc) }
      else { (tail_spans, ts, tc) }
    }
    else { lex_normal(line, pos + 1) }
  }
}

/// Tokenise one line, given whether it starts inside an unterminated
/// string/block comment carried over from the previous line. Returns
/// `(row-local (start, end, kind) spans, still-in-string, still-in-comment)`
/// for the caller to thread into the next line.
pub fun lex_line(line: string, in_string: bool, in_comment: bool) : (list<(int, int, TokenKind)>, bool, bool) =>
  if in_comment { lex_block_comment(line, 0, 0) }
  else if in_string { lex_string(line, 0, 0) }
  else { lex_normal(line, 0) }
