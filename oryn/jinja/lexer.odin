#+private
package jinja

import "base:intrinsics"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

Token_Kind :: enum u8 {
    EOF,
    Data,           // template text, already whitespace-controlled
    Variable_Begin, // {{
    Variable_End,   // }}
    Block_Begin,    // {%
    Block_End,      // %}
    Name,
    String,
    Integer,
    Float,
    Operator,
}

Token :: struct {
    kind:   Token_Kind,
    text:   string, // decoded text of strings, names, operators and data
    number: i64,
    float:  f64,
    line:   int,
}

Lex_Options :: struct {
    trim_blocks:           bool,
    lstrip_blocks:         bool,
    keep_trailing_newline: bool,
}

@(private="file")
Lexer :: struct {
    src:    string,
    pos:    int,
    line:   int,
    opts:   Lex_Options,
    tokens: [dynamic]Token,
    err:    Error,
}

// tokenize splits a template into tokens. Newlines are normalized to "\n".
tokenize :: proc(source: string, name: string, opts: Lex_Options) -> ([]Token, Error) {
    src := source
    if strings.contains_rune(src, '\r') {
        src, _ = strings.replace_all(src, "\r\n", "\n")
        src, _ = strings.replace_all(src, "\r", "\n")
    }
    if !opts.keep_trailing_newline && strings.has_suffix(src, "\n") do src = src[:len(src) - 1]
    lx := Lexer{src = src, line = 1, opts = opts}
    lx.tokens = make([dynamic]Token, 0, len(src) / 8 + 8)
    for lx.pos < len(lx.src) && lx.err.kind == .None {
        lex_step(&lx)
    }
    if lx.err.kind != .None {
        lx.err.template = name
        return nil, lx.err
    }
    append(&lx.tokens, Token{kind = .EOF, line = lx.line})
    return lx.tokens[:], {}
}

@(private="file")
lex_error :: proc(lx: ^Lexer, message: string) {
    if lx.err.kind != .None do return
    lx.err = Error{kind = .Syntax, line = lx.line, message = message}
}

@(private="file")
emit :: proc(lx: ^Lexer, kind: Token_Kind, text: string) {
    append(&lx.tokens, Token{kind = kind, text = text, line = lx.line})
}

@(private="file")
advance :: proc(lx: ^Lexer, n: int) {
    lx.line += strings.count(lx.src[lx.pos:lx.pos + n], "\n")
    lx.pos += n
}

// find_tag finds the next "{{", "{%" or "{#" at or after from.
@(private="file")
find_tag :: proc(src: string, from: int) -> int {
    i := from
    for {
        j := strings.index_byte(src[i:], '{')
        if j < 0 || i + j + 1 >= len(src) do return -1
        c := src[i + j + 1]
        if c == '{' || c == '%' || c == '#' do return i + j
        i += j + 1
    }
}

// lex_step lexes the data before the next tag and then the tag itself.
@(private="file")
lex_step :: proc(lx: ^Lexer) {
    start := find_tag(lx.src, lx.pos)
    if start < 0 {
        emit(lx, .Data, lx.src[lx.pos:])
        advance(lx, len(lx.src) - lx.pos)
        return
    }
    opener := lx.src[start + 1]
    sign: u8 = lx.src[start + 2] if start + 2 < len(lx.src) else 0
    data := lx.src[lx.pos:start]
    is_raw := opener == '%' && raw_begins(lx.src[start + 2:])
    if sign == '-' {
        data = strings.trim_right_proc(data, is_space)
    } else if lx.opts.lstrip_blocks && sign != '+' && opener != '{' {
        data = lstrip_line(lx.src, lx.pos, data)
    }
    if len(data) > 0 do emit(lx, .Data, data)
    advance(lx, start - lx.pos)
    skip := 3 if sign == '-' || sign == '+' else 2
    switch {
    case opener == '#': lex_comment(lx, skip)
    case is_raw: lex_raw(lx, skip)
    case opener == '{':
        emit(lx, .Variable_Begin, "{{")
        advance(lx, skip)
        lex_expression(lx, .Variable_End)
    case:
        emit(lx, .Block_Begin, "{%")
        advance(lx, skip)
        lex_expression(lx, .Block_End)
    }
}

// lstrip_line removes spaces and tabs before a block tag when they are the only thing
// on the tag's line (lstrip_blocks).
@(private="file")
lstrip_line :: proc(src: string, data_start: int, data: string) -> string {
    l := strings.last_index_byte(data, '\n') + 1
    at_line_start := l > 0 || data_start == 0 || src[data_start - 1] == '\n'
    if !at_line_start do return data
    for c in transmute([]u8)data[l:] {
        if c != ' ' && c != '\t' do return data
    }
    return data[:l]
}

// after_tag applies "-" (strip all whitespace) or trim_blocks (drop one newline).
@(private="file")
after_tag :: proc(lx: ^Lexer, sign: u8, is_block: bool) {
    if sign == '-' {
        n := 0
        for lx.pos + n < len(lx.src) && is_space(rune(lx.src[lx.pos + n])) do n += 1
        advance(lx, n)
    } else if sign != '+' && is_block && lx.opts.trim_blocks {
        if lx.pos < len(lx.src) && lx.src[lx.pos] == '\n' do advance(lx, 1)
    }
}

@(private="file")
lex_comment :: proc(lx: ^Lexer, skip: int) {
    begin_line := lx.line
    advance(lx, skip)
    end := strings.index(lx.src[lx.pos:], "#}")
    if end < 0 {
        lx.line = begin_line
        lex_error(lx, "Missing end of comment tag")
        return
    }
    sign: u8 = lx.src[lx.pos + end - 1] if end > 0 else 0
    advance(lx, end + 2)
    after_tag(lx, sign, true)
}

@(private="file")
raw_begins :: proc(s: string) -> bool {
    rest := s
    if len(rest) > 0 && (rest[0] == '-' || rest[0] == '+') do rest = rest[1:]
    rest = strings.trim_left(rest, " \t\n")
    if !strings.has_prefix(rest, "raw") do return false
    rest = strings.trim_left(rest[3:], " \t\n")
    if len(rest) > 0 && (rest[0] == '-' || rest[0] == '+') do rest = rest[1:]
    return strings.has_prefix(rest, "%}")
}

// lex_raw copies everything up to {% endraw %} as data.
@(private="file")
lex_raw :: proc(lx: ^Lexer, skip: int) {
    close := strings.index(lx.src[lx.pos:], "%}")
    begin_sign := lx.src[lx.pos + close - 1]
    advance(lx, close + 2)
    if begin_sign == '-' do after_tag(lx, '-', true)
    body_start := lx.pos
    search := lx.pos
    for {
        tag := strings.index(lx.src[search:], "{%")
        if tag < 0 {
            lex_error(lx, "Missing end of raw directive")
            return
        }
        at := search + tag
        inner := lx.src[at + 2:]
        sign: u8 = inner[0] if len(inner) > 0 else 0
        if sign == '-' || sign == '+' do inner = inner[1:]
        trimmed := strings.trim_left(inner, " \t\n")
        if strings.has_prefix(trimmed, "endraw") {
            rest := strings.trim_left(trimmed[6:], " \t\n")
            end_sign: u8 = 0
            if len(rest) > 0 && (rest[0] == '-' || rest[0] == '+') {
                end_sign = rest[0]
                rest = rest[1:]
            }
            if strings.has_prefix(rest, "%}") {
                body := lx.src[body_start:at]
                if sign == '-' {
                    body = strings.trim_right_proc(body, is_space)
                } else if lx.opts.lstrip_blocks && sign != '+' {
                    body = lstrip_line(lx.src, body_start, body)
                }
                if len(body) > 0 do emit(lx, .Data, body)
                tag_end := len(lx.src) - len(rest) + 2
                advance(lx, tag_end - lx.pos)
                after_tag(lx, end_sign, true)
                return
            }
        }
        search = at + 2
    }
}

// lex_expression lexes the tokens of a {{ }} or {% %} tag up to its end.
@(private="file")
lex_expression :: proc(lx: ^Lexer, end_kind: Token_Kind) {
    closer := "}}" if end_kind == .Variable_End else "%}"
    depth := 0
    for lx.err.kind == .None {
        for lx.pos < len(lx.src) && is_space(rune(lx.src[lx.pos])) do advance(lx, 1)
        if lx.pos >= len(lx.src) {
            what := "print statement" if end_kind == .Variable_End else "statement block"
            lex_error(lx, strings.concatenate({"unexpected end of template, expected 'end of ",
                what, "'."}))
            return
        }
        rest := lx.src[lx.pos:]
        if depth == 0 {
            sign: u8 = 0
            if (rest[0] == '-' || rest[0] == '+') && strings.has_prefix(rest[1:], closer) {
                sign = rest[0]
                rest = rest[1:]
            }
            if strings.has_prefix(rest, closer) {
                emit(lx, end_kind, closer)
                advance(lx, 2 if sign == 0 else 3)
                after_tag(lx, sign, end_kind == .Block_End)
                return
            }
        }
        lex_token(lx, &depth)
    }
}

@(private="file")
OPERATORS := [?]string {
    "//", "**", "==", "!=", ">=", "<=", "+", "-", "*", "/", "%", "~", "[", "]", "(", ")",
    "{", "}", ">", "<", "=", ".", ":", "|", ",", ";",
}

@(private="file")
lex_token :: proc(lx: ^Lexer, depth: ^int) {
    rest := lx.src[lx.pos:]
    c := rest[0]
    r, size := utf8.decode_rune_in_string(rest)
    switch {
    case c == '"' || c == '\'':
        lex_string(lx)
    case '0' <= c && c <= '9':
        lex_number(lx)
    case c == '_' || unicode.is_letter(r):
        n := size
        for n < len(rest) {
            r2, s2 := utf8.decode_rune_in_string(rest[n:])
            if r2 != '_' && !unicode.is_letter(r2) && !unicode.is_digit(r2) do break
            n += s2
        }
        emit(lx, .Name, rest[:n])
        advance(lx, n)
    case:
        for op in OPERATORS {
            if !strings.has_prefix(rest, op) do continue
            switch op {
            case "(", "[", "{": depth^ += 1
            case ")", "]", "}":
                if depth^ == 0 {
                    lex_error(lx, strings.concatenate({"unexpected '", op, "'"}))
                    return
                }
                depth^ -= 1
            }
            emit(lx, .Operator, op)
            advance(lx, len(op))
            return
        }
        lex_error(lx, strings.concatenate({"unexpected char ", repr(string(rest[:size]))}))
    }
}

@(private="file")
lex_string :: proc(lx: ^Lexer) {
    rest := lx.src[lx.pos:]
    quote := rest[0]
    i := 1
    for i < len(rest) && rest[i] != quote {
        if rest[i] == '\\' do i += 1
        i += 1
    }
    if i >= len(rest) {
        lex_error(lx, "unexpected end of string")
        return
    }
    emit(lx, .String, unescape_literal(rest[1:i]))
    advance(lx, i + 1)
}

// unescape_literal decodes Python string escapes; unknown escapes keep the backslash.
unescape_literal :: proc(s: string) -> string {
    if strings.index_byte(s, '\\') < 0 do return s
    b := strings.builder_make(0, len(s))
    i := 0
    for i < len(s) {
        if s[i] != '\\' || i + 1 >= len(s) {
            strings.write_byte(&b, s[i])
            i += 1
            continue
        }
        e := s[i + 1]
        i += 2
        switch e {
        case 'n': strings.write_byte(&b, '\n')
        case 't': strings.write_byte(&b, '\t')
        case 'r': strings.write_byte(&b, '\r')
        case 'a': strings.write_byte(&b, '\a')
        case 'b': strings.write_byte(&b, '\b')
        case 'f': strings.write_byte(&b, '\f')
        case 'v': strings.write_byte(&b, '\v')
        case '0': strings.write_byte(&b, 0)
        case '\\', '\'', '"': strings.write_byte(&b, e)
        case '\n':
        case 'x', 'u', 'U':
            width := 2 if e == 'x' else (4 if e == 'u' else 8)
            code, ok := strconv.parse_u64_of_base(s[i:min(i + width, len(s))], 16)
            if ok && i + width <= len(s) {
                strings.write_rune(&b, rune(code))
                i += width
            } else {
                strings.write_byte(&b, '\\')
                strings.write_byte(&b, e)
            }
        case:
            strings.write_byte(&b, '\\')
            strings.write_byte(&b, e)
        }
    }
    return strings.to_string(b)
}

@(private="file")
lex_number :: proc(lx: ^Lexer) {
    rest := lx.src[lx.pos:]
    after_dot := len(lx.tokens) > 0 && lx.tokens[len(lx.tokens) - 1].text == "." &&
        lx.tokens[len(lx.tokens) - 1].kind == .Operator
    if len(rest) > 1 && rest[0] == '0' && strings.index_byte("xXoObB", rest[1]) >= 0 {
        base := 16
        switch rest[1] {
        case 'o', 'O': base = 8
        case 'b', 'B': base = 2
        }
        n := 2
        for n < len(rest) && (rest[n] == '_' || digit_value(rest[n]) < base) do n += 1
        v, ok := parse_digits(strip_underscores(rest[2:n]), base)
        if !ok { lex_error(lx, "integer literal out of range"); return }
        append(&lx.tokens, Token{kind = .Integer, number = v, line = lx.line, text = rest[:n]})
        advance(lx, n)
        return
    }
    n := scan_digits(rest, 0)
    is_float := false
    if !after_dot && n + 1 < len(rest) && rest[n] == '.' && is_digit(rest[n + 1]) {
        n = scan_digits(rest, n + 1)
        is_float = true
    }
    if !after_dot && n < len(rest) && (rest[n] == 'e' || rest[n] == 'E') {
        m := n + 1
        if m < len(rest) && (rest[m] == '+' || rest[m] == '-') do m += 1
        if m < len(rest) && is_digit(rest[m]) {
            n = scan_digits(rest, m)
            is_float = true
        }
    }
    text := strip_underscores(rest[:n])
    if is_float {
        f, _ := strconv.parse_f64(text)
        append(&lx.tokens, Token{kind = .Float, float = f, line = lx.line, text = rest[:n]})
    } else {
        v, ok := parse_digits(text, 10)
        if !ok { lex_error(lx, "integer literal out of range"); return }
        append(&lx.tokens, Token{kind = .Integer, number = v, line = lx.line, text = rest[:n]})
    }
    advance(lx, n)
}

@(private="file")
scan_digits :: proc(s: string, from: int) -> int {
    n := from
    for n < len(s) && (is_digit(s[n]) || (s[n] == '_' && n + 1 < len(s) && is_digit(s[n + 1]))) {
        n += 1
    }
    return n
}

is_digit :: proc(c: u8) -> bool { return '0' <= c && c <= '9' }

digit_value :: proc(c: u8) -> int {
    switch c {
    case '0' ..= '9': return int(c - '0')
    case 'a' ..= 'z': return int(c - 'a') + 10
    case 'A' ..= 'Z': return int(c - 'A') + 10
    }
    return 99
}

strip_underscores :: proc(s: string) -> string {
    if strings.index_byte(s, '_') < 0 do return s
    out, _ := strings.remove_all(s, "_")
    return out
}

// parse_digits parses unsigned digits in base with overflow detection (strconv wraps).
parse_digits :: proc(text: string, base: int) -> (i64, bool) {
    if len(text) == 0 do return 0, false
    v: i64 = 0
    for c in transmute([]u8)text {
        d := digit_value(c)
        if d >= base do return 0, false
        o1, o2: bool
        v, o1 = intrinsics.overflow_mul(v, i64(base))
        v, o2 = intrinsics.overflow_add(v, i64(d))
        if o1 || o2 do return 0, false
    }
    return v, true
}
