package jinja

import "core:fmt"

// ---------------------------------------------------------------------------------------
// Helpers for native procedures

// fail records a runtime error from a native procedure; return its result. The message
// is formatted with context.allocator, the render's arena.
fail :: proc(c: ^Call, format: string, args: ..any) -> Value {
    return runtime_error(c.state, .Runtime, "%s", fmt.aprintf(format, ..args))
}

// arg returns positional argument index, else the keyword argument name, else default.
arg :: proc(c: ^Call, index: int, name: string, default: Value = Undefined{}) -> Value {
    if index >= 0 && index < len(c.args) do return c.args[index]
    for kw in c.kwargs do if kw.name == name do return kw.value
    return default
}

// has_arg reports whether the argument was passed at all.
has_arg :: proc(c: ^Call, index: int, name: string) -> bool {
    if index >= 0 && index < len(c.args) do return true
    for kw in c.kwargs do if kw.name == name do return true
    return false
}

// check_args enforces a Python signature: at most len(names) positional arguments and
// only the named keywords, each at most once. who names the callable in errors.
check_args :: proc(c: ^Call, who: string, names: []string, required := 0) -> bool {
    if len(c.args) > len(names) {
        fail(c, "%s() takes at most %d arguments (%d given)", who, len(names), len(c.args))
        return false
    }
    for kw in c.kwargs {
        index := -1
        for name, i in names do if name == kw.name do index = i
        if index < 0 {
            fail(c, "%s() got an unexpected keyword argument %s", who, repr(kw.name))
            return false
        }
        if index < len(c.args) {
            fail(c, "%s() got multiple values for argument %s", who, repr(kw.name))
            return false
        }
    }
    for i in 0 ..< required {
        if !has_arg(c, i, names[i]) {
            fail(c, "%s() missing required argument %s", who, repr(names[i]))
            return false
        }
    }
    return true
}

// autoescaping reports whether the call happens while autoescape is on.
autoescaping :: proc(c: ^Call) -> bool { return c.state != nil && c.state.autoescape }

// arg_int reads an integer argument (bools and integral floats accepted).
arg_int :: proc(c: ^Call, index: int, name: string, default: i64) -> (i64, bool) {
    v := arg(c, index, name, default)
    i, f, kind := as_number(v)
    switch kind {
    case .Int: return i, true
    case .Float: return i64(f), true
    case .None:
    }
    if is_none(v) do return default, true
    fail(c, "%s must be an integer, not %s", name, type_name(v))
    return 0, false
}

// ---------------------------------------------------------------------------------------
// Calls

// eval_arguments evaluates the arguments of a call, filter or test; input, when given,
// is the first positional argument (the value being filtered or tested). A macro call
// in an argument recurses through here, so the work besides evaluating is out of line.
@(private)
eval_arguments :: proc(s: ^State, scope: ^Scope, n: ^Node,
    input: ^Value = nil) -> (args: []Value, kwargs: []Keyword) {
    first := 0 if input == nil else 1
    args, kwargs = argument_slots(first + len(n.args), len(n.names))
    if len(args) < first + len(n.args) || len(kwargs) < len(n.names) do return nil, nil
    if input != nil do args[0] = input^
    for a, i in n.args do args[first + i] = eval(s, scope, a)
    for name, i in n.names {
        kwargs[i].name = name
        kwargs[i].value = eval(s, scope, n.values[i])
    }
    if n.b != nil do args = spread_arguments(s, scope, n.b, args)
    if n.c != nil do kwargs = spread_keywords(s, scope, n.c, kwargs)
    return
}

// argument_slots makes room for a call's positional and keyword arguments. A refused
// request leaves a slice empty, and the render stopped.
@(private)
argument_slots :: #force_no_inline proc(positional, keywords: int) -> ([]Value, []Keyword) {
    args, _ := make([]Value, positional)
    kwargs, _ := make([]Keyword, keywords)
    return args, kwargs
}

// spread_arguments appends the items of *n to the positional arguments.
@(private)
spread_arguments :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node,
    args: []Value) -> []Value {
    extra := eval(s, scope, n)
    items, ok := iterate(s, extra)
    if !ok || len(items) == 0 do return args
    all := make([dynamic]Value, 0, len(args) + len(items))
    append(&all, ..args)
    append(&all, ..items)
    return all[:]
}

// spread_keywords appends the entries of **n to the keyword arguments.
@(private)
spread_keywords :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node,
    kwargs: []Keyword) -> []Keyword {
    extra := eval(s, scope, n)
    d, ok := extra.(^Dict)
    if !ok {
        if !s.failed {
            runtime_error(s, .Type, "argument after ** must be a mapping, not %s",
                type_name(extra))
        }
        return kwargs
    }
    all := make([dynamic]Keyword, 0, len(kwargs) + len(d.keys))
    append(&all, ..kwargs)
    for key, i in d.keys do append(&all, Keyword{to_string(key), d.values[i]})
    return all[:]
}

@(private)
eval_call :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    callee := eval(s, scope, n.a)
    if s.failed do return
    args, kwargs := eval_arguments(s, scope, n)
    if s.failed do return
    s.line = n.line
    // As call_value, without its frame: macros, recursive loops and natives such as
    // self.name() all recurse through here.
    if c, ok := callee.(^Callable); ok {
        if c.macro != nil do return call_macro(s, c, args, kwargs)
        return call_native(s, c, args, kwargs)
    }
    if loop, ok := callee.(^Loop); ok do return call_loop(s, loop, args)
    return not_callable(s, callee)
}

// call_value calls a callable value with evaluated arguments.
@(private)
call_value :: proc(s: ^State, callee: Value, args: []Value, kwargs: []Keyword) -> Value {
    if c, ok := callee.(^Callable); ok {
        if c.macro != nil do return call_macro(s, c, args, kwargs)
        return call_native(s, c, args, kwargs)
    }
    if loop, ok := callee.(^Loop); ok do return call_loop(s, loop, args)
    return not_callable(s, callee)
}

// call_native calls a procedure written in Odin. It is out of line to keep eval_call's
// frame small, since a native such as super() or self.name() may render a block.
@(private)
call_native :: #force_no_inline proc(s: ^State, x: ^Callable, args: []Value,
    kwargs: []Keyword) -> (v: Value) {
    c: Call
    c.args, c.kwargs, c.user, c.name, c.state = args, kwargs, x.user, x.name, s
    c.self = x.self
    v = x.procedure(&c)
    if s.failed do v = Undefined{}
    return
}

@(private)
not_callable :: #force_no_inline proc(s: ^State, callee: Value) -> Value {
    if u, ok := callee.(Undefined); ok {
        if s.env.options.undefined == .Chainable do return callee
        return undefined_error(s, u)
    }
    return runtime_error(s, .Type, "'%s' object is not callable", type_name(callee))
}

// ---------------------------------------------------------------------------------------
// Macros

@(private)
make_macro :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Value {
    m := new(Macro)
    c := new(Callable)
    if m == nil || c == nil do return Undefined{}
    m^ = Macro{node = n, scope = scope, ctx = s.ctx, template = s.current,
        autoescape = s.autoescape}
    c^ = Callable{name = n.text if n.kind == .Macro else "caller", macro = m}
    return c
}

@(private)
callable_attribute :: proc(c: ^Callable, name: string) -> (Value, bool) {
    if c.macro == nil do return Undefined{}, false
    n := c.macro.node
    switch name {
    case "name": return c.name, true
    case "arguments":
        l := new_list(len(n.names), true)
        if l == nil do return Undefined{}, true
        for p in n.names do append(&l.items, p)
        return l, true
    case "catch_kwargs": return .Uses_Kwargs in n.flags, true
    case "catch_varargs": return .Uses_Varargs in n.flags, true
    case "caller": return .Uses_Caller in n.flags, true
    }
    return Undefined{}, false
}

@(private)
call_macro :: proc(s: ^State, c: ^Callable, args: []Value, kwargs: []Keyword) -> (v: Value) {
    m := c.macro
    if !enter_depth(s) do return
    defer s.depth -= 1
    scope := macro_scope(s, c, args, kwargs)
    if scope == nil do return
    saved_ctx, saved_tpl, saved_escape := s.ctx, s.current, s.autoescape
    s.ctx, s.current, s.autoescape = m.ctx, m.template, m.autoescape
    saved := begin_capture(s)
    exec_body(s, scope, m.node.body)
    text := end_capture(s, saved)
    s.ctx, s.current, s.autoescape = saved_ctx, saved_tpl, saved_escape
    if s.failed do return
    if m.autoescape {
        v = Markup(text)
    } else {
        v = text
    }
    return
}

// macro_scope is the scope a macro's body runs in, holding its arguments.
@(private)
macro_scope :: #force_no_inline proc(s: ^State, c: ^Callable, args: []Value,
    kwargs: []Keyword) -> ^Scope {
    scope := new_scope(c.macro.scope)
    if scope == nil || !bind_macro_args(s, c, scope, args, kwargs) do return nil
    return scope
}

@(private)
bind_macro_args :: proc(s: ^State, c: ^Callable, scope: ^Scope, args: []Value,
    kwargs: []Keyword) -> bool {
    n := c.macro.node
    extra_kwargs := new_dict(.Dict)
    if extra_kwargs == nil do return false
    has_caller := false
    for kw in kwargs {
        found := false
        for name, i in n.names {
            if name != kw.name do continue
            if i < len(args) {
                runtime_error(s, .Type, "macro %s got multiple values for argument %s",
                    repr(c.name), repr(name))
                return false
            }
            found = true
        }
        if !found && kw.name == "caller" {
            has_caller = true
            if .Uses_Caller in n.flags {
                scope.vars["caller"] = kw.value
                continue
            }
        }
        if !found do dict_set(extra_kwargs, kw.name, kw.value)
    }
    for name, i in n.names {
        v: Value
        if i < len(args) {
            v = args[i]
        } else if kv, ok := find_keyword(kwargs, name); ok {
            v = kv
        } else if n.values[i] != nil {
            scope.vars[name] = Undefined{}
            v = eval(s, scope, n.values[i])
            if s.failed do return false
        } else {
            v = Undefined{name = name, hint = fmt.aprintf("parameter %s was not provided",
                repr(name))}
        }
        scope.vars[name] = v
    }
    return bind_macro_rest(s, c, scope, args, extra_kwargs, has_caller)
}

@(private)
bind_macro_rest :: proc(s: ^State, c: ^Callable, scope: ^Scope, args: []Value,
    extra_kwargs: ^Dict, has_caller: bool) -> bool {
    n := c.macro.node
    if len(args) > len(n.names) {
        if .Uses_Varargs not_in n.flags {
            runtime_error(s, .Type, "macro %s takes not more than %d argument(s)",
                repr(c.name), len(n.names))
            return false
        }
        scope.vars["varargs"] = list_value(list_of(args[len(n.names):], true))
    } else if .Uses_Varargs in n.flags {
        scope.vars["varargs"] = list_value(new_list(0, true))
    }
    if s.failed do return false
    if len(extra_kwargs.keys) > 0 && .Uses_Kwargs not_in n.flags {
        runtime_error(s, .Type, "macro %s takes no keyword argument %s", repr(c.name),
            repr(to_string(extra_kwargs.keys[0])))
        return false
    }
    if .Uses_Kwargs in n.flags do scope.vars["kwargs"] = extra_kwargs
    if .Uses_Caller in n.flags && !has_caller {
        if _, declared := scope.vars["caller"]; !declared {
            scope.vars["caller"] = Undefined{name = "caller", hint = "No caller defined"}
        }
    }
    return true
}

@(private)
find_keyword :: proc(kwargs: []Keyword, name: string) -> (Value, bool) {
    for kw in kwargs do if kw.name == name do return kw.value, true
    return Undefined{}, false
}

@(private)
exec_call_block :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    call := n.a
    callee := eval(s, scope, call.a)
    if s.failed do return .Error
    args, kwargs := eval_arguments(s, scope, call)
    if s.failed do return .Error
    kwargs = with_caller(s, scope, n, kwargs)
    s.line = n.line
    write_output(s, call_value(s, callee, args, kwargs))
    return .Normal
}

// with_caller adds the body of a call block, as the macro caller, to the keyword
// arguments of its call.
@(private)
with_caller :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node,
    kwargs: []Keyword) -> []Keyword {
    all := make([dynamic]Keyword, 0, len(kwargs) + 1)
    append(&all, ..kwargs)
    append(&all, Keyword{"caller", make_macro(s, scope, n)})
    return all[:]
}

// ---------------------------------------------------------------------------------------
// Filters and tests

// apply_filter applies the filter n to input. A macro call in the filter's arguments
// recurses through here, so finding and calling the filter are out of line.
@(private)
apply_filter :: proc(s: ^State, scope: ^Scope, n: ^Node, input: ^Value) -> Value {
    f, ok := find_registered(s, "filter", n.text)
    if !ok do return Undefined{}
    args, kwargs := eval_arguments(s, scope, n, input)
    if s.failed do return Undefined{}
    s.line = n.line
    return call_registered(s, f, n.text, args, kwargs)
}

// apply_filter_chain applies a filter chain whose innermost operand is nil to input.
@(private)
apply_filter_chain :: proc(s: ^State, scope: ^Scope, chain: ^Node, input: Value) -> Value {
    if chain == nil do return input
    inner := input
    if chain.a != nil do inner = apply_filter_chain(s, scope, chain.a, input)
    if s.failed do return Undefined{}
    return apply_filter(s, scope, chain, &inner)
}

@(private)
apply_test :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    input := eval(s, scope, n.a)
    if s.failed do return
    return test_value(s, scope, n, &input)
}

// test_value applies the test n to input, out of line to keep apply_test's frame small.
@(private)
test_value :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node,
    input: ^Value) -> Value {
    t, ok := find_registered(s, "test", n.text)
    if !ok do return Undefined{}
    args, kwargs := eval_arguments(s, scope, n, input)
    if s.failed do return Undefined{}
    s.line = n.line
    return truthy(call_registered(s, t, n.text, args, kwargs))
}

// find_registered finds the filter or test (what) called name, or reports that there is
// none.
@(private)
find_registered :: #force_no_inline proc(s: ^State, what, name: string) -> (Registered,
    bool) {
    table := s.env.filters if what == "filter" else s.env.tests
    if r, ok := table[name]; ok do return r, true
    unknown_name(s, what, name, map_keys(table))
    return {}, false
}

// call_registered calls a filter or test with evaluated arguments.
@(private)
call_registered :: #force_no_inline proc(s: ^State, r: Registered, name: string,
    args: []Value, kwargs: []Keyword) -> Value {
    c := Call{args = args, kwargs = kwargs, user = r.user, name = name, state = s}
    v := r.procedure(&c)
    if s.failed do return Undefined{}
    return v
}

// call_filter runs a registered filter by name (used by map, and by hosts).
call_filter :: proc(s: ^State, name: string, args: []Value, kwargs: []Keyword) -> Value {
    f, ok := s.env.filters[name]
    if !ok do return unknown_name(s, "filter", name, map_keys(s.env.filters))
    c := Call{args = args, kwargs = kwargs, user = f.user, name = name, state = s}
    return f.procedure(&c)
}

// call_test runs a registered test by name (used by select and reject).
call_test :: proc(s: ^State, name: string, args: []Value, kwargs: []Keyword) -> bool {
    t, ok := s.env.tests[name]
    if !ok {
        unknown_name(s, "test", name, map_keys(s.env.tests))
        return false
    }
    c := Call{args = args, kwargs = kwargs, user = t.user, name = name, state = s}
    return truthy(t.procedure(&c))
}

