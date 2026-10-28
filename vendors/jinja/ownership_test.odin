package jinja

import "base:sanitizer"
import "core:mem"
import "core:strings"
import "core:testing"

// Poison is a memory that never reuses what is freed: it fills it with 0xDD instead,
// and keeps it until poison_destroy. A value still pointing into freed memory then reads
// garbage every time, instead of reading what happened to be left there; built with
// -sanitize:address, the read is reported where it happens.
@(private = "file")
Poison :: struct {
    backing: mem.Allocator,
    blocks:  [dynamic][]u8, // everything handed out, freed or not.
}

@(private = "file")
poison_init :: proc(p: ^Poison, backing: mem.Allocator) {
    p^ = Poison{backing = backing, blocks = make([dynamic][]u8, backing)}
}

@(private = "file")
poison_destroy :: proc(p: ^Poison) {
    for b in p.blocks {
        sanitizer.address_unpoison(b)
        mem.free_bytes(b, p.backing)
    }
    delete(p.blocks)
}

// kill marks freed memory: garbage to read, and, under -sanitize:address, a report.
@(private = "file")
kill :: proc(b: []u8) {
    mem.set(raw_data(b), 0xDD, len(b))
    sanitizer.address_poison(b)
}

@(private = "file")
poison_block :: proc(p: ^Poison, old: rawptr) -> []u8 {
    for b in p.blocks do if raw_data(b) == old do return b
    return nil
}

@(private = "file")
poison_allocator :: proc(p: ^Poison) -> mem.Allocator {
    return {procedure = proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
        old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]u8,
        mem.Allocator_Error) {
        p := (^Poison)(data)
        switch mode {
        case .Alloc, .Alloc_Non_Zeroed:
            out, err := mem.alloc_bytes(max(size, 1), alignment, p.backing)
            if err != nil do return nil, err
            append(&p.blocks, out)
            return out[:size], nil
        case .Resize, .Resize_Non_Zeroed:
            out, err := mem.alloc_bytes(max(size, 1), alignment, p.backing)
            if err != nil do return nil, err
            append(&p.blocks, out)
            if old := poison_block(p, old_memory); old != nil {
                copy(out, old[:min(old_size, size, len(old))])
                kill(old)
            }
            return out[:size], nil
        case .Free:
            if old := poison_block(p, old_memory); old != nil {
                kill(old)
            }
        case .Free_All, .Query_Info:
            return nil, .Mode_Not_Implemented
        case .Query_Features:
            set := (^mem.Allocator_Mode_Set)(old_memory)
            if set != nil {
                set^ = {.Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed, .Free,
                    .Query_Features}
            }
        }
        return nil, nil
    }, data = p}
}

// Values a template stores in the caller's lists and dicts are the caller's: they are in
// the containers' own memory after the render, whose scratch memory is freed, and after
// the environment, which held the template's literals, is destroyed. Inside the render
// they are shared as in Jinja: a list appended and then changed is kept as changed.
@(test)
stored_values_outlive_the_render :: proc(t: ^testing.T) {
    p: Poison
    poison_init(&p, context.allocator)
    defer poison_destroy(&p)
    context.allocator = poison_allocator(&p)
    items := list(str("a"))
    empty := dict() // its arrays are made at its first entry, during the render.
    ctx := dict()
    set(ctx, "items", items)
    set(ctx, "d", empty)
    env := create_environment()
    tpl, perr := parse_template(&env, "page.html", "{% set n = 1 %}{% set late = [] %}" +
        "{% do items.append('b' ~ n) %}{% do items.extend(['c', ['x' ~ n]]) %}" +
        "{% do items.append(late) %}{% do late.append('after' ~ n) %}" +
        "{% do items.insert(1, 'lit') %}{% do d.update(k='v' ~ n) %}" +
        "{% do d.setdefault('lit', ('t', 'u')) %}{% set ns = namespace(a=1) %}" +
        "{% do d.update(ns=ns) %}{% set ns.a = 'two' * 2 %}{% do items.append(range) %}" +
        "{% for x in [1] %}{% do items.append(loop) %}{% endfor %}")
    testing.expect_value(t, perr.kind, Error_Kind.None)
    out, err := render(&tpl, ctx)
    testing.expect_value(t, err.kind, Error_Kind.None)
    testing.expect_value(t, out, "")
    destroy_environment(&env)
    testing.expect_value(t, repr(items), "['a', 'lit', 'b1', 'c', ['x1'], ['after1'], " +
        "<built-in function range>, <LoopContext 1/1>]")
    testing.expect_value(t, repr(empty), "{'k': 'v1', 'lit': ('t', 'u'), " +
        "'ns': <Namespace {'a': 'twotwo'}>}")
    testing.expect_value(t, to_string(get(empty, "k")), "v1")
    ns := get(empty, "ns")
    testing.expect_value(t, to_string(get(ns, "a")), "twotwo")
    // A second render sees the values the first one stored.
    env = create_environment()
    defer destroy_environment(&env)
    again, aerr := render_source(&env, "{{ items[2] }} {{ items[5][0] }} {{ d.ns.a }} " +
        "{{ items[6](2)|list }}", ctx)
    testing.expect_value(t, aerr.kind, Error_Kind.None)
    testing.expect_value(t, again, "b1 after1 twotwo [0, 1]")
}

// A macro, a joiner or a block reference belongs to the render that made it: stored in
// the caller's list, it is still there after the render, and calling it later is an
// error that says so, instead of reaching into the render's freed memory.
@(test)
stored_macros_cannot_be_called_after_their_render :: proc(t: ^testing.T) {
    p: Poison
    poison_init(&p, context.allocator)
    defer poison_destroy(&p)
    context.allocator = poison_allocator(&p)
    items := list()
    ctx := dict()
    set(ctx, "items", items)
    env := create_environment()
    defer destroy_environment(&env)
    _, err := render_source(&env, "{% macro card(x) %}<{{ x }}>{% endmacro %}" +
        "{% do items.append(card) %}{% do items.append(joiner(',')) %}{{ items[0](1) }}",
        ctx)
    testing.expect_value(t, err.kind, Error_Kind.None)
    testing.expect_value(t, length(items), 2)
    _, later := render_source(&env, "{{ items[0](1) }}", ctx)
    testing.expect_value(t, later.kind, Error_Kind.Runtime)
    testing.expectf(t, strings.contains(later.message, "'card'") &&
        strings.contains(later.message, "render that has ended"), "%s", later.message)
    testing.expectf(t, strings.contains(later.hint, "import"), "%s", later.hint)
    _, later = render_source(&env, "{{ items[1]() }}", ctx)
    testing.expect_value(t, later.kind, Error_Kind.Runtime)
}

// A list extended with itself reads its items before it grows, not from the storage the
// growth freed.
@(test)
lists_extend_with_themselves :: proc(t: ^testing.T) {
    p: Poison
    poison_init(&p, context.allocator)
    defer poison_destroy(&p)
    context.allocator = poison_allocator(&p)
    env := create_environment()
    defer destroy_environment(&env)
    out, err := render_source(&env, "{% set l = [7] * 2000 %}{% do l.extend(l) %}" +
        "{{ l|length }} {{ l|sum }}")
    testing.expect_value(t, err.kind, Error_Kind.None)
    testing.expect_value(t, out, "4000 28000")
}

// A render that stops still leaves the caller's containers holding only their own memory.
@(test)
failed_renders_leave_stored_values_whole :: proc(t: ^testing.T) {
    p: Poison
    poison_init(&p, context.allocator)
    defer poison_destroy(&p)
    context.allocator = poison_allocator(&p)
    items := list()
    ctx := dict()
    set(ctx, "items", items)
    env := create_environment()
    defer destroy_environment(&env)
    _, err := render_source(&env, "{% do items.append('kept' ~ 1) %}{{ missing.attr }}", ctx)
    testing.expect_value(t, err.kind, Error_Kind.Undefined)
    testing.expect_value(t, repr(items), "['kept1']")
}
