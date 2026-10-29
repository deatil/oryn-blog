# Jinja cheat sheet

`package jinja` is a standalone Jinja 3.x template engine: supporting tags, filters, tests, globals, template inheritance, macros, autoescaping, and error reporting. Guidedog uses it to render HTML templates without requiring a Python environment.

```odin
package main

import "core:fmt"
import "lib/jinja"

main :: proc() {
    env := jinja.create_environment({autoescape = true,
        loader = jinja.filesystem_loader({"themes/mine", "themes/basic"})})
    defer jinja.destroy_environment(&env)

    t, err := jinja.load_template(&env, "page.html")          // cached per environment
    if err.kind != .None { fmt.eprint(jinja.format_error(err)); return }

    ctx := jinja.dict()
    jinja.set(ctx, "title", jinja.str("Hello <World>"))
    jinja.set(ctx, "pages", jinja.list(jinja.str("a"), jinja.str("b")))
    out, rerr := jinja.render(&t, ctx)                         // out uses context.allocator
    if rerr.kind != .None { fmt.eprint(jinja.format_error(rerr)); return }
    fmt.println(out)
}
```

## Environment

| Procedure | Does |
|---|---|
| `create_environment(options) -> Environment` | filters, tests, globals and a template cache |
| `destroy_environment(&env)` | frees the cache, tables and the loader |
| `load_template(&env, name) -> (Template, Error)` | through the loader; cached |
| `parse_template(&env, name, source) -> (Template, Error)` | from a string; not cached |
| `add_template(&env, name, source) -> Error` | parse and cache, so `extends`/`include` find it |
| `render(&t, ctx) -> (string, Error)` | `ctx` is a dict value (or nothing) |
| `render_source(&env, source, ctx) -> (string, Error)` | parse and render once, caching nothing |
| `evaluate(&env, "a.b + 1", ctx) -> (Value, Error)` | one expression (Jinja's `compile_expression`) |
| `render_position() -> (template, line, excerpt, ok)` | where the render running on this thread is, for a host asked about it mid-render (a memory question) |
| `clear_cache(&env)` | reload templates on the next `load_template` |

`Options`:

| Field | Default | Meaning |
|---|---|---|
| `autoescape` | false | HTML-escape `{{ }}` output that is not `Markup` |
| `autoescape_extensions` | none | e.g. `{".html", ".xml"}`: decide per template name instead |
| `trim_blocks`, `lstrip_blocks` | false | Jinja's whitespace options |
| `keep_trailing_newline` | false | keep the source's final newline |
| `undefined` | `.Default` | `.Strict`, `.Chainable` or `.Debug`, like Jinja's Undefined classes |
| `loader` | none | where `load_template`, `extends`, `include` and `import` read from |
| `max_recursion` | 200 | nested macros, includes, blocks and recursive loops |
| `max_iterations` | 10,000,000 | loop iterations (and `range()` sizes) per render |
| `max_output` | unlimited | bytes per render, and per value a render builds (a repetition, padding, a join), checked before it is allocated |
| `max_nesting` | 100 | how deep template syntax nests: brackets, tags, and operator, filter, attribute and elif chains |
| `stack_bytes` | 512 KiB | machine stack parsing and rendering may use |
| `random_seed` | fixed | seeds `random` and `lipsum`; renders are deterministic |

## Loaders

| Procedure | Serves |
|---|---|
| `memory_loader(&sources)` | a `map[string]string` you own |
| `filesystem_loader({"dir1", "dir2"})` | the first directory holding the name; `..` is refused |
| `Loader{procedure, user, destroy}` | your own: `proc(user, name, allocator) -> (source, found)` |

## Values

`Value` is a union: `Undefined`, `None`, `bool`, `i64`, `f64`, `string`, `Markup`,
`^List` (list or tuple), `^Dict` (ordered; also namespaces and imported modules),
`^Callable` (native procedure or macro), `^Loop`, `^Cycler`. Its zero value is Undefined.

| Build | Read |
|---|---|
| `str("x")`, `integer(1)`, `float(1.5)`, `boolean(true)`, `none()` | `get(d, "key")`, `length(v)` |
| `markup("<b>")` (safe HTML), `undefined()` | `to_string(v)` (Python `str`), `repr(v)` |
| `list(a, b)`, `tuple(a, b)`, `append_value(l, c)` | `truthy(v)`, `values_equal(a, b)` |
| `dict()`, `set(d, "k", v)`, `set_key(d, key, v)` | `type_name(v)`, `is_undefined(v)`, `is_none(v)`, `is_markup(v)` |
| `function("name", procedure, user)` | `escape(v) -> Markup`, `escape_string(s)` |

Integers are 64-bit: overflow is an error, not a wrap. (`int` would shadow Odin's type, so
the integer helper is `integer`.)

## Your own filters, tests and globals

Every native procedure has one signature, `proc(c: ^Call) -> Value`. For filters and tests
`c.args[0]` is the value being filtered or tested.

```odin fragment
import "core:strings"
import "lib/jinja"

env := jinja.create_environment({autoescape = true})
defer jinja.destroy_environment(&env)
long_test :: proc(c: ^jinja.Call) -> jinja.Value {
    return jinja.boolean(len(jinja.to_string(c.args[0])) > 40)
}
pathto :: proc(c: ^jinja.Call) -> jinja.Value { return jinja.str("index.html") }

shout :: proc(c: ^jinja.Call) -> jinja.Value {
    times, _ := jinja.arg_int(c, 1, "times", 1)        // positional 1 or times=...
    return strings.repeat(jinja.to_string(c.args[0]), int(times))
}
jinja.add_filter(&env, "shout", shout)                  // {{ name|shout(2) }}
jinja.add_test(&env, "long", long_test)                 // {% if s is long %}
jinja.add_function(&env, "pathto", pathto)              // {{ pathto('index') }}
jinja.add_global(&env, "project", jinja.str("Docs"))    // must outlive renders
```

| Helper | Does |
|---|---|
| `arg(c, index, "name", default)` | positional argument, else keyword, else default |
| `arg_int(c, index, "name", default) -> (i64, bool)` | an integer argument |
| `has_arg(c, index, "name")` | was it passed? |
| `check_args(c, "who", {"value", "a", "b"}, required)` | Python-style argument checking |
| `fail(c, "format", args..)` | report an error; the render stops with it |
| `autoescaping(c)` | is autoescape on where the call happens? |
| `call_filter(c.state, "name", args, kwargs)`, `call_test(...)` | reuse registered ones |
| `c.user`, `c.self`, `c.kwargs` | registration pointer, method receiver, keywords |

## Errors

`Error{kind, template, line, message, excerpt, hint}`; `kind == .None` means success.
Kinds: `.Syntax`, `.Undefined`, `.Type`, `.Not_Found`, `.Limit`, `.Memory`, `.Runtime`.
Nothing panics on bad templates or data, nor when memory runs out (see Memory). `format_error(err)` renders an Elm-style report:

```
-- UNDEFINED VALUE -------------------------------------------------- page.html:3

'usr' is undefined

3| <h1>{{ usr.name }}</h1>

Hint: Did you mean 'user'?
```

Hints suggest close names for variables, filters, tests and tags. Errors returned by
`render`, `load_template` and friends are allocated with `context.allocator`;
`destroy_error(err)` frees them.

## Deep nesting and the stack

The parser and renderer are recursive, so hostile templates (100,000 nested brackets, a
100,000-term `1 + 1 + ...`, a macro calling itself) are stopped by limits and reported as
`.Limit` errors, never a stack overflow:

- `max_nesting` bounds the depth of the tree the parser builds. Each bracket, nested tag,
  and link of an operator, filter, test, attribute or `elif` chain is one level, so every
  later walk over the tree is bounded too. It is the same on every platform.
- `max_recursion` bounds macro calls, includes, blocks and recursive loops. It is the
  same on every platform too.
- `stack_bytes` bounds the machine stack itself, measured from the first public call on
  the environment (`render`, `load_template`, `evaluate`, ...). It is the backstop for
  what depth counts cannot see, such as every level of a recursion evaluating a deeply
  nested expression, whatever the compiler's frame sizes.

The defaults agree: the default `stack_bytes` holds the default `max_nesting` and
`max_recursion` with room to spare, on x86-64 and arm64 and at every optimization level,
so an ordinary template that nests or recurses too far always meets `max_nesting` or
`max_recursion` first. A level of recursion takes at most about 1.1 KiB of stack in an
optimized build and 1.9 KiB in a debug one (four times that under AddressSanitizer,
whose builds get a budget four times larger). Raise `stack_bytes` together with
`max_nesting` or `max_recursion`, and run on a thread whose stack is at least
`stack_bytes` plus what your caller and the filters you register need.
- Values have no syntax: repr, equality, ordering and `tojson` follow nested lists and
  dicts 200 levels deep. Beyond that, repr prints `[...]` as Python does for a list that
  contains itself, and `tojson` reports a `.Limit` error.

## Memory

`render` does all its work in a private arena backed by `context.allocator` and frees it
before returning; only the output string (and an error) is yours. Parsed templates live in
the environment's arena until `destroy_environment`.

`context.allocator` may refuse memory (a budget, a small arena): the parse or render then
stops with a `.Memory` error at the line it was working on (title `OUT OF MEMORY`), and
frees what it had. Nothing is used after a refused request, and no request is retried
larger. Values whose size is known before they are built (`"x" * n`, `[1] * n`,
`range(n)`, `join`, `center`, `indent`, `format` and `%` padding, `zfill`, `~`) are sized
first: past `max_output` they are a `.Limit` error, and otherwise they are allocated once,
at their exact size, so a refusal comes before anything larger than the value is
requested. An environment whose own tables do not fit sets `out_of_memory`, and every
template it parses fails with a `.Memory` error. The constructors (`list`, `tuple`,
`dict`, `function`) return `Undefined` when their memory is refused, and `set`,
`set_key` and `append_value` then change nothing. The easy path is to render inside
your own arena and drop it; values you put in the context stay yours. An environment is
not thread-safe; use one per thread.

### Values templates store in your lists and dicts

Every list and dict is owned by the allocator it was made with, and names it
(`List.allocator`, `Dict.allocator`): the list grows there, and so does a dict's
index. Templates may store values in lists and dicts you gave them, in the context or
the globals: `{% do items.append(x) %}`, `extend`, `insert`, `d.update(...)`,
`d.setdefault(...)`, `{% set ns.a = x %}`. Those values are yours after the render,
safe to read after the render's scratch memory is freed and after
`destroy_environment`:

- During the render, values are shared as in Jinja. A list appended to yours and then
  changed shows the change.
- When the render ends, whether it succeeded or failed, whatever your containers hold
  of the render's scratch memory or of the environment's arena (a template's literal
  text) is copied into their own allocator. The copies are of the final state. A value
  stored twice is copied once, so it stays shared, and cycles stay cycles.
- A macro, a `joiner`, or a block reference belongs to the render that made it. Its
  copy keeps the name, but calling it in a later render is an error that says so. To
  share a macro, import it.
- When your allocator refuses a copy, the value is replaced with `Undefined` and the
  render fails with a `.Memory` error. Your containers never keep a view into freed
  memory.

The copies are allocated with your containers' allocator and are never freed on their
own, so make the context's lists and dicts in an arena you drop as a whole. A native
procedure runs with the render's scratch memory as `context.allocator`, so it must copy
anything it keeps past the render. The value `evaluate` returns is in the caller's memory,
but the global functions it may hold (`range`, your `add_function`s) live only until
`destroy_environment`.

The procedures and types on this page are the package's surface, each with its contract
in the source; the lexer, parser, evaluator, and the built-in filters, tests, and
globals are private.

## Language coverage

Tags: `if/elif/else`, `for` (with `else`, `if` filter, `recursive`, tuple unpacking,
`break`, `continue`), `set` (plain, tuple, block with filters, `ns.attr`), `with`, `filter`,
`macro` (defaults, `varargs`, `kwargs`, `caller`), `call`, `extends`, `block` (`super()`,
`scoped`, `required`, `self.name()`), `include` (lists, `ignore missing`, with/without
context), `import`, `from ... import ... as`, `raw`, `autoescape`, `do`, `trans` /
`pluralize` (pass-through `gettext`; register your own `gettext`/`ngettext` globals to
translate). Whitespace control with `-` and `+`, comments, `trim_blocks`, `lstrip_blocks`.

Filters: `abs attr batch capitalize center count d default dictsort e escape filesizeformat
first float forceescape format groupby indent int items join last length list lower map
max min pprint random reject rejectattr replace reverse round safe select selectattr slice
sort string striptags sum title tojson trim truncate unique upper urlencode urlize wordcount
wordwrap xmlattr`.

Tests: `boolean callable defined divisibleby eq equalto == escaped even false filter float
ge >= gt > greaterthan in integer iterable le <= lower lt < lessthan mapping ne != none number
odd sameas sequence string test true undefined upper`.

Globals: `range dict lipsum cycler joiner namespace gettext _ ngettext`. Methods of
Python's `str`, `list` and `dict` (`split`, `format`, `startswith`, `items`, `get`,
`append`, ...) work as in Jinja.

## Differences from Jinja

- Line statements (`line_statement_prefix`) are not supported.
- After a render, the values a template stored in your lists and dicts are copies in
  their memory, not the render's objects (see Memory); a macro stored there cannot be
  called by a later render.
- `break`, `continue`, `do` and `trans` are always available (Jinja needs extensions).
- An unknown filter or test is reported when it runs, not when the template is parsed.
- Integers are 64-bit; `range(3)` prints as `[0, 1, 2]`, not `range(0, 3)`.
- Case mapping is Unicode's simple mapping (`'ß'|upper` stays `ß`); `striptags` decodes
  numeric and common named entities, not all of HTML5's.
- `random` and `lipsum` use their own seeded generator, so their picks differ from Python.
- `pprint` is `repr` without line wrapping; `urlize` follows Jinja 3.1's rules closely but
  not its exact regular expressions.

Project documentation: [manual](../../docs/manual/index.rst), [API project](../../docs/api/README.md), and [build workflow](../../docs/manual/README.md).
