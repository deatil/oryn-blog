#+private
package jinja

import "base:intrinsics"
import "core:math"
import "core:strings"

// lookup resolves a variable through the scopes, the host context and the globals.
lookup :: proc(s: ^State, scope: ^Scope, name: string) -> Value {
    for sc := scope; sc != nil; sc = sc.parent {
        if v, ok := sc.vars[name]; ok do return v
        if sc.dict != nil {
            if v, ok := dict_get(sc.dict, name); ok do return v
        }
    }
    if v, ok := s.env.globals[name]; ok do return v
    if name == "self" && s.ctx != nil do return self_reference(s)
    return Undefined{name = name}
}

// Eval evaluates one kind of expression.
Eval :: #type proc(s: ^State, scope: ^Scope, n: ^Node) -> Value

// EVAL is the evaluator of each node kind. eval calls through it rather than switching,
// so that no optimizer inlines every evaluator into eval's frame (stack.odin).
@(rodata)
EVAL := [Node_Kind]Eval {
    .Const = eval_const, .Name = eval_name, .List = eval_sequence, .Tuple = eval_sequence,
    .Dict = eval_dict, .Getattr = eval_getattr, .Getitem = eval_getitem, .Call = eval_call,
    .Filter = eval_filter, .Test = apply_test, .Unary = eval_unary, .Binary = eval_binary,
    .Concat = eval_concat, .Compare = eval_compare, .Cond = eval_cond,
    // Parts of subscripts and assignment targets, and statements: never evaluated.
    .Slice = cannot_run, .Ns_Ref = cannot_run, .Data = cannot_run, .Output = cannot_run,
    .If = cannot_run, .For = cannot_run, .Set = cannot_run, .Set_Block = cannot_run,
    .Macro = cannot_run, .Call_Block = cannot_run, .Filter_Block = cannot_run,
    .With = cannot_run, .Block = cannot_run, .Extends = cannot_run, .Include = cannot_run,
    .Import = cannot_run, .From_Import = cannot_run, .Autoescape = cannot_run,
    .Do = cannot_run, .Break = cannot_run, .Continue = cannot_run, .Trans = cannot_run,
}

// eval evaluates an expression. It is on the stack once per level of every nested
// expression, macro call and include, so it only dispatches. (Its early returns leave
// the named result, Undefined, so that no build makes room for a value of its own.)
eval :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    if s.failed do return
    s.line = n.line
    if stack_exhausted(s.env.stack) {
        stack_error(s)
        return
    }
    return EVAL[n.kind](s, scope, n)
}

// cannot_run reports a node in the wrong place (a statement evaluated as an expression
// or the reverse); the parser never builds one.
cannot_run :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Value {
    return runtime_error(s, .Runtime, "cannot evaluate %v", n.kind)
}

eval_const :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Value {
    return n.value
}

eval_name :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Value {
    return lookup(s, scope, n.text)
}

eval_sequence :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    l := new_list(len(n.args), n.kind == .Tuple)
    if l == nil do return
    for item in n.args do append(&l.items, eval(s, scope, item))
    return l
}

eval_dict :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    d := new_dict(.Dict)
    if d == nil do return
    for key, i in n.args {
        k := eval(s, scope, key)
        dict_set(d, k, eval(s, scope, n.values[i]))
    }
    return d
}

eval_getattr :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    obj := eval(s, scope, n.a)
    if s.failed do return
    return get_attr(s, obj, n.text)
}

eval_filter :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    input := eval(s, scope, n.a)
    if s.failed do return
    return apply_filter(s, scope, n, &input)
}

eval_cond :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    holds := condition(s, scope, n.a)
    if s.failed do return
    if holds do return eval(s, scope, n.b)
    if n.c != nil do return eval(s, scope, n.c)
    return no_else(n)
}

// no_else is the value of an inline if-expression that is false and has no else.
no_else :: #force_no_inline proc(n: ^Node) -> Value {
    return Undefined{hint = strings.concatenate({"the inline if-expression on line ",
        to_string(i64(n.line)), " evaluated to false and no else section was defined."})}
}

eval_getitem :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    obj := eval(s, scope, n.a)
    if s.failed do return
    if n.b.kind == .Slice do return eval_slice(s, scope, n.b, obj)
    key := eval(s, scope, n.b)
    if s.failed do return
    return get_item(s, obj, key)
}

// eval_slice applies the slice n (obj[a:b:c]) to obj.
eval_slice :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node, obj: Value) -> Value {
    bounds: [3]Value = {None{}, None{}, None{}}
    parts := [3]^Node{n.a, n.b, n.c}
    for part, i in parts {
        if part != nil do bounds[i] = eval(s, scope, part)
    }
    if s.failed do return Undefined{}
    if u, ok := obj.(Undefined); ok && s.env.options.undefined != .Chainable {
        return undefined_error(s, u)
    }
    return slice_value(s, obj, bounds[0], bounds[1], bounds[2])
}

// ---------------------------------------------------------------------------------------
// Attribute and item access

// get_attr is Jinja's environment.getattr: attribute first, then item.
get_attr :: #force_no_inline proc(s: ^State, obj: Value, name: string) -> Value {
    if u, ok := obj.(Undefined); ok {
        if s.env.options.undefined == .Chainable do return obj
        return undefined_error(s, u)
    }
    if v, found := attribute_of(s, obj, name); found do return v
    if v, found := item_of(obj, name); found do return v
    return Undefined{name = name, owner = object_name(obj)}
}

// get_item is Jinja's environment.getitem: item first, then attribute for string keys.
get_item :: #force_no_inline proc(s: ^State, obj: Value, key: Value) -> Value {
    if u, ok := obj.(Undefined); ok {
        if s.env.options.undefined == .Chainable do return obj
        return undefined_error(s, u)
    }
    if v, found := item_of(obj, key); found do return v
    if name, is_str := key.(string); is_str {
        if v, found := attribute_of(s, obj, name); found do return v
        return Undefined{name = name, owner = object_name(obj)}
    }
    return Undefined{name = to_string(key), owner = object_name(obj)}
}

// attribute_of finds Python attributes: methods of builtin types and object fields.
attribute_of :: proc(s: ^State, obj: Value, name: string) -> (Value, bool) {
    #partial switch x in obj {
    case ^Dict:
        if x.kind != .Dict do return dict_get(x, name)
        if is_dict_method(name) do return bound_method(obj, name), true
    case ^List:
        for field, i in x.fields {
            if field == name && i < len(x.items) do return x.items[i], true
        }
        if is_list_method(name, x.tuple) do return bound_method(obj, name), true
    case string, Markup:
        if is_string_method(name, is_markup(obj)) do return bound_method(obj, name), true
    case ^Loop: return loop_attribute(s, x, name)
    case ^Cycler:
        switch name {
        case "current": return x.items[x.pos] if len(x.items) > 0 else Value(None{}), true
        case "next", "reset": return bound_method(obj, name), true
        }
    case ^Callable: return callable_attribute(x, name)
    case i64, f64, bool:
        switch name {
        case "real": return obj, true
        case "imag": return i64(0), true
        case "is_integer", "conjugate", "bit_length": return bound_method(obj, name), true
        }
    }
    return Undefined{}, false
}

// item_of reads obj[key] for dicts, sequences and strings.
item_of :: proc(obj: Value, key: Value) -> (Value, bool) {
    #partial switch x in obj {
    case ^Dict:
        if x.kind == .Dict do return dict_get(x, key)
    case ^List:
        i, _, kind := as_number(key)
        if kind != .Int do return Undefined{}, false
        n := i64(len(x.items))
        if i < 0 do i += n
        if i < 0 || i >= n do return Undefined{}, false
        return x.items[i], true
    case string, Markup:
        i, _, kind := as_number(key)
        if kind != .Int do return Undefined{}, false
        text, _ := key_string(obj)
        n := i64(strings.rune_count(text))
        if i < 0 do i += n
        if i < 0 || i >= n do return Undefined{}, false
        return rune_slice(text, int(i), int(i) + 1), true
    }
    return Undefined{}, false
}

bound_method :: proc(obj: Value, name: string) -> Value {
    c := new(Callable)
    if c == nil do return Undefined{}
    c^ = Callable{name = name, procedure = dispatch_method, self = obj}
    return c
}

// slice_value applies Python slicing to lists, tuples and strings.
slice_value :: proc(s: ^State, obj, start, stop, step: Value) -> Value {
    n := length(obj)
    #partial switch _ in obj {
    case ^List, string, Markup:
    case:
        return runtime_error(s, .Type, "'%s' object is not subscriptable", type_name(obj))
    }
    indices, ok := slice_indices(s, n, start, stop, step)
    if !ok do return Undefined{}
    #partial switch x in obj {
    case ^List:
        out := new_list(len(indices), x.tuple)
        if out == nil do return Undefined{}
        for i in indices do append(&out.items, x.items[i])
        return out
    case:
        text, _ := key_string(obj)
        r := runes_of(text)
        if len(r) != n do return Undefined{} // refused: the render has stopped.
        b := strings.builder_make(0, len(indices))
        for i in indices do strings.write_rune(&b, r[i])
        if is_markup(obj) do return Markup(strings.to_string(b))
        return strings.to_string(b)
    }
}

slice_indices :: proc(s: ^State, n: int, start, stop, step: Value) -> ([]int, bool) {
    step_n := 1
    if !is_none(step) {
        v, _, k := as_number(step)
        if k != .Int {
            runtime_error(s, .Type, "slice indices must be integers or None")
            return nil, false
        }
        if v == 0 {
            runtime_error(s, .Runtime, "slice step cannot be zero")
            return nil, false
        }
        step_n = int(v)
    }
    bound :: proc(v: Value, n, default_value: int, neg_step: bool) -> (int, bool) {
        if is_none(v) do return default_value, true
        i, _, k := as_number(v)
        if k != .Int do return 0, false
        x := int(i)
        if x < 0 do x += n
        if neg_step do return clamp(x, -1, n - 1), true
        return clamp(x, 0, n), true
    }
    neg := step_n < 0
    lo, ok1 := bound(start, n, n - 1 if neg else 0, neg)
    hi, ok2 := bound(stop, n, -1 if neg else n, neg)
    if !ok1 || !ok2 {
        runtime_error(s, .Type, "slice indices must be integers or None")
        return nil, false
    }
    out := make([dynamic]int)
    if neg {
        for i := lo; i > hi; i += step_n do append(&out, i)
    } else {
        for i := lo; i < hi; i += step_n do append(&out, i)
    }
    return out[:], true
}

// ---------------------------------------------------------------------------------------
// Operators

eval_unary :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    operand := eval(s, scope, n.a)
    if s.failed do return
    return unary_op(s, n, operand)
}

unary_op :: #force_no_inline proc(s: ^State, n: ^Node, v: Value) -> Value {
    if n.text == "not" do return !is_true(s, v)
    if u, ok := v.(Undefined); ok do return undefined_error(s, u)
    i, f, kind := as_number(v)
    switch kind {
    case .Int: return -i if n.text == "-" else i
    case .Float: return -f if n.text == "-" else f
    case .None:
    }
    return runtime_error(s, .Type, "bad operand type for unary %s: '%s'", n.text, type_name(v))
}

eval_binary :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    left := eval(s, scope, n.a)
    if s.failed do return
    switch n.text {
    case "and":
        if !is_true(s, left) do return left
        return eval(s, scope, n.b)
    case "or":
        if is_true(s, left) || s.failed do return left
        return eval(s, scope, n.b)
    }
    right := eval(s, scope, n.b)
    if s.failed do return
    return binary_op(s, n.text, left, right)
}

binary_op :: #force_no_inline proc(s: ^State, op: string, left, right: Value) -> Value {
    if u, ok := left.(Undefined); ok do return undefined_error(s, u)
    if u, ok := right.(Undefined); ok do return undefined_error(s, u)
    li, lf, lk := as_number(left)
    ri, rf, rk := as_number(right)
    if lk != .None && rk != .None do return numeric_op(s, op, li, lf, lk, ri, rf, rk)
    switch op {
    case "+": return add_values(s, left, right)
    case "*":
        if rk == .Int do return repeat_value(s, left, ri)
        if lk == .Int do return repeat_value(s, right, li)
    case "%":
        if fmt_text, ok := key_string(left); ok do return percent_format(s, left, fmt_text, right)
    }
    return runtime_error(s, .Type, "unsupported operand type(s) for %s: '%s' and '%s'",
        "**" if op == "**" else op, type_name(left), type_name(right))
}

numeric_op :: proc(s: ^State, op: string, li: i64, lf: f64, lk: Number_Kind, ri: i64,
    rf: f64, rk: Number_Kind) -> Value {
    ints := lk == .Int && rk == .Int
    switch op {
    case "+", "-", "*":
        if !ints do return lf + rf if op == "+" else (lf - rf if op == "-" else lf * rf)
        r: i64
        overflow: bool
        switch op {
        case "+": r, overflow = intrinsics.overflow_add(li, ri)
        case "-": r, overflow = intrinsics.overflow_sub(li, ri)
        case: r, overflow = intrinsics.overflow_mul(li, ri)
        }
        if overflow do return overflow_error(s)
        return r
    case "/":
        if rf == 0 do return runtime_error(s, .Runtime, "division by zero")
        return lf / rf
    case "//":
        if rf == 0 do return runtime_error(s, .Runtime, "integer division or modulo by zero")
        if ints do return floor_div(li, ri)
        return math.floor(lf / rf)
    case "%":
        if rf == 0 do return runtime_error(s, .Runtime, "integer division or modulo by zero")
        if ints do return li - floor_div(li, ri) * ri
        m := math.mod(lf, rf)
        if m != 0 && ((m < 0) != (rf < 0)) do m += rf
        return m
    case "**":
        if ints && ri >= 0 {
            result, ok := int_pow(li, ri)
            if !ok do return overflow_error(s)
            return result
        }
        if lf == 0 && rf < 0 {
            return runtime_error(s, .Runtime, "0.0 cannot be raised to a negative power")
        }
        return math.pow(lf, rf)
    }
    return runtime_error(s, .Type, "unsupported operator %s", op)
}

floor_div :: proc(a, b: i64) -> i64 {
    q := a / b
    if (a % b != 0) && ((a < 0) != (b < 0)) do q -= 1
    return q
}

add_values :: proc(s: ^State, left, right: Value) -> Value {
    if is_markup(left) || is_markup(right) {
        if is_stringish(left) && is_stringish(right) do return markup_concat(left, right)
    }
    if a, ok := left.(string); ok {
        if b, ok2 := right.(string); ok2 do return strings.concatenate({a, b})
        return runtime_error(s, .Type, "can only concatenate str (not \"%s\") to str",
            type_name(right))
    }
    la, ok := left.(^List)
    lb, ok2 := right.(^List)
    if ok && ok2 && la.tuple == lb.tuple {
        out := new_list(len(la.items) + len(lb.items), la.tuple)
        if out == nil do return Undefined{}
        append(&out.items, ..la.items[:])
        append(&out.items, ..lb.items[:])
        return out
    }
    if ok {
        return runtime_error(s, .Type, "can only concatenate %s (not \"%s\") to %s",
            type_name(left), type_name(right), type_name(left))
    }
    return runtime_error(s, .Type, "unsupported operand type(s) for +: '%s' and '%s'",
        type_name(left), type_name(right))
}

// repeat_value is sequence * n: its size is known before it is built, so it is checked
// and allocated once (repeat_text, reserve_bytes).
repeat_value :: proc(s: ^State, v: Value, times: i64) -> Value {
    count := int(clamp(times, 0, i64(max(int))))
    #partial switch x in v {
    case string:
        text, ok := repeat_text(s, x, count)
        return text if ok else Undefined{}
    case Markup:
        text, ok := repeat_text(s, string(x), count)
        return Markup(text) if ok else Undefined{}
    case ^List:
        items, ok := reserve_bytes(s, len(x.items), count)
        if !ok do return Undefined{}
        if _, fits := reserve_bytes(s, items, size_of(Value)); !fits do return Undefined{}
        out := new_list(items, x.tuple)
        if out == nil do return Undefined{}
        for _ in 0 ..< count do append(&out.items, ..x.items[:])
        return out
    }
    return runtime_error(s, .Type, "can't multiply sequence by non-int of type '%s'",
        type_name(v))
}

// eval_concat is the ~ operator: strings joined, Markup-aware when autoescaping.
eval_concat :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    values, err := make([]Value, len(n.args))
    if err != nil do return // refused: the render stopped.
    for arg, i in n.args {
        values[i] = eval(s, scope, arg)
        if s.failed || !strict_check(s, values[i]) do return
    }
    return join_values(s, values)
}

// join_values joins the operands of ~ as strings.
join_values :: #force_no_inline proc(s: ^State, values: []Value) -> Value {
    parts, err := make([]string, len(values))
    if err != nil do return Undefined{}
    any_markup := false
    for v in values do if is_markup(v) do any_markup = true
    total := 0
    for v, i in values {
        parts[i] = string(escape(v)) if s.autoescape && any_markup else to_string(v)
        total += len(parts[i])
    }
    // The joined text is sized first, and allocated once.
    b := strings.builder_make()
    if !reserve_text(s, &b, total) do return Undefined{}
    for part in parts do strings.write_string(&b, part)
    if s.autoescape && any_markup do return Markup(strings.to_string(b))
    return strings.to_string(b)
}

eval_compare :: proc(s: ^State, scope: ^Scope, n: ^Node) -> (v: Value) {
    left := eval(s, scope, n.a)
    holds := true
    for op, i in n.names {
        if s.failed do return
        right := eval(s, scope, n.args[i])
        if s.failed do return
        holds = compare_op(s, op, left, right)
        if s.failed do return
        if !holds do break
        left = right
    }
    v = holds
    return
}

compare_op :: #force_no_inline proc(s: ^State, op: string, left, right: Value) -> bool {
    switch op {
    case "==", "!=":
        if !strict_check(s, left) || !strict_check(s, right) do return false
        eq := values_equal(left, right)
        return eq if op == "==" else !eq
    case "in", "notin":
        found := contains(s, right, left)
        return found if op == "in" else !found
    }
    if u, ok := left.(Undefined); ok { undefined_error(s, u); return false }
    if u, ok := right.(Undefined); ok { undefined_error(s, u); return false }
    order, ok := compare_values(left, right)
    if !ok {
        runtime_error(s, .Type, "'%s' not supported between instances of '%s' and '%s'", op,
            type_name(left), type_name(right))
        return false
    }
    if order == 2 do return false
    switch op {
    case "<": return order < 0
    case "<=": return order <= 0
    case ">": return order > 0
    case ">=": return order >= 0
    }
    return false
}

// contains is Python's "item in container".
contains :: proc(s: ^State, container, item: Value) -> bool {
    #partial switch x in container {
    case string, Markup:
        text, _ := key_string(container)
        needle, ok := key_string(item)
        if !ok {
            runtime_error(s, .Type, "'in <string>' requires string as left operand, not %s",
                type_name(item))
            return false
        }
        return strings.contains(text, needle)
    case ^List:
        for v in x.items do if values_equal(v, item) do return true
        return false
    case ^Dict:
        return dict_find(x, item) >= 0
    case Undefined:
        return strict_check(s, container) && false
    }
    runtime_error(s, .Type, "argument of type '%s' is not iterable", type_name(container))
    return false
}

overflow_error :: proc(s: ^State) -> Value {
    runtime_error(s, .Runtime, "integer overflow: results must fit in 64 bits")
    set_hint(s, "Use a float literal (2.0 ** 100) for very large numbers.")
    return Undefined{}
}

// int_pow raises base to a non-negative power by squaring; ok is false on overflow.
int_pow :: proc(base, exp: i64) -> (i64, bool) {
    result: i64 = 1
    b, e := base, exp
    for e > 0 {
        overflow: bool
        if e & 1 == 1 {
            result, overflow = intrinsics.overflow_mul(result, b)
            if overflow do return 0, false
        }
        e >>= 1
        if e > 0 {
            b, overflow = intrinsics.overflow_mul(b, b)
            if overflow do return 0, false
        }
    }
    return result, true
}
