#+private
package jinja

import "core:unicode"

// The built-in tests: {{ x is defined }}, select("odd"), ...

register_tests :: proc(env: ^Environment) {
    add_test(env, "boolean", test_type)
    add_test(env, "callable", test_type)
    add_test(env, "defined", test_type)
    add_test(env, "undefined", test_type)
    add_test(env, "none", test_type)
    add_test(env, "false", test_type)
    add_test(env, "true", test_type)
    add_test(env, "float", test_type)
    add_test(env, "integer", test_type)
    add_test(env, "number", test_type)
    add_test(env, "string", test_type)
    add_test(env, "mapping", test_type)
    add_test(env, "sequence", test_type)
    add_test(env, "iterable", test_type)
    add_test(env, "escaped", test_type)
    add_test(env, "lower", test_case)
    add_test(env, "upper", test_case)
    add_test(env, "even", test_parity)
    add_test(env, "odd", test_parity)
    add_test(env, "divisibleby", test_divisibleby)
    add_test(env, "sameas", test_sameas)
    add_test(env, "in", test_in)
    add_test(env, "filter", test_registered)
    add_test(env, "test", test_registered)
    comparisons := [?][2]string {
        {"eq", "=="}, {"equalto", "=="}, {"==", "=="}, {"ne", "!="}, {"!=", "!="},
        {"lt", "<"}, {"lessthan", "<"}, {"<", "<"}, {"le", "<="}, {"<=", "<="},
        {"gt", ">"}, {"greaterthan", ">"}, {">", ">"}, {"ge", ">="}, {">=", ">="},
    }
    for pair in comparisons {
        op := pair[1]
        user: rawptr
        switch op {
        case "==": user = &OP_EQ
        case "!=": user = &OP_NE
        case "<": user = &OP_LT
        case "<=": user = &OP_LE
        case ">": user = &OP_GT
        case ">=": user = &OP_GE
        }
        add_test(env, pair[0], test_compare, user)
    }
}

@(private="file") OP_EQ := "=="
@(private="file") OP_NE := "!="
@(private="file") OP_LT := "<"
@(private="file") OP_LE := "<="
@(private="file") OP_GT := ">"
@(private="file") OP_GE := ">="

@(private="file")
test_type :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "value")
    switch c.name {
    case "defined": return !is_undefined(v)
    case "undefined": return is_undefined(v)
    case "none": return is_none(v)
    case "boolean":
        _, ok := v.(bool)
        return ok
    case "true":
        b, ok := v.(bool)
        return ok && b
    case "false":
        b, ok := v.(bool)
        return ok && !b
    case "integer":
        _, ok := v.(i64)
        return ok
    case "float":
        _, ok := v.(f64)
        return ok
    case "number": return is_number(v)
    case "string": return is_stringish(v)
    case "escaped": return is_markup(v)
    case "callable":
        #partial switch x in v {
        case ^Callable, ^Loop: return true
        case ^Dict: return false
        }
        return false
    case "mapping":
        d, ok := v.(^Dict)
        return ok && d.kind == .Dict
    case "sequence":
        #partial switch x in v {
        case string, Markup, ^List: return true
        case ^Dict: return x.kind == .Dict
        }
        return false
    case "iterable":
        #partial switch x in v {
        case string, Markup, ^List, Undefined: return true
        case ^Dict: return x.kind == .Dict
        }
        return false
    }
    return false
}

@(private="file")
test_case :: proc(c: ^Call) -> Value {
    text := to_string(arg(c, 0, "value"))
    cased := false
    for r in text {
        if unicode.is_upper(r) {
            if c.name == "lower" do return false
            cased = true
        } else if unicode.is_lower(r) {
            if c.name == "upper" do return false
            cased = true
        }
    }
    return cased
}

@(private="file")
test_parity :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "value")
    i, f, kind := as_number(v)
    switch kind {
    case .Int: return (i % 2 == 0) == (c.name == "even")
    case .Float:
        m := f - 2 * f64(i64(f / 2))
        return (m == 0) == (c.name == "even")
    case .None:
    }
    return fail(c, "unsupported operand type(s) for %%: '%s' and 'int'", type_name(v))
}

@(private="file")
test_divisibleby :: proc(c: ^Call) -> Value {
    v, num := arg(c, 0, "value"), arg(c, 1, "num")
    r := binary_op(c.state, "%", v, num)
    if c.state.failed do return false
    return values_equal(r, i64(0))
}

@(private="file")
test_sameas :: proc(c: ^Call) -> Value {
    a, b := arg(c, 0, "value"), arg(c, 1, "other")
    switch x in a {
    case ^List:
        y, ok := b.(^List)
        return ok && x == y
    case ^Dict:
        y, ok := b.(^Dict)
        return ok && x == y
    case ^Callable:
        y, ok := b.(^Callable)
        return ok && x == y
    case Undefined, None, bool, i64, f64, string, Markup, ^Loop, ^Cycler:
        if type_name(a) != type_name(b) do return false
        return values_equal(a, b)
    }
    return false
}

@(private="file")
test_in :: proc(c: ^Call) -> Value {
    return contains(c.state, arg(c, 1, "seq"), arg(c, 0, "value"))
}

@(private="file")
test_registered :: proc(c: ^Call) -> Value {
    name, ok := arg(c, 0, "value").(string)
    if !ok do return false
    if c.name == "filter" {
        _, found := c.state.env.filters[name]
        return found
    }
    _, found := c.state.env.tests[name]
    return found
}

@(private="file")
test_compare :: proc(c: ^Call) -> Value {
    op := (^string)(c.user)^
    return compare_op(c.state, op, arg(c, 0, "value"), arg(c, 1, "other"))
}
