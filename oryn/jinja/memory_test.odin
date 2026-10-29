package jinja

import "base:runtime"
import "core:mem"
import "core:strings"
import "core:testing"

// Faulty refuses requests by number, as a memory that runs out does: the request
// numbered fail_at alone (only), or it and every one after. Requests that pass go to
// an arena the test frees at once.
@(private = "file")
Faulty :: struct {
    arena:   Arena,
    count:   int,
    fail_at: int, // -1: never.
    only:    bool,
}

@(private = "file")
faulty_allocator :: proc(f: ^Faulty) -> mem.Allocator {
    return {procedure = proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
        old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]u8,
        mem.Allocator_Error) {
        f := (^Faulty)(data)
        #partial switch mode {
        case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
            if mode == .Alloc || mode == .Alloc_Non_Zeroed || size > old_size {
                n := f.count
                f.count += 1
                if n == f.fail_at || !f.only && f.fail_at >= 0 && n > f.fail_at {
                    return nil, .Out_Of_Memory
                }
            }
        }
        a := arena_allocator(&f.arena)
        return a.procedure(a.data, mode, size, alignment, old_memory, old_size, loc)
    }, data = f}
}

// render_faulty parses and renders source with every request of the parse and the
// render going to a Faulty allocator (not through an arena of blocks, so that each one
// can be refused), and returns what it rendered and how many requests it made.
@(private = "file")
render_faulty :: proc(env: ^Environment, source: string, ctx: Value, fail_at: int,
    only: bool) -> (text: string, err: Error, requests: int) {
    f := Faulty{fail_at = fail_at, only = only}
    arena_init(&f.arena, context.allocator)
    defer arena_destroy(&f.arena)
    started := begin_stack(env)
    defer end_stack(env, started)
    caller := context.allocator
    guard := Guard{backing = faulty_allocator(&f), doing = "Parsing"}
    {
        context.allocator = guard_allocator(&guard)
        compiled, perr := parse(env, source, "page.html", &guard)
        if perr.kind == .None {
            guard.doing = "Rendering"
            text, err = render_compiled(env, compiled, ctx, &guard, &f.arena, caller)
        } else {
            err = perr
        }
    }
    text = strings.clone(text)
    err = clone_error(err, context.allocator)
    return text, err, f.count
}

@(private = "file", rodata)
FAULT_TEMPLATES := [?]string{
    "Hello {{ name }}! {{ items|join(', ') }} {{ items|length }}",
    "{% for x in items %}{{ loop.index }}:{{ x|upper }}{% if not loop.last %},{% endif %}" +
    "{% else %}none{% endfor %}",
    "{% macro card(t, n=1) %}<{{ t }}*{{ n }}{{ varargs }}{{ kwargs }}>{% endmacro %}" +
    "{{ card('a') }}{{ card('b', 2, 3, k=4) }}{% call card('c') %}in{% endcall %}",
    "{% set ns = namespace(total=0) %}{% for x in [1, 2, 3] %}{% set ns.total = " +
    "ns.total + x %}{% endfor %}{{ ns.total }} {{ {'a': [1, (2, 3)], 'b': none}|tojson }}",
    "{% extends 'base.html' %}{% block body %}[{{ super() }}|{{ self.title() }}]" +
    "{% endblock %}",
    "{% include 'part.html' %}{% from 'macros.html' import m %}{{ m(3) }}" +
    "{% import 'macros.html' as lib %}{{ lib.m(4) }}",
    "{% set text %}{{ '%-6s|%05.1f' % ('ab', 3.14159) }}{% endset %}{{ text|trim }} " +
    "{{ '{:>6}|{:^7}'.format('x', 'yz') }} {{ 'a b c'.split()|reverse|list }}",
    "{{ items|map('upper')|select('ne', 'B')|join }} {{ items|sort(reverse=true)|first }} " +
    "{{ [3, 1, 2]|sort|sum }} {{ items|batch(2)|list }} {{ items|groupby('0')|list }}",
    "{% filter upper %}{{ 'x' * 3 }}{{ [1] * 2 }}{{ 'y'|center(7) }}{% endfilter %}" +
    "{{ 'wrap these words please'|wordwrap(9) }}{{ 'line\nnext'|indent(2, true) }}",
    "{{ range(5)|list }} {{ 'a' ~ 1 ~ none }} {{ lipsum(1, false, 3, 5) }} " +
    "{{ items[1:] }} {{ 'abcdef'[::2] }} {{ {'k': 'v'}.items()|list }}",
    "{% trans count=items|length %}{{ count }} item{% pluralize %}{{ count }} items" +
    "{% endtrans %} {{ missing|default('fallback') }} {{ 'x' in items }}",
    "{% for row in [[1, 2], [3]] recursive %}{{ row }}{% endfor %}{{ cycler(1, 2).next() }}" +
    "{% with a = 1, b = 2 %}{{ a + b }}{% endwith %}{{ undefined_name.attr }}",
    "{{ '<b>x</b> www.example.com'|urlize }} {{ '<p>a</p>'|striptags }} {{ 'a&b'|e }} " +
    "{{ {'q': 'a b'}|urlencode }} {{ 'Hello World'|truncate(8) }} {{ items|unique|list }}",
    "{{ 'abc def'|title }} {{ 3.14159|round(2) }} {{ 1234567|filesizeformat }} " +
    "{{ '%s' % items }} {{ 'a,b'.split(',')|max }} {{ 'x'.ljust(5) }}| {{ 'x'.zfill(4) }} " +
    "{{ {'b': 1, 'a': 2}|dictsort }} {{ items|slice(2)|list }} {{ 'x'|pprint }}",
}

@(private = "file")
fault_environment :: proc() -> Environment {
    env := create_environment({autoescape = true})
    add_template(&env, "base.html", "<t>{% block title %}T{% endblock %}</t>" +
        "{% block body %}B{% endblock %}")
    add_template(&env, "part.html", "(part {{ name }})")
    add_template(&env, "macros.html", "{% macro m(x) %}m{{ x }}{% endmacro %}")
    return env
}

// Whatever request a parse or render has refused, alone or with every one after it,
// the render ends with the text it renders with enough memory or with a Memory error
// (or the error the template has anyway), never with a crash or a wrong text.
@(test)
refused_requests_never_crash_a_render :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    env := fault_environment()
    defer destroy_environment(&env)
    data, derr := evaluate(&env, "{'name': 'World', 'items': ['a', 'b', 'c']}")
    testing.expect_value(t, derr.kind, Error_Kind.None)
    for source in FAULT_TEMPLATES {
        want, want_err, requests := render_faulty(&env, source, data, -1, false)
        testing.expectf(t, requests >= 20, "%q made %d requests", source, requests)
        for n in 0 ..< requests {
            for only in ([]bool{true, false}) {
                got, err, _ := render_faulty(&env, source, data, n, only)
                if err.kind == .Memory {
                    testing.expectf(t, err.message != "" && err.hint != "",
                        "%q, request %d: a Memory error without a message", source, n)
                    continue
                }
                testing.expectf(t, err.kind == want_err.kind && got == want,
                    "%q, request %d refused (only %v): got %q (%v), want %q (%v)", source,
                    n, only, got, err.kind, want, want_err.kind)
            }
        }
    }
}

// An environment whose memory runs out while it is set up says so, and so does every
// template parsed in it, instead of failing on a filter it could not register.
@(test)
refused_setup_fails_every_parse :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    for n in 0 ..< 8 {
        f := Faulty{fail_at = n}
        arena_init(&f.arena, context.temp_allocator)
        defer arena_destroy(&f.arena)
        env: Environment
        {
            context.allocator = faulty_allocator(&f)
            env = create_environment()
        }
        tpl, err := parse_template(&env, "t.html", "{{ 'a'|upper }}")
        if env.out_of_memory {
            testing.expect_value(t, err.kind, Error_Kind.Memory)
        } else {
            testing.expect_value(t, err.kind, Error_Kind.None)
            out, rerr := render(&tpl)
            testing.expect(t, rerr.kind == .None && out == "A" || rerr.kind == .Memory)
        }
        destroy_environment(&env)
    }
}

// Budget is a memory of cap bytes, as a build's budget is: a request that would take
// more is refused before it is allocated, and peak is the most held at once.
@(private = "file")
Budget :: struct {
    cap, used, peak: int,
}

@(private = "file")
budget_allocator :: proc(b: ^Budget) -> mem.Allocator {
    return {procedure = proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
        old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]u8,
        mem.Allocator_Error) {
        b := (^Budget)(data)
        grow := size
        #partial switch mode {
        case .Resize, .Resize_Non_Zeroed: grow = size - old_size
        case .Free: grow = -old_size
        case .Alloc, .Alloc_Non_Zeroed:
        case: grow = 0
        }
        if grow > 0 && grow > b.cap - b.used do return nil, .Out_Of_Memory
        out, err := runtime.heap_allocator_proc(nil, mode, size, alignment, old_memory, old_size,
            loc)
        if err == nil {
            b.used += grow
            b.peak = max(b.peak, b.used)
        }
        return out, err
    }, data = b}
}

// Values whose size is known before they are built are refused before they are
// allocated: a render in 4 MiB that asks for tens of MiB fails with a Memory error at
// the line that asked, and never holds more than its budget.
@(test)
large_values_are_refused_before_they_are_built :: proc(t: ^testing.T) {
    CAP :: 4 << 20
    cases := [?]string{
        "line one\n{{ 'x' * 60000000 }}",
        "line one\n{{ [1, 2] * 30000000 }}",
        "line one\n{{ range(5000000)|join(',') }}",
        "line one\n{{ 'x'|center(60000000) }}",
        "line one\n{{ '%60000000d' % 1 }}",
        "line one\n{{ '{:>60000000}'.format(1) }}",
        "line one\n{{ 'a\\nb'|indent(60000000) }}",
        "line one\n{{ ('x' * 3000000) ~ ('y' * 3000000) }}",
        "line one\n{{ 'z'.zfill(60000000) }}",
        "line one\n{% for i in range(100000) %}{{ 'x' * 100 }}{% endfor %}",
        "line one\n{{ 'x' * 9223372036854775807 }}",
    }
    for source in cases {
        b := Budget{cap = CAP}
        err: Error
        {
            context.allocator = budget_allocator(&b)
            env := create_environment()
            _, e := render_source(&env, source)
            err = clone_error(e, context.temp_allocator)
            destroy_error(e)
            destroy_environment(&env)
        }
        testing.expectf(t, err.kind == .Memory, "%q: got %v, want a Memory error", source,
            err.kind)
        testing.expectf(t, err.line == 2, "%q: error on line %d, want 2", source, err.line)
        testing.expectf(t, b.peak <= CAP, "%q: held %d bytes, more than %d", source, b.peak,
            CAP)
        testing.expectf(t, b.used == 0, "%q: %d bytes not freed", source, b.used)
        report := format_error(err, context.temp_allocator)
        testing.expectf(t, strings.contains(report, "OUT OF MEMORY") &&
            strings.contains(report, "<template>:2"), "%q: %s", source, report)
    }
}

// With max_output set, a value larger than it is a Limit error before anything is
// allocated for it.
@(test)
max_output_bounds_each_value :: proc(t: ^testing.T) {
    b := Budget{cap = 64 << 20}
    err: Error
    {
        context.allocator = budget_allocator(&b)
        env := create_environment({max_output = 1000})
        _, e := render_source(&env, "{{ ('x' * 60000000)|length }}")
        err = clone_error(e, context.temp_allocator)
        destroy_error(e)
        destroy_environment(&env)
    }
    testing.expect_value(t, err.kind, Error_Kind.Limit)
    testing.expectf(t, strings.contains(err.message, "output limit of 1000"), "%s",
        err.message)
    testing.expectf(t, b.peak < 1 << 20, "held %d bytes", b.peak)
}

// The arena survives a refused block: the request fails, nothing changes, and the next
// request is served from a real block (a Dynamic_Arena would hand out address 0).
@(test)
arenas_survive_refused_blocks :: proc(t: ^testing.T) {
    f := Faulty{fail_at = 1, only = true}
    arena_init(&f.arena, context.allocator)
    defer arena_destroy(&f.arena)
    a: Arena
    arena_init(&a, faulty_allocator(&f), 1024)
    defer arena_destroy(&a)
    alloc := arena_allocator(&a)
    for _ in 0 ..< 4 { // the first block, all but 24 bytes.
        first, e1 := mem.alloc_bytes(250, 8, alloc)
        testing.expect(t, e1 == nil && len(first) == 250)
    }
    _, e2 := mem.alloc_bytes(250, 8, alloc) // needs a second block: refused.
    testing.expect_value(t, e2, mem.Allocator_Error.Out_Of_Memory)
    third, e3 := mem.alloc_bytes(250, 8, alloc)
    testing.expect(t, e3 == nil && raw_data(third) != nil && len(third) == 250)
    third[249] = 7
    grown, e4 := mem.resize_bytes(third, 256, 8, alloc) // the last request grows in place.
    testing.expect(t, e4 == nil && raw_data(grown) == raw_data(third) && grown[249] == 7)
    big, e5 := mem.alloc_bytes(10_000, 8, alloc) // a block of its own.
    testing.expect(t, e5 == nil && len(big) == 10_000)
    big[9_999] = 1
    bigger, e6 := mem.resize_bytes(big, 20_000, 8, alloc)
    testing.expect(t, e6 == nil && bigger[9_999] == 1 && bigger[19_999] == 0)
    testing.expect(t, a.large != nil && a.large.next == nil) // the old block was freed.
}
