// syntax_test.hc — pure tests for the M16 line-by-line lexer.

import "../src/syntax"

test "plain line with no tokens of interest yields no spans" {
  let (spans, ins, inc) = lex_line("x = y + 1", false, false)
  assert(spans == [(8, 9, NumberLit)])
  assert(!ins)
  assert(!inc)
}

test "a keyword is highlighted as a Keyword span" {
  let (spans, _, _) = lex_line("fun add(a, b)", false, false)
  assert(spans == [(0, 3, Keyword)])
}

test "an identifier that merely contains a keyword substring is not highlighted" {
  let (spans, _, _) = lex_line("let letter = 1", false, false)
  assert(spans == [(0, 3, Keyword), (13, 14, NumberLit)])
}

test "a single-line string literal is highlighted, keywords inside it are not" {
  let (spans, ins, _) = lex_line("let s = \"if true\"", false, false)
  assert(spans == [(0, 3, Keyword), (8, 17, StringLit)])
  assert(!ins)
}

test "an unterminated string carries in_string to the next line" {
  let (spans1, ins1, _) = lex_line("let s = \"hello", false, false)
  assert(spans1 == [(0, 3, Keyword), (8, 14, StringLit)])
  assert(ins1)
  let (spans2, ins2, _) = lex_line("world\"", true, false)
  assert(spans2 == [(0, 6, StringLit)])
  assert(!ins2)
}

test "a line comment spans to the end of the line and never carries over" {
  let (spans, ins, inc) = lex_line("let x = 1 // set x", false, false)
  assert(spans == [(0, 3, Keyword), (8, 9, NumberLit), (10, 18, Comment)])
  assert(!ins)
  assert(!inc)
}

test "a block comment on one line is a single Comment span" {
  let (spans, _, inc) = lex_line("/* comment */ let x = 1", false, false)
  assert(spans == [(0, 13, Comment), (14, 17, Keyword), (22, 23, NumberLit)])
  assert(!inc)
}

test "an unterminated block comment carries in_comment to the next line" {
  let (spans1, _, inc1) = lex_line("/* start of a comment", false, false)
  assert(spans1 == [(0, 21, Comment)])
  assert(inc1)
  let (spans2, _, inc2) = lex_line("still comment */ let x = 1", false, true)
  assert(spans2 == [(0, 16, Comment), (17, 20, Keyword), (25, 26, NumberLit)])
  assert(!inc2)
}
