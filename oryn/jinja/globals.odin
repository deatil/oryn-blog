#+private
package jinja

import "core:strings"

// The built-in globals: range, dict, lipsum, cycler, joiner, namespace and the
// pass-through gettext functions of the i18n extension.

register_globals :: proc(env: ^Environment) {
    add_function(env, "range", global_range)
    add_function(env, "dict", global_dict)
    add_function(env, "lipsum", global_lipsum)
    add_function(env, "cycler", global_cycler)
    add_function(env, "joiner", global_joiner)
    add_function(env, "namespace", global_namespace)
    add_function(env, "gettext", global_gettext)
    add_function(env, "_", global_gettext)
    add_function(env, "ngettext", global_ngettext)
}

@(private="file")
global_range :: proc(c: ^Call) -> Value {
    if len(c.kwargs) > 0 do return fail(c, "range() takes no keyword arguments")
    if len(c.args) == 0 || len(c.args) > 3 {
        return fail(c, "range expected at most 3 arguments, got %d", len(c.args))
    }
    bounds: [3]i64 = {0, 0, 1}
    for v, i in c.args {
        n, _, kind := as_number(v)
        if kind != .Int {
            return fail(c, "'%s' object cannot be interpreted as an integer", type_name(v))
        }
        bounds[i] = n
    }
    start, stop, step := bounds[0], bounds[1], bounds[2]
    if len(c.args) == 1 do start, stop = 0, bounds[0]
    if step == 0 do return fail(c, "range() arg 3 must not be zero")
    count: i64 = 0
    if step > 0 && stop > start do count = (stop - start + step - 1) / step
    if step < 0 && stop < start do count = (start - stop - step - 1) / -step
    limit := i64(c.state.env.options.max_iterations)
    if count > limit {
        runtime_error(c.state, .Limit, "range() of %d items exceeds the iteration limit %d",
            count, limit)
        return Undefined{}
    }
    if _, ok := reserve_bytes(c.state, int(count), size_of(Value)); !ok do return Undefined{}
    out := new_list(int(count))
    if out == nil do return Undefined{}
    for i in 0 ..< count do append(&out.items, start + i * step)
    return out
}

@(private="file")
global_dict :: proc(c: ^Call) -> Value {
    d := new_dict(.Dict)
    if d == nil do return Undefined{}
    if len(c.args) > 1 do return fail(c, "dict expected at most 1 argument, got %d", len(c.args))
    if len(c.args) == 1 {
        #partial switch x in c.args[0] {
        case ^Dict:
            for key, i in x.keys do dict_set(d, key, x.values[i])
        case:
            items, ok := iterate(c.state, x)
            if !ok do return Undefined{}
            for item in items {
                pair, is_list := item.(^List)
                if !is_list || len(pair.items) != 2 {
                    return fail(c, "dictionary update sequence element has wrong length")
                }
                dict_set(d, pair.items[0], pair.items[1])
            }
        }
    }
    for kw in c.kwargs do dict_set(d, kw.name, kw.value)
    return d
}

@(private="file")
global_namespace :: proc(c: ^Call) -> Value {
    v := global_dict(c)
    if d, ok := v.(^Dict); ok do d.kind = .Namespace
    return v
}

@(private="file")
global_cycler :: proc(c: ^Call) -> Value {
    cy := new(Cycler)
    items := list_of(c.args)
    if cy == nil || items == nil do return Undefined{}
    cy.items = items.items[:]
    return cy
}

Joiner :: struct {
    sep:  Value,
    used: bool,
}

@(private="file")
global_joiner :: proc(c: ^Call) -> Value {
    j := new(Joiner)
    if j == nil do return Undefined{}
    j.sep = arg(c, 0, "sep", string(", "))
    call :: proc(c: ^Call) -> Value {
        j := (^Joiner)(c.user)
        if !j.used {
            j.used = true
            return string("")
        }
        return j.sep
    }
    return function("joiner", call, j)
}

@(private="file")
global_gettext :: proc(c: ^Call) -> Value {
    return arg(c, 0, "message", string(""))
}

@(private="file")
global_ngettext :: proc(c: ^Call) -> Value {
    n, _, _ := as_number(arg(c, 2, "n", i64(1)))
    if n == 1 do return arg(c, 0, "singular", string(""))
    return arg(c, 1, "plural", string(""))
}

// ---------------------------------------------------------------------------------------
// Deterministic random numbers (PCG32), seeded from Options.random_seed

random_u32 :: proc(s: ^State) -> u32 {
    old := s.rng
    s.rng = old * 6364136223846793005 + 1442695040888963407
    xorshifted := u32(((old >> 18) ~ old) >> 27)
    rot := u32(old >> 59)
    return (xorshifted >> rot) | (xorshifted << ((-rot) & 31))
}

// random_below returns a number in [0, n).
random_below :: proc(s: ^State, n: int) -> int {
    if n <= 0 do return 0
    return int(u64(random_u32(s)) * u64(n) >> 32)
}

@(private="file")
LOREM := [?]string {
    "a", "ac", "accumsan", "ad", "adipiscing", "aenean", "aliquam", "aliquet", "amet",
    "ante", "aptent", "arcu", "at", "auctor", "augue", "bibendum", "blandit", "class",
    "commodo", "condimentum", "congue", "consectetuer", "consequat", "conubia", "convallis",
    "cras", "cubilia", "cum", "curabitur", "curae", "cursus", "dapibus", "diam", "dictum",
    "dictumst", "dignissim", "dis", "dolor", "donec", "dui", "duis", "egestas", "eget",
    "eleifend", "elementum", "elit", "enim", "erat", "eros", "est", "et", "etiam", "eu",
    "euismod", "facilisi", "facilisis", "fames", "faucibus", "felis", "fermentum",
    "feugiat", "fringilla", "fusce", "gravida", "habitant", "habitasse", "hac", "hendrerit",
    "hymenaeos", "iaculis", "id", "imperdiet", "in", "inceptos", "integer", "interdum",
    "ipsum", "justo", "lacinia", "lacus", "laoreet", "lectus", "leo", "libero", "ligula",
    "litora", "lobortis", "lorem", "luctus", "maecenas", "magna", "magnis", "malesuada",
    "massa", "mattis", "mauris", "metus", "mi", "molestie", "mollis", "montes", "morbi",
    "mus", "nam", "nascetur", "natoque", "nec", "neque", "netus", "nibh", "nisi", "nisl",
    "non", "nonummy", "nostra", "nulla", "nullam", "nunc", "odio", "orci", "ornare",
    "parturient", "pede", "pellentesque", "penatibus", "per", "pharetra", "phasellus",
    "placerat", "platea", "porta", "porttitor", "posuere", "potenti", "praesent", "pretium",
    "primis", "proin", "pulvinar", "purus", "quam", "quis", "quisque", "rhoncus",
    "ridiculus", "risus", "rutrum", "sagittis", "sapien", "scelerisque", "sed", "sem",
    "semper", "senectus", "sit", "sociis", "sociosqu", "sodales", "sollicitudin",
    "suscipit", "suspendisse", "taciti", "tellus", "tempor", "tempus", "tincidunt",
    "torquent", "tortor", "tristique", "turpis", "ullamcorper", "ultrices", "ultricies",
    "urna", "ut", "varius", "vehicula", "vel", "velit", "venenatis", "vestibulum", "vitae",
    "vivamus", "viverra", "volutpat", "vulputate",
}

// global_lipsum generates lorem ipsum paragraphs like Jinja's generate_lorem_ipsum:
// commas every few words, a period at the end, capitalized sentences.
@(private="file")
global_lipsum :: proc(c: ^Call) -> Value {
    s := c.state
    n, _ := arg_int(c, 0, "n", 5)
    html := truthy(arg(c, 1, "html", true))
    lo, _ := arg_int(c, 2, "min", 20)
    hi, _ := arg_int(c, 3, "max", 100)
    paragraphs := make([dynamic]string)
    for _ in 0 ..< n {
        if !limit_iteration(s) do return Undefined{}
        count := int(lo) + random_below(s, int(max(hi - lo, 0)) + 1)
        b := strings.builder_make()
        next_capital := true
        last_comma, last_fullstop := 0, 0
        last_word := ""
        for i in 0 ..< count {
            if !limit_iteration(s) do return Undefined{}
            word := LOREM[random_below(s, len(LOREM))]
            for word == last_word do word = LOREM[random_below(s, len(LOREM))]
            last_word = word
            if i > 0 do strings.write_byte(&b, ' ')
            strings.write_string(&b, python_capitalize(word) if next_capital else word)
            next_capital = false
            if i - random_below(s, 7) - 3 > last_comma {
                last_comma = i
                last_fullstop += 2
                strings.write_byte(&b, ',')
            }
            if i - random_below(s, 11) - 10 > last_fullstop {
                last_comma, last_fullstop = i, i
                strings.write_byte(&b, '.')
                next_capital = true
            }
        }
        text := strings.to_string(b)
        text = strings.trim_right(text, ",")
        if !strings.has_suffix(text, ".") do text = strings.concatenate({text, "."})
        append(&paragraphs, text)
    }
    if !html do return strings.join(paragraphs[:], "\n\n")
    b := strings.builder_make()
    for p, i in paragraphs {
        if i > 0 do strings.write_string(&b, "\n")
        strings.write_string(&b, "<p>")
        write_escaped(&b, p)
        strings.write_string(&b, "</p>")
    }
    return Markup(strings.to_string(b))
}
