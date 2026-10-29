#+private
package jinja

import "core:math"
import "core:strconv"
import "core:strings"

// Spec is a parsed Python format specification ("%-8.2f" or "{:>8,.2f}").
Spec :: struct {
    fill:      string,
    align:     byte, // 0, '<', '>', '^', '='
    sign:      byte, // 0, '+', '-', ' '
    alt:       bool,
    zero:      bool,
    width:     int,
    grouping:  byte, // 0, ',', '_'
    precision: int,  // -1 when absent
    type:      byte, // 0 or a presentation type
}

// format_value writes v formatted by spec, as Python's format(v, spec) does.
format_value :: proc(s: ^State, b: ^strings.Builder, v: Value, spec: Spec) -> bool {
    spec := spec
    body: string
    negative := false
    is_num := false
    #partial switch x in v {
    case i64, f64:
        is_num = true
        ok: bool
        body, negative, ok = format_number(s, v, spec)
        if !ok do return false
    case bool:
        if spec.type == 0 {
            body = "True" if x else "False"
        } else {
            is_num = true
            ok: bool
            body, negative, ok = format_number(s, i64(x), spec)
            if !ok do return false
        }
    case:
        if spec.type != 0 && spec.type != 's' {
            runtime_error(s, .Type, "Unknown format code '%c' for object of type '%s'",
                rune(spec.type), type_name(v))
            return false
        }
        body = to_string(v)
        if spec.precision >= 0 do body = rune_slice(body, 0, spec.precision)
    }
    sign := ""
    if is_num {
        if negative {
            sign = "-"
        } else if spec.sign == '+' {
            sign = "+"
        } else if spec.sign == ' ' {
            sign = " "
        }
    }
    fill := spec.fill if spec.fill != "" else " "
    align := spec.align
    if spec.zero && align == 0 && is_num {
        fill = "0"
        align = '='
    }
    if align == 0 do align = '>' if is_num else '<'
    n := strings.rune_count(sign) + strings.rune_count(body)
    if align == '=' {
        // The padding is sized first, and b grown once for it.
        fills, ok := reserve_bytes(s, max(spec.width - n, 0), len(fill))
        if !ok do return false
        size, summed := sum_bytes(s, fills, len(sign) + len(body))
        if !summed || !reserve_text(s, b, size) do return false
        strings.write_string(b, sign)
        if fill != "" do for _ in n ..< spec.width do strings.write_string(b, fill)
        strings.write_string(b, body)
        return true
    }
    text := strings.concatenate({sign, body})
    padded, ok := pad(s, text, spec.width, fill, 'c' if align == '^' else align)
    if !ok do return false
    strings.write_string(b, padded)
    return true
}

// format_number formats the magnitude of a number and reports its sign separately.
format_number :: proc(s: ^State, v: Value, spec: Spec) -> (string, bool, bool) {
    i, f, kind := as_number(v)
    t := spec.type
    switch t {
    case 0, 'd', 'n', 'x', 'X', 'o', 'b', 'c':
        if kind == .Float {
            if t == 0 do return format_float(f, spec)
            runtime_error(s, .Type, "Unknown format code '%c' for object of type 'float'",
                rune(t))
            return "", false, false
        }
        return format_int(i, spec), i < 0, true
    case 'f', 'F', 'e', 'E', 'g', 'G', '%':
        return format_float(f, spec)
    }
    runtime_error(s, .Type, "Unknown format code '%c' for object of type '%s'", rune(t),
        type_name(v))
    return "", false, false
}

format_int :: proc(i: i64, spec: Spec) -> string {
    b := strings.builder_make()
    mag := u64(i) if i >= 0 else u64(-(i + 1)) + 1
    base: u64 = 10
    prefix := ""
    switch spec.type {
    case 'x', 'X': base, prefix = 16, "0x" if spec.type == 'x' else "0X"
    case 'o': base, prefix = 8, "0o"
    case 'b': base, prefix = 2, "0b"
    case 'c':
        strings.write_rune(&b, rune(i))
        return strings.to_string(b)
    }
    if spec.alt do strings.write_string(&b, prefix)
    digits: [64]u8
    n := len(digits)
    for x := mag; x > 0 || n == len(digits); x /= base {
        n -= 1
        d := x % base
        digits[n] = u8('0' + d) if d < 10 else u8('a' + d - 10)
        if spec.type == 'X' && d >= 10 do digits[n] = u8('A' + d - 10)
    }
    strings.write_string(&b, group_digits(string(digits[n:]), spec.grouping))
    return strings.to_string(b)
}

group_digits :: proc(digits: string, sep: byte) -> string {
    if sep == 0 || len(digits) <= 3 do return strings.clone(digits)
    b := strings.builder_make()
    first := len(digits) % 3
    if first == 0 do first = 3
    strings.write_string(&b, digits[:first])
    for i := first; i < len(digits); i += 3 {
        strings.write_byte(&b, sep)
        strings.write_string(&b, digits[i:i + 3])
    }
    return strings.to_string(b)
}

// fixed_float writes |f| with precision digits after the point, rounding half-even on
// the exact binary value like Python.
fixed_float :: proc(f: f64, precision: int, letter: byte = 'f') -> string {
    buf: [512]u8
    text := strconv.write_float(buf[:], abs(f), letter, precision, 64)
    if len(text) > 0 && (text[0] == '+' || text[0] == '-') do text = text[1:]
    return strings.clone(text)
}

format_float :: proc(f: f64, spec: Spec) -> (string, bool, bool) {
    negative := math.sign_bit(f) && !math.is_nan(f)
    if math.is_nan(f) || math.is_inf(f) {
        word := "nan" if math.is_nan(f) else "inf"
        if spec.type == 'F' || spec.type == 'E' || spec.type == 'G' do word = to_upper(word)
        return word, negative, true
    }
    p := spec.precision
    body: string
    switch spec.type {
    case 'f', 'F': body = fixed_float(f, 6 if p < 0 else p)
    case '%': body = strings.concatenate({fixed_float(f * 100, 6 if p < 0 else p), "%"})
    case 'e', 'E':
        body = sci_float(f, 6 if p < 0 else p)
        if spec.type == 'E' do body = to_upper(body)
    case 'g', 'G':
        body = general_float(f, 6 if p < 0 else p, spec.alt)
        if spec.type == 'G' do body = to_upper(body)
    case:
        if p < 0 {
            b := strings.builder_make()
            write_float_repr(&b, abs(f))
            body = strings.to_string(b)
        } else {
            body = general_float(f, p, spec.alt)
            if strings.index_any(body, ".e") < 0 do body = strings.concatenate({body, ".0"})
        }
    }
    if spec.grouping != 0 {
        dot := strings.index_any(body, ".e%")
        if dot < 0 do dot = len(body)
        body = strings.concatenate({group_digits(body[:dot], spec.grouping), body[dot:]})
    }
    return body, negative, true
}

// sci_float is "%.{p}e" with at least two exponent digits.
sci_float :: proc(f: f64, p: int) -> string {
    text := fixed_float(f, p, 'e')
    e := strings.index_byte(text, 'e')
    if e < 0 do return text
    exp, _ := strconv.parse_int(text[e + 1:])
    b := strings.builder_make()
    strings.write_string(&b, text[:e])
    write_exponent(&b, exp)
    return strings.to_string(b)
}

// general_float is Python's "g" presentation.
general_float :: proc(f: f64, precision: int, alt: bool) -> string {
    p := max(precision, 1)
    if f == 0 {
        if alt do return strings.concatenate({"0.", strings.repeat("0", p - 1)})
        return "0"
    }
    sci := sci_float(f, p - 1)
    e := strings.index_byte(sci, 'e')
    exp, _ := strconv.parse_int(sci[e + 1:])
    out: string
    if -4 <= exp && exp < p {
        out = fixed_float(f, p - 1 - exp)
    } else {
        out = sci
    }
    if alt do return out
    mantissa, suffix := out, ""
    if i := strings.index_byte(out, 'e'); i >= 0 do mantissa, suffix = out[:i], out[i:]
    if strings.contains_rune(mantissa, '.') {
        mantissa = strings.trim_right(mantissa, "0")
        mantissa = strings.trim_suffix(mantissa, ".")
    }
    return strings.concatenate({mantissa, suffix})
}

// parse_format_spec parses the format() mini-language.
parse_format_spec :: proc(text: string) -> (Spec, bool) {
    spec := Spec{precision = -1}
    i := 0
    r, size := first_rune(text)
    if size > 0 && size < len(text) && strings.index_byte("<>^=", text[size]) >= 0 {
        spec.fill = text[:size]
        spec.align = text[size]
        i = size + 1
    } else if len(text) > 0 && strings.index_byte("<>^=", text[0]) >= 0 {
        spec.align = text[0]
        i = 1
    }
    _ = r
    if i < len(text) && strings.index_byte("+- ", text[i]) >= 0 { spec.sign = text[i]; i += 1 }
    if i < len(text) && text[i] == '#' { spec.alt = true; i += 1 }
    if i < len(text) && text[i] == '0' { spec.zero = true; i += 1 }
    for i < len(text) && is_digit(text[i]) {
        spec.width = spec.width * 10 + int(text[i] - '0')
        i += 1
    }
    if i < len(text) && (text[i] == ',' || text[i] == '_') { spec.grouping = text[i]; i += 1 }
    if i < len(text) && text[i] == '.' {
        i += 1
        spec.precision = 0
        if i >= len(text) || !is_digit(text[i]) do return spec, false
        for i < len(text) && is_digit(text[i]) {
            spec.precision = spec.precision * 10 + int(text[i] - '0')
            i += 1
        }
    }
    if i < len(text) { spec.type = text[i]; i += 1 }
    return spec, i == len(text)
}

// ---------------------------------------------------------------------------------------
// printf-style formatting: "%s and %d" % (a, b)

percent_format :: proc(s: ^State, fmt_value: Value, text: string, args: Value) -> Value {
    markup := is_markup(fmt_value)
    positional: []Value = {args}
    mapping: ^Dict
    if l, ok := args.(^List); ok && l.tuple do positional = l.items[:]
    if d, ok := args.(^Dict); ok do mapping = d
    b := strings.builder_make()
    next := 0
    i := 0
    for i < len(text) {
        c := text[i]
        if c != '%' { strings.write_byte(&b, c); i += 1; continue }
        i += 1
        if i >= len(text) do return runtime_error(s, .Type, "incomplete format")
        if text[i] == '%' { strings.write_byte(&b, '%'); i += 1; continue }
        value: Value
        has_value := false
        if text[i] == '(' {
            end := strings.index_byte(text[i:], ')')
            if end < 0 do return runtime_error(s, .Type, "incomplete format key")
            if mapping == nil do return runtime_error(s, .Type, "format requires a mapping")
            key := text[i + 1:i + end]
            v, found := dict_get(mapping, key)
            if !found do return runtime_error(s, .Type, "KeyError: %s", repr(key))
            value, has_value = v, true
            i += end + 1
        }
        spec, consumed, ok := parse_percent_spec(s, text[i:], positional, &next)
        if !ok do return Undefined{}
        i += consumed
        if !has_value {
            if next >= len(positional) {
                return runtime_error(s, .Type, "not enough arguments for format string")
            }
            value = positional[next]
            next += 1
        }
        if !write_percent_field(s, &b, value, spec, markup) do return Undefined{}
    }
    if mapping == nil && next < len(positional) {
        return runtime_error(s, .Type,
            "not all arguments converted during string formatting")
    }
    if markup do return Markup(strings.to_string(b))
    return strings.to_string(b)
}

parse_percent_spec :: proc(s: ^State, text: string, args: []Value, next: ^int) -> (Spec,
    int, bool) {
    spec := Spec{precision = -1}
    i := 0
    for i < len(text) && strings.index_byte("-+ #0", text[i]) >= 0 {
        switch text[i] {
        case '-': spec.align = '<'
        case '+': spec.sign = '+'
        case ' ': if spec.sign == 0 do spec.sign = ' '
        case '#': spec.alt = true
        case '0': spec.zero = true
        }
        i += 1
    }
    star :: proc(s: ^State, args: []Value, next: ^int) -> (int, bool) {
        if next^ >= len(args) {
            runtime_error(s, .Type, "not enough arguments for format string")
            return 0, false
        }
        n, _, kind := as_number(args[next^])
        next^ += 1
        if kind != .Int do runtime_error(s, .Type, "* wants int")
        return int(n), kind == .Int
    }
    if i < len(text) && text[i] == '*' {
        w, ok := star(s, args, next)
        if !ok do return spec, 0, false
        spec.width = w
        i += 1
    }
    for i < len(text) && is_digit(text[i]) {
        spec.width = spec.width * 10 + int(text[i] - '0')
        i += 1
    }
    if i < len(text) && text[i] == '.' {
        i += 1
        spec.precision = 0
        if i < len(text) && text[i] == '*' {
            p, ok := star(s, args, next)
            if !ok do return spec, 0, false
            spec.precision = p
            i += 1
        }
        for i < len(text) && is_digit(text[i]) {
            spec.precision = spec.precision * 10 + int(text[i] - '0')
            i += 1
        }
    }
    for i < len(text) && strings.index_byte("hlL", text[i]) >= 0 do i += 1
    if i >= len(text) {
        runtime_error(s, .Type, "incomplete format")
        return spec, 0, false
    }
    spec.type = text[i]
    if spec.align == '<' do spec.zero = false
    return spec, i + 1, true
}

write_percent_field :: proc(s: ^State, b: ^strings.Builder, v: Value, spec: Spec,
    markup: bool) -> bool {
    spec := spec
    switch spec.type {
    case 's', 'r', 'a':
        text := to_string(v) if spec.type == 's' else repr(v)
        if markup && !(spec.type == 's' && is_markup(v)) do text = escape_string(text)
        spec.type = 0
        spec.zero = false
        if spec.align == 0 do spec.align = '>'
        return format_value(s, b, text, spec)
    case 'd', 'i', 'u':
        i, f, kind := as_number(v)
        if kind == .None {
            runtime_error(s, .Type, "%%%c format: a real number is required, not %s",
                rune(spec.type), type_name(v))
            return false
        }
        if kind == .Float do i = i64(f)
        spec.type = 'd'
        if spec.precision >= 0 do spec.precision = -1
        return format_value(s, b, i, spec)
    case 'f', 'F', 'e', 'E', 'g', 'G', 'x', 'X', 'o', 'c':
        i, f, kind := as_number(v)
        if kind == .None {
            runtime_error(s, .Type, "%%%c format: a real number is required, not %s",
                rune(spec.type), type_name(v))
            return false
        }
        switch spec.type {
        case 'x', 'X', 'o', 'c':
            if kind == .Float {
                runtime_error(s, .Type, "%%%c format: an integer is required, not float",
                    rune(spec.type))
                return false
            }
            return format_value(s, b, i, spec)
        }
        return format_value(s, b, f, spec)
    }
    runtime_error(s, .Type, "unsupported format character '%c'", rune(spec.type))
    return false
}

// ---------------------------------------------------------------------------------------
// str.format: "{} {name:>8}".format(a, name=b)

str_format :: proc(c: ^Call, text: string, markup: bool) -> Value {
    s := c.state
    kwargs := c.kwargs
    if c.name == "format_map" {
        d, ok := arg(c, 0, "mapping").(^Dict)
        if !ok do return fail(c, "format_map() argument must be a mapping")
        list := make([dynamic]Keyword)
        for key, i in d.keys do append(&list, Keyword{to_string(key), d.values[i]})
        kwargs = list[:]
    }
    positional := c.args if c.name == "format" else nil
    b := strings.builder_make()
    auto := 0
    i := 0
    for i < len(text) {
        ch := text[i]
        if ch == '}' {
            if i + 1 < len(text) && text[i + 1] == '}' {
                strings.write_byte(&b, '}')
                i += 2
                continue
            }
            return fail(c, "Single '}' encountered in format string")
        }
        if ch != '{' { strings.write_byte(&b, ch); i += 1; continue }
        if i + 1 < len(text) && text[i + 1] == '{' {
            strings.write_byte(&b, '{')
            i += 2
            continue
        }
        end, depth := i + 1, 1
        for end < len(text) && depth > 0 {
            if text[end] == '{' do depth += 1
            if text[end] == '}' do depth -= 1
            end += 1
        }
        if depth > 0 do return fail(c, "expected '}' before end of string")
        field := text[i + 1:end - 1]
        if !format_field(s, &b, field, positional, kwargs, &auto, markup) do return Undefined{}
        i = end
    }
    if markup do return Markup(strings.to_string(b))
    return strings.to_string(b)
}

format_field :: proc(s: ^State, b: ^strings.Builder, field: string, positional: []Value,
    kwargs: []Keyword, auto: ^int, markup: bool) -> bool {
    name, conversion, spec_text := field, "", ""
    if colon := strings.index_byte(field, ':'); colon >= 0 {
        name, spec_text = field[:colon], field[colon + 1:]
    }
    if bang := strings.index_byte(name, '!'); bang >= 0 {
        name, conversion = name[:bang], name[bang + 1:]
    }
    if strings.contains_rune(spec_text, '{') {
        inner := Call{args = positional, kwargs = kwargs, state = s, name = "format"}
        expanded := str_format(&inner, spec_text, false)
        if s.failed do return false
        spec_text = to_string(expanded)
    }
    root := name
    rest := ""
    if cut := strings.index_any(name, ".["); cut >= 0 do root, rest = name[:cut], name[cut:]
    v: Value
    if root == "" || is_digit(root[0]) {
        index := auto^
        if root == "" {
            auto^ += 1
        } else {
            n, _ := strconv.parse_int(root)
            index = n
        }
        if index >= len(positional) {
            runtime_error(s, .Runtime, "Replacement index %d out of range for positional " +
                "args tuple", index)
            return false
        }
        v = positional[index]
    } else {
        found := false
        v, found = find_keyword(kwargs, root)
        if !found {
            runtime_error(s, .Runtime, "KeyError: %s", repr(root))
            return false
        }
    }
    v = format_lookup(s, v, rest)
    if s.failed do return false
    switch conversion {
    case "r", "a": v = repr(v)
    case "s": v = to_string(v)
    }
    spec, ok := parse_format_spec(spec_text)
    if !ok {
        runtime_error(s, .Runtime, "Invalid format specifier %s", repr(spec_text))
        return false
    }
    if !markup || is_markup(v) do return format_value(s, b, v, spec)
    tmp := strings.builder_make()
    if !format_value(s, &tmp, v, spec) do return false
    write_escaped(b, strings.to_string(tmp))
    return true
}

// format_lookup follows ".attr" and "[key]" parts of a replacement field.
format_lookup :: proc(s: ^State, v: Value, path: string) -> Value {
    v, rest := v, path
    for len(rest) > 0 && !s.failed {
        if rest[0] == '.' {
            end := strings.index_any(rest[1:], ".[")
            end = len(rest) if end < 0 else end + 1
            v = get_attr(s, v, rest[1:end])
            rest = rest[end:]
        } else if rest[0] == '[' {
            end := strings.index_byte(rest, ']')
            if end < 0 do return runtime_error(s, .Runtime, "Missing ']' in format string")
            key := rest[1:end]
            n, is_int := strconv.parse_i64_of_base(key, 10)
            v = get_item(s, v, n if is_int else Value(key))
            rest = rest[end + 1:]
        } else {
            return runtime_error(s, .Runtime, "Only '.' or '[' may follow ']' in format field")
        }
    }
    return v
}
