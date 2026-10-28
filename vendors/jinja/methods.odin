#+private
package jinja

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

// Methods of Python's builtin types that templates call: "a,b".split(","), d.items().

@(private="file")
STRING_METHODS := [?]string {
    "upper", "lower", "title", "capitalize", "swapcase", "casefold", "strip", "lstrip",
    "rstrip", "split", "rsplit", "splitlines", "join", "replace", "startswith", "endswith",
    "find", "rfind", "index", "rindex", "count", "format", "format_map", "center", "ljust",
    "rjust", "zfill", "isdigit", "isalpha", "isalnum", "isspace", "islower", "isupper",
    "istitle", "isdecimal", "isnumeric", "isidentifier", "isascii", "partition",
    "rpartition", "removeprefix", "removesuffix", "expandtabs", "encode",
}

is_string_method :: proc(name: string, markup: bool) -> bool {
    for m in STRING_METHODS do if m == name do return true
    return markup && (name == "striptags" || name == "unescape" || name == "escape")
}

is_list_method :: proc(name: string, tuple: bool) -> bool {
    switch name {
    case "index", "count": return true
    case "append", "extend", "insert", "pop", "remove", "reverse", "sort", "clear", "copy":
        return !tuple
    }
    return false
}

is_dict_method :: proc(name: string) -> bool {
    switch name {
    case "items", "keys", "values", "get", "pop", "popitem", "setdefault", "update", "copy",
         "clear":
        return true
    }
    return false
}

// dispatch_method is the procedure of every bound method value.
dispatch_method :: proc(c: ^Call) -> Value {
    #partial switch x in c.self {
    case string, Markup: return string_method(c)
    case ^List: return list_method(c, x)
    case ^Dict: return dict_method(c, x)
    case ^Loop: return loop_method(c)
    case ^Cycler:
        if c.name == "reset" {
            x.pos = 0
            return None{}
        }
        if len(x.items) == 0 do return None{}
        v := x.items[x.pos]
        x.pos = (x.pos + 1) % len(x.items)
        return v
    case i64, f64, bool:
        _, f, kind := as_number(c.self)
        switch c.name {
        case "is_integer": return kind == .Int || f == f64(i64(f))
        case "conjugate": return c.self
        case "bit_length":
            i, _, _ := as_number(c.self)
            n: i64 = 0
            for v := abs(i); v > 0; v >>= 1 do n += 1
            return n
        }
    }
    return fail(c, "'%s' object has no attribute %s", type_name(c.self), repr(c.name))
}

// ---------------------------------------------------------------------------------------
// str

map_runes :: proc(s: string, f: proc(r: rune) -> rune) -> string {
    b := strings.builder_make(0, len(s))
    for r in s do strings.write_rune(&b, f(r))
    return strings.to_string(b)
}

to_upper :: proc(s: string) -> string { return map_runes(s, unicode.to_upper) }
to_lower :: proc(s: string) -> string { return map_runes(s, unicode.to_lower) }

// python_title is str.title(): a cased letter after a cased letter is lowercased.
python_title :: proc(s: string) -> string {
    b := strings.builder_make(0, len(s))
    prev_cased := false
    for r in s {
        cased := unicode.is_letter(r)
        if cased {
            strings.write_rune(&b, unicode.to_lower(r) if prev_cased else unicode.to_upper(r))
        } else {
            strings.write_rune(&b, r)
        }
        prev_cased = cased
    }
    return strings.to_string(b)
}

python_capitalize :: proc(s: string) -> string {
    b := strings.builder_make(0, len(s))
    for r, i in s {
        strings.write_rune(&b, unicode.to_upper(r) if i == 0 else unicode.to_lower(r))
    }
    return strings.to_string(b)
}

// strip_chars strips chars (whitespace when chars is empty) from the chosen sides.
strip_chars :: proc(s: string, chars: Value, left, right: bool) -> string {
    set, has := key_string(chars)
    is_strip :: proc(r: rune, set: string, has: bool) -> bool {
        if has do return strings.contains_rune(set, r)
        return is_space(r)
    }
    out := s
    if left {
        for len(out) > 0 {
            r, size := first_rune(out)
            if !is_strip(r, set, has) do break
            out = out[size:]
        }
    }
    if right {
        for len(out) > 0 {
            r, size := last_rune(out)
            if !is_strip(r, set, has) do break
            out = out[:len(out) - size]
        }
    }
    return out
}

first_rune :: proc(s: string) -> (rune, int) {
    return utf8.decode_rune_in_string(s)
}

last_rune :: proc(s: string) -> (rune, int) {
    return utf8.decode_last_rune_in_string(s)
}

rune_size :: proc(r: rune) -> int {
    switch {
    case r < 0x80: return 1
    case r < 0x800: return 2
    case r < 0x10000: return 3
    }
    return 4
}

// python_split_sep is str.split(sep, maxsplit) / rsplit with an explicit separator.
python_split_sep :: proc(s, sep: string, maxsplit: int, from_right: bool) -> []string {
    out := make([dynamic]string)
    rest := s
    splits := 0
    if !from_right {
        for maxsplit < 0 || splits < maxsplit {
            i := strings.index(rest, sep)
            if i < 0 do break
            append(&out, rest[:i])
            rest = rest[i + len(sep):]
            splits += 1
        }
        append(&out, rest)
        return out[:]
    }
    for maxsplit < 0 || splits < maxsplit {
        i := strings.last_index(rest, sep)
        if i < 0 do break
        inject_at(&out, 0, rest[i + len(sep):])
        rest = rest[:i]
        splits += 1
    }
    inject_at(&out, 0, rest)
    return out[:]
}

// python_split_ws is str.split() / rsplit() on whitespace with maxsplit.
python_split_ws :: proc(s: string, maxsplit: int, from_right: bool) -> []string {
    if maxsplit < 0 do return python_split(s)
    out := make([dynamic]string)
    if !from_right {
        rest := strip_chars(s, None{}, true, false)
        for len(rest) > 0 && len(out) < maxsplit {
            end := 0
            for r, i in rest {
                if is_space(r) do break
                end = i + rune_size(r)
            }
            append(&out, rest[:end])
            rest = strip_chars(rest[end:], None{}, true, false)
        }
        if len(rest) > 0 do append(&out, rest)
        return out[:]
    }
    rest := strip_chars(s, None{}, false, true)
    for len(rest) > 0 && len(out) < maxsplit {
        start := len(rest)
        for start > 0 {
            r, size := last_rune(rest[:start])
            if is_space(r) do break
            start -= size
        }
        inject_at(&out, 0, rest[start:])
        rest = strip_chars(rest[:start], None{}, false, true)
    }
    if len(rest) > 0 do inject_at(&out, 0, rest)
    return out[:]
}

// python_splitlines is str.splitlines(keepends).
python_splitlines :: proc(s: string, keepends := false) -> []string {
    out := make([dynamic]string)
    start := 0
    i := 0
    for i < len(s) {
        r, size := first_rune(s[i:])
        is_break := false
        switch r {
        case '\n', '\r', '\v', '\f', 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029: is_break = true
        }
        if !is_break { i += size; continue }
        end := i
        i += size
        if r == '\r' && i < len(s) && s[i] == '\n' do i += 1
        append(&out, s[start:i] if keepends else s[start:end])
        start = i
    }
    if start < len(s) do append(&out, s[start:])
    return out[:]
}

python_replace :: proc(s, old, new: string, count: int) -> string {
    if len(old) == 0 {
        b := strings.builder_make()
        n := 0
        for r in s {
            if count < 0 || n < count { strings.write_string(&b, new); n += 1 }
            strings.write_rune(&b, r)
        }
        if count < 0 || n < count do strings.write_string(&b, new)
        return strings.to_string(b)
    }
    out, _ := strings.replace(s, old, new, count)
    return out
}

// pad centers or justifies text to width runes with fill (str.center, ljust, rjust). The
// padded text is sized first and allocated once; ok is false when the render stopped.
pad :: proc(st: ^State, s: string, width: int, fill: string, align: byte) -> (string, bool) {
    n := strings.rune_count(s)
    if width <= n || fill == "" do return s, true
    total := width - n
    left := 0
    switch align {
    case '>': left = total
    case '^': left = total / 2 + (total & width & 1)
    case 'c': left = total / 2
    }
    fills, ok := reserve_bytes(st, total, len(fill))
    if !ok do return "", false
    size, sized := sum_bytes(st, fills, len(s))
    b := strings.builder_make()
    if !sized || !reserve_text(st, &b, size) do return "", false
    for _ in 0 ..< left do strings.write_string(&b, fill)
    strings.write_string(&b, s)
    for _ in 0 ..< total - left do strings.write_string(&b, fill)
    return strings.to_string(b), true
}

string_method :: proc(c: ^Call) -> Value {
    text, _ := key_string(c.self)
    markup := is_markup(c.self)
    wrap :: proc(v: string, markup: bool) -> Value {
        if markup do return Markup(v)
        return v
    }
    switch c.name {
    case "upper": return wrap(to_upper(text), markup)
    case "lower", "casefold": return wrap(to_lower(text), markup)
    case "title": return wrap(python_title(text), markup)
    case "capitalize": return wrap(python_capitalize(text), markup)
    case "swapcase":
        swap :: proc(r: rune) -> rune {
            if unicode.is_upper(r) do return unicode.to_lower(r)
            return unicode.to_upper(r)
        }
        return wrap(map_runes(text, swap), markup)
    case "strip": return wrap(strip_chars(text, arg(c, 0, "chars", None{}), true, true), markup)
    case "lstrip": return wrap(strip_chars(text, arg(c, 0, "chars", None{}), true, false), markup)
    case "rstrip": return wrap(strip_chars(text, arg(c, 0, "chars", None{}), false, true), markup)
    case "split", "rsplit": return split_method(c, text, markup)
    case "splitlines":
        lines := python_splitlines(text, truthy(arg(c, 0, "keepends", false)))
        out := new_list(len(lines))
        if out == nil do return Undefined{}
        for line in lines do append(&out.items, wrap(line, markup))
        return out
    case "join": return join_method(c, text, markup)
    case "replace":
        old, new := arg(c, 0, "old"), arg(c, 1, "new")
        count, _ := arg_int(c, 2, "count", -1)
        if markup {
            return Markup(python_replace(text, string(escape(old)), string(escape(new)),
                int(count)))
        }
        return python_replace(text, to_string(old), to_string(new), int(count))
    case "format", "format_map": return str_format(c, text, markup)
    }
    return string_method_more(c, text, markup)
}

split_method :: proc(c: ^Call, text: string, markup: bool) -> Value {
    sep := arg(c, 0, "sep", None{})
    maxsplit, _ := arg_int(c, 1, "maxsplit", -1)
    parts: []string
    if is_none(sep) {
        parts = python_split_ws(text, int(maxsplit), c.name == "rsplit")
    } else {
        sep_text := to_string(sep)
        if sep_text == "" do return fail(c, "empty separator")
        parts = python_split_sep(text, sep_text, int(maxsplit), c.name == "rsplit")
    }
    out := new_list(len(parts))
    if out == nil do return Undefined{}
    for p in parts do append(&out.items, Value(Markup(p)) if markup else Value(p))
    return out
}

join_method :: proc(c: ^Call, text: string, markup: bool) -> Value {
    items, ok := iterate(c.state, arg(c, 0, "iterable"))
    if !ok do return Undefined{}
    // The joined text is sized first, and allocated once.
    parts, err := make([]string, len(items))
    if err != nil do return Undefined{}
    total := 0
    for item, i in items {
        if markup {
            parts[i] = string(escape(item))
        } else if s, is_str := key_string(item); is_str {
            parts[i] = s
        } else {
            return fail(c, "sequence item %d: expected str instance, %s found", i,
                type_name(item))
        }
        total += len(parts[i])
    }
    seps, sized := reserve_bytes(c.state, max(len(items) - 1, 0), len(text))
    if !sized do return Undefined{}
    size, summed := sum_bytes(c.state, total, seps)
    b := strings.builder_make()
    if !summed || !reserve_text(c.state, &b, size) do return Undefined{}
    for part, i in parts {
        if i > 0 do strings.write_string(&b, text)
        strings.write_string(&b, part)
    }
    if markup do return Markup(strings.to_string(b))
    return strings.to_string(b)
}

find_in :: proc(text, sub: string, from_right: bool) -> int {
    i := strings.last_index(text, sub) if from_right else strings.index(text, sub)
    if i < 0 do return -1
    return strings.rune_count(text[:i])
}

string_method_more :: proc(c: ^Call, text: string, markup: bool) -> Value {
    switch c.name {
    case "startswith", "endswith":
        prefixes := arg(c, 0, "prefix")
        options: []Value = {prefixes}
        if l, ok := prefixes.(^List); ok do options = l.items[:]
        for p in options {
            ps := to_string(p)
            hit := strings.has_prefix(text, ps) if c.name == "startswith" else
                strings.has_suffix(text, ps)
            if hit do return true
        }
        return false
    case "find", "rfind", "index", "rindex":
        i := find_in(text, to_string(arg(c, 0, "sub")), c.name[0] == 'r')
        if i < 0 && (c.name == "index" || c.name == "rindex") {
            return fail(c, "substring not found")
        }
        return i64(i)
    case "count":
        sub := to_string(arg(c, 0, "sub"))
        if sub == "" do return i64(strings.rune_count(text) + 1)
        return i64(strings.count(text, sub))
    case "center", "ljust", "rjust":
        width, _ := arg_int(c, 0, "width", 0)
        fill := to_string(arg(c, 1, "fillchar", string(" ")))
        align: byte = '^' if c.name == "center" else ('<' if c.name == "ljust" else '>')
        out, padded := pad(c.state, text, int(clamp(width, 0, i64(max(int)))), fill, align)
        if !padded do return Undefined{}
        return Value(Markup(out)) if markup else Value(out)
    case "zfill":
        width, _ := arg_int(c, 0, "width", 0)
        n := strings.rune_count(text)
        if int(width) <= n do return c.self
        sign := ""
        body := text
        if len(body) > 0 && (body[0] == '-' || body[0] == '+') {
            sign = body[:1]
            body = body[1:]
        }
        zeros, ok := repeat_text(c.state, "0", int(clamp(width, 0, i64(max(int)))) - n)
        if !ok do return Undefined{}
        return strings.concatenate({sign, zeros, body})
    case "partition", "rpartition":
        sep := to_string(arg(c, 0, "sep"))
        i := strings.last_index(text, sep) if c.name == "rpartition" else strings.index(text, sep)
        if i < 0 {
            if c.name == "rpartition" do return tuple(string(""), string(""), text)
            return tuple(text, string(""), string(""))
        }
        return tuple(text[:i], sep, text[i + len(sep):])
    case "removeprefix":
        return strings.trim_prefix(text, to_string(arg(c, 0, "prefix")))
    case "removesuffix":
        return strings.trim_suffix(text, to_string(arg(c, 0, "suffix")))
    case "expandtabs":
        size, _ := arg_int(c, 0, "tabsize", 8)
        return expand_tabs(text, int(size))
    case "encode": return text
    case "striptags": return striptags(text)
    case "unescape": return unescape_html(text)
    case "escape": return c.self
    }
    return string_predicate(c, text)
}

expand_tabs :: proc(s: string, size: int) -> string {
    b := strings.builder_make()
    col := 0
    for r in s {
        switch r {
        case '\t':
            if size > 0 {
                spaces := size - col % size
                for _ in 0 ..< spaces do strings.write_byte(&b, ' ')
                col += spaces
            }
        case '\n', '\r':
            strings.write_rune(&b, r)
            col = 0
        case:
            strings.write_rune(&b, r)
            col += 1
        }
    }
    return strings.to_string(b)
}

string_predicate :: proc(c: ^Call, text: string) -> Value {
    if len(text) == 0 && c.name != "isascii" do return false
    switch c.name {
    case "isdigit", "isdecimal", "isnumeric":
        for r in text do if !unicode.is_digit(r) && !unicode.is_number(r) do return false
        return true
    case "isalpha":
        for r in text do if !unicode.is_letter(r) do return false
        return true
    case "isalnum":
        for r in text do if !unicode.is_letter(r) && !unicode.is_number(r) do return false
        return true
    case "isspace":
        for r in text do if !is_space(r) do return false
        return true
    case "isascii":
        for r in text do if r > 0x7f do return false
        return true
    case "isidentifier":
        for r, i in text {
            if r == '_' || unicode.is_letter(r) do continue
            if i > 0 && unicode.is_digit(r) do continue
            return false
        }
        return true
    case "islower", "isupper":
        cased := false
        for r in text {
            if unicode.is_upper(r) {
                if c.name == "islower" do return false
                cased = true
            } else if unicode.is_lower(r) {
                if c.name == "isupper" do return false
                cased = true
            }
        }
        return cased
    case "istitle": return text == python_title(text) && python_title(text) != to_lower(text)
    }
    return fail(c, "'str' object has no attribute %s", repr(c.name))
}

// ---------------------------------------------------------------------------------------
// list and dict

list_method :: proc(c: ^Call, l: ^List) -> Value {
    switch c.name {
    case "index":
        x := arg(c, 0, "value")
        for item, i in l.items do if values_equal(item, x) do return i64(i)
        return fail(c, "%s is not in list", repr(x))
    case "count":
        x := arg(c, 0, "value")
        n: i64 = 0
        for item in l.items do if values_equal(item, x) do n += 1
        return n
    // What is stored in a list the render does not own is noted first (note_store).
    case "append":
        if note_store(c.state, l) do list_append(l, {arg(c, 0, "object")})
        return None{}
    case "extend":
        items, ok := iterate(c.state, arg(c, 0, "iterable"))
        if ok && note_store(c.state, l) do list_append(l, items)
        return None{}
    case "insert":
        if !note_store(c.state, l) do return None{}
        i, _ := arg_int(c, 0, "index", 0)
        n := i64(len(l.items))
        if i < 0 do i = max(i + n, 0)
        context.allocator = owned_by(l.allocator)
        inject_at(&l.items, int(min(i, n)), arg(c, 1, "object"))
        return None{}
    case "pop":
        if len(l.items) == 0 do return fail(c, "pop from empty list")
        i, _ := arg_int(c, 0, "index", -1)
        if i < 0 do i += i64(len(l.items))
        if i < 0 || i >= i64(len(l.items)) do return fail(c, "pop index out of range")
        v := l.items[i]
        ordered_remove(&l.items, int(i))
        return v
    case "remove":
        x := arg(c, 0, "value")
        for item, i in l.items {
            if values_equal(item, x) {
                ordered_remove(&l.items, i)
                return None{}
            }
        }
        return fail(c, "list.remove(x): x not in list")
    case "reverse":
        for i in 0 ..< len(l.items) / 2 {
            j := len(l.items) - 1 - i
            l.items[i], l.items[j] = l.items[j], l.items[i]
        }
        return None{}
    case "sort":
        sorted, ok := sort_values(c.state, l.items[:], truthy(arg(c, 1, "reverse", false)),
            true, nil)
        if ok do copy(l.items[:], sorted)
        return None{}
    case "clear":
        clear(&l.items)
        return None{}
    case "copy": return list_value(list_of(l.items[:]))
    }
    return fail(c, "'list' object has no attribute %s", repr(c.name))
}

dict_method :: proc(c: ^Call, d: ^Dict) -> Value {
    switch c.name {
    case "items":
        out := new_list(len(d.keys))
        if out == nil do return Undefined{}
        for key, i in d.keys do append(&out.items, tuple(key, d.values[i]))
        return out
    case "keys": return list_value(list_of(d.keys[:]))
    case "values": return list_value(list_of(d.values[:]))
    case "get":
        v, found := dict_get(d, arg(c, 0, "key"))
        if found do return v
        return arg(c, 1, "default", None{})
    case "pop":
        v, found := dict_remove(d, arg(c, 0, "key"))
        if found do return v
        if has_arg(c, 1, "default") do return arg(c, 1, "default")
        return fail(c, "%s", repr(arg(c, 0, "key")))
    case "popitem":
        if len(d.keys) == 0 do return fail(c, "'popitem(): dictionary is empty'")
        key := d.keys[len(d.keys) - 1]
        v, _ := dict_remove(d, key)
        return tuple(key, v)
    case "setdefault":
        key := arg(c, 0, "key")
        if v, found := dict_get(d, key); found do return v
        v := arg(c, 1, "default", None{})
        if note_store(c.state, d) do dict_set(d, key, v)
        return v
    case "update":
        if !note_store(c.state, d) do return None{}
        if other, ok := arg(c, 0, "other", None{}).(^Dict); ok {
            for key, i in other.keys do dict_set(d, key, other.values[i])
        }
        for kw in c.kwargs do dict_set(d, kw.name, kw.value)
        return None{}
    case "copy": return dict_value(dict_copy(d))
    case "clear":
        clear(&d.keys)
        clear(&d.values)
        clear(&d.index)
        return None{}
    }
    return fail(c, "'dict' object has no attribute %s", repr(c.name))
}
