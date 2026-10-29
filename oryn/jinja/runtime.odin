package jinja

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"

// State is one render in progress. Natives reach it through Call.state.
State :: struct {
    env:        ^Environment,
    out:        ^strings.Builder,
    err:        Error,
    failed:     bool,
    autoescape: bool,
    depth:      int,
    iterations: int,
    ctx:        ^Context,
    current:    ^Compiled,
    line:       int,
    rng:        u64,
    guard:      ^Guard, // the render's allocator; see memory.odin.
    scratch:    ^Arena, // the render's own memory, or nil; see ownership.odin.
    caller:     mem.Allocator, // context.allocator of the call that renders.
    stored:     map[rawptr]Value, // containers not the render's own it stored values in.
}

// Scope holds variables. The root scope of a render also reads the host's context dict.
@(private)
Scope :: struct {
    vars:   map[string]Value,
    dict:   ^Dict,
    parent: ^Scope,
}

// Context is one template render (the main template, an include or an import): the
// variables of its top level and the block chain built by extends.
@(private)
Context :: struct {
    root:     ^Scope,
    blocks:   map[string][dynamic]Block_Ref,
    parent:   ^Compiled,
    top_out:  ^strings.Builder,
    template: ^Compiled,
}

@(private)
Block_Ref :: struct {
    node:     ^Node,
    template: ^Compiled,
}

// Macro is a macro or call-block body together with where it was defined.
@(private)
Macro :: struct {
    node:       ^Node,
    scope:      ^Scope,
    ctx:        ^Context,
    template:   ^Compiled,
    autoescape: bool,
}

// Recursion lets loop(...) re-enter a recursive for loop.
@(private)
Recursion :: struct {
    node:     ^Node,
    scope:    ^Scope,
    ctx:      ^Context,
    template: ^Compiled,
}

@(private)
Flow :: enum u8 { Normal, Break, Continue, Error }

@(private)
new_scope :: proc(parent: ^Scope) -> ^Scope {
    sc := new(Scope)
    if sc != nil do sc.parent = parent // nil: refused, and the render stopped.
    return sc
}

// ---------------------------------------------------------------------------------------
// Errors

// runtime_error records the first error of the render and returns Undefined.
@(private)
runtime_error :: proc(s: ^State, kind: Error_Kind, format: string, args: ..any) -> Value {
    if s.failed do return Undefined{}
    message := fmt.aprintf(format, ..args)
    if s.failed do return Undefined{} // the message itself ran out of memory.
    s.failed = true
    name, excerpt := "", ""
    if s.current != nil do name, excerpt = s.current.name, source_line(s.current.source, s.line)
    s.err = Error{kind = kind, template = name, line = s.line, excerpt = excerpt,
        message = message}
    return Undefined{}
}

@(private)
undefined_message :: proc(u: Undefined) -> string {
    if u.hint != "" do return u.hint
    if u.owner == "" do return fmt.aprintf("%s is undefined", repr(u.name))
    return fmt.aprintf("'%s' has no attribute %s", u.owner, repr(u.name))
}

// undefined_error raises the error that using an undefined value produces.
@(private)
undefined_error :: proc(s: ^State, u: Undefined) -> Value {
    runtime_error(s, .Undefined, "%s", undefined_message(u))
    hint_undefined(s, u)
    return Undefined{}
}

// strict_check fails when v is undefined and the environment uses StrictUndefined.
@(private)
strict_check :: proc(s: ^State, v: Value) -> bool {
    if u, ok := v.(Undefined); ok && s.env.options.undefined == .Strict {
        undefined_error(s, u)
        return false
    }
    return true
}

// is_true is truthiness with StrictUndefined's error.
@(private)
is_true :: proc(s: ^State, v: Value) -> bool {
    if !strict_check(s, v) do return false
    return truthy(v)
}

@(private)
limit_iteration :: proc(s: ^State) -> bool {
    s.iterations += 1
    if s.iterations > s.env.options.max_iterations {
        runtime_error(s, .Limit, "loop iteration limit of %d reached",
            s.env.options.max_iterations)
        return false
    }
    return true
}

// enter_depth enters one more level of macro call, include, block or recursive loop;
// the caller undoes it (s.depth -= 1) when it returns true.
@(private)
enter_depth :: proc(s: ^State) -> bool {
    s.depth += 1
    if s.depth <= s.env.options.max_recursion do return true
    recursion_error(s)
    return false
}

@(private)
recursion_error :: #force_no_inline proc(s: ^State) {
    runtime_error(s, .Limit, "recursion limit of %d reached (macros, includes, blocks and " +
        "recursive loops)", s.env.options.max_recursion)
    set_hint(s, "Give the recursion a condition that ends it, or raise " +
        "Options.max_recursion (and Options.stack_bytes with it).")
}

// ---------------------------------------------------------------------------------------
// Output

@(private)
emit :: proc(s: ^State, text: string) {
    ctx := s.ctx
    if ctx != nil && ctx.parent != nil && s.out == ctx.top_out do return
    limit := s.env.options.max_output
    if limit > 0 && len(text) > limit - strings.builder_len(s.out^) {
        runtime_error(s, .Limit, "output limit of %d bytes reached", limit)
        return
    }
    strings.write_string(s.out, text)
}

// write_output prints an expression result, escaping it when autoescape is on. It is out
// of line to keep the frames of the statements that call it small (stack.odin).
@(private)
write_output :: #force_no_inline proc(s: ^State, v: Value) {
    ctx := s.ctx
    if ctx != nil && ctx.parent != nil && s.out == ctx.top_out do return
    #partial switch x in v {
    case Undefined:
        switch s.env.options.undefined {
        case .Default, .Chainable:
        case .Strict: undefined_error(s, x)
        case .Debug: emit(s, debug_undefined(x))
        }
        return
    case string:
        if s.autoescape {
            b := strings.builder_make(0, len(x) + 8)
            write_escaped(&b, x)
            emit(s, strings.to_string(b))
        } else {
            emit(s, x)
        }
        return
    case Markup:
        emit(s, string(x))
        return
    }
    text := to_string(v)
    emit(s, escape_string(text) if s.autoescape else text)
}

@(private)
debug_undefined :: proc(u: Undefined) -> string {
    if u.hint != "" do return fmt.aprintf("{{{{ undefined value printed: %s }}}}", u.hint)
    if u.owner == "" do return fmt.aprintf("{{{{ %s }}}}", u.name)
    return fmt.aprintf("{{{{ no such element: %s[%s] }}}}", u.owner, repr(u.name))
}

// begin_capture redirects output into a fresh buffer; end_capture restores it.
@(private)
begin_capture :: proc(s: ^State) -> ^strings.Builder {
    saved := s.out
    if out := new(strings.Builder); out != nil {
        out^ = strings.builder_make()
        s.out = out
    } // else the render has stopped (the guard), and output goes nowhere new.
    return saved
}

@(private)
end_capture :: proc(s: ^State, saved: ^strings.Builder) -> string {
    if s.out == saved do return ""
    text := strings.to_string(s.out^)
    s.out = saved
    return text
}

// captured wraps captured output as Markup when autoescape is on.
@(private)
captured :: proc(s: ^State, text: string) -> Value {
    if s.autoescape do return Markup(text)
    return text
}

// ---------------------------------------------------------------------------------------
// Statements
//
// exec_body and the statements that run a body are on the stack once per level of every
// nested tag, macro call, include and recursive loop, so they keep small frames and
// leave the rest to helpers out of line (stack.odin).

// exec_body runs statements in order, stopping at an error, break or continue. It
// dispatches each through EXEC itself rather than through a procedure per statement,
// sparing a frame per level of nesting.
@(private)
exec_body :: proc(s: ^State, scope: ^Scope, body: []^Node) -> Flow {
    for n in body {
        if s.failed do return .Error // also when scope could not be made (nil).
        s.line = n.line
        if stack_exhausted(s.env.stack) {
            stack_error(s)
            return .Error
        }
        flow := EXEC[n.kind](s, scope, n)
        if s.failed do return .Error
        if flow != .Normal do return flow
    }
    return .Normal
}

// Exec runs one kind of statement.
@(private)
Exec :: #type proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow

// EXEC is the statement of each node kind. exec_body calls through it rather than
// switching, so that no optimizer inlines every statement into its frame.
@(private, rodata)
EXEC := [Node_Kind]Exec {
    .Data = exec_data, .Output = exec_output, .If = exec_if, .For = exec_for,
    .Set = exec_set, .Set_Block = exec_set_block, .Macro = exec_macro,
    .Call_Block = exec_call_block, .Filter_Block = exec_filter_block, .With = exec_with,
    .Block = exec_block_tag, .Extends = exec_extends, .Include = exec_include,
    .Import = exec_import, .From_Import = exec_import, .Autoescape = exec_autoescape,
    .Do = exec_do, .Break = exec_break, .Continue = exec_continue, .Trans = exec_trans,
    .Const = cannot_execute, .Name = cannot_execute, .List = cannot_execute,
    .Tuple = cannot_execute, .Dict = cannot_execute, .Getattr = cannot_execute,
    .Getitem = cannot_execute, .Slice = cannot_execute, .Call = cannot_execute,
    .Filter = cannot_execute, .Test = cannot_execute, .Unary = cannot_execute,
    .Binary = cannot_execute, .Concat = cannot_execute, .Compare = cannot_execute,
    .Cond = cannot_execute, .Ns_Ref = cannot_execute,
}

// exec runs one statement.
@(private)
exec :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    body := [1]^Node{n}
    return exec_body(s, scope, body[:])
}

// cannot_execute reports an expression where a statement belongs; the parser never
// builds one.
@(private)
cannot_execute :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    runtime_error(s, .Runtime, "cannot execute %v", n.kind)
    return .Error
}

@(private)
exec_data :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    emit(s, n.text)
    return .Normal
}

@(private)
exec_output :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    write_output(s, eval(s, scope, n.a))
    return .Normal
}

@(private)
exec_macro :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    scope.vars[n.text] = make_macro(s, scope, n)
    return .Normal
}

@(private)
exec_do :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    eval(s, scope, n.a)
    return .Normal
}

@(private)
exec_break :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow { return .Break }

@(private)
exec_continue :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow { return .Continue }

@(private)
exec_if :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    holds := condition(s, scope, n.a)
    if s.failed do return .Error
    return exec_body(s, scope, n.body if holds else n.else_body)
}

// condition evaluates a test (if, elif, the inline if, a loop filter) to a boolean, out
// of line so that the value it tests never takes room in the caller's frame.
@(private)
condition :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node) -> bool {
    v := eval(s, scope, n)
    return !s.failed && is_true(s, v)
}

@(private)
exec_set :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    v := eval(s, scope, n.b)
    if !s.failed do assign(s, scope, n.a, v)
    return .Normal
}

@(private)
exec_filter_block :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    saved := begin_capture(s)
    flow := exec_body(s, new_scope(scope), n.body)
    text := end_capture(s, saved)
    if flow != .Error do filter_block_output(s, scope, n, text)
    return .Normal
}

@(private)
filter_block_output :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node,
    text: string) {
    v := apply_filter_chain(s, scope, n.a, captured(s, text))
    if !s.failed do emit(s, to_string(v))
}

@(private)
exec_autoescape :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    on := autoescape_setting(s, scope, n.a)
    if s.failed do return .Error
    saved := s.autoescape
    s.autoescape = on
    flow := exec_body(s, scope, n.body)
    s.autoescape = saved
    return flow
}

@(private)
autoescape_setting :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node) -> bool {
    return truthy(eval(s, scope, n))
}

@(private)
exec_set_block :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    saved := begin_capture(s)
    flow := exec_body(s, new_scope(scope), n.body)
    text := end_capture(s, saved)
    if flow != .Error do assign_block(s, scope, n, text)
    return .Normal
}

@(private)
assign_block :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node, text: string) {
    v := captured(s, text)
    if n.c != nil do v = apply_filter_chain(s, scope, n.c, v)
    if !s.failed do assign(s, scope, n.a, v)
}

@(private)
exec_with :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    inner := with_scope(s, scope, n)
    if inner == nil do return .Error
    return exec_body(s, inner, n.body)
}

// with_scope is the scope of a with block, holding the values it assigns.
@(private)
with_scope :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node) -> ^Scope {
    inner := new_scope(scope)
    values, err := make([]Value, len(n.values))
    if inner == nil || err != nil do return nil
    for v, i in n.values {
        values[i] = eval(s, scope, v)
        if s.failed do return nil
    }
    for target, i in n.args do assign(s, inner, target, values[i])
    return nil if s.failed else inner
}

// assign stores v into a name, unpacks it into a tuple of targets, or sets a namespace
// attribute.
@(private)
assign :: #force_no_inline proc(s: ^State, scope: ^Scope, target: ^Node, v: Value) {
    #partial switch target.kind {
    case .Name:
        scope.vars[target.text] = v
    case .Tuple, .List:
        #partial switch _ in v {
        case ^List, ^Dict, string, Markup:
        case:
            runtime_error(s, .Type, "cannot unpack non-iterable %s object", type_name(v))
            return
        }
        items, ok := iterate(s, v)
        if !ok do return
        want := len(target.args)
        if len(items) > want {
            runtime_error(s, .Type, "too many values to unpack (expected %d)", want)
            return
        }
        if len(items) < want {
            runtime_error(s, .Type, "not enough values to unpack (expected %d, got %d)", want,
                len(items))
            return
        }
        for t, i in target.args do assign(s, scope, t, items[i])
    case .Ns_Ref:
        ns := lookup(s, scope, target.a.text)
        d, ok := ns.(^Dict)
        if !ok || d.kind != .Namespace {
            runtime_error(s, .Type, "cannot assign attribute on non-namespace object")
            return
        }
        if note_store(s, d) do dict_set(d, target.text, v)
    case:
        // The parser accepts only the targets above (can_assign); anything else would
        // drop the value silently.
        runtime_error(s, .Runtime, "cannot assign to %v", target.kind)
    }
}

// iterate lists the items a for loop sees: list items, dict keys, string characters.
@(private)
iterate :: proc(s: ^State, v: Value) -> ([]Value, bool) {
    #partial switch x in v {
    case ^List: return x.items[:], true
    case ^Dict:
        if x.kind == .Dict do return x.keys[:], true
    case string: return string_chars(x), true
    case Markup: return string_chars(string(x)), true
    case Undefined:
        if !strict_check(s, v) do return nil, false
        return nil, true
    }
    runtime_error(s, .Type, "'%s' object is not iterable", type_name(v))
    return nil, false
}

@(private)
string_chars :: proc(s: string) -> []Value {
    out := make([dynamic]Value, 0, len(s))
    i := 0
    for i < len(s) {
        _, size := utf8.decode_rune_in_string(s[i:])
        append(&out, s[i:i + size])
        i += size
    }
    return out[:]
}

// ---------------------------------------------------------------------------------------
// For loops

@(private)
exec_for :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    loop, inner := start_loop(s, scope, n)
    if loop == nil do return .Error
    return run_loop(s, inner, n, loop)
}

// start_loop evaluates what a for loop iterates over and makes its loop variable, in
// a scope of its own.
@(private)
start_loop :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node) -> (^Loop, ^Scope) {
    iterable := eval(s, scope, n.b)
    if s.failed do return nil, nil
    items, ok := iterate(s, iterable)
    if !ok do return nil, nil
    rec: ^Recursion
    if .Recursive in n.flags {
        rec = new(Recursion)
        if rec == nil do return nil, nil
        rec^ = Recursion{node = n, scope = scope, ctx = s.ctx, template = s.current}
    }
    return new_loop(s, scope, n, items, 0, rec)
}

// new_loop makes the loop variable of a for loop over items, in a new scope below
// scope, keeping only the items that pass the loop's filter (for x in xs if ...).
@(private)
new_loop :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node, items: []Value,
    depth0: int, rec: ^Recursion) -> (^Loop, ^Scope) {
    inner := new_scope(scope)
    if inner == nil do return nil, nil
    kept := items
    if n.c != nil {
        filtered := make([dynamic]Value, 0, len(items))
        for item in items {
            if !limit_iteration(s) do return nil, nil
            assign(s, inner, n.a, item)
            if condition(s, inner, n.c) do append(&filtered, item)
            if s.failed do return nil, nil
        }
        kept = filtered[:]
    }
    loop := new(Loop)
    if loop == nil do return nil, nil
    loop^ = Loop{items = kept, depth0 = depth0, recurse = rec}
    return loop, inner
}

// run_loop runs the body of a for loop once for each of loop's items.
@(private)
run_loop :: proc(s: ^State, inner: ^Scope, n: ^Node, loop: ^Loop) -> Flow {
    for i in 0 ..< len(loop.items) {
        if !next_item(s, inner, n, loop, i) do return .Error
        flow := exec_body(s, inner, n.body)
        if flow == .Error do return .Error
        if flow == .Break do break
    }
    if len(loop.items) == 0 do return exec_body(s, inner, n.else_body)
    return .Normal
}

// next_item counts an iteration and assigns the loop's target and loop variable.
@(private)
next_item :: #force_no_inline proc(s: ^State, inner: ^Scope, n: ^Node, loop: ^Loop,
    i: int) -> bool {
    if !limit_iteration(s) do return false
    loop.index0 = i
    assign(s, inner, n.a, loop.items[i])
    inner.vars["loop"] = loop
    return !s.failed
}

// call_loop runs the body of a recursive loop again: loop(children).
@(private)
call_loop :: proc(s: ^State, loop: ^Loop, args: []Value) -> (v: Value) {
    again, inner := recursive_loop(s, loop, args)
    if again == nil || !enter_depth(s) do return
    defer s.depth -= 1
    rec := loop.recurse
    saved_ctx, saved_tpl := s.ctx, s.current
    s.ctx, s.current = rec.ctx, rec.template
    saved := begin_capture(s)
    run_loop(s, inner, rec.node, again)
    text := end_capture(s, saved)
    s.ctx, s.current = saved_ctx, saved_tpl
    return captured(s, text)
}

// recursive_loop checks a call loop(children) and makes the loop over children.
@(private)
recursive_loop :: #force_no_inline proc(s: ^State, loop: ^Loop, args: []Value) -> (^Loop,
    ^Scope) {
    rec := loop.recurse
    if rec == nil {
        runtime_error(s, .Type, "Tried to call non recursive loop.  Maybe you forgot the " +
            "'recursive' modifier.")
        return nil, nil
    }
    if len(args) != 1 {
        runtime_error(s, .Type, "loop() takes exactly 1 argument")
        return nil, nil
    }
    items, ok := iterate(s, args[0])
    if !ok do return nil, nil
    return new_loop(s, rec.scope, rec.node, items, loop.depth0 + 1, rec)
}


// loop_attribute reads loop.index and friends.
@(private)
loop_attribute :: proc(s: ^State, loop: ^Loop, name: string) -> (Value, bool) {
    n := len(loop.items)
    i := loop.index0
    switch name {
    case "index": return i64(i + 1), true
    case "index0": return i64(i), true
    case "revindex": return i64(n - i), true
    case "revindex0": return i64(n - i - 1), true
    case "first": return i == 0, true
    case "last": return i == n - 1, true
    case "length": return i64(n), true
    case "depth": return i64(loop.depth0 + 1), true
    case "depth0": return i64(loop.depth0), true
    case "previtem":
        if i > 0 do return loop.items[i - 1], true
        return Undefined{hint = "there is no previous item"}, true
    case "nextitem":
        if i + 1 < n do return loop.items[i + 1], true
        return Undefined{hint = "there is no next item"}, true
    case "cycle", "changed":
        return bound_method(Value(loop), name), true
    }
    return Undefined{}, false
}

@(private)
loop_method :: proc(c: ^Call) -> Value {
    loop := c.self.(^Loop)
    switch c.name {
    case "cycle":
        if len(c.args) == 0 do return fail(c, "no items for cycling given")
        return c.args[loop.index0 % len(c.args)]
    case "changed":
        l := list_of(c.args)
        if l == nil do return Undefined{}
        current := Value(l)
        if loop.changed && values_equal(current, loop.last_seen) do return false
        loop.changed = true
        loop.last_seen = current
        return true
    }
    return fail(c, "unknown loop method %s", c.name)
}
