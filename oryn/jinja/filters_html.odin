#+private
package jinja

import "core:math"
import "core:strings"
import "core:unicode"

// Filters that produce or inspect HTML, URLs and JSON.

register_html_filters :: proc(env: ^Environment) {
    add_filter(env, "escape", filter_escape)
    add_filter(env, "e", filter_escape)
    add_filter(env, "forceescape", filter_escape)
    add_filter(env, "safe", filter_safe)
    add_filter(env, "striptags", filter_striptags)
    add_filter(env, "tojson", filter_tojson)
    add_filter(env, "urlencode", filter_urlencode)
    add_filter(env, "urlize", filter_urlize)
    add_filter(env, "xmlattr", filter_xmlattr)
}

@(private="file")
filter_escape :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "value")
    if c.name == "forceescape" do return Markup(escape_string(to_string(v)))
    return escape(v)
}

@(private="file")
filter_safe :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "value")
    if is_markup(v) do return v
    return Markup(to_string(v))
}

@(private="file")
filter_striptags :: proc(c: ^Call) -> Value {
    return striptags(to_string(arg(c, 0, "value")))
}

// ---------------------------------------------------------------------------------------
// tojson: json.dumps(sort_keys=True) made safe for HTML

@(private="file")
filter_tojson :: proc(c: ^Call) -> Value {
    if !check_args(c, "tojson", {"value", "indent"}) do return Undefined{}
    indent := ""
    has_indent := false
    iv := arg(c, 1, "indent", None{})
    if text, ok := key_string(iv); ok {
        indent, has_indent = text, true
    } else if !is_none(iv) {
        n, _ := arg_int(c, 1, "indent", 0)
        spaces, made := repeat_text(c.state, " ", int(clamp(n, 0, i64(max(int)))))
        if !made do return Undefined{}
        indent, has_indent = spaces, true
    }
    b := strings.builder_make()
    w := Json_Writer{s = c.state, b = &b, indent = indent, pretty = has_indent}
    if !write_json(&w, arg(c, 0, "value"), 0) do return Undefined{}
    return Markup(strings.to_string(b))
}

@(private="file")
Json_Writer :: struct {
    s:      ^State,
    b:      ^strings.Builder,
    indent: string,
    pretty: bool,
}

@(private="file")
json_newline :: proc(w: ^Json_Writer, depth: int) {
    strings.write_byte(w.b, '\n')
    for _ in 0 ..< depth do strings.write_string(w.b, w.indent)
}

@(private="file")
write_json :: proc(w: ^Json_Writer, v: Value, depth: int) -> bool {
    if depth > MAX_VALUE_DEPTH {
        runtime_error(w.s, .Limit, "tojson: the value nests more than %d levels deep " +
            "(a list or dict that contains itself?)", MAX_VALUE_DEPTH)
        return false
    }
    switch x in v {
    case None: strings.write_string(w.b, "null")
    case bool: strings.write_string(w.b, "true" if x else "false")
    case i64: strings.write_i64(w.b, x)
    case f64:
        switch {
        case math.is_nan(x): strings.write_string(w.b, "NaN")
        case math.is_inf(x): strings.write_string(w.b, "Infinity" if x > 0 else "-Infinity")
        case: write_float_repr(w.b, x)
        }
    case string: write_json_string(w.b, x)
    case Markup: write_json_string(w.b, string(x))
    case ^List:
        if len(x.items) == 0 { strings.write_string(w.b, "[]"); return true }
        strings.write_byte(w.b, '[')
        for item, i in x.items {
            if i > 0 do strings.write_string(w.b, "," if w.pretty else ", ")
            if w.pretty do json_newline(w, depth + 1)
            if !write_json(w, item, depth + 1) do return false
        }
        if w.pretty do json_newline(w, depth)
        strings.write_byte(w.b, ']')
    case ^Dict:
        if x.kind == .Module do break
        return write_json_object(w, x, depth)
    case Undefined, ^Callable, ^Loop, ^Cycler:
    }
    #partial switch _ in v {
    case Undefined, ^Callable, ^Loop, ^Cycler, ^Dict:
        runtime_error(w.s, .Type, "Object of type %s is not JSON serializable", type_name(v))
        return false
    }
    return true
}

@(private="file")
write_json_object :: proc(w: ^Json_Writer, d: ^Dict, depth: int) -> bool {
    if len(d.keys) == 0 { strings.write_string(w.b, "{}"); return true }
    order, ok := sort_order(w.s, d.keys[:], false, true)
    if !ok do return false
    strings.write_byte(w.b, '{')
    for index, i in order {
        if i > 0 do strings.write_string(w.b, "," if w.pretty else ", ")
        if w.pretty do json_newline(w, depth + 1)
        key := d.keys[index]
        #partial switch k in key {
        case string, Markup: write_json(w, key, 0)
        case None: strings.write_string(w.b, "\"null\"")
        case bool: strings.write_string(w.b, "\"true\"" if k else "\"false\"")
        case i64, f64:
            strings.write_byte(w.b, '"')
            write_json(w, key, 0)
            strings.write_byte(w.b, '"')
        case:
            runtime_error(w.s, .Type, "keys must be str, int, float, bool or None, not %s",
                type_name(key))
            return false
        }
        strings.write_string(w.b, ": ")
        if !write_json(w, d.values[index], depth + 1) do return false
    }
    if w.pretty do json_newline(w, depth)
    strings.write_byte(w.b, '}')
    return true
}

// write_json_string escapes like json.dumps(ensure_ascii=True), plus the HTML-safety
// replacements of < > & and '.
@(private="file")
write_json_string :: proc(b: ^strings.Builder, s: string) {
    strings.write_byte(b, '"')
    for r in s {
        switch r {
        case '"': strings.write_string(b, `\"`)
        case '\\': strings.write_string(b, `\\`)
        case '\n': strings.write_string(b, `\n`)
        case '\r': strings.write_string(b, `\r`)
        case '\t': strings.write_string(b, `\t`)
        case '\b': strings.write_string(b, `\b`)
        case '\f': strings.write_string(b, `\f`)
        case '<', '>', '&', '\'': write_u_escape(b, r)
        case:
            if r < 0x20 || r > 0x7e {
                if r > 0xffff {
                    v := r - 0x10000
                    write_u_escape(b, 0xd800 + (v >> 10))
                    write_u_escape(b, 0xdc00 + (v & 0x3ff))
                } else {
                    write_u_escape(b, r)
                }
            } else {
                strings.write_rune(b, r)
            }
        }
    }
    strings.write_byte(b, '"')
}

@(private="file")
write_u_escape :: proc(b: ^strings.Builder, r: rune) {
    strings.write_string(b, `\u`)
    write_hex(b, u64(r), 4)
}

// ---------------------------------------------------------------------------------------
// urlencode

@(private="file")
filter_urlencode :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "value")
    b := strings.builder_make()
    #partial switch x in v {
    case ^Dict:
        for key, i in x.keys {
            if i > 0 do strings.write_byte(&b, '&')
            write_url_quoted(&b, to_string(key), "", true)
            strings.write_byte(&b, '=')
            write_url_quoted(&b, to_string(x.values[i]), "", true)
        }
    case ^List:
        for item, i in x.items {
            pair, ok := item.(^List)
            if !ok || len(pair.items) != 2 do return fail(c, "urlencode expects pairs")
            if i > 0 do strings.write_byte(&b, '&')
            write_url_quoted(&b, to_string(pair.items[0]), "", true)
            strings.write_byte(&b, '=')
            write_url_quoted(&b, to_string(pair.items[1]), "", true)
        }
    case:
        write_url_quoted(&b, to_string(v), "/", false)
    }
    return strings.to_string(b)
}

// ---------------------------------------------------------------------------------------
// xmlattr

@(private="file")
filter_xmlattr :: proc(c: ^Call) -> Value {
    d, ok := arg(c, 0, "d").(^Dict)
    if !ok do return fail(c, "xmlattr expects a mapping")
    b := strings.builder_make()
    first := true
    for key, i in d.keys {
        value := d.values[i]
        if is_none(value) || is_undefined(value) do continue
        name := to_string(key)
        for r in name {
            if is_ascii_space(r) || r == '/' || r == '>' || r == '=' {
                return fail(c, "Invalid character in attribute name: %s", repr(name))
            }
        }
        if !first do strings.write_byte(&b, ' ')
        first = false
        write_escaped(&b, name)
        strings.write_string(&b, "=\"")
        write_escaped(&b, to_string(value))
        strings.write_byte(&b, '"')
    }
    out := strings.to_string(b)
    if truthy(arg(c, 1, "autospace", true)) && len(out) > 0 {
        out = strings.concatenate({" ", out})
    }
    if autoescaping(c) do return Markup(out)
    return out
}

is_ascii_space :: proc(r: rune) -> bool {
    return r == ' ' || r == '\t' || r == '\n' || r == '\r' || r == '\v' || r == '\f'
}

// ---------------------------------------------------------------------------------------
// urlize

@(private="file")
Urlize :: struct {
    trim_limit: int,
    rel:        string,
    target:     string,
    schemes:    []string,
}

@(private="file")
filter_urlize :: proc(c: ^Call) -> Value {
    names := []string{"value", "trim_url_limit", "nofollow", "target", "rel", "extra_schemes"}
    if !check_args(c, "urlize", names) do return Undefined{}
    u := Urlize{trim_limit = -1}
    if limit := arg(c, 1, "trim_url_limit", None{}); !is_none(limit) {
        n, _ := arg_int(c, 1, "trim_url_limit", 0)
        u.trim_limit = int(n)
    }
    rel_parts := make([dynamic]string)
    if rel := arg(c, 4, "rel", None{}); !is_none(rel) {
        append(&rel_parts, ..python_split(to_string(rel)))
    }
    if truthy(arg(c, 2, "nofollow", false)) do append(&rel_parts, "nofollow")
    append(&rel_parts, "noopener")
    sorted, _ := sort_values(c.state, strings_to_values(rel_parts[:]), false, true, nil)
    unique := make([dynamic]string)
    for v in sorted {
        text := to_string(v)
        if len(unique) == 0 || unique[len(unique) - 1] != text do append(&unique, text)
    }
    u.rel = strings.join(unique[:], " ")
    if target := arg(c, 3, "target", None{}); !is_none(target) do u.target = to_string(target)
    if schemes, ok := arg(c, 5, "extra_schemes", None{}).(^List); ok {
        list := make([dynamic]string)
        for sv in schemes.items do append(&list, to_string(sv))
        u.schemes = list[:]
    }
    out := urlize_text(string(escape(arg(c, 0, "value"))), u)
    if autoescaping(c) do return Markup(out)
    return out
}

strings_to_values :: proc(items: []string) -> []Value {
    out, err := make([]Value, len(items))
    if err != nil do return nil
    for s, i in items do out[i] = s
    return out
}

@(private="file")
urlize_text :: proc(text: string, u: Urlize) -> string {
    b := strings.builder_make()
    i := 0
    for i < len(text) {
        j := i
        space := is_space(rune(text[i]))
        for j < len(text) && is_space(rune(text[j])) == space do j += 1
        if space {
            strings.write_string(&b, text[i:j])
        } else {
            urlize_word(&b, text[i:j], u)
        }
        i = j
    }
    return strings.to_string(b)
}

@(private="file")
urlize_word :: proc(b: ^strings.Builder, word: string, u: Urlize) {
    middle := word
    head_end := 0
    for {
        if strings.has_prefix(middle[head_end:], "&lt;") { head_end += 4; continue }
        if head_end < len(middle) && (middle[head_end] == '(' || middle[head_end] == '<') {
            head_end += 1
            continue
        }
        break
    }
    head := middle[:head_end]
    middle = middle[head_end:]
    tail_start := len(middle)
    for tail_start > 0 {
        if strings.has_suffix(middle[:tail_start], "&gt;") { tail_start -= 4; continue }
        ch := middle[tail_start - 1]
        if ch == ')' || ch == '>' || ch == '.' || ch == ',' || ch == '\n' {
            tail_start -= 1
            continue
        }
        break
    }
    tail := middle[tail_start:]
    middle = middle[:tail_start]
    pairs := [3][2]string{{"(", ")"}, {"<", ">"}, {"&lt;", "&gt;"}}
    for pair in pairs {
        opens := strings.count(middle, pair[0])
        if opens <= strings.count(middle, pair[1]) do continue
        for _ in 0 ..< min(opens, strings.count(tail, pair[1])) {
            end := strings.index(tail, pair[1]) + len(pair[1])
            middle = strings.concatenate({middle, tail[:end]})
            tail = tail[end:]
        }
    }
    strings.write_string(b, head)
    urlize_middle(b, middle, u)
    strings.write_string(b, tail)
}

@(private="file")
urlize_middle :: proc(b: ^strings.Builder, middle: string, u: Urlize) {
    attrs := strings.builder_make()
    if u.rel != "" {
        strings.write_string(&attrs, " rel=\"")
        write_escaped(&attrs, u.rel)
        strings.write_byte(&attrs, '"')
    }
    if u.target != "" {
        strings.write_string(&attrs, " target=\"")
        write_escaped(&attrs, u.target)
        strings.write_byte(&attrs, '"')
    }
    extra := strings.to_string(attrs)
    shown := middle
    if u.trim_limit >= 0 && strings.rune_count(middle) > u.trim_limit {
        shown = strings.concatenate({rune_slice(middle, 0, u.trim_limit), "..."})
    }
    lower := to_lower(middle)
    switch {
    case match_http(middle):
        href := middle
        if !strings.has_prefix(lower, "http://") && !strings.has_prefix(lower, "https://") {
            href = strings.concatenate({"https://", middle})
        }
        strings.write_string(b, strings.concatenate({"<a href=\"", href, "\"", extra, ">", shown,
            "</a>"}))
    case strings.has_prefix(middle, "mailto:") && match_email(middle[7:]):
        strings.write_string(b, strings.concatenate({"<a href=\"", middle, "\">", middle[7:],
            "</a>"}))
    case strings.contains_rune(middle, '@') && !strings.has_prefix(middle, "www.") &&
         !strings.contains_rune(middle, ':') && match_email(middle):
        strings.write_string(b, strings.concatenate({"<a href=\"mailto:", middle, "\">", middle,
            "</a>"}))
    case:
        for scheme in u.schemes {
            if middle != scheme && strings.has_prefix(middle, scheme) {
                strings.write_string(b, strings.concatenate({"<a href=\"", middle, "\"", extra,
                    ">", middle, "</a>"}))
                return
            }
        }
        strings.write_string(b, middle)
    }
}

@(private="file")
is_label_rune :: proc(r: rune) -> bool {
    return is_word_rune(r) || r == '%' || r == '-'
}

@(private="file")
all_runes :: proc(s: string, f: proc(r: rune) -> bool) -> bool {
    for r in s do if !f(r) do return false
    return true
}

@(private="file")
is_ascii_letter :: proc(r: rune) -> bool {
    return ('a' <= r && r <= 'z') || ('A' <= r && r <= 'Z')
}

// match_http follows Jinja's _http_re: a scheme or www. with a host and tld, a bare
// domain with a common tld, or a scheme with an IP address; then port and path.
@(private="file")
match_http :: proc(text: string) -> bool {
    lower := to_lower(text)
    scheme := ""
    if strings.has_prefix(lower, "https://") {
        scheme = text[:8]
    } else if strings.has_prefix(lower, "http://") {
        scheme = text[:7]
    }
    host := text[len(scheme):]
    if cut := strings.index_any(host, "/?#"); cut >= 0 do host = host[:cut]
    if colon := strings.last_index_byte(host, ':'); colon >= 0 && !strings.has_suffix(host, "]") {
        port := host[colon + 1:]
        if len(port) >= 1 && len(port) <= 5 && all_runes(port, unicode.is_digit) {
            host = host[:colon]
        }
    }
    if scheme != "" && is_ip_host(host) do return true
    if scheme == "" && strings.has_prefix(to_lower(host), "www.") {
        scheme = "www."
        host = host[4:]
    }
    labels := strings.split(host, ".")
    if len(labels) == 0 do return false
    tld := labels[len(labels) - 1]
    if scheme != "" {
        tld_ok := len(tld) >= 2 && len(tld) <= 63 && all_runes(tld, is_ascii_letter)
        if strings.has_prefix(to_lower(tld), "xn--") {
            tld_ok = len(tld) >= 6 && len(tld) <= 63
        }
        if !tld_ok do return false
        for label in labels[:len(labels) - 1] {
            if len(label) == 0 || !all_runes(label, is_label_rune) do return false
        }
        return true
    }
    switch to_lower(tld) {
    case "com", "net", "int", "edu", "gov", "org", "info", "mil":
    case: return false
    }
    if len(labels) < 2 do return false
    for label in labels[:len(labels) - 1] {
        n := strings.rune_count(label)
        if n < 2 || n > 63 || !all_runes(label, is_label_rune) do return false
    }
    return true
}

@(private="file")
is_ip_host :: proc(host: string) -> bool {
    if strings.has_prefix(host, "[") && strings.has_suffix(host, "]") {
        inner := host[1:len(host) - 1]
        return strings.count(inner, ":") >= 2 && all_runes(inner, proc(r: rune) -> bool {
            return r == ':' || unicode.is_digit(r) || ('a' <= r && r <= 'f') ||
                ('A' <= r && r <= 'F')
        })
    }
    parts := strings.split(host, ".")
    if len(parts) != 4 do return false
    for p in parts {
        if len(p) < 1 || len(p) > 3 || !all_runes(p, unicode.is_digit) do return false
    }
    return true
}

// match_email follows ^\S+@\w[\w.-]*\.\w+$.
@(private="file")
match_email :: proc(text: string) -> bool {
    at := strings.last_index_byte(text, '@')
    if at <= 0 do return false
    for r in text[:at] do if is_space(r) do return false
    rest := text[at + 1:]
    dot := strings.last_index_byte(rest, '.')
    if dot < 1 || dot == len(rest) - 1 do return false
    first, _ := first_rune(rest)
    if !is_word_rune(first) do return false
    domain_ok :: proc(r: rune) -> bool { return is_word_rune(r) || r == '.' || r == '-' }
    return all_runes(rest[:dot], domain_ok) && all_runes(rest[dot + 1:], is_word_rune)
}
