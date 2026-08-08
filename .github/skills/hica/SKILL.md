# Hica — Skill Card

> Drop this file into a model's context to teach it idiomatic hica.
> Self-contained. For anything not covered here, run the toolchain or
> consult `docs/` and `examples/`.

---

## 1. What hica is

hica is a statically typed, expression-oriented language that **transpiles to Koka (v3.2.3)**.

```
.hc  →  lexer  →  parser  →  type checker  →  codegen  →  .kk  →  native binary
                                                                   └──→  JavaScript
```

- **Memory**: Koka's **Perceus** deterministic reference counting — no GC, no tracing, no pauses
- **Effects**: IO, `div`, `exn` are tracked structurally by Koka under the hood; hica programmers do not write effect annotations
- **Type inference**: Hindley-Milner — annotations are optional everywhere; annotate for documentation or to resolve ambiguity
- **No null**: absence is always `None : maybe<T>`; null pointer exceptions cannot occur
- **No undefined behaviour**: Perceus RC is safe and deterministic — no use-after-free, no dangling pointers
- **Targets**: native binary (default), JavaScript (`--target=js`)

**Key trade-offs vs similar languages:**

| vs | Trade-off |
|----|-----------|
| Koka | Friendlier syntax and implicit effects; gives up user-defined algebraic effect handlers |
| Rust | No borrow checker / lifetime annotations; gives up fine-grained manual memory layout |
| Python | Static types, no exceptions, deterministic memory; gives up dynamic flexibility |
| Gleam | Brace syntax, loops, mutable `var`; shares the "no null, Result types" philosophy |

---

## 2. Lean on the toolchain

Run code early and often — the compiler is the reference, not this card.

| Command | Description |
|---------|-------------|
| `hica run <file>` | Transpile, compile, and execute a `.hc` file |
| `hica build <file>` | Compile to a native binary |
| `hica check <file>` | Type-check and report errors without running |
| `hica test <file>` | Run all `test "..."` blocks in the file |
| `hica fmt <file>` | Format the file in place |
| `hica repl` | Start an interactive REPL |
| `hica run --target=js <file>` | Compile and run via Node.js |

Error messages point to `.hc` source lines: `hica` remaps Koka line numbers back to the original `.hc` source using `// .hc:N` comments in generated code. All errors reference the `.hc` file.

`hica check` surfaces effect errors and type errors. It is more permissive than `hica test` for generics (see §11).

---

## 3. Syntax cheat sheet

```hica
// Functions
fun add(a: int, b: int) : int => a + b          // arrow body — single expression
fun greet(name: string) {                        // block body — multiple statements
  let msg = "Hello, " + name
  println(msg)
  msg                                            // last expression is the return value
}
pub fun exported() => "visible outside module"  // pub = exported from module

// Variables
let x = 42          // immutable
var count = 0       // mutable
count = count + 1   // reassignment — no `let`/`var` on reassignment

// Lambdas
let sq  = (n) => n * n
let add = (a, b) => a + b
```

**Critical syntax rules:**
- Keyword `fun` (NOT `fn`)
- Return type: `: ReturnType` after params (NOT `->`)
- No `return` keyword — the **last expression is the return value**
- Identifiers: `snake_case` only — hyphens are NOT valid
- Booleans: `true` / `false` (lowercase)
- Boolean operators: `&&` `||` `!` — words `and`/`or`/`not` are plain identifiers, not operators
- String interpolation: `"value is {expr}"` — escape literal braces with `\{` and `\}`
- String/list slicing: `s[n:m]`, `s[n:]`, `s[:m]` — colons, NOT dots
- String concatenation: `+` (NOT `++`)
- Int/float to string: `show(n)` (NOT `str(n)` or `to_string(n)`)
- Types: lowercase — `int`, `string`, `float`, `bool`, `list<T>` (NOT `Int`, `String`, etc.)
- Empty else branch: `else { }` — never `else { () }`

---

## 4. Control flow

All control flow is **expression-based** (returns a value):

```hica
// if / else-if / else
let label = if n < 0 { "neg" } else if n == 0 { "zero" } else { "pos" }

// match — arms separated by commas, wildcard is `_`
// match is an expression — valid as arrow body: fun f(x) => match x { ... }
fun classify(n: int) : string => match n {
  0             => "zero",
  x if x < 0   => "negative",
  1 | 2 | 3    => "small",
  _             => "other"
}

// Range patterns in match arms
fun letter_grade(g: int) : string => match g {
  90..=100 => "A",
  80..=89  => "B",
  70..=79  => "C",
  60..=69  => "D",
  _        => "F"
}

// Loops (statements, not expressions — produce unit)
for i in 0..10 { println(i) }           // exclusive upper bound
for item in my_list { println(item) }   // iterate collection
while cond { do_work() }
repeat(3) { println("hi") }
```

**No early return.** A bare `if cond { Err("msg") }` inside a block body evaluates to `Err(...)` and **discards it** — execution continues. Use `if/else if/else` chains or nested `match` for all code paths.

---

## 5. Types: structs and enums

```hica
// Struct — field access with dot notation
struct Point { x: int, y: int }
let p = Point { x: 3, y: 4 }
println(p.x)

// Struct update: reconstruct fully (no spread yet)
let p2 = Point { x: 10, y: p.y }

// Enum (algebraic data type) — variants matched exhaustively
type Shape {
  Circle(radius: float),
  Rect(width: float, height: float),
  Point
}

fun area(s: Shape) : float => match s {
  Circle(r)   => 3.14159 * r * r,
  Rect(w, h)  => w * h,
  Point       => 0.0
}
```

- Enums require **pattern matching** for field access — dot notation does NOT work on enum variants
- **No type aliases**: `type X = Y` is not valid. Use a named `struct` or pass tuples directly
- Tuple positional access: `.0`, `.1`, `.2` — named fields require `struct`
- Tuple param destructuring in `fun` signatures is NOT supported: `fun swap((a,b))` is a parse error; destructure in the body

---

## 6. Maybe and Result

```hica
// maybe<T> — absence of a value
match find_user(id) {
  Some(user) => println("found: {user}"),
  None       => println("not found")
}

// result<T, E> — success or failure with a message
match read_file("data.txt") {
  Ok(text) => println(text),
  Err(e)   => println("error: {e}")
}

// Combinators
let n = Some("42") |> and_then((s) => parse_int(s)) |> map_maybe((n) => n * 2)
let v = safe_divide(100, 4) |> unwrap_or(0)

// ? operator — short-circuit propagation
fun lookup(db, id) : maybe<string> {
  let entry = find(db, (p) => p.0 == id)?   // returns None early
  Some(entry.1)
}
```

**Combinator API:**
| Function | Works on | Notes |
|----------|----------|-------|
| `and_then(m, f)` | `maybe<T>` ONLY | `f: T -> maybe<U>` |
| `map_maybe(m, f)` | `maybe<T>` | `f: T -> U`, re-wraps in `Some` |
| `unwrap_maybe_or(m, default)` | `maybe<T>` | returns `T` or `default` |
| `is_some(m)` / `is_none(m)` | `maybe<T>` | |
| `and_then_result(r, f)` | `result<T,E>` ONLY | `f: T -> result<U,E>` |
| `map_result(r, f)` | `result<T,E>` | `f: T -> U`, re-wraps in `Ok` |
| `unwrap_or(r, default)` | `result<T,E>` ONLY | returns `T` or `default` |
| `unwrap(r)` | `result<T,E>` | panics if `Err` |
| `is_ok(r)` / `is_err(r)` | `result<T,E>` | |

**Never mix:** `unwrap_or` on `maybe`, `and_then` on `result`, `and_then_result` on `maybe` — all are type errors.

**`and_then` / `and_then_result` pattern** — when the function you want to apply *itself* returns a wrapped value, use `and_then`/`and_then_result` to avoid double-wrapping (`maybe<maybe<T>>`). It is `flat_map` for wrapped types:

```hica
// WITHOUT and_then: map_maybe would give maybe<maybe<int>>
// WITH and_then: stays flat
let result = Some("42")
  |> and_then((s) => parse_int(s))    // parse_int returns maybe<int>
  |> map_maybe((n) => n * 2)          // transform the int inside
```

**`?` operator — three constraints:**
1. The enclosing function **must have a return type annotation** — the compiler needs it
2. The wrapper type must match: `?` on `maybe` only inside a `maybe`-returning function
3. **Cannot be used in `main()`** — `main()` returns `()`. Move fallible logic into a helper

```hica
fun add_strings(a: string, b: string) : maybe<int> {  // annotation required
  let x = parse_int(a)?   // returns None early if fails
  let y = parse_int(b)?
  Some(x + y)
}
```

---

## 7. Lists and higher-order functions

```hica
let nums    = [1, 2, 3, 4, 5]
let squares = map(nums, (x) => x * x)
let evens   = filter(nums, (x) => x % 2 == 0)
let total   = fold(nums, 0, (acc, x) => acc + x)

// Range list literals (prelude — no import needed)
let a = [1..10]    // [1..9]   exclusive upper bound
let b = [1..=10]   // [1..10]  inclusive upper bound

// List patterns in match
fun sum(xs: list<int>) : int => match xs {
  []           => 0,
  [x, ..rest]  => x + sum(rest)
}
```

```hica
// concat: flatten one level of nesting
let nested = [[1, 2], [3, 4], [5, 6]]
println(concat(nested))   // [1, 2, 3, 4, 5, 6]

// flat_map: map + flatten in one step (reach for it when your function returns a list)
let sentences = ["hello world", "foo bar"]
let words = flat_map(sentences, (s) => split(s, " "))
// ["hello", "world", "foo", "bar"]

// Point-free style: drop the lambda when you're just forwarding the argument
fun is_even(x) => x % 2 == 0
fun square(x)  => x * x
let result = [1..5] |> filter(is_even) |> map(square)   // [4, 16]
```

- Use `foreach` for **side-effectful** iteration, not `map`
- `map` returns `list<T>` — if you only want side effects, use `foreach`
- `head(xs)` returns `maybe<T>`, NOT `T` — use `head_or(xs, default)` from `import "std/list"`
- List spread `[x, ..rest]` is **pattern position only** — in expressions use `[x] + list` to prepend
- `concat` flattens one level; `flat_map(xs, f)` is `concat(map(xs, f))` — prefer `flat_map` in pipes

---

## 8. The `|>` pipe operator

```hica
// |> and .f() are equivalent — both desugar to f(a)
let a = [1,2,3,4,5]
  |> filter((x) => x % 2 == 0)
  |> map((x) => x * 10)
  |> fold(0, (acc, x) => acc + x)

// dot-call style (same result)
let b = [1,2,3,4,5]
  .filter((x) => x % 2 == 0)
  .map((x) => x * 10)
  .fold(0, (acc, x) => acc + x)
```

- `a |> f` → `f(a)` (single-arg)
- `a |> f(b)` → `f(a, b)` (extra args, piped value is FIRST arg)
- `a.f(b)` → `f(a, b)` (dot-call, same)
- Use `|>` for single-argument steps; use `.f()` when passing extra arguments
- **Precedence**: `|>` is very low — wrap in parens or use `let` when combining with `+` or `==`
- `_or` functions (2-arg) can't be piped — call as `str_or(expr, default)` not `expr |> str_or(default)`

---

## 9. Idioms

Write hica in a functional style: small pure functions composed with `|>`. Avoid mutable state unless you need it.

```hica
// Default to let; use var only when state genuinely changes
let total = fold(scores, 0, (acc, x) => acc + x)

// Structs are immutable — "update" by constructing a new value
fun add_score(p: Player, points: int) : Player =>
  Player { name: p.name, score: p.score + points }

// Name predicates and transformations — use point-free in pipes
fun passing(s: Student) : bool => s.grade >= 60
let passing_students = filter(students, passing)

// Pipe multi-step transformations left to right
let result = students
  |> filter(passing)
  |> map((s) => s.grade)
  |> fold(0, (acc, g) => acc + g)

// Use flat_map when a step fans out one element to many
let all_words = sentences |> flat_map((s) => split(s, " "))

// Use and_then to chain steps that each return maybe/result — keeps the chain flat
let value = Some("42")
  |> and_then((s) => parse_int(s))
  |> map_maybe((n) => n * 2)

// Use ? for fallible helpers — never in main()
fun parse_both(a: string, b: string) : maybe<int> {
  let x = parse_int(a)?
  let y = parse_int(b)?
  Some(x + y)
}

// Recursive functions over lists use [x, ..rest] split
fun contains(xs, target) => match xs {
  []          => false,
  [x, ..rest] => x == target || contains(rest, target)
}

// Recursive enums for tree-shaped data
type Tree {
  Leaf,
  Node(value: int, left: Tree, right: Tree)
}
fun tree_sum(t: Tree) : int => match t {
  Leaf          => 0,
  Node(v, l, r) => v + tree_sum(l) + tree_sum(r)
}
```

| Concept | hica idiom |
|---------|------------|
| Immutable data | `let` by default, `var` when needed |
| Transformation | `map`, `filter`, `fold` |
| Flatten / fan-out | `concat` (flatten), `flat_map` (map + flatten) |
| Chaining wrapped values | `and_then` (maybe), `and_then_result` (result) |
| Early exit | `?` operator in typed helper (not in `main`) |
| Composition | `\|>` pipe operator |
| Point-free | pass named function directly: `filter(xs, is_even)` |
| Tree data | recursive `type` + recursive `fun` |

---

## 10. Prelude (always available, no import)

```
println  eprintln  print  show  show_fixed
length  str_length  map  filter  fold  foreach  zip
head  tail  reverse  sort  range  range_inc
is_empty  max  min  abs
parse_int  parse_float
split  trim  to_upper  to_lower  starts_with  ends_with  contains  replace  join  lines
Some  None  Ok  Err
unwrap  unwrap_or  unwrap_maybe_or  is_some  is_none  is_ok  is_err
map_maybe  and_then  map_result  and_then_result  map_err
exit  get_args  get_env
```

**Key signatures:**
- `length(xs)` — works on both `list<T>` and `string`
- `head(xs: list<T>) : maybe<T>` — returns `maybe<T>`; use `head_or` from `std/list` for a default
- `min(a, b) : int` and `max(a, b) : int` — **two args**, not a list
- `is_empty` — overloaded for both `string` and `list<T>`
- Do NOT `import "std/io"` just to use `println` — it's already in the prelude

---

## 11. Standard library imports

```hica
import "std/io"         // read_file, write_file, read_lines, write_lines, exec, exec_lines
import "std/list"       // head_or, zip_with, flatten, flat_map, index_of, char_to_string
import "std/string"     // show_float, char_to_string, from_chars, index_of
import "std/datetime"   // date/time functions
import "std/env"        // env_or, env_require, env_int
import "std/cli"        // CLI argument parsing
import "../src/mymod"   // relative path — no .hc extension
```

**`std/io` function signatures:**

| Function | Returns | Notes |
|----------|---------|-------|
| `read_file(path)` | `result<string, string>` | match on `Ok`/`Err` |
| `write_file(path, content)` | `()` | panics on failure |
| `read_lines(path)` | `list<string>` | panics on missing file — do NOT match `Ok`/`Err` |
| `write_lines(path, lines)` | `()` | panics on failure |
| `exec(cmd)` | `result<string, string>` | runs shell command, returns stdout or error |
| `exec_lines(cmd)` | `result<list<string>, string>` | returns stdout as lines |

**Known stdlib gaps:**
- No `char_at(s, i)` or `drop_prefix(s, n)` — use `s[i:i+1]` for single chars, `s[n:]` to drop prefix
- No `get_cwd()` — use `get_env("PWD")` (Unix) or `exec("pwd")` (cross-platform)
- No `return` keyword — restructure with `match` chains or `and_then_result`
- `split(s, "")` does NOT yield individual characters — use `s[i:i+1]` with a cursor index

---

## 12. Multi-file libraries

Every function in a library `.hc` file must be `pub`. Non-pub functions cause "undefined variable" when the module is imported.

```hica
// lib/greet.hc
pub fun greet(name: string) : string =>
  "Hello, " + name

pub fun shout(name: string) : string =>
  to_upper(greet(name))
```

```hica
// main.hc
import "../lib/greet"

fun main() {
  println(greet("world"))
  println(shout("world"))
}
```

For larger libraries use a barrel module:

```hica
// mylib/mylib.hc  — re-exports everything
pub import "mylib/types"
pub import "mylib/parser"
pub import "mylib/api"
```

Callers then `import "mylib/mylib"` to get the full surface.

---

## 13. Testing

Tests live alongside implementation code. Run with `hica test <file>`.

```hica
test "addition is commutative" {
  assert(add(2, 3) == add(3, 2))
}

test "word count" {
  let r = count_words("hello world hello")
  assert(length(r) == 2)
}
```

- Use `assert(bool_expr)` — **do NOT** pipe into `assert` or use `assert(match ...)` directly
- Assign to `let` first: `let r = x |> f |> g; assert(r == expected)`
- `assert(match ...)` breaks — use `let r = match ...; assert(r == ...)`
- Each `test` block has an **independent type-inference scope** (see §13)

---

## 14. Generics — scoping rules

hica's type inference is **file-scoped in test mode**: all top-level `fun` declarations and `main()` share one inference context. Only `test` blocks are independent.

| Scenario | Works? |
|----------|--------|
| Different `test` blocks each use `id` with different types | ✓ each test block is independent |
| Same `test` block calls `id(42)` and `id("hello")` | ✓ |
| `main()` uses `id(42)`, a test block uses `id("hello")` | ✗ shared context |
| `main()` calls `id(42)` then `id("hello")` | ✗ locked to `int` after first call |
| Two top-level helpers `use_int()` and `use_str()` calling same generic | ✗ top-level funs share context |

**Correct pattern** — omit `main()` entirely from files with multi-type generic tests:

```hica
// generic_tests.hc — NO main(), only test blocks
fun id(x) => x

test "int"    { assert(id(42) == 42) }
test "string" { assert(id("hello") == "hello") }
```

---

## 15. Project layout

```
hica.hml           # manifest: name, version, dependencies, description
src/main.hc        # entry point (or whatever entry: names)
src/               # source files
lib/               # library modules
tests/             # additional test files
examples/          # runnable examples
```

```hml
# hica.hml — HML format (hica's own config language)
@project {
    name: "my-project"
    version: "0.1.0"
    license: "MIT"
    entry: "src/main.hc"
}

@dependencies {
}

@description {
    summary: "What this project does"
    author: "yourname"
    homepage: "https://www.hica.dev"
    repository: "https://github.com/yourname/my-project"
}
```

Use `hica add <package>` to add dependencies and `hica fetch` to download them.

---

## 16. Common pitfalls

| Wrong | Right |
|-------|-------|
| `fn foo()` | `fun foo()` |
| `foo() -> int` | `fun foo() : int` |
| `s[n..m]` slice (dots) | `s[n:m]` (colons) — `..` is list-range only |
| `if cond then x else y` | `if cond { x } else { y }` — no `then` keyword |
| `return x` anywhere | no `return` keyword — last expression is the value |
| `"a" ++ "b"` | `"a" + "b"` |
| `str(n)` | `show(n)` |
| `else { () }` | `else { }` |
| `my-variable` | `my_variable` — no hyphens |
| `a and b`, `a or b` | `a && b`, `a \|\| b` |
| `assert(x \|> f == val)` | `let r = x \|> f; assert(r == val)` |
| `assert(match ...)` | `let r = match ...; assert(r == ...)` |
| `items[i]` list index | recursive pattern match `[x, ..rest]` |
| `unwrap_or` on `maybe<T>` | `unwrap_maybe_or(m, default)` |
| `and_then` on `result<T,E>` | `and_then_result(r, f)` |
| `and_then_result` on `maybe<T>` | `and_then(m, f)` |
| `map_result(plain_value, f)` where value is not a `result` | just call `f(value)` directly |
| `let (a, b) = some_result` | `match some_result { Ok((a, b)) => ..., Err(e) => ... }` |
| `let rec aux = ...` local recursive function | top-level `fun aux(...)` — no local recursion |
| `fun swap((a, b)) => ...` tuple param destructuring | `fun swap(pair) { match pair { (a, b) => ... } }` |
| `tok.field` on an enum variant | pattern match: `match tok { Variant(v) => v, _ => default }` |
| `type Cursor = (string, int)` type alias | hica has no type aliases — use `struct Cursor { s: string, pos: int }` |
| `c.pos` on a tuple | tuples use positional access `.0` `.1`; use `struct` for named fields |
| `"{"` or `"}"` bare in strings/patterns | escape: `"\{"` `"\}"` — unescaped braces trigger interpolation |
| `Ok(value, cursor)` two-arg Ok | `Ok` takes ONE arg: `Ok((value, cursor))` |
| `show(x)` in interpolation with generic `x` | use `"{x}"` directly — interpolation calls show implicitly |
| Calling `id(42)` then `id("hello")` in `main()` | use separate `test` blocks for multi-type generic usage |
| Top-level helpers to work around generics | still shares context — use separate `test` blocks |
| `bare if { Err(...) }` for early exit in a block | use `if/else if/else` chains or nested `match` |
| Match-bound variable used outside its match arm | move usage inside the arm or bind the match result |
| `import "std/io"` just to use `println` | `println` is in the prelude — no import needed |
| Non-`pub` function in a library | mark all exported functions `pub` |

---

## 17. Canonical example

```hica
// word_count.hc — count word frequencies from a string
import "std/list"

struct WordEntry { word: string, count: int }

fun increment_count(entries: list<WordEntry>, w: string) : list<WordEntry> =>
  match entries {
    [] => [WordEntry { word: w, count: 1 }],
    [e, ..rest] =>
      if e.word == w {
        [WordEntry { word: w, count: e.count + 1 }] + rest
      } else {
        [e] + increment_count(rest, w)
      }
  }

fun count_words(text: string) : list<WordEntry> =>
  fold(split(trim(text), " "), [], (acc, w) =>
    if is_empty(w) { acc } else { increment_count(acc, w) }
  )

fun show_entry(e: WordEntry) : string => "{e.word}: {show(e.count)}"

fun main() {
  let text = "the quick brown fox jumps over the lazy dog the fox"
  let counts = count_words(text)
  foreach(counts, (e) => println(show_entry(e)))
}

test "empty string gives empty list" {
  let result = count_words("")
  assert(length(result) == 0)
}

test "single word counted once" {
  let result = count_words("hello")
  assert(length(result) == 1)
}
```

---

## 18. When in doubt

- `hica check <file>` — type-check without running
- `hica run <file>` — run and see; the runtime error will clarify
- `examples/` — runnable `.hc` files covering most language features
- `docs/language-reference.md` — full syntax reference
- `docs/standard-library.md` — stdlib API
- `documentation/developer-guide.md` — compiler internals
- Spec: the generated `.kk` file (keep with `--generate`) shows exactly what hica emits

The Modelfile at the repo root is the extended version of this card formatted for Ollama/local models. This file is the canonical source.

---

## 19. AI Coding & Behavioral Guidelines

To produce high-quality, bug-free, and idiomatic hica code, you must strictly follow these cognitive and behavioral guidelines before and during code generation:

1. **Strict Language Contrast (No Syntax Blending)**:
   - Always remember that hica is NOT Rust, Python, Gleam, or Koka.
   - If tempted to write `fn` or `def`, force yourself to write `fun`.
   - If tempted to write `->` for return types, write `: ReturnType`.
   - If tempted to write `and`, `or`, or `not`, use `&&`, `||`, and `!`.
   - If tempted to write `return`, restructure the code as nested `match` chains, `if/else`, or `and_then_result` pipelines.

2. **Pre-Generation Checking Checklist**:
   - Before outputting any hica code, review the **Common Pitfalls** section.
   - Check if you have used any generic functions inside `main()` with more than one concrete type.
   - Verify that all string literals containing literal braces `{` or `}` have them escaped as `\{` and `\}`. This includes all error strings, match patterns, and helper strings.
   - Verify that you are not using index brackets on collections (e.g., `xs[i]`). Indexing on lists via brackets raises partial `exn` exception effects in Koka and aborts compilation of pure/total hica functions. All list decompositions must use safe pattern matching like `match list { [p0, p1, p2] => ... }` or `[head, ..tail]` recursion.

3. **Precedence Warnings**:
   - **Crucial `|>` Precedence**: `|>` has extremely low precedence (lower than function application and comma arguments). Never write `assert_eq(compare(...) |> unwrap, -1)` or `assert(eq(...) |> unwrap)`. These parse as `assert_eq(compare(...), -1) |> unwrap` and `(assert(eq(...))) |> unwrap`. Always use dot-called `.unwrap()` syntax instead: `assert_eq(compare(...).unwrap(), -1)` or `assert(eq(...).unwrap())`.

4. **Factual API Anchoring**:
   - Do NOT assume any functions or library modules exist unless they are explicitly listed in the **Prelude** or **Stdlib** documentation.
   - There is no `drop_prefix` function—use `s[n:]` slicing syntax instead.
   - There is no `char_at` function—use `s[i:i+1]` slicing syntax instead.

5. **Functional & Pipeline Composition**:
   - Prefer left-to-right pipelines (`|>`) and dot-called chaining (`.map()`, `.filter()`) over mutable `var` state and complex `while` loops whenever possible.
   - Keep functions small, pure, and focused on single-responsibility transformations.
