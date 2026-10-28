package jinja

import "core:math"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

// to_string converts a value as Python's str() does (Undefined gives ""). A string or
// Markup value is returned as it is, borrowed; anything else is written into a string
// allocated with allocator, so the result belongs in an arena, as values do.
to_string :: proc(v: Value, allocator := context.allocator) -> string {
    #partial switch x in v {
    case string: return x
    case Markup: return string(x)
    }
    b := strings.builder_make(allocator)
    write_str(&b, v)
    return strings.to_string(b)
}

// repr converts a value as Python's repr() does, in a string allocated with allocator,
// which the caller owns.
repr :: proc(v: Value, allocator := context.allocator) -> string {
    b := strings.builder_make(allocator)
    write_repr(&b, v)
    return strings.to_string(b)
}

@(private)
write_str :: proc(b: ^strings.Builder, v: Value) {
    switch x in v {
    case Undefined:
    case None: strings.write_string(b, "None")
    case bool: strings.write_string(b, "True" if x else "False")
    case i64: strings.write_i64(b, x)
    case f64: write_float_repr(b, x)
    case string: strings.write_string(b, x)
    case Markup: strings.write_string(b, string(x))
    case ^List, ^Dict, ^Callable, ^Loop, ^Cycler: write_repr(b, v)
    }
}

@(private)
write_repr :: proc(b: ^strings.Builder, v: Value, depth := 0) {
    switch x in v {
    case Undefined: strings.write_string(b, "Undefined")
    case None, bool, i64, f64: write_str(b, v)
    case string: write_string_repr(b, x)
    case Markup:
        strings.write_string(b, "Markup(")
        write_string_repr(b, string(x))
        strings.write_byte(b, ')')
    case ^List: write_list_repr(b, x, depth)
    case ^Dict:
        switch x.kind {
        case .Dict: write_dict_repr(b, x, depth)
        case .Namespace:
            strings.write_string(b, "<Namespace ")
            write_dict_repr(b, x, depth)
            strings.write_byte(b, '>')
        case .Module:
            strings.write_string(b, "<TemplateModule ")
            write_string_repr(b, x.name)
            strings.write_byte(b, '>')
        }
    case ^Callable:
        if x.macro != nil {
            strings.write_string(b, "<Macro ")
            write_string_repr(b, x.name)
            strings.write_byte(b, '>')
        } else {
            strings.write_string(b, "<built-in function ")
            strings.write_string(b, x.name)
            strings.write_byte(b, '>')
        }
    case ^Loop:
        strings.write_string(b, "<LoopContext ")
        strings.write_int(b, x.index0 + 1)
        strings.write_byte(b, '/')
        strings.write_int(b, len(x.items))
        strings.write_byte(b, '>')
    case ^Cycler: strings.write_string(b, "<Cycler object>")
    }
}

@(private)
write_list_repr :: proc(b: ^strings.Builder, l: ^List, depth: int) {
    // Past MAX_VALUE_DEPTH (a list that contains itself) print Python's "[...]".
    if depth >= MAX_VALUE_DEPTH {
        strings.write_string(b, "(...)" if l.tuple else "[...]")
        return
    }
    strings.write_byte(b, '(' if l.tuple else '[')
    for item, i in l.items {
        if i > 0 do strings.write_string(b, ", ")
        write_repr(b, item, depth + 1)
    }
    if l.tuple && len(l.items) == 1 do strings.write_byte(b, ',')
    strings.write_byte(b, ')' if l.tuple else ']')
}

@(private)
write_dict_repr :: proc(b: ^strings.Builder, d: ^Dict, depth: int) {
    if depth >= MAX_VALUE_DEPTH {
        strings.write_string(b, "{...}")
        return
    }
    strings.write_byte(b, '{')
    for key, i in d.keys {
        if i > 0 do strings.write_string(b, ", ")
        write_repr(b, key, depth + 1)
        strings.write_string(b, ": ")
        write_repr(b, d.values[i], depth + 1)
    }
    strings.write_byte(b, '}')
}

// write_string_repr quotes like Python: single quotes unless the text holds a single
// quote and no double quote.
@(private)
write_string_repr :: proc(b: ^strings.Builder, s: string) {
    quote: byte = '\''
    if strings.contains_rune(s, '\'') && !strings.contains_rune(s, '"') do quote = '"'
    strings.write_byte(b, quote)
    for r in s {
        switch r {
        case '\\': strings.write_string(b, `\\`)
        case '\n': strings.write_string(b, `\n`)
        case '\r': strings.write_string(b, `\r`)
        case '\t': strings.write_string(b, `\t`)
        case:
            if r == rune(quote) {
                strings.write_byte(b, '\\')
                strings.write_rune(b, r)
            } else if r < 0x20 || r == 0x7f || (r >= 0x80 && r < 0xa0) {
                strings.write_string(b, `\x`)
                write_hex(b, u64(r), 2)
            } else {
                strings.write_rune(b, r)
            }
        }
    }
    strings.write_byte(b, quote)
}

@(private)
write_hex :: proc(b: ^strings.Builder, n: u64, width: int, upper := false) {
    digits := "0123456789ABCDEF" if upper else "0123456789abcdef"
    buf: [16]u8
    i := len(buf)
    for v := n; v > 0 || i == len(buf); v >>= 4 {
        i -= 1
        buf[i] = digits[v & 15]
    }
    for _ in 0 ..< width - (len(buf) - i) do strings.write_byte(b, '0')
    strings.write_string(b, string(buf[i:]))
}

// shortest_digits gives the shortest decimal digits that round-trip f, and the position
// of the decimal point relative to the first digit (Python's decpt).
@(private)
shortest_digits :: proc(buf: []u8, f: f64) -> (digits: string, point: int) {
    text := strconv.write_float(buf, abs(f), 'e', -1, 64)
    if len(text) > 0 && (text[0] == '+' || text[0] == '-') do text = text[1:]
    e := strings.index_byte(text, 'e')
    mantissa, exponent := text[:e], text[e + 1:]
    n := 0
    for c, i in transmute([]u8)mantissa {
        if c == '.' do continue
        buf[n] = c
        n += 1
        _ = i
    }
    x, _ := strconv.parse_int(exponent)
    return string(buf[:n]), x + 1
}

// write_float_repr writes a float as Python's repr(): 1.0, 0.1, 1e+16, 1.5e-05.
@(private)
write_float_repr :: proc(b: ^strings.Builder, f: f64) {
    if math.is_nan(f) { strings.write_string(b, "nan"); return }
    if math.is_inf(f) { strings.write_string(b, "inf" if f > 0 else "-inf"); return }
    if math.sign_bit(f) do strings.write_byte(b, '-')
    if f == 0 { strings.write_string(b, "0.0"); return }
    buf: [64]u8
    digits, point := shortest_digits(buf[:], f)
    if point <= -4 || point > 16 {
        strings.write_byte(b, digits[0])
        if len(digits) > 1 {
            strings.write_byte(b, '.')
            strings.write_string(b, digits[1:])
        }
        write_exponent(b, point - 1)
        return
    }
    switch {
    case point <= 0:
        strings.write_string(b, "0.")
        for _ in 0 ..< -point do strings.write_byte(b, '0')
        strings.write_string(b, digits)
    case point >= len(digits):
        strings.write_string(b, digits)
        for _ in 0 ..< point - len(digits) do strings.write_byte(b, '0')
        strings.write_string(b, ".0")
    case:
        strings.write_string(b, digits[:point])
        strings.write_byte(b, '.')
        strings.write_string(b, digits[point:])
    }
}

@(private)
write_exponent :: proc(b: ^strings.Builder, exponent: int, letter: byte = 'e') {
    strings.write_byte(b, letter)
    strings.write_byte(b, '-' if exponent < 0 else '+')
    e := abs(exponent)
    if e < 10 do strings.write_byte(b, '0')
    strings.write_int(b, e)
}

// ---------------------------------------------------------------------------------------
// Truth, numbers, equality and ordering

// truthy is Python truthiness (Undefined is false).
truthy :: proc(v: Value) -> bool {
    switch x in v {
    case Undefined, None: return false
    case bool: return x
    case i64: return x != 0
    case f64: return x != 0
    case string: return len(x) > 0
    case Markup: return len(x) > 0
    case ^List: return len(x.items) > 0
    case ^Dict: return x.kind != .Dict || len(x.keys) > 0
    case ^Callable, ^Loop, ^Cycler: return true
    }
    return false
}

@(private)
Number_Kind :: enum u8 { None, Int, Float }

// as_number reads bool, int and float values (bools are ints, as in Python).
@(private)
as_number :: proc(v: Value) -> (i: i64, f: f64, kind: Number_Kind) {
    #partial switch x in v {
    case bool: return i64(x), f64(i64(x)), .Int
    case i64: return x, f64(x), .Int
    case f64: return 0, x, .Float
    }
    return 0, 0, .None
}

@(private)
is_number :: proc(v: Value) -> bool {
    _, _, k := as_number(v)
    return k != .None
}

// values_equal compares as Python's == does: lists and dicts by content, 200 levels deep.
values_equal :: proc(a, b: Value) -> bool { return equal_at(a, b, 0) }

// equal_at compares values nested depth levels deep. Like Python, a list or dict equals
// itself; values nested past MAX_VALUE_DEPTH compare unequal.
@(private)
equal_at :: proc(a, b: Value, depth: int) -> bool {
    if depth > MAX_VALUE_DEPTH do return false
    ai, af, ak := as_number(a)
    bi, bf, bk := as_number(b)
    if ak != .None && bk != .None {
        if ak == .Int && bk == .Int do return ai == bi
        return af == bf
    }
    if sa, ok := key_string(a); ok {
        sb, ok2 := key_string(b)
        return ok2 && sa == sb
    }
    switch x in a {
    case Undefined: return is_undefined(b)
    case None: return is_none(b)
    case bool, i64, f64, string, Markup: return false
    case ^List:
        y, ok := b.(^List)
        if !ok || x.tuple != y.tuple || len(x.items) != len(y.items) do return false
        if x == y do return true
        for item, i in x.items do if !equal_at(item, y.items[i], depth + 1) do return false
        return true
    case ^Dict:
        y, ok := b.(^Dict)
        if !ok || len(x.keys) != len(y.keys) do return false
        if x == y do return true
        if x.kind != .Dict || y.kind != .Dict do return false
        for key, i in x.keys {
            other, found := dict_get(y, key)
            if !found || !equal_at(x.values[i], other, depth + 1) do return false
        }
        return true
    case ^Callable:
        y, ok := b.(^Callable)
        if !ok do return false
        if x == y do return true
        return x.procedure == y.procedure && x.macro == y.macro && x.name == y.name &&
            equal_at(x.self, y.self, depth + 1) && x.procedure != nil
    case ^Loop:
        y, ok := b.(^Loop)
        return ok && x == y
    case ^Cycler:
        y, ok := b.(^Cycler)
        return ok && x == y
    }
    return false
}

// compare_values orders two values as Python does; ok is false when Python raises
// TypeError ("'<' not supported between instances of ..."), and for lists nested past
// MAX_VALUE_DEPTH.
@(private)
compare_values :: proc(a, b: Value, depth := 0) -> (order: int, ok: bool) {
    if depth > MAX_VALUE_DEPTH do return 0, false
    ai, af, ak := as_number(a)
    bi, bf, bk := as_number(b)
    if ak != .None && bk != .None {
        if ak == .Int && bk == .Int do return int(ai > bi) - int(ai < bi), true
        if math.is_nan(af) || math.is_nan(bf) do return 2, true
        return int(af > bf) - int(af < bf), true
    }
    if sa, is_a := key_string(a); is_a {
        sb := key_string(b) or_return
        return strings.compare(sa, sb), true
    }
    la, is_list := a.(^List)
    if !is_list do return 0, false
    lb := b.(^List) or_return
    if la.tuple != lb.tuple do return 0, false
    for i in 0 ..< min(len(la.items), len(lb.items)) {
        if equal_at(la.items[i], lb.items[i], depth + 1) do continue
        return compare_values(la.items[i], lb.items[i], depth + 1)
    }
    n, m := len(la.items), len(lb.items)
    return int(n > m) - int(n < m), true
}

// ---------------------------------------------------------------------------------------
// Unicode case helpers shared by filters and methods

@(private)
runes_of :: proc(s: string, allocator := context.allocator) -> []rune {
    return utf8.string_to_runes(s, allocator)
}

// rune_slice returns s[start:end] counted in runes, with Python's clamping.
@(private)
rune_slice :: proc(s: string, start, end: int) -> string {
    n := strings.rune_count(s)
    lo, hi := clamp(start, 0, n), clamp(end, 0, n)
    if lo >= hi do return ""
    byte_lo, byte_hi := len(s), len(s)
    i := 0
    for _, offset in s {
        if i == lo do byte_lo = offset
        if i == hi { byte_hi = offset; break }
        i += 1
    }
    return s[byte_lo:byte_hi]
}
