package jinja

import "core:strings"
import "core:testing"

// Test helpers. Every test renders with context.allocator = context.temp_allocator.

// run renders source with a context written as a Jinja dict literal ("{'a': 1}").
run :: proc(source: string, ctx := "", options: Options = {},
    templates: map[string]string = nil) -> (string, Error) {
    env := create_environment(options)
    defer destroy_environment(&env)
    for name, text in templates {
        if err := add_template(&env, name, text); err.kind != .None do return "", err
    }
    data: Value
    if ctx != "" {
        v, err := evaluate(&env, ctx)
        if err.kind != .None do return "", err
        data = v
    }
    return render_source(&env, source, data)
}

// check asserts that source renders to expected.
check :: proc(t: ^testing.T, source, expected: string, ctx := "", options: Options = {},
    templates: map[string]string = nil, loc := #caller_location) {
    out, err := run(source, ctx, options, templates)
    if err.kind != .None {
        testing.expectf(t, false, "%q: unexpected error: %s", source, format_error(err),
            loc = loc)
        return
    }
    testing.expectf(t, out == expected, "%q:\n  got      %q\n  expected %q", source, out,
        expected, loc = loc)
}

// check_error asserts that rendering fails with a message containing want.
check_error :: proc(t: ^testing.T, source, want: string, ctx := "", options: Options = {},
    templates: map[string]string = nil, line := 0, loc := #caller_location) {
    out, err := run(source, ctx, options, templates)
    if err.kind == .None {
        testing.expectf(t, false, "%q: expected error containing %q, got output %q", source,
            want, out, loc = loc)
        return
    }
    testing.expectf(t, strings.contains(err.message, want), "%q: error %q lacks %q", source,
        err.message, want, loc = loc)
    if line > 0 {
        testing.expectf(t, err.line == line, "%q: error on line %d, expected %d", source,
            err.line, line, loc = loc)
    }
}

@(test)
smoke :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "Hello {{ name }}!", "Hello World!", "{'name': 'World'}")
    check(t, "{% for x in [1, 2, 3] %}{{ x }}{% endfor %}", "123")
}
