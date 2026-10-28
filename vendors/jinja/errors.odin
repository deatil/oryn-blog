package jinja

import "core:fmt"
import "core:mem"
import "core:strings"

Error_Kind :: enum u8 {
    None,
    Syntax,    // the template does not parse (TemplateSyntaxError)
    Undefined, // an undefined value was used (UndefinedError)
    Type,      // an operation got the wrong kind of value (TypeError)
    Not_Found, // a template could not be loaded (TemplateNotFound)
    Limit,     // a recursion, iteration or output limit was reached
    Memory,    // the memory the parse or render may use could not hold it (MemoryError)
    Runtime,   // any other failure while rendering
}

// Error describes a failure. kind == .None means success. excerpt is the template line
// the error points at; hint, when set, suggests a fix.
Error :: struct {
    kind:     Error_Kind,
    template: string,
    line:     int,
    message:  string,
    excerpt:  string,
    hint:     string,
}

// format_error renders an error as a friendly report in the style of Elm's compiler, in
// a string allocated with allocator that the caller owns ("" for no error):
//
//     -- UNDEFINED VALUE ------------------------------------------ page.html:3
//
//     'user' is undefined
//
//     3| <h1>{{ user.name }}</h1>
//
//     Hint: Pass it in the render context, or test it with `is defined`.
format_error :: proc(err: Error, allocator := context.allocator) -> string {
    if err.kind == .None do return ""
    b := strings.builder_make(allocator)
    title: string
    switch err.kind {
    case .None:
    case .Syntax: title = "SYNTAX ERROR"
    case .Undefined: title = "UNDEFINED VALUE"
    case .Type: title = "TYPE ERROR"
    case .Not_Found: title = "TEMPLATE NOT FOUND"
    case .Limit: title = "LIMIT REACHED"
    case .Memory: title = "OUT OF MEMORY"
    case .Runtime: title = "RENDER ERROR"
    }
    message := err.message
    if message == "" && err.kind == .Memory do message = MEMORY_MESSAGE
    where_ := err.template if err.template != "" else "<template>"
    if err.line > 0 do where_ = fmt.tprintf("%s:%d", where_, err.line)
    dashes := max(80 - len(title) - len(where_) - 5, 3)
    fmt.sbprintf(&b, "-- %s %s %s\n\n%s\n", title, strings.repeat("-", dashes,
        context.temp_allocator), where_, wrap_report(message))
    if err.excerpt != "" {
        fmt.sbprintf(&b, "\n%d| %s\n", err.line, err.excerpt)
    }
    if err.hint != "" do fmt.sbprintf(&b, "\n%s\n", wrap_report(strings.concatenate({"Hint: ",
        err.hint}, context.temp_allocator)))
    return strings.to_string(b)
}

@(private)
clone_error :: proc(err: Error, allocator: mem.Allocator) -> Error {
    out := err
    out.template = strings.clone(err.template, allocator)
    out.message = strings.clone(err.message, allocator)
    out.excerpt = strings.clone(err.excerpt, allocator)
    out.hint = strings.clone(err.hint, allocator)
    return out
}

// destroy_error frees an error returned by this package.
destroy_error :: proc(err: Error, allocator := context.allocator) {
    delete(err.template, allocator)
    delete(err.message, allocator)
    delete(err.excerpt, allocator)
    delete(err.hint, allocator)
}

// source_line returns line number `line` (1-based) of source, without its newline.
@(private)
source_line :: proc(source: string, line: int) -> string {
    if line <= 0 do return ""
    rest := source
    n := 1
    for text in strings.split_lines_iterator(&rest) {
        if n == line do return strings.trim_right(text, "\r")
        n += 1
    }
    return ""
}

// set_hint attaches a hint to the error just raised.
@(private)
set_hint :: proc(s: ^State, format: string, args: ..any) {
    if s.failed && s.err.hint == "" do s.err.hint = fmt.aprintf(format, ..args)
}

// edit_distance is the Levenshtein distance between two short names.
@(private)
edit_distance :: proc(a, b: string) -> int {
    if len(a) > 64 || len(b) > 64 do return 99
    prev, cur: [65]int
    for j in 0 ..= len(b) do prev[j] = j
    for i in 1 ..= len(a) {
        cur[0] = i
        for j in 1 ..= len(b) {
            cost := 0 if a[i - 1] == b[j - 1] else 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        }
        prev = cur
    }
    return prev[len(b)]
}

// closest picks the candidate nearest to name, if it is close enough to be a typo.
@(private)
closest :: proc(name: string, candidates: []string) -> string {
    best, best_d := "", 3
    for c in candidates {
        if c == name do continue
        d := edit_distance(name, c)
        limit := 1 if len(name) <= 3 else 2
        if d <= limit && d < best_d {
            best, best_d = c, d
        }
    }
    return best
}

// map_keys lists the keys of a string-keyed map.
@(private)
map_keys :: proc(m: map[string]$T) -> []string {
    out := make([dynamic]string, 0, len(m))
    for k in m do append(&out, k)
    return out[:]
}

// visible_names lists the variables a template could have meant.
@(private)
visible_names :: proc(s: ^State) -> []string {
    out := make([dynamic]string)
    if s.ctx != nil {
        for sc := s.ctx.root; sc != nil; sc = sc.parent {
            for k in sc.vars do append(&out, k)
            if sc.dict != nil {
                for k in sc.dict.keys do if name, ok := k.(string); ok do append(&out, name)
            }
        }
    }
    for k in s.env.globals do append(&out, k)
    return out[:]
}

// hint_undefined explains an undefined variable and suggests a close name.
@(private)
hint_undefined :: proc(s: ^State, u: Undefined) {
    if u.hint != "" do return
    if u.owner != "" {
        set_hint(s, "Check the attribute name, or give it a fallback: " +
            "{{{{ value.%s | default('') }}}}.", u.name)
        return
    }
    if near := closest(u.name, visible_names(s)); near != "" {
        set_hint(s, "Did you mean %s?", repr(near))
        return
    }
    set_hint(s, "Pass %s in the render context, set it with {{%% set %s = ... %%}}, or " +
        "guard it with {{%% if %s is defined %%}}.", repr(u.name), u.name, u.name)
}

// unknown_name reports a missing filter or test and suggests a close match.
@(private)
unknown_name :: proc(s: ^State, what, name: string, known: []string) -> Value {
    runtime_error(s, .Runtime, "No %s named %s.", what, repr(name))
    if near := closest(name, known); near != "" {
        set_hint(s, "Did you mean the %s %s?", what, repr(near))
    } else {
        set_hint(s, "Register it with jinja.add_%s(&env, %s, procedure).", what, repr(name))
    }
    return Undefined{}
}

// wrap_report wraps prose at 80 columns, keeping each input line separate.
@(private)
wrap_report :: proc(text: string) -> string {
    context.allocator = context.temp_allocator
    b := strings.builder_make()
    for line, i in python_splitlines(text) {
        if i > 0 do strings.write_byte(&b, '\n')
        for piece, j in text_wrap(line, {width = 80, break_on_hyphens = false}) {
            if j > 0 do strings.write_byte(&b, '\n')
            strings.write_string(&b, piece)
        }
    }
    return strings.to_string(b)
}
