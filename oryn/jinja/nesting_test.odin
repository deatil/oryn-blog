package jinja

import "core:fmt"
import "core:strings"
import "core:testing"

// Hostile nesting must end in a Limit error, never a stack overflow.

@(private = "file")
DEEP :: 100_000

@(private = "file")
wrap :: proc(open, inner, close: string, n: int) -> string {
    return strings.concatenate({strings.repeat(open, n), inner, strings.repeat(close, n)})
}

@(private = "file")
expect_limit :: proc(t: ^testing.T, what, source: string, want: string,
    options: Options = {}, loc := #caller_location) {
    out, err := run(source, options = options)
    testing.expectf(t, err.kind == .Limit, "%s: got %v %q (output %d bytes)", what, err.kind,
        err.message, len(out), loc = loc)
    testing.expectf(t, strings.contains(err.message, want), "%s: %q lacks %q", what,
        err.message, want, loc = loc)
}

@(test)
deeply_nested_syntax_is_a_limit_error :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    nests := "nests more than 100 levels"
    expect_limit(t, "parentheses", wrap("{{ ", wrap("(", "1", ")", DEEP), " }}", 1), nests)
    expect_limit(t, "lists", wrap("{{ ", wrap("[", "1", "]", DEEP), " }}", 1), nests)
    expect_limit(t, "dicts", wrap("{{ ", wrap("{'a': ", "1", "}", DEEP), " }}", 1), nests)
    expect_limit(t, "calls", wrap("{{ ", wrap("f(", "1", ")", DEEP), " }}", 1), nests)
    expect_limit(t, "tags", wrap("{% if 1 %}", "x", "{% endif %}", DEEP), nests)
    expect_limit(t, "elif", wrap("{% if 0 %}", strings.repeat("{% elif 0 %}", DEEP),
        "{% endif %}", 1), nests)
    // Chains build left-deep trees, so they nest too.
    expect_limit(t, "plus", wrap("{{ 1", strings.repeat(" + 1", DEEP), " }}", 1), nests)
    expect_limit(t, "and", wrap("{{ 1", strings.repeat(" and 1", DEEP), " }}", 1), nests)
    expect_limit(t, "not", wrap("{{ ", strings.repeat("not ", DEEP), "1 }}", 1), nests)
    expect_limit(t, "minus", wrap("{{ ", strings.repeat("- ", DEEP), "1 }}", 1), nests)
    expect_limit(t, "filters", wrap("{{ 1", strings.repeat("|abs", DEEP), " }}", 1), nests)
    expect_limit(t, "attributes", wrap("{{ x", strings.repeat(".a", DEEP), " }}", 1), nests)
    expect_limit(t, "tests", wrap("{{ 1", strings.repeat(" is number", DEEP), " }}", 1),
        nests)
    expect_limit(t, "conditions", wrap("{{ 1", strings.repeat(" if 1 else 2", DEEP), " }}", 1),
        nests)
    env := create_environment()
    defer destroy_environment(&env)
    _, err := evaluate(&env, wrap("(", "1", ")", DEEP))
    testing.expectf(t, err.kind == .Limit, "evaluate: got %v", err.kind)
}

// margin is a stack budget that the default limits must fit in with room to spare: half
// the default in an optimized build, all of it in an unoptimized or sanitized one, whose
// frames are larger (stack.odin).
@(private = "file")
margin :: proc() -> int {
    when ODIN_OPTIMIZATION_MODE != .None && ASAN_FRAME_SCALE == 1 {
        return DEFAULT_STACK_BYTES / 2
    } else {
        return DEFAULT_STACK_BYTES
    }
}

@(test)
nesting_up_to_the_limit_renders :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    // 98 brackets, plus the output expression and its tag, is 100 levels.
    for budget in ([2]int{0, margin()}) {
        options := Options{stack_bytes = budget}
        check(t, wrap("{{ ", wrap("(", "7", ")", 98), " }}", 1), "7", options = options)
        check(t, wrap("{{ ", wrap("[", "7", "]", 98), " }}", 1), wrap("[", "7", "]", 98),
            options = options)
        check(t, wrap("{{ ", wrap("{'a': ", "7", "}", 98), "|length }}", 1), "1",
            options = options)
        check(t, wrap("{% if 1 %}", "x", "{% endif %}", 99), "x", options = options)
        check(t, wrap("{{ 1", strings.repeat(" + 1", 98), " }}", 1), "99", options = options)
    }
    expect_limit(t, "raised", wrap("{{ ", wrap("(", "7", ")", 150), " }}", 1),
        "levels", options = {max_nesting = 120})
    check(t, wrap("{{ ", wrap("(", "7", ")", 110), " }}", 1), "7",
        options = {max_nesting = 120})
}

// Runaway is a template that recurses without end in one of the ways templates recurse.
@(private = "file")
Runaway :: struct {
    what, source, ctx: string,
}

@(private = "file")
RUNAWAYS := [?]Runaway {
    {"macro", "{% macro f(n) %}{{ f(n + 1) if n >= 0 else n }}{% endmacro %}{{ f(0) }}", ""},
    {"tag", "{% macro f(n) %}{% if n >= 0 %}{% set x = f(n + 1) %}{{ x }}{% endif %}" +
        "{% endmacro %}{{ f(0) }}", ""},
    {"loop", "{% for x in items recursive %}{% if loop.depth > 0 %}{{ loop(items) }}" +
        "{% endif %}{% endfor %}", "{'items': [1]}"},
    {"include", "{% include 'self.html' %}", ""},
    {"call block", "{% macro f(n) %}{% call f(n + 1) %}x{% endcall %}" +
        "{{ caller() if n > 0 else '' }}{% endmacro %}{{ f(0) }}", ""},
}

@(private = "file")
run_runaway :: proc(r: Runaway, options: Options) -> Error {
    templates := make(map[string]string)
    templates["self.html"] = "{% if true %}{% include 'self.html' %}{% endif %}"
    _, err := run(r.source, r.ctx, options, templates)
    return err
}

// The default stack budget holds the default max_recursion, with room to spare, so a
// template that recurses without end meets the recursion limit first, on every platform
// and at every optimization level.
@(test)
the_recursion_limit_comes_before_the_stack_budget :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    want := fmt.tprintf("recursion limit of %d", DEFAULT_MAX_RECURSION)
    for r in RUNAWAYS {
        for stack_bytes in ([2]int{0, margin()}) {
            err := run_runaway(r, {stack_bytes = stack_bytes})
            testing.expectf(t, strings.contains(err.message, want),
                "%s, stack budget %d: %q lacks %q", r.what, stack_bytes, err.message, want)
        }
    }
}

// Past the stack budget, recursion that max_recursion allows stops with a Limit error.
@(test)
the_stack_budget_stops_deep_recursion :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    unbounded := Options{max_recursion = 100_000, stack_bytes = 64 << 10}
    for r in RUNAWAYS {
        err := run_runaway(r, unbounded)
        testing.expectf(t, err.kind == .Limit &&
            strings.contains(err.message, "stack budget of 65536 bytes"), "%s: %v %q",
            r.what, err.kind, err.message)
    }
    expect_limit(t, "parse", wrap("{{ ", wrap("(", "1", ")", 5000), " }}", 1),
        "stack budget of 65536 bytes", options = {max_nesting = 100_000,
        stack_bytes = 64 << 10})
    // The default budget is the backstop for recursion the limits allow but whose levels
    // are each deep: here every macro call evaluates a list nested 90 levels deep.
    default_budget := fmt.tprintf("stack budget of %d bytes", DEFAULT_STACK_BYTES)
    deep := strings.concatenate({"{% macro f(n) %}{{ ", wrap("[", "f(n + 1)", "]", 90),
        " }}{% endmacro %}{{ f(0) }}"})
    expect_limit(t, "deep levels", deep, default_budget)
    err := run_runaway(RUNAWAYS[0], {max_recursion = 100_000})
    testing.expectf(t, strings.contains(err.message, default_budget), "macro: %q",
        err.message)
}

@(test)
self_containing_values_do_not_recurse_forever :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    grow := "{% set l = [] %}{% do l.append(l) %}"
    out, err := run(strings.concatenate({grow, "{{ l|length }}{{ l == l }}{{ [l] == [l] }}"}))
    testing.expectf(t, err.kind == .None && out == "1TrueTrue", "equality: %q %v", out, err)
    out, err = run(strings.concatenate({grow, "{{ l }}"}))
    testing.expectf(t, err.kind == .None && strings.contains(out, "[[[...]]]"), "repr: %q",
        out)
    check_error(t, strings.concatenate({grow, "{{ l|tojson }}"}), "contains itself")
    sorted := "{{ [[l], [l]]|sort(case_sensitive=false)|length }}"
    out, err = run(strings.concatenate({grow, sorted}))
    testing.expectf(t, err.kind == .Type || out == "2", "sort: %q %v", out, err.kind)
    deep := "{% set ns = namespace(l=[]) %}{% for i in range(5000) %}{% set ns.l = [ns.l] %}" +
        "{% endfor %}{{ ns.l }}"
    out, err = run(deep)
    testing.expectf(t, err.kind == .None && strings.contains(out, "[...]"), "deep: %v", err)
}

// Nodes in the wrong place (which the parser never builds) fail loudly instead of
// being skipped.
@(test)
misplaced_nodes_are_errors :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    defer free_all(context.temp_allocator)
    env := create_environment()
    defer destroy_environment(&env)
    out := strings.builder_make()
    s := new_state(&env, &out, nil)
    scope := new_scope(nil)
    assign(&s, scope, new_node(.Getattr, 1), i64(1))
    testing.expect(t, s.failed && strings.contains(s.err.message, "cannot assign"))
    s = new_state(&env, &out, nil)
    eval(&s, scope, new_node(.Data, 1))
    testing.expect(t, s.failed && strings.contains(s.err.message, "cannot evaluate"))
    s = new_state(&env, &out, nil)
    exec(&s, scope, new_node(.Const, 1))
    testing.expect(t, s.failed && strings.contains(s.err.message, "cannot execute"))
}
