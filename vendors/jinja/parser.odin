#+private
package jinja

import "core:fmt"
import "core:strings"

Parser :: struct {
    tokens:     []Token,
    pos:        int,
    name:       string,
    err:        Error,
    blocks:     map[string]^Node,
    tag_stack:  [dynamic]string,
    end_stack:  [dynamic][]string,
    loop_depth: int,
    depth:      int, // nesting of the node being built; see stack.odin
    max_depth:  int,
    stack:      Stack_Guard,
    guard:      ^Guard, // the parse's allocator: a refusal fails the parse (failed).
    sink:       Node,   // see make_node.
}

// parse turns template source into a Compiled template (allocated with context.allocator,
// which guard watches: a refused request is a Memory error).
parse :: proc(env: ^Environment, source, name: string, guard: ^Guard) -> (^Compiled, Error) {
    tokens, lex_err := tokenize(source, name, lex_options(env))
    if guard.refused > 0 || len(tokens) == 0 && lex_err.kind == .None {
        err := parse_memory_error(guard, 1)
        err.template = name
        return nil, err
    }
    if lex_err.kind != .None {
        lex_err.excerpt = source_line(source, lex_err.line)
        return nil, lex_err
    }
    p := new_parser(env, tokens, name, guard)
    body := subparse(&p, nil)
    if failed(&p) {
        p.err.template = name
        p.err.excerpt = source_line(source, p.err.line)
        return nil, p.err
    }
    t := new(Compiled)
    if t == nil do return nil, Error{kind = .Memory, template = name, line = 1,
        message = guard.message, hint = MEMORY_HINT_PARSE}
    t^ = Compiled{name = name, source = source, body = body, blocks = p.blocks}
    return t, {}
}

// parse_expression_source parses a single expression (compile_expression in Jinja).
parse_expression_source :: proc(env: ^Environment, source, name: string, guard: ^Guard) ->
    (^Node, Error) {
    tokens, lex_err := tokenize(strings.concatenate({"{{ ", source, " }}"}), name, {})
    if guard.refused > 0 || len(tokens) == 0 && lex_err.kind == .None {
        err := parse_memory_error(guard, 1)
        err.template = name
        return nil, err
    }
    if lex_err.kind != .None do return nil, lex_err
    p := new_parser(env, tokens, name, guard)
    expect(&p, .Variable_Begin, "")
    n := parse_tuple(&p)
    expect(&p, .Variable_End, "")
    if peek(&p).kind != .EOF do fail_unexpected(&p)
    if failed(&p) {
        p.err.template = name
        return nil, p.err
    }
    return n, {}
}

// ---------------------------------------------------------------------------------------
// Token stream

// peek is the current token, or the one ahead of it. It and next_token point into the
// token stream rather than copy a token, since the parser's recursive procedures call
// them and an unoptimized build makes room for every copy in the caller's frame.
peek :: proc(p: ^Parser, ahead := 0) -> ^Token {
    return &p.tokens[min(p.pos + ahead, len(p.tokens) - 1)]
}

// next_token consumes the current token and returns it.
next_token :: proc(p: ^Parser) -> ^Token {
    t := &p.tokens[p.pos]
    if p.pos < len(p.tokens) - 1 do p.pos += 1
    return t
}

// at reports whether the current token is the operator or name text.
at :: proc(p: ^Parser, text: string, ahead := 0) -> bool {
    t := peek(p, ahead)
    return (t.kind == .Operator || t.kind == .Name) && t.text == text
}

at_name :: proc(p: ^Parser, text: string, ahead := 0) -> bool {
    t := peek(p, ahead)
    return t.kind == .Name && t.text == text
}

skip_if :: proc(p: ^Parser, text: string) -> bool {
    if at(p, text) {
        next_token(p)
        return true
    }
    return false
}

parse_fail :: proc(p: ^Parser, line: int, format: string, args: ..any) {
    if failed(p) do return
    message := fmt.aprintf(format, ..args)
    if failed(p) do return // the message itself ran out of memory.
    p.err = Error{kind = .Syntax, line = line, message = message}
    p.pos = len(p.tokens) - 1
}

// failed reports whether the parse has failed: with an error, or with memory its guard
// refused, which becomes its Memory error here.
failed :: proc(p: ^Parser) -> bool {
    if p.err.kind != .None do return true
    if p.guard == nil || p.guard.refused == 0 do return false
    p.err = parse_memory_error(p.guard, peek(p).line)
    p.pos = len(p.tokens) - 1
    return true
}

new_parser :: proc(env: ^Environment, tokens: []Token, name: string, guard: ^Guard) -> Parser {
    return Parser{tokens = tokens, name = name, max_depth = env.options.max_nesting,
        stack = env.stack, guard = guard}
}

// nest enters one more level of nesting: a nested expression or tag, or one more link
// of an operator, filter, attribute or elif chain, each of which deepens the tree the
// parser builds. Past max_nesting or the stack budget it reports a Limit error and
// stops the parse; the caller undoes its levels (p.depth -= n) either way.
nest :: proc(p: ^Parser) {
    p.depth += 1
    if failed(p) || p.depth <= p.max_depth && !stack_exhausted(p.stack) do return
    line := peek(p).line
    if p.depth > p.max_depth {
        parse_fail(p, line, "the template nests more than %d levels deep", p.max_depth)
        p.err.hint = "Split the nested expression or tags, or raise Options.max_nesting."
    } else {
        parse_fail(p, line, "the template nests too deeply for the stack budget of %d bytes",
            p.stack.limit)
        p.err.hint = "Split the nested expression or tags, or raise Options.stack_bytes."
    }
    p.err.kind = .Limit
}

describe_token :: proc(t: Token) -> string {
    switch t.kind {
    case .EOF: return "end of template"
    case .Data: return "template data / text"
    case .Variable_Begin: return "begin of print statement"
    case .Variable_End: return "end of print statement"
    case .Block_Begin: return "begin of statement block"
    case .Block_End: return "end of statement block"
    case .Name, .Operator: return t.text
    case .String: return "string"
    case .Integer: return "integer"
    case .Float: return "float"
    }
    return "token"
}

describe_kind :: proc(kind: Token_Kind) -> string {
    if kind == .Name do return "name"
    return describe_token(Token{kind = kind})
}

fail_unexpected :: proc(p: ^Parser) {
    t := peek(p)
    if t.kind == .EOF {
        fail_eof(p, "", t.line)
        return
    }
    parse_fail(p, t.line, "unexpected %s", repr(describe_token(t^)))
}

// expect consumes a token of the given kind (and text, when text is not empty).
expect :: proc(p: ^Parser, kind: Token_Kind, text: string) -> ^Token {
    t := peek(p)
    if t.kind == kind && (text == "" || t.text == text) do return next_token(p)
    if t.kind == .EOF {
        want := text if text != "" else describe_kind(kind)
        parse_fail(p, t.line, "unexpected end of template, expected %s.", repr(want))
        return t
    }
    want := text if text != "" else describe_kind(kind)
    parse_fail(p, t.line, "expected token %s, got %s", repr(want), repr(describe_token(t^)))
    return t
}

// new_node makes a node, or returns nil when memory is refused.
new_node :: proc(kind: Node_Kind, line: int) -> ^Node {
    n := new(Node)
    if n == nil do return nil
    n.kind = kind
    n.line = line
    return n
}

// make_node makes a node for the parser. When memory is refused it returns the parser's
// sink, emptied, so the code building the tree can go on writing to it until it checks
// failed(p), which reports the refusal; a tree with the sink in it is never returned.
make_node :: proc(p: ^Parser, kind: Node_Kind, line: int) -> ^Node {
    if n := new_node(kind, line); n != nil do return n
    p.sink = Node{kind = kind, line = line}
    return &p.sink
}

// ---------------------------------------------------------------------------------------
// Expressions, in Jinja's precedence order

// parse_tuple parses an expression, or a tuple when commas follow. It is on the stack
// once per bracket, so the tuple's items are gathered out of line, after the first.
parse_tuple :: proc(p: ^Parser, simplified := false, with_condexpr := true,
    extra_end: []string = nil, explicit_parens := false) -> ^Node {
    line := peek(p).line
    first: ^Node
    if !failed(p) && !tuple_end(p, extra_end) {
        first = parse_tuple_item(p, simplified, with_condexpr)
        if !at_comma(p) do return first
    }
    return parse_tuple_rest(p, line, first, simplified, with_condexpr, extra_end,
        explicit_parens)
}

parse_tuple_item :: proc(p: ^Parser, simplified, with_condexpr: bool) -> ^Node {
    if simplified do return parse_primary(p)
    return parse_expr(p, with_condexpr)
}

at_comma :: proc(p: ^Parser) -> bool {
    t := peek(p)
    return t.kind == .Operator && t.text == ","
}

// parse_tuple_rest parses the items of a tuple after first, which a comma follows, or an
// empty tuple when first is nil.
parse_tuple_rest :: #force_no_inline proc(p: ^Parser, line: int, first: ^Node,
    simplified, with_condexpr: bool, extra_end: []string, explicit_parens: bool) -> ^Node {
    items := make([dynamic]^Node)
    if first != nil do append(&items, first)
    for first != nil && at_comma(p) && !failed(p) {
        expect(p, .Operator, ",")
        if tuple_end(p, extra_end) do break
        append(&items, parse_tuple_item(p, simplified, with_condexpr))
    }
    if first == nil && !explicit_parens {
        t := peek(p)
        parse_fail(p, t.line, "Expected an expression, got %s", repr(describe_token(t^)))
    }
    n := make_node(p, .Tuple, line)
    n.args = items[:]
    return n
}

tuple_end :: proc(p: ^Parser, extra_end: []string) -> bool {
    t := peek(p)
    if t.kind == .Variable_End || t.kind == .Block_End || t.kind == .EOF do return true
    if t.kind == .Operator && t.text == ")" do return true
    for name in extra_end do if at_name(p, name) do return true
    return false
}

parse_expr :: proc(p: ^Parser, with_condexpr := true) -> ^Node {
    if with_condexpr do return parse_condexpr(p)
    return parse_or(p)
}

parse_condexpr :: proc(p: ^Parser) -> ^Node {
    line := peek(p).line
    expr1 := parse_or(p)
    levels := 0
    defer p.depth -= levels
    for at_name(p, "if") && !failed(p) {
        next_token(p)
        levels += 1
        nest(p)
        n := make_node(p, .Cond, line)
        n.b = expr1
        n.a = parse_or(p)
        if at_name(p, "else") {
            next_token(p)
            n.c = parse_condexpr(p)
        }
        expr1 = n
    }
    return expr1
}

binary :: proc(p: ^Parser, op: string, line: int, left, right: ^Node) -> ^Node {
    n := make_node(p, .Binary, line)
    n.text = op
    n.a = left
    n.b = right
    return n
}

parse_or :: proc(p: ^Parser) -> ^Node {
    levels := 1
    defer p.depth -= levels
    nest(p)
    left := parse_and(p)
    for at_name(p, "or") && !failed(p) {
        levels += 1
        nest(p)
        line := next_token(p).line
        left = binary(p, "or", line, left, parse_and(p))
    }
    return left
}

parse_and :: proc(p: ^Parser) -> ^Node {
    left := parse_not(p)
    levels := 0
    defer p.depth -= levels
    for at_name(p, "and") && !failed(p) {
        levels += 1
        nest(p)
        line := next_token(p).line
        left = binary(p, "and", line, left, parse_not(p))
    }
    return left
}

parse_not :: proc(p: ^Parser) -> ^Node {
    if at_name(p, "not") {
        line := next_token(p).line
        n := make_node(p, .Unary, line)
        n.text = "not"
        nest(p)
        defer p.depth -= 1
        n.a = parse_not(p)
        return n
    }
    return parse_compare(p)
}

// parse_compare parses a comparison chain. It is on the stack once per bracket, so the
// chain is gathered out of line, after the first operand.
parse_compare :: proc(p: ^Parser) -> ^Node {
    line := peek(p).line
    first := parse_math1(p)
    if failed(p) || compare_operator(p) == "" do return first
    return parse_compare_chain(p, line, first)
}

// compare_operator is the comparison operator at the current token ("notin" for not in),
// or "" when there is none.
compare_operator :: proc(p: ^Parser) -> string {
    t := peek(p)
    if t.kind == .Operator {
        switch t.text {
        case "==", "!=", "<", "<=", ">", ">=": return t.text
        }
    }
    if at_name(p, "in") do return "in"
    if at_name(p, "not") && at_name(p, "in", 1) do return "notin"
    return ""
}

parse_compare_chain :: #force_no_inline proc(p: ^Parser, line: int, first: ^Node) -> ^Node {
    ops := make([dynamic]string)
    operands := make([dynamic]^Node)
    for !failed(p) {
        op := compare_operator(p)
        if op == "" do break
        next_token(p)
        if op == "notin" do next_token(p)
        append(&ops, op)
        append(&operands, parse_math1(p))
    }
    n := make_node(p, .Compare, line)
    n.a = first
    n.names = ops[:]
    n.args = operands[:]
    return n
}
parse_math1 :: proc(p: ^Parser) -> ^Node {
    left := parse_concat(p)
    levels := 0
    defer p.depth -= levels
    for (at(p, "+") || at(p, "-")) && peek(p).kind == .Operator && !failed(p) {
        levels += 1
        nest(p)
        t := next_token(p)
        left = binary(p, t.text, t.line, left, parse_concat(p))
    }
    return left
}

parse_concat :: proc(p: ^Parser) -> ^Node {
    line := peek(p).line
    first := parse_math2(p)
    if !at(p, "~") do return first
    items := make([dynamic]^Node)
    append(&items, first)
    for at(p, "~") && !failed(p) {
        next_token(p)
        append(&items, parse_math2(p))
    }
    n := make_node(p, .Concat, line)
    n.args = items[:]
    return n
}

parse_math2 :: proc(p: ^Parser) -> ^Node {
    left := parse_pow(p)
    levels := 0
    defer p.depth -= levels
    for !failed(p) {
        t := peek(p)
        if t.kind != .Operator do break
        if t.text != "*" && t.text != "/" && t.text != "//" && t.text != "%" do break
        next_token(p)
        levels += 1
        nest(p)
        left = binary(p, t.text, t.line, left, parse_pow(p))
    }
    return left
}

parse_pow :: proc(p: ^Parser) -> ^Node {
    left := parse_unary(p)
    levels := 0
    defer p.depth -= levels
    for at(p, "**") && peek(p).kind == .Operator && !failed(p) {
        levels += 1
        nest(p)
        t := next_token(p)
        left = binary(p, "**", t.line, left, parse_unary(p))
    }
    return left
}

parse_unary :: proc(p: ^Parser, with_filter := true) -> ^Node {
    t := peek(p)
    node: ^Node
    if t.kind == .Operator && (t.text == "-" || t.text == "+") {
        next_token(p)
        node = make_node(p, .Unary, t.line)
        node.text = t.text
        nest(p)
        defer p.depth -= 1
        node.a = parse_unary(p, false)
    } else {
        node = parse_primary(p)
    }
    node = parse_postfix(p, node)
    if with_filter do node = parse_filter_expr(p, node)
    return node
}

// parse_primary parses a bracketed expression or a literal. The nested case stays in a
// small frame: it is on the stack once per bracket.
parse_primary :: proc(p: ^Parser) -> ^Node {
    t := peek(p)
    if t.kind == .Operator {
        switch t.text {
        case "(":
            next_token(p)
            n := parse_tuple(p, explicit_parens = true)
            expect(p, .Operator, ")")
            return n
        case "[": return parse_list(p)
        case "{": return parse_dict(p)
        }
    }
    return parse_literal(p)
}

parse_literal :: proc(p: ^Parser) -> ^Node {
    t := peek(p)
    #partial switch t.kind {
    case .Name:
        next_token(p)
        switch t.text {
        case "true", "True": return const_node(p, true, t.line)
        case "false", "False": return const_node(p, false, t.line)
        case "none", "None": return const_node(p, None{}, t.line)
        }
        n := make_node(p, .Name, t.line)
        n.text = t.text
        return n
    case .String:
        next_token(p)
        text := t.text
        if peek(p).kind == .String {
            b := strings.builder_make()
            strings.write_string(&b, text)
            for peek(p).kind == .String do strings.write_string(&b, next_token(p).text)
            text = strings.to_string(b)
        }
        return const_node(p, text, t.line)
    case .Integer:
        next_token(p)
        return const_node(p, t.number, t.line)
    case .Float:
        next_token(p)
        return const_node(p, t.float, t.line)
    }
    fail_unexpected(p) // an operator, or the end of a tag
    return const_node(p, None{}, t.line)
}

const_node :: proc(p: ^Parser, v: Value, line: int) -> ^Node {
    n := make_node(p, .Const, line)
    n.value = v
    return n
}

parse_list :: proc(p: ^Parser) -> ^Node {
    t := expect(p, .Operator, "[")
    items := make([dynamic]^Node)
    for !at(p, "]") && !failed(p) {
        if len(items) > 0 {
            expect(p, .Operator, ",")
            if at(p, "]") do break
        }
        append(&items, parse_expr(p))
    }
    expect(p, .Operator, "]")
    n := make_node(p, .List, t.line)
    n.args = items[:]
    return n
}

parse_dict :: proc(p: ^Parser) -> ^Node {
    t := expect(p, .Operator, "{")
    keys := make([dynamic]^Node)
    values := make([dynamic]^Node)
    for !at(p, "}") && !failed(p) {
        if len(keys) > 0 {
            expect(p, .Operator, ",")
            if at(p, "}") do break
        }
        append(&keys, parse_expr(p))
        expect(p, .Operator, ":")
        append(&values, parse_expr(p))
    }
    expect(p, .Operator, "}")
    n := make_node(p, .Dict, t.line)
    n.args = keys[:]
    n.values = values[:]
    return n
}

// parse_postfix parses attribute, item and call links; each link nests one level.
parse_postfix :: proc(p: ^Parser, node: ^Node) -> ^Node {
    node := node
    levels := 0
    defer p.depth -= levels
    for !failed(p) {
        t := peek(p)
        if t.kind != .Operator || (t.text != "." && t.text != "[" && t.text != "(") do break
        levels += 1
        nest(p)
        node = parse_call(p, node) if t.text == "(" else parse_subscript(p, node)
    }
    return node
}

// parse_filter_expr parses filter, test and call links; tests and calls nest one level
// each (parse_filter counts its own chain).
parse_filter_expr :: proc(p: ^Parser, node: ^Node) -> ^Node {
    node := node
    levels := 0
    defer p.depth -= levels
    for !failed(p) {
        if at(p, "|") && peek(p).kind == .Operator {
            node = parse_filter(p, node)
            continue
        }
        is_test := at_name(p, "is")
        if !is_test && !(at(p, "(") && peek(p).kind == .Operator) do break
        levels += 1
        nest(p)
        node = parse_test(p, node) if is_test else parse_call(p, node)
    }
    return node
}

parse_subscript :: proc(p: ^Parser, node: ^Node) -> ^Node {
    t := next_token(p)
    if t.text == "." {
        attr := peek(p)
        if attr.kind == .Name {
            next_token(p)
            n := make_node(p, .Getattr, t.line)
            n.a = node
            n.text = attr.text
            return n
        }
        if attr.kind == .Integer {
            next_token(p)
            n := make_node(p, .Getitem, t.line)
            n.a = node
            n.b = const_node(p, attr.number, attr.line)
            return n
        }
        parse_fail(p, attr.line, "expected name or number")
        return node
    }
    items := make([dynamic]^Node)
    for !at(p, "]") && !failed(p) {
        if len(items) > 0 {
            expect(p, .Operator, ",")
            if at(p, "]") do break
        }
        append(&items, parse_subscribed(p))
    }
    expect(p, .Operator, "]")
    n := make_node(p, .Getitem, t.line)
    n.a = node
    if len(items) == 1 {
        n.b = items[0]
    } else {
        n.b = make_node(p, .Tuple, t.line)
        n.b.args = items[:]
    }
    return n
}

parse_subscribed :: proc(p: ^Parser) -> ^Node {
    line := peek(p).line
    start: ^Node
    if !at(p, ":") {
        start = parse_expr(p)
        if !at(p, ":") do return start
    }
    next_token(p)
    n := make_node(p, .Slice, line)
    n.a = start
    if !at(p, "]") && !at(p, ",") && !at(p, ":") do n.b = parse_expr(p)
    if skip_if(p, ":") {
        if !at(p, "]") && !at(p, ",") do n.c = parse_expr(p)
    }
    return n
}

// parse_call_args fills args, keyword names and values, *b and **c of n.
parse_call_args :: proc(p: ^Parser, n: ^Node) {
    expect(p, .Operator, "(")
    args := make([dynamic]^Node)
    names := make([dynamic]string)
    values := make([dynamic]^Node)
    for !at(p, ")") && !failed(p) {
        if len(args) + len(names) > 0 || n.b != nil || n.c != nil {
            expect(p, .Operator, ",")
            if at(p, ")") do break
        }
        t := peek(p)
        if at(p, "**") && t.kind == .Operator {
            next_token(p)
            n.c = parse_expr(p)
        } else if at(p, "*") && t.kind == .Operator {
            next_token(p)
            n.b = parse_expr(p)
        } else if t.kind == .Name && at(p, "=", 1) && peek(p, 1).kind == .Operator {
            next_token(p)
            next_token(p)
            append(&names, t.text)
            append(&values, parse_expr(p))
        } else {
            if len(names) > 0 || n.b != nil || n.c != nil {
                parse_fail(p, t.line, "Invalid argument syntax")
            }
            append(&args, parse_expr(p))
        }
    }
    expect(p, .Operator, ")")
    n.args = args[:]
    n.names = names[:]
    n.values = values[:]
}

parse_call :: proc(p: ^Parser, node: ^Node) -> ^Node {
    n := make_node(p, .Call, peek(p).line)
    n.a = node
    parse_call_args(p, n)
    return n
}

dotted_name :: proc(p: ^Parser) -> string {
    name := expect(p, .Name, "").text
    for at(p, ".") && peek(p, 1).kind == .Name && !failed(p) {
        next_token(p)
        name = strings.concatenate({name, ".", next_token(p).text})
    }
    return name
}

// parse_filter parses "| name(args)" repeatedly; start_inline parses a first filter
// without a leading "|" (filter blocks).
parse_filter :: proc(p: ^Parser, node: ^Node, start_inline := false) -> ^Node {
    node := node
    inline := start_inline
    levels := 0
    defer p.depth -= levels
    for (inline || (at(p, "|") && peek(p).kind == .Operator)) && !failed(p) {
        levels += 1
        nest(p)
        if !inline do next_token(p)
        inline = false
        n := make_node(p, .Filter, peek(p).line)
        n.text = dotted_name(p)
        n.a = node
        if at(p, "(") && peek(p).kind == .Operator do parse_call_args(p, n)
        node = n
    }
    return node
}

parse_test :: proc(p: ^Parser, node: ^Node) -> ^Node {
    line := next_token(p).line
    negated := false
    if at_name(p, "not") {
        next_token(p)
        negated = true
    }
    n := make_node(p, .Test, line)
    n.a = node
    n.text = dotted_name(p)
    t := peek(p)
    if at(p, "(") && t.kind == .Operator {
        parse_call_args(p, n)
    } else if test_arg_follows(t^) {
        arg := parse_postfix(p, parse_primary(p))
        if args, err := make([]^Node, 1); err == nil {
            args[0] = arg
            n.args = args
        }
    }
    if !negated do return n
    not := make_node(p, .Unary, line)
    not.text = "not"
    not.a = n
    return not
}

@(private="file")
test_arg_follows :: proc(t: Token) -> bool {
    #partial switch t.kind {
    case .Name:
        switch t.text {
        case "else", "or", "and", "if", "in", "is", "not", "recursive": return false
        }
        return true
    case .String, .Integer, .Float: return true
    case .Operator: return t.text == "[" || t.text == "{"
    }
    return false
}
