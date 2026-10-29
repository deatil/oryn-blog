#+private
package jinja

import "core:strings"

// subparse parses template content until one of end_tags opens a block tag. It returns
// with the tag name as the current token; the caller consumes it.
subparse :: proc(p: ^Parser, end_tags: []string) -> []^Node {
    body := make([dynamic]^Node)
    ends := len(p.end_stack)
    if end_tags != nil do append(&p.end_stack, end_tags)
    defer resize(&p.end_stack, ends) // what the append added, if it could.

    for !failed(p) {
        t := peek(p)
        #partial switch t.kind {
        case .EOF:
            if end_tags != nil do fail_eof(p, "", t.line)
            return body[:]
        case .Data:
            next_token(p)
            n := make_node(p, .Data, t.line)
            n.text = t.text
            append(&body, n)
        case .Variable_Begin:
            next_token(p)
            n := make_node(p, .Output, t.line)
            n.a = parse_tuple(p)
            expect(p, .Variable_End, "")
            append(&body, n)
        case .Block_Begin:
            next_token(p)
            name := peek(p)
            if name.kind == .Name {
                for tag in end_tags do if tag == name.text do return body[:]
            }
            if n := parse_statement(p); n != nil do append(&body, n)
        case:
            fail_unexpected(p)
        }
    }
    return body[:]
}

// fail_eof reports an unknown tag or an unexpected end, naming the tags Jinja expected.
fail_eof :: proc(p: ^Parser, name: string, line: int) {
    b := strings.builder_make()
    if name == "" {
        strings.write_string(&b, "Unexpected end of template.")
    } else {
        strings.write_string(&b, "Encountered unknown tag ")
        write_string_repr(&b, name)
        strings.write_string(&b, ".")
    }
    if len(p.end_stack) > 0 {
        expected := false
        for tags in p.end_stack do for tag in tags do if tag == name do expected = true
        looking := strings.builder_make()
        for tag, i in p.end_stack[len(p.end_stack) - 1] {
            if i > 0 do strings.write_string(&looking, " or ")
            write_string_repr(&looking, tag)
        }
        if name != "" && expected {
            strings.write_string(&b, " You probably made a nesting mistake. Jinja is expecting ")
            strings.write_string(&b, "this tag, but currently looking for ")
        } else {
            strings.write_string(&b, " Jinja was looking for the following tags: ")
        }
        strings.write_string(&b, strings.to_string(looking))
        strings.write_string(&b, ".")
    }
    if len(p.tag_stack) > 0 {
        strings.write_string(&b, " The innermost block that needs to be closed is ")
        write_string_repr(&b, p.tag_stack[len(p.tag_stack) - 1])
        strings.write_string(&b, ".")
    }
    parse_fail(p, line, "%s", strings.to_string(b))
}

parse_statement :: proc(p: ^Parser) -> ^Node {
    t := peek(p)
    if t.kind != .Name {
        parse_fail(p, t.line, "tag name expected")
        return nil
    }
    tags := len(p.tag_stack)
    append(&p.tag_stack, t.text)
    defer resize(&p.tag_stack, tags)
    nest(p)
    defer p.depth -= 1
    switch t.text {
    case "if": return parse_if(p)
    case "for": return parse_for(p)
    case "set": return parse_set(p)
    case "macro": return parse_macro(p)
    case "call": return parse_call_block(p)
    case "filter": return parse_filter_block(p)
    case "with": return parse_with(p)
    case "block": return parse_block(p)
    case "extends", "do", "autoescape": return parse_simple(p)
    case "include": return parse_include(p)
    case "import": return parse_import(p)
    case "from": return parse_from(p)
    case "break", "continue":
        next_token(p)
        if p.loop_depth == 0 {
            parse_fail(p, t.line, "%s outside of a loop", repr(t.text))
            return nil
        }
        expect(p, .Block_End, "")
        return make_node(p, .Break if t.text == "break" else .Continue, t.line)
    case "trans": return parse_trans(p)
    }
    resize(&p.tag_stack, tags)
    fail_eof(p, t.text, t.line)
    known := []string{"if", "elif", "else", "endif", "for", "endfor", "set", "endset", "macro",
        "endmacro", "call", "endcall", "filter", "endfilter", "with", "endwith", "block",
        "endblock", "extends", "include", "import", "from", "autoescape", "endautoescape",
        "do", "break", "continue", "trans", "pluralize", "endtrans", "raw", "endraw"}
    if near := closest(t.text, known); near != "" && p.err.hint == "" {
        p.err.hint = strings.concatenate({"Did you mean {% ", near, " %}?"})
    }
    return nil
}

// end_tag consumes the closing tag name (already current) and the block end.
end_tag :: proc(p: ^Parser) {
    next_token(p)
    expect(p, .Block_End, "")
}

parse_if :: proc(p: ^Parser) -> ^Node {
    line := next_token(p).line
    result := make_node(p, .If, line)
    node := result
    levels := 0 // each elif nests the next branch one level deeper
    defer p.depth -= levels
    for !failed(p) {
        node.a = parse_tuple(p, with_condexpr = false)
        expect(p, .Block_End, "")
        node.body = subparse(p, {"elif", "else", "endif"})
        t := next_token(p)
        if t.text == "elif" {
            levels += 1
            nest(p)
            inner := make_node(p, .If, t.line)
            branch, err := make([]^Node, 1)
            if err != nil do break
            branch[0] = inner
            node.else_body = branch
            node = inner
            continue
        }
        if t.text == "else" {
            expect(p, .Block_End, "")
            node.else_body = subparse(p, {"endif"})
            next_token(p)
        }
        expect(p, .Block_End, "")
        break
    }
    return result
}

parse_for :: proc(p: ^Parser) -> ^Node {
    n := make_node(p, .For, next_token(p).line)
    n.a = parse_assign_target(p, extra_end = {"in"})
    expect(p, .Name, "in")
    n.b = parse_tuple(p, with_condexpr = false, extra_end = {"recursive"})
    if at_name(p, "if") {
        next_token(p)
        n.c = parse_expr(p)
    }
    if at_name(p, "recursive") {
        next_token(p)
        n.flags += {.Recursive}
    }
    expect(p, .Block_End, "")
    p.loop_depth += 1
    n.body = subparse(p, {"endfor", "else"})
    p.loop_depth -= 1
    if next_token(p).text == "else" {
        expect(p, .Block_End, "")
        n.else_body = subparse(p, {"endfor"})
        next_token(p)
    }
    expect(p, .Block_End, "")
    return n
}

// parse_assign_target parses a name, a tuple of names, or (with_namespace) ns.attr.
parse_assign_target :: proc(p: ^Parser, extra_end: []string = nil, name_only := false,
    with_namespace := false) -> ^Node {
    t := peek(p)
    target: ^Node
    if with_namespace && t.kind == .Name && at(p, ".", 1) && peek(p, 2).kind == .Name {
        next_token(p)
        next_token(p)
        target = make_node(p, .Ns_Ref, t.line)
        target.a = make_node(p, .Name, t.line)
        target.a.text = t.text
        target.text = next_token(p).text
        return target
    }
    if name_only {
        name := expect(p, .Name, "")
        target = make_node(p, .Name, name.line)
        target.text = name.text
    } else {
        target = parse_tuple(p, simplified = true, extra_end = extra_end)
    }
    if !failed(p) && !can_assign(target) {
        parse_fail(p, target.line, "can't assign to %s", repr(node_kind_name(target)))
    }
    return target
}

can_assign :: proc(n: ^Node) -> bool {
    #partial switch n.kind {
    case .Name:
        switch n.text {
        case "true", "false", "none", "True", "False", "None": return false
        }
        return true
    case .Tuple, .List:
        for item in n.args do if !can_assign(item) do return false
        return true
    case .Ns_Ref: return true
    }
    return false
}

node_kind_name :: proc(n: ^Node) -> string {
    #partial switch n.kind {
    case .Const: return "Const"
    case .Call: return "Call"
    case .Getattr: return "Getattr"
    case .Getitem: return "Getitem"
    case .Binary, .Unary: return "BinExpr"
    }
    return "expression"
}

parse_set :: proc(p: ^Parser) -> ^Node {
    line := next_token(p).line
    target := parse_assign_target(p, with_namespace = true)
    if at(p, "=") && peek(p).kind == .Operator {
        next_token(p)
        n := make_node(p, .Set, line)
        n.a = target
        n.b = parse_tuple(p)
        expect(p, .Block_End, "")
        return n
    }
    n := make_node(p, .Set_Block, line)
    n.a = target
    if at(p, "|") do n.c = parse_filter(p, nil)
    expect(p, .Block_End, "")
    n.body = subparse(p, {"endset"})
    end_tag(p)
    return n
}

// parse_signature parses "(a, b=1)" into names and default values.
parse_signature :: proc(p: ^Parser, n: ^Node) {
    names := make([dynamic]string)
    values := make([dynamic]^Node)
    expect(p, .Operator, "(")
    for !at(p, ")") && !failed(p) {
        if len(names) > 0 do expect(p, .Operator, ",")
        if at(p, ")") do break
        arg := parse_assign_target(p, name_only = true)
        default: ^Node
        if at(p, "=") && peek(p).kind == .Operator {
            next_token(p)
            default = parse_expr(p)
        } else if len(values) > 0 && values[len(values) - 1] != nil {
            parse_fail(p, arg.line, "non-default argument follows default argument")
        }
        append(&names, arg.text)
        append(&values, default)
    }
    expect(p, .Operator, ")")
    n.names = names[:]
    n.values = values[:]
}

// mark_uses records whether a macro body reads caller, varargs or kwargs.
mark_uses :: proc(p: ^Parser, n: ^Node) {
    if failed(p) do return // the tree may hold the sink (make_node).

    visit :: proc(x: ^Node, user: rawptr) {
        owner := (^Node)(user)
        if x.kind != .Name do return
        switch x.text {
        case "caller": owner.flags += {.Uses_Caller}
        case "varargs": owner.flags += {.Uses_Varargs}
        case "kwargs": owner.flags += {.Uses_Kwargs}
        }
    }
    for s in n.body do walk_node(s, visit, n, skip_scopes = true)
    for name in n.names {
        switch name {
        case "caller": n.flags += {.Uses_Caller}
        case "varargs": n.flags += {.Uses_Varargs}
        case "kwargs": n.flags += {.Uses_Kwargs}
        }
    }
}

parse_macro :: proc(p: ^Parser) -> ^Node {
    n := make_node(p, .Macro, next_token(p).line)
    n.text = expect(p, .Name, "").text
    parse_signature(p, n)
    expect(p, .Block_End, "")
    depth := p.loop_depth
    p.loop_depth = 0
    n.body = subparse(p, {"endmacro"})
    p.loop_depth = depth
    end_tag(p)
    mark_uses(p, n)
    return n
}

parse_call_block :: proc(p: ^Parser) -> ^Node {
    n := make_node(p, .Call_Block, next_token(p).line)
    if at(p, "(") && peek(p).kind == .Operator do parse_signature(p, n)
    n.a = parse_expr(p)
    if !failed(p) && n.a.kind != .Call do parse_fail(p, n.line, "expected call")
    expect(p, .Block_End, "")
    depth := p.loop_depth
    p.loop_depth = 0
    n.body = subparse(p, {"endcall"})
    p.loop_depth = depth
    end_tag(p)
    mark_uses(p, n)
    return n
}

parse_filter_block :: proc(p: ^Parser) -> ^Node {
    n := make_node(p, .Filter_Block, next_token(p).line)
    n.a = parse_filter(p, nil, start_inline = true)
    expect(p, .Block_End, "")
    n.body = subparse(p, {"endfilter"})
    end_tag(p)
    return n
}

parse_with :: proc(p: ^Parser) -> ^Node {
    n := make_node(p, .With, next_token(p).line)
    targets := make([dynamic]^Node)
    values := make([dynamic]^Node)
    for peek(p).kind != .Block_End && !failed(p) {
        if len(targets) > 0 do expect(p, .Operator, ",")
        append(&targets, parse_assign_target(p))
        expect(p, .Operator, "=")
        append(&values, parse_expr(p))
    }
    expect(p, .Block_End, "")
    n.args = targets[:]
    n.values = values[:]
    n.body = subparse(p, {"endwith"})
    end_tag(p)
    return n
}

parse_block :: proc(p: ^Parser) -> ^Node {
    n := make_node(p, .Block, next_token(p).line)
    n.text = expect(p, .Name, "").text
    if at_name(p, "scoped") { next_token(p); n.flags += {.Scoped} }
    if at_name(p, "required") { next_token(p); n.flags += {.Required} }
    if failed(p) do return nil
    if n.text in p.blocks {
        parse_fail(p, n.line, "block %s defined twice", repr(n.text))
        return nil
    }
    expect(p, .Block_End, "")
    depth := p.loop_depth
    p.loop_depth = 0
    n.body = subparse(p, {"endblock"})
    p.loop_depth = depth
    next_token(p)
    if at(p, n.text) && peek(p).kind == .Name {
        next_token(p)
    } else if peek(p).kind == .Name {
        t := peek(p)
        parse_fail(p, t.line, "mismatching name of block. Expected %s, got %s",
            repr(n.text), repr(t.text))
    }
    expect(p, .Block_End, "")
    if .Required in n.flags {
        for s in n.body {
            if s.kind != .Data || len(strings.trim_space(s.text)) > 0 {
                parse_fail(p, s.line, "Required blocks can only contain comments or whitespace")
            }
        }
    }
    p.blocks[n.text] = n
    return n
}

// parse_simple parses extends, do and autoescape, which take one expression.
parse_simple :: proc(p: ^Parser) -> ^Node {
    t := next_token(p)
    kind: Node_Kind = .Extends
    if t.text == "do" do kind = .Do
    if t.text == "autoescape" do kind = .Autoescape
    n := make_node(p, kind, t.line)
    n.a = parse_tuple(p) if kind == .Do else parse_expr(p)
    expect(p, .Block_End, "")
    if kind == .Autoescape {
        n.body = subparse(p, {"endautoescape"})
        end_tag(p)
    }
    return n
}

// parse_context reads "with context" or "without context".
parse_context :: proc(p: ^Parser, n: ^Node) -> bool {
    if (at_name(p, "with") || at_name(p, "without")) && at_name(p, "context", 1) {
        if next_token(p).text == "with" {
            n.flags += {.With_Context}
        } else {
            n.flags -= {.With_Context}
        }
        next_token(p)
        return true
    }
    return false
}

parse_include :: proc(p: ^Parser) -> ^Node {
    n := make_node(p, .Include, next_token(p).line)
    n.a = parse_expr(p)
    n.flags += {.With_Context}
    if at_name(p, "ignore") && at_name(p, "missing", 1) {
        next_token(p)
        next_token(p)
        n.flags += {.Ignore_Missing}
    }
    parse_context(p, n)
    expect(p, .Block_End, "")
    return n
}

parse_import :: proc(p: ^Parser) -> ^Node {
    n := make_node(p, .Import, next_token(p).line)
    n.a = parse_expr(p)
    expect(p, .Name, "as")
    n.text = parse_assign_target(p, name_only = true).text
    parse_context(p, n)
    expect(p, .Block_End, "")
    return n
}

parse_from :: proc(p: ^Parser) -> ^Node {
    n := make_node(p, .From_Import, next_token(p).line)
    n.a = parse_expr(p)
    expect(p, .Name, "import")
    names := make([dynamic]string)
    aliases := make([dynamic]string)
    for !failed(p) {
        if len(names) > 0 do expect(p, .Operator, ",")
        if peek(p).kind != .Name {
            expect(p, .Name, "")
            break
        }
        if parse_context(p, n) do break
        target := parse_assign_target(p, name_only = true)
        if strings.has_prefix(target.text, "_") {
            parse_fail(p, target.line, "names starting with an underline can not be imported")
        }
        alias := target.text
        if at_name(p, "as") {
            next_token(p)
            alias = parse_assign_target(p, name_only = true).text
        }
        append(&names, target.text)
        append(&aliases, alias)
        if parse_context(p, n) || !at(p, ",") do break
    }
    expect(p, .Block_End, "")
    n.names = names[:]
    n.aliases = aliases[:]
    return n
}
