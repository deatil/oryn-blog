#+private
package jinja

// Node_Kind names every expression and statement. One Node struct serves them all; the
// comment on each kind says which fields it uses.
Node_Kind :: enum u8 {
    // Expressions
    Const,       // value
    Name,        // text
    List,        // args
    Tuple,       // args
    Dict,        // args = keys, values
    Getattr,     // a . text
    Getitem,     // a [ b ]
    Slice,       // a : b : c (each may be nil); only inside Getitem
    Call,        // a ( args, names = values, *b, **c )
    Filter,      // a | text ( args, names = values, *b, **c ); a is nil in filter blocks
    Test,        // a is text ( args, names = values, *b, **c )
    Unary,       // text a  ("not", "-", "+")
    Binary,      // a text b ("and", "or", "+", "-", "*", "/", "//", "%", "**", "in", "notin")
    Concat,      // args joined with ~
    Compare,     // a, then names[i] (operator) against args[i]
    Cond,        // b if a else c (c may be nil)
    Ns_Ref,      // a . text as an assignment target (namespace attribute)
    // Statements
    Data,        // text
    Output,      // {{ a }}
    If,          // if a: body else else_body (elif is a nested If in else_body)
    For,         // for a in b if c: body else else_body; flags .Recursive
    Set,         // set a = b
    Set_Block,   // set a | c: body (c is a filter chain or nil)
    Macro,       // macro text(names = values): body; flags .Uses_*
    Call_Block,  // call(names = values) a: body; flags .Uses_*
    Filter_Block,// filter a: body
    With,        // with args[i] = values[i]: body
    Block,       // block text: body; flags .Scoped, .Required
    Extends,     // extends a
    Include,     // include a; flags .Ignore_Missing, .With_Context
    Import,      // import a as text; flags .With_Context
    From_Import, // from a import names[i] as aliases[i]; flags .With_Context
    Autoescape,  // autoescape a: body
    Do,          // do a
    Break,
    Continue,
    Trans,       // text = singular, plural; names = values; count = counter name
}

Node_Flag :: enum u8 {
    Recursive,
    Scoped,
    Required,
    Ignore_Missing,
    With_Context,
    Uses_Caller,
    Uses_Varargs,
    Uses_Kwargs,
    Trimmed,
    Has_Plural,
    Has_Vars,
}

Node :: struct {
    kind:      Node_Kind,
    flags:     bit_set[Node_Flag],
    line:      int,
    text:      string,
    value:     Value,
    a, b, c:   ^Node,
    args:      []^Node,
    names:     []string,
    values:    []^Node,
    aliases:   []string,
    body:      []^Node,
    else_body: []^Node,
    plural:    string,
    count:     string,
}

// Compiled is a parsed template, owned by its environment.
Compiled :: struct {
    name:       string,
    source:     string,
    body:       []^Node,
    blocks:     map[string]^Node,
    autoescape: bool,
}

// walk_node calls visit on node and all nodes below it, skipping the bodies of nested
// macros and call blocks when skip_scopes is set.
walk_node :: proc(n: ^Node, visit: proc(n: ^Node, user: rawptr), user: rawptr,
    skip_scopes := false) {
    if n == nil do return
    visit(n, user)
    if skip_scopes && (n.kind == .Macro || n.kind == .Call_Block) {
        walk_node(n.a, visit, user, skip_scopes)
        for v in n.values do walk_node(v, visit, user, skip_scopes)
        return
    }
    walk_node(n.a, visit, user, skip_scopes)
    walk_node(n.b, visit, user, skip_scopes)
    walk_node(n.c, visit, user, skip_scopes)
    for x in n.args do walk_node(x, visit, user, skip_scopes)
    for x in n.values do walk_node(x, visit, user, skip_scopes)
    for x in n.body do walk_node(x, visit, user, skip_scopes)
    for x in n.else_body do walk_node(x, visit, user, skip_scopes)
}
