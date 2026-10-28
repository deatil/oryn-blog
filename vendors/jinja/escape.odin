package jinja

import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

// write_escaped writes text with the five HTML special characters replaced, exactly as
// MarkupSafe does (&amp; &lt; &gt; &#34; &#39;).
@(private)
write_escaped :: proc(b: ^strings.Builder, s: string) {
    start := 0
    for i in 0 ..< len(s) {
        replacement: string
        switch s[i] {
        case '&': replacement = "&amp;"
        case '<': replacement = "&lt;"
        case '>': replacement = "&gt;"
        case '"': replacement = "&#34;"
        case '\'': replacement = "&#39;"
        case: continue
        }
        strings.write_string(b, s[start:i])
        strings.write_string(b, replacement)
        start = i + 1
    }
    strings.write_string(b, s[start:])
}

@(private)
needs_escape :: proc(s: string) -> bool {
    for i in 0 ..< len(s) {
        switch s[i] {
        case '&', '<', '>', '"', '\'': return true
        }
    }
    return false
}

// escape_string replaces the five HTML special characters as MarkupSafe does. When s has
// none it is returned as it is, borrowed; otherwise the result is allocated with
// allocator, which the caller owns (or, as usual, an arena holds).
escape_string :: proc(s: string, allocator := context.allocator) -> string {
    if !needs_escape(s) do return s
    b := strings.builder_make(0, len(s) + 16, allocator)
    write_escaped(&b, s)
    return strings.to_string(b)
}

// escape converts a value to Markup: Markup stays as it is, everything else is converted
// to a string and escaped (MarkupSafe's escape()), allocating with allocator when it must;
// the result may borrow v, so it belongs in an arena, as values do.
escape :: proc(v: Value, allocator := context.allocator) -> Markup {
    if m, ok := v.(Markup); ok do return m
    return Markup(escape_string(to_string(v, allocator), allocator))
}

// markup_concat joins two values the way Markup's + does when either side is Markup:
// the plain side is escaped.
@(private)
markup_concat :: proc(a, b: Value) -> Markup {
    return Markup(strings.concatenate({string(escape(a)), string(escape(b))}))
}

// ---------------------------------------------------------------------------------------
// striptags and unescape (MarkupSafe)

@(private)
striptags :: proc(s: string) -> string {
    b := strings.builder_make()
    i := 0
    for i < len(s) {
        if strings.has_prefix(s[i:], "<!--") {
            end := strings.index(s[i + 4:], "-->")
            if end >= 0 { i += 4 + end + 3; continue }
        }
        if s[i] == '<' {
            end := strings.index_byte(s[i + 1:], '>')
            if end >= 0 { i += end + 2; continue }
        }
        strings.write_byte(&b, s[i])
        i += 1
    }
    words := python_split(strings.to_string(b))
    return unescape_html(strings.join(words, " "))
}

@(private="file")
ENTITIES := [?]struct { name: string, value: string } {
    {"amp", "&"}, {"lt", "<"}, {"gt", ">"}, {"quot", "\""}, {"apos", "'"},
    {"nbsp", " "}, {"copy", "©"}, {"reg", "®"}, {"trade", "™"},
    {"hellip", "…"}, {"mdash", "—"}, {"ndash", "–"}, {"lsquo", "‘"},
    {"rsquo", "’"}, {"ldquo", "“"}, {"rdquo", "”"}, {"laquo", "«"},
    {"raquo", "»"}, {"middot", "·"}, {"bull", "•"}, {"para", "¶"},
    {"sect", "§"}, {"deg", "°"}, {"times", "×"}, {"divide", "÷"},
    {"euro", "€"}, {"pound", "£"}, {"yen", "¥"}, {"cent", "¢"},
    {"larr", "←"}, {"rarr", "→"}, {"uarr", "↑"}, {"darr", "↓"},
    {"shy", "­"}, {"iexcl", "¡"}, {"iquest", "¿"}, {"szlig", "ß"},
}

// unescape_html replaces character references: numeric ones and the common named ones.
@(private)
unescape_html :: proc(s: string) -> string {
    if strings.index_byte(s, '&') < 0 do return s
    b := strings.builder_make()
    i := 0
    outer: for i < len(s) {
        if s[i] != '&' { strings.write_byte(&b, s[i]); i += 1; continue }
        semi := strings.index_byte(s[i:], ';')
        if semi > 1 && semi < 40 {
            name := s[i + 1:i + semi]
            if name[0] == '#' {
                code, ok := parse_char_ref(name[1:])
                if ok { strings.write_rune(&b, code); i += semi + 1; continue }
            }
            for e in ENTITIES {
                if e.name == name {
                    strings.write_string(&b, e.value)
                    i += semi + 1
                    continue outer
                }
            }
        }
        strings.write_byte(&b, '&')
        i += 1
    }
    return strings.to_string(b)
}

@(private="file")
parse_char_ref :: proc(s: string) -> (rune, bool) {
    if len(s) == 0 do return 0, false
    v: u64
    ok: bool
    if s[0] == 'x' || s[0] == 'X' {
        v, ok = strconv.parse_u64_of_base(s[1:], 16)
    } else {
        v, ok = strconv.parse_u64_of_base(s, 10)
    }
    if !ok || v == 0 || v > 0x10ffff do return utf8.RUNE_ERROR, ok
    return rune(v), true
}

// python_split splits on runs of whitespace like str.split() without arguments.
@(private)
python_split :: proc(s: string, allocator := context.allocator) -> []string {
    out := make([dynamic]string, allocator)
    start := -1
    for r, i in s {
        if is_space(r) {
            if start >= 0 { append(&out, s[start:i]); start = -1 }
        } else if start < 0 {
            start = i
        }
    }
    if start >= 0 do append(&out, s[start:])
    return out[:]
}

@(private)
is_space :: proc(r: rune) -> bool {
    switch r {
    case ' ', '\t', '\n', '\r', '\v', '\f', 0x1c ..= 0x1f, 0x85, 0xa0, 0x1680, 0x2000 ..= 0x200a,
         0x2028, 0x2029, 0x202f, 0x205f, 0x3000:
        return true
    }
    return false
}

@(private)
is_word_rune :: proc(r: rune) -> bool {
    return r == '_' || unicode.is_letter(r) || unicode.is_digit(r) || unicode.is_number(r)
}

// ---------------------------------------------------------------------------------------
// URL quoting (urllib.parse.quote)

@(private)
write_url_quoted :: proc(b: ^strings.Builder, s: string, safe: string, plus_spaces: bool) {
    for i in 0 ..< len(s) {
        c := s[i]
        switch {
        case 'a' <= c && c <= 'z', 'A' <= c && c <= 'Z', '0' <= c && c <= '9':
            strings.write_byte(b, c)
        case c == '_' || c == '.' || c == '-' || c == '~':
            strings.write_byte(b, c)
        case strings.index_byte(safe, c) >= 0:
            strings.write_byte(b, c)
        case c == ' ' && plus_spaces:
            strings.write_byte(b, '+')
        case:
            strings.write_byte(b, '%')
            write_hex(b, u64(c), 2, upper = true)
        }
    }
}
