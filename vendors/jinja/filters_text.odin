#+private
package jinja

import "core:math"
import "core:strconv"
import "core:strings"
import "core:unicode"

// Filters over text and numbers.

register_filters :: proc(env: ^Environment) {
    register_sequence_filters(env)
    register_html_filters(env)
    add_filter(env, "abs", filter_abs)
    add_filter(env, "capitalize", filter_case)
    add_filter(env, "lower", filter_case)
    add_filter(env, "upper", filter_case)
    add_filter(env, "title", filter_case)
    add_filter(env, "center", filter_center)
    add_filter(env, "filesizeformat", filter_filesizeformat)
    add_filter(env, "float", filter_float)
    add_filter(env, "format", filter_format)
    add_filter(env, "indent", filter_indent)
    add_filter(env, "int", filter_int)
    add_filter(env, "pprint", filter_pprint)
    add_filter(env, "replace", filter_replace)
    add_filter(env, "round", filter_round)
    add_filter(env, "string", filter_string)
    add_filter(env, "trim", filter_trim)
    add_filter(env, "truncate", filter_truncate)
    add_filter(env, "wordcount", filter_wordcount)
    add_filter(env, "wordwrap", filter_wordwrap)
}

// text_arg reads argument 0 as text (Markup stays Markup), the way soft_str does.
text_arg :: proc(c: ^Call) -> (string, bool) {
    v := arg(c, 0, "s")
    if !strict_check(c.state, v) do return "", false
    text := to_string(v)
    return text, is_markup(v)
}

keep_markup :: proc(text: string, markup: bool) -> Value {
    if markup do return Markup(text)
    return text
}

@(private="file")
filter_abs :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "x")
    i, f, kind := as_number(v)
    switch kind {
    case .Int: return abs(i)
    case .Float: return abs(f)
    case .None:
    }
    return fail(c, "bad operand type for abs(): '%s'", type_name(v))
}

// title_case is Jinja's title filter: words start after spaces, "-", "(", "{", "[", "<".
title_case :: proc(s: string) -> string {
    b := strings.builder_make(0, len(s))
    at_start := true
    for r in s {
        is_sep := is_space(r) || r == '-' || r == '(' || r == '{' || r == '[' || r == '<'
        if is_sep {
            strings.write_rune(&b, r)
            at_start = true
            continue
        }
        strings.write_rune(&b, unicode.to_upper(r) if at_start else unicode.to_lower(r))
        at_start = false
    }
    return strings.to_string(b)
}

@(private="file")
filter_case :: proc(c: ^Call) -> Value {
    text, markup := text_arg(c)
    if c.state.failed do return Undefined{}
    out: string
    switch c.name {
    case "capitalize": out = python_capitalize(text)
    case "lower": out = to_lower(text)
    case "upper": out = to_upper(text)
    case "title": out = title_case(text)
    }
    return keep_markup(out, markup)
}

@(private="file")
filter_center :: proc(c: ^Call) -> Value {
    text, markup := text_arg(c)
    width, _ := arg_int(c, 1, "width", 80)
    out, ok := pad(c.state, text, int(clamp(width, 0, i64(max(int)))), " ", '^')
    if !ok do return Undefined{}
    return keep_markup(out, markup)
}

@(private="file")
filter_filesizeformat :: proc(c: ^Call) -> Value {
    _, size, kind := as_number(arg(c, 0, "value"))
    if kind == .None {
        v, ok := strconv.parse_f64(to_string(arg(c, 0, "value")))
        if !ok do return fail(c, "could not convert string to float")
        size = v
    }
    binary := truthy(arg(c, 1, "binary", false))
    base: f64 = 1024 if binary else 1000
    prefixes := [?]string{"KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"} if binary else
        [?]string{"kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"}
    if size == 1 do return string("1 Byte")
    if size < base {
        b := strings.builder_make()
        strings.write_i64(&b, i64(size))
        strings.write_string(&b, " Bytes")
        return strings.to_string(b)
    }
    unit: f64
    prefix: string
    for p, i in prefixes {
        unit = math.pow(base, f64(i + 2))
        prefix = p
        if size < unit do break
    }
    return strings.concatenate({fixed_float(base * size / unit, 1), " ", prefix})
}

// to_float converts like Jinja's float filter; ok is false when conversion fails.
to_float :: proc(v: Value) -> (f64, bool) {
    _, f, kind := as_number(v)
    if kind != .None do return f, true
    text, is_str := key_string(v)
    if !is_str do return 0, false
    t := strings.trim_space(text)
    switch to_lower(t) {
    case "inf", "+inf", "infinity": return math.inf_f64(1), true
    case "-inf", "-infinity": return math.inf_f64(-1), true
    case "nan", "+nan", "-nan": return math.nan_f64(), true
    }
    return strconv.parse_f64(strip_underscores(t))
}

@(private="file")
filter_float :: proc(c: ^Call) -> Value {
    f, ok := to_float(arg(c, 0, "value"))
    if !ok do return arg(c, 1, "default", 0.0)
    return f
}

// parse_python_int parses int(text, base) including prefixes, signs and underscores.
parse_python_int :: proc(text: string, base: int) -> (i64, bool) {
    t := strings.trim_space(text)
    negative := false
    if len(t) > 0 && (t[0] == '-' || t[0] == '+') {
        negative = t[0] == '-'
        t = t[1:]
    }
    b := base
    if len(t) > 2 && t[0] == '0' {
        p := t[1] | 0x20
        prefix_base := 16 if p == 'x' else (8 if p == 'o' else (2 if p == 'b' else 0))
        if prefix_base != 0 && (b == 0 || b == prefix_base) {
            b = prefix_base
            t = t[2:]
        }
    }
    if b == 0 do b = 10
    if len(t) == 0 || t[0] == '_' || t[len(t) - 1] == '_' do return 0, false
    v, ok := parse_digits(strip_underscores(t), b)
    if !ok do return 0, false
    return -v if negative else v, true
}

@(private="file")
filter_int :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "value")
    default := arg(c, 1, "default", i64(0))
    base, _ := arg_int(c, 2, "base", 10)
    i, f, kind := as_number(v)
    switch kind {
    case .Int: return i
    case .Float:
        if math.is_nan(f) || math.is_inf(f) do return default
        return i64(f)
    case .None:
    }
    text, is_str := key_string(v)
    if !is_str do return default
    if n, ok := parse_python_int(text, int(base)); ok do return n
    if fv, ok := strconv.parse_f64(strings.trim_space(text)); ok && !math.is_nan(fv) &&
       !math.is_inf(fv) {
        return i64(fv)
    }
    return default
}

@(private="file")
filter_format :: proc(c: ^Call) -> Value {
    if len(c.args) > 1 && len(c.kwargs) > 0 {
        return fail(c, "can't handle positional and keyword arguments at the same time")
    }
    v := arg(c, 0, "value")
    text, _ := key_string(v)
    if !is_stringish(v) do text = to_string(v)
    params: Value = list_value(list_of(c.args[1:], true))
    if len(c.kwargs) > 0 {
        d := new_dict(.Dict)
        if d == nil do return Undefined{}
        for kw in c.kwargs do dict_set(d, kw.name, kw.value)
        params = d
    }
    return percent_format(c.state, v if is_markup(v) else Value(text), text, params)
}

@(private="file")
filter_indent :: proc(c: ^Call) -> Value {
    names := []string{"s", "width", "first", "blank"}
    if !check_args(c, "indent", names) do return Undefined{}
    text, markup := text_arg(c)
    width := arg(c, 1, "width", i64(4))
    indention: string
    if w, ok := key_string(width); ok {
        indention = w
    } else {
        n, _ := arg_int(c, 1, "width", 4)
        spaces, made := repeat_text(c.state, " ", int(clamp(n, 0, i64(max(int)))))
        if !made do return Undefined{}
        indention = spaces
    }
    lines := python_splitlines(strings.concatenate({text, "\n"}))
    // The indented text is sized first, and allocated once.
    indents, sized := reserve_bytes(c.state, len(lines) + 1, len(indention))
    if !sized do return Undefined{}
    size, summed := sum_bytes(c.state, indents, len(text) + len(lines))
    b := strings.builder_make()
    if !summed || !reserve_text(c.state, &b, size) do return Undefined{}
    blank := truthy(arg(c, 3, "blank", false))
    if truthy(arg(c, 2, "first", false)) do strings.write_string(&b, indention)
    for line, i in lines {
        if i > 0 {
            strings.write_byte(&b, '\n')
            if blank || len(line) > 0 do strings.write_string(&b, indention)
        }
        strings.write_string(&b, line)
    }
    return keep_markup(strings.to_string(b), markup)
}

@(private="file")
filter_pprint :: proc(c: ^Call) -> Value {
    return repr(arg(c, 0, "value"))
}

@(private="file")
filter_replace :: proc(c: ^Call) -> Value {
    names := []string{"s", "old", "new", "count"}
    if !check_args(c, "replace", names, 3) do return Undefined{}
    v := arg(c, 0, "s")
    old, new := arg(c, 1, "old"), arg(c, 2, "new")
    count, _ := arg_int(c, 3, "count", -1)
    if !autoescaping(c) {
        return python_replace(to_string(v), to_string(old), to_string(new), int(count))
    }
    if is_markup(old) || is_markup(new) || is_markup(v) {
        text := string(escape(v))
        return Markup(python_replace(text, string(escape(old)), string(escape(new)),
            int(count)))
    }
    return python_replace(to_string(v), to_string(old), to_string(new), int(count))
}

// python_round rounds half to even on the exact binary value, like Python's round().
python_round :: proc(f: f64, precision: int) -> f64 {
    if math.is_nan(f) || math.is_inf(f) do return f
    if precision < 0 {
        scale := math.pow(10, f64(-precision))
        return python_round(f / scale, 0) * scale
    }
    text := fixed_float(f, precision)
    v, _ := strconv.parse_f64(text)
    return -v if f < 0 else v
}

@(private="file")
filter_round :: proc(c: ^Call) -> Value {
    names := []string{"value", "precision", "method"}
    if !check_args(c, "round", names) do return Undefined{}
    v := arg(c, 0, "value")
    precision, _ := arg_int(c, 1, "precision", 0)
    method := to_string(arg(c, 2, "method", string("common")))
    i, f, kind := as_number(v)
    if kind == .None do return fail(c, "type %s doesn't define __round__ method", type_name(v))
    switch method {
    case "common":
        if kind == .Int do return i
        return python_round(f, int(precision))
    case "ceil", "floor":
        scale := math.pow(10, f64(precision))
        r := math.ceil(f * scale) if method == "ceil" else math.floor(f * scale)
        return r / scale
    }
    return fail(c, "method must be common, ceil or floor")
}

@(private="file")
filter_string :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "value")
    if is_markup(v) do return v
    return to_string(v)
}

@(private="file")
filter_trim :: proc(c: ^Call) -> Value {
    text, markup := text_arg(c)
    return keep_markup(strip_chars(text, arg(c, 1, "chars", None{}), true, true), markup)
}

@(private="file")
filter_truncate :: proc(c: ^Call) -> Value {
    names := []string{"s", "length", "killwords", "end", "leeway"}
    if !check_args(c, "truncate", names) do return Undefined{}
    text, _ := text_arg(c)
    size, _ := arg_int(c, 1, "length", 255)
    end := to_string(arg(c, 3, "end", string("...")))
    leeway, _ := arg_int(c, 4, "leeway", 5)
    n := strings.rune_count(text)
    end_n := strings.rune_count(end)
    if int(size) < end_n do return fail(c, "expected length >= %d, got %d", end_n, size)
    if leeway < 0 do return fail(c, "expected leeway >= 0, got %d", leeway)
    if n <= int(size + leeway) do return text
    head := rune_slice(text, 0, int(size) - end_n)
    if truthy(arg(c, 2, "killwords", false)) do return strings.concatenate({head, end})
    if space := strings.last_index_byte(head, ' '); space >= 0 do head = head[:space]
    return strings.concatenate({head, end})
}

@(private="file")
filter_wordcount :: proc(c: ^Call) -> Value {
    text, _ := text_arg(c)
    count: i64 = 0
    in_word := false
    for r in text {
        w := is_word_rune(r)
        if w && !in_word do count += 1
        in_word = w
    }
    return count
}

@(private="file")
filter_wordwrap :: proc(c: ^Call) -> Value {
    names := []string{"s", "width", "break_long_words", "wrapstring", "break_on_hyphens"}
    if !check_args(c, "wordwrap", names) do return Undefined{}
    text, _ := text_arg(c)
    width, _ := arg_int(c, 1, "width", 79)
    if width <= 0 do return fail(c, "invalid width %d (must be > 0)", width)
    opts := Wrap_Options{width = int(width),
        break_long_words = truthy(arg(c, 2, "break_long_words", true)),
        break_on_hyphens = truthy(arg(c, 4, "break_on_hyphens", true))}
    wrapstring := to_string(arg(c, 3, "wrapstring", string("\n")))
    if is_none(arg(c, 3, "wrapstring", None{})) do wrapstring = "\n"
    b := strings.builder_make()
    for line, i in python_splitlines(text) {
        if i > 0 do strings.write_string(&b, wrapstring)
        for piece, j in text_wrap(line, opts) {
            if j > 0 do strings.write_string(&b, wrapstring)
            strings.write_string(&b, piece)
        }
    }
    return strings.to_string(b)
}

Wrap_Options :: struct {
    width:            int,
    break_long_words: bool,
    break_on_hyphens: bool,
}

// wrap_chunks splits text like textwrap: runs of whitespace, and words (split after
// hyphens between letters when break_on_hyphens is set).
@(private="file")
wrap_chunks :: proc(text: string, break_on_hyphens: bool) -> []string {
    out := make([dynamic]string)
    r := runes_of(text)
    offsets, err := make([]int, len(r) + 1)
    if err != nil || len(r) != strings.rune_count(text) do return nil // refused.
    pos := 0
    for x, i in r { offsets[i] = pos; pos += rune_size(x) }
    offsets[len(r)] = pos
    i := 0
    for i < len(r) {
        j := i
        if is_space(r[i]) {
            for j < len(r) && is_space(r[j]) do j += 1
        } else {
            for j < len(r) && !is_space(r[j]) {
                j += 1
                if break_on_hyphens && r[j - 1] == '-' && j < len(r) && j >= 2 &&
                   unicode.is_letter(r[j - 2]) && unicode.is_letter(r[j]) {
                    break
                }
            }
        }
        append(&out, text[offsets[i]:offsets[j]])
        i = j
    }
    return out[:]
}

// text_wrap is textwrap.wrap with expand_tabs and replace_whitespace off.
text_wrap :: proc(text: string, opts: Wrap_Options) -> []string {
    chunks := wrap_chunks(text, opts.break_on_hyphens)
    lines := make([dynamic]string)
    i := 0
    for i < len(chunks) {
        line := make([dynamic]string)
        used := 0
        if strings.trim_space(chunks[i]) == "" && len(lines) > 0 do i += 1
        for i < len(chunks) {
            n := strings.rune_count(chunks[i])
            if used + n <= opts.width {
                append(&line, chunks[i])
                used += n
                i += 1
            } else {
                break
            }
        }
        if i < len(chunks) && strings.rune_count(chunks[i]) > opts.width {
            space := opts.width - used
            if opts.break_long_words {
                head := rune_slice(chunks[i], 0, space)
                if opts.break_on_hyphens {
                    cut := strings.last_index_byte(head, '-')
                    if cut > 0 && strings.trim_left(head[:cut], "-") != "" do head = head[:cut + 1]
                }
                append(&line, head)
                chunks[i] = chunks[i][len(head):]
            } else if len(line) == 0 {
                append(&line, chunks[i])
                i += 1
            }
        }
        for len(line) > 0 && strings.trim_space(line[len(line) - 1]) == "" do pop(&line)
        if len(line) > 0 do append(&lines, strings.concatenate(line[:]))
    }
    return lines[:]
}
