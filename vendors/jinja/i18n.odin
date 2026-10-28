#+private
package jinja

import "core:strings"

// The i18n extension's {% trans %} tag. Translation is a pass-through unless the host
// registers gettext / ngettext globals of its own.

parse_trans :: proc(p: ^Parser) -> ^Node {
    n := make_node(p, .Trans, next_token(p).line)
    names := make([dynamic]string)
    values := make([dynamic]^Node)
    trimmed_set := false
    for peek(p).kind != .Block_End && !failed(p) {
        if len(names) > 0 do expect(p, .Operator, ",")
        if skip_if(p, ":") do break
        t := expect(p, .Name, "")
        if failed(p) do break
        for name in names {
            if name == t.text do parse_fail(p, t.line, "translatable variable %s defined twice.",
                repr(t.text))
        }
        value: ^Node
        if at(p, "=") && peek(p).kind == .Operator {
            next_token(p)
            value = parse_expr(p)
        } else if !trimmed_set && (t.text == "trimmed" || t.text == "notrimmed") {
            trimmed_set = true
            if t.text == "trimmed" do n.flags += {.Trimmed}
            continue
        } else {
            value = make_node(p, .Name, t.line)
            value.text = t.text
        }
        append(&names, t.text)
        append(&values, value)
        if n.a == nil do n.a = value
    }
    expect(p, .Block_End, "")
    singular, referenced := trans_block(p, true)
    if n.a == nil && len(referenced) > 0 {
        n.a = make_node(p, .Name, n.line)
        n.a.text = referenced[0]
    }
    if at_name(p, "pluralize") {
        n.flags += {.Has_Plural}
        next_token(p)
        if peek(p).kind != .Block_End {
            t := expect(p, .Name, "")
            found := false
            for name, i in names {
                if name == t.text && i < len(values) { n.a = values[i]; found = true }
            }
            if !found do parse_fail(p, t.line, "unknown variable %s for pluralization",
                repr(t.text))
        }
        expect(p, .Block_End, "")
        plural, more := trans_block(p, false)
        n.plural = plural
        append(&referenced, ..more[:])
    }
    next_token(p)
    expect(p, .Block_End, "")
    for name in referenced {
        known := false
        for have in names do if have == name do known = true
        if known do continue
        append(&names, name)
        v := make_node(p, .Name, n.line)
        v.text = name
        append(&values, v)
    }
    if .Has_Plural in n.flags && n.a == nil do parse_fail(p, n.line, "pluralize without variables")
    if len(referenced) > 0 do n.flags += {.Has_Vars}
    if .Trimmed in n.flags {
        singular = trim_trans(singular)
        n.plural = trim_trans(n.plural)
    }
    if .Has_Vars not_in n.flags {
        singular, _ = strings.replace_all(singular, "%%", "%")
        n.plural, _ = strings.replace_all(n.plural, "%%", "%")
    }
    n.text = singular
    n.names = names[:]
    n.values = values[:]
    return n
}

// trans_block collects the text of a trans section with %(name)s placeholders.
@(private="file")
trans_block :: proc(p: ^Parser, allow_plural: bool) -> (string, [dynamic]string) {
    b := strings.builder_make()
    referenced := make([dynamic]string)
    for !failed(p) {
        t := peek(p)
        #partial switch t.kind {
        case .Data:
            next_token(p)
            text, _ := strings.replace_all(t.text, "%", "%%")
            strings.write_string(&b, text)
        case .Variable_Begin:
            next_token(p)
            name := expect(p, .Name, "").text
            append(&referenced, name)
            strings.write_string(&b, "%(")
            strings.write_string(&b, name)
            strings.write_string(&b, ")s")
            expect(p, .Variable_End, "")
        case .Block_Begin:
            next_token(p)
            if at_name(p, "endtrans") do return strings.to_string(b), referenced
            if at_name(p, "pluralize") {
                if allow_plural do return strings.to_string(b), referenced
                parse_fail(p, t.line, "a translatable section can have only one pluralize " +
                    "section")
            } else {
                parse_fail(p, t.line, "control structures in translatable sections are not " +
                    "allowed")
            }
        case .EOF:
            parse_fail(p, t.line, "unclosed translation block")
        case:
            fail_unexpected(p)
        }
    }
    return strings.to_string(b), referenced
}

@(private="file")
trim_trans :: proc(s: string) -> string {
    words := strings.builder_make()
    text := strings.trim_space(s)
    i := 0
    for i < len(text) {
        if is_space(rune(text[i])) {
            j := i
            for j < len(text) && is_space(rune(text[j])) do j += 1
            if strings.contains_rune(text[i:j], '\n') {
                strings.write_byte(&words, ' ')
            } else {
                strings.write_string(&words, text[i:j])
            }
            i = j
            continue
        }
        strings.write_byte(&words, text[i])
        i += 1
    }
    return strings.to_string(words)
}

exec_trans :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    vars := new_dict(.Dict)
    if vars == nil do return .Error
    for name, i in n.names {
        v := eval(s, scope, n.values[i])
        if s.failed do return .Error
        dict_set(vars, name, v)
    }
    message: Value
    if .Has_Plural in n.flags {
        count := eval(s, scope, n.a)
        if s.failed do return .Error
        fn := lookup(s, scope, "ngettext")
        message = call_value(s, fn, {n.text, n.plural, count}, nil)
    } else {
        fn := lookup(s, scope, "gettext")
        message = call_value(s, fn, {n.text}, nil)
    }
    if s.failed do return .Error
    text := to_string(message)
    result: Value = Markup(text) if s.autoescape else Value(text)
    if len(n.names) > 0 {
        result = percent_format(s, result, text, vars)
        if s.failed do return .Error
    }
    write_output(s, result)
    return .Normal
}
