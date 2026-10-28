#+private
package jinja

import "core:strconv"
import "core:strings"

// Filters over sequences and mappings.

register_sequence_filters :: proc(env: ^Environment) {
    add_filter(env, "attr", filter_attr)
    add_filter(env, "batch", filter_batch)
    add_filter(env, "count", filter_length)
    add_filter(env, "length", filter_length)
    add_filter(env, "default", filter_default)
    add_filter(env, "d", filter_default)
    add_filter(env, "dictsort", filter_dictsort)
    add_filter(env, "first", filter_first)
    add_filter(env, "last", filter_last)
    add_filter(env, "groupby", filter_groupby)
    add_filter(env, "items", filter_items)
    add_filter(env, "join", filter_join)
    add_filter(env, "list", filter_list)
    add_filter(env, "map", filter_map)
    add_filter(env, "max", filter_minmax)
    add_filter(env, "min", filter_minmax)
    add_filter(env, "random", filter_random)
    add_filter(env, "select", filter_select)
    add_filter(env, "reject", filter_select)
    add_filter(env, "selectattr", filter_select)
    add_filter(env, "rejectattr", filter_select)
    add_filter(env, "reverse", filter_reverse)
    add_filter(env, "slice", filter_slice)
    add_filter(env, "sort", filter_sort)
    add_filter(env, "sum", filter_sum)
    add_filter(env, "unique", filter_unique)
}

// items_of lists the items a filter iterates (like Python's list(value)).
items_of :: proc(c: ^Call, v: Value) -> ([]Value, bool) {
    return iterate(c.state, v)
}

// attribute_getter follows a dotted attribute path ("a.b.0") with environment.getitem.
attribute_getter :: proc(s: ^State, item: Value, attribute: Value, default: Value = {},
    lower := false) -> Value {
    v := item
    if path, ok := key_string(attribute); ok {
        rest := path
        for part in strings.split_iterator(&rest, ".") {
            key: Value = part
            if n, is_int := strconv.parse_i64_of_base(part, 10); is_int && len(part) > 0 &&
               is_digit(part[0]) {
                key = n
            }
            v = get_item(s, v, key)
            if s.failed do return Undefined{}
        }
    } else if !is_none(attribute) {
        v = get_item(s, v, attribute)
    }
    if is_undefined(v) && !is_undefined(default) do v = default
    if lower {
        if text, ok := v.(string); ok do return to_lower(text)
    }
    return v
}

@(private="file")
filter_attr :: proc(c: ^Call) -> Value {
    if !check_args(c, "attr", {"obj", "name"}, 2) do return Undefined{}
    obj := arg(c, 0, "obj")
    name := to_string(arg(c, 1, "name"))
    if u, ok := obj.(Undefined); ok do return undefined_error(c.state, u)
    if v, found := attribute_of(c.state, obj, name); found do return v
    return Undefined{name = name, owner = object_name(obj)}
}

@(private="file")
filter_batch :: proc(c: ^Call) -> Value {
    if !check_args(c, "batch", {"value", "linecount", "fill_with"}, 2) do return Undefined{}
    items, ok := items_of(c, arg(c, 0, "value"))
    if !ok do return Undefined{}
    size, _ := arg_int(c, 1, "linecount", 1)
    if size <= 0 do return fail(c, "batch size must be positive")
    fill := arg(c, 2, "fill_with", None{})
    out := new_list()
    if out == nil do return Undefined{}
    for i := 0; i < len(items); i += int(size) {
        row := list_of(items[i:min(i + int(size), len(items))])
        if row == nil do return Undefined{}
        if !is_none(fill) {
            for len(row.items) < int(size) do append(&row.items, fill)
        }
        append(&out.items, row)
    }
    return out
}

filter_length :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "obj")
    #partial switch x in v {
    case string, Markup, ^List: return i64(length(v))
    case ^Dict: return i64(len(x.keys))
    case Undefined:
        if !strict_check(c.state, v) do return Undefined{}
        return i64(0)
    }
    return fail(c, "object of type '%s' has no len()", type_name(v))
}

@(private="file")
filter_default :: proc(c: ^Call) -> Value {
    names := []string{"value", "default_value", "boolean"}
    if !check_args(c, "default", names) do return Undefined{}
    v := arg(c, 0, "value")
    fallback := arg(c, 1, "default_value", string(""))
    if is_undefined(v) || (truthy(arg(c, 2, "boolean", false)) && !truthy(v)) do return fallback
    return v
}

@(private="file")
filter_dictsort :: proc(c: ^Call) -> Value {
    names := []string{"value", "case_sensitive", "by", "reverse"}
    if !check_args(c, "dictsort", names) do return Undefined{}
    d, ok := arg(c, 0, "value").(^Dict)
    if !ok do return fail(c, "You can only sort by either \"key\" or \"value\"")
    by := to_string(arg(c, 2, "by", string("key")))
    pos := 0
    switch by {
    case "key": pos = 0
    case "value": pos = 1
    case: return fail(c, "You can only sort by either \"key\" or \"value\"")
    }
    pairs, perr := make([]Value, len(d.keys))
    keys, kerr := make([]Value, len(d.keys))
    if perr != nil || kerr != nil do return Undefined{}
    for key, i in d.keys {
        pairs[i] = tuple(key, d.values[i])
        keys[i] = key if pos == 0 else d.values[i]
    }
    sorted, sorted_ok := sort_values(c.state, pairs, truthy(arg(c, 3, "reverse", false)),
        truthy(arg(c, 1, "case_sensitive", false)), keys)
    if !sorted_ok do return Undefined{}
    return list_value(list_of(sorted))
}

@(private="file")
filter_first :: proc(c: ^Call) -> Value {
    items, ok := items_of(c, arg(c, 0, "seq"))
    if !ok do return Undefined{}
    if len(items) == 0 do return Undefined{hint = "No first item, sequence was empty."}
    return items[0]
}

@(private="file")
filter_last :: proc(c: ^Call) -> Value {
    items, ok := items_of(c, arg(c, 0, "seq"))
    if !ok do return Undefined{}
    if len(items) == 0 do return Undefined{hint = "No last item, sequence was empty."}
    return items[len(items) - 1]
}

@(private="file")
filter_groupby :: proc(c: ^Call) -> Value {
    names := []string{"value", "attribute", "default", "case_sensitive"}
    if !check_args(c, "groupby", names, 2) do return Undefined{}
    s := c.state
    items, ok := items_of(c, arg(c, 0, "value"))
    if !ok do return Undefined{}
    attribute := arg(c, 1, "attribute")
    default := arg(c, 2, "default", Undefined{})
    case_sensitive := truthy(arg(c, 3, "case_sensitive", false))
    keys, kerr := make([]Value, len(items))
    if kerr != nil do return Undefined{}
    for item, i in items {
        keys[i] = attribute_getter(s, item, attribute, default, !case_sensitive)
        if s.failed do return Undefined{}
    }
    order, sorted_ok := sort_order(s, keys, false, true)
    if !sorted_ok do return Undefined{}
    out := new_list()
    if out == nil do return Undefined{}
    for k := 0; k < len(order); {
        j := k
        group := new_list()
        if group == nil do return Undefined{}
        for j < len(order) && values_equal(keys[order[j]], keys[order[k]]) {
            append(&group.items, items[order[j]])
            j += 1
        }
        grouper := keys[order[k]]
        if len(group.items) == 0 do return Undefined{} // refused: the render stopped.
        if !case_sensitive do grouper = attribute_getter(s, group.items[0], attribute, default)
        pair := new_list(2, true)
        if pair == nil do return Undefined{}
        append(&pair.items, grouper, Value(group))
        pair.fields = GROUP_FIELDS[:]
        append(&out.items, pair)
        k = j
    }
    return out
}

@(private="file")
filter_items :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "value")
    if is_undefined(v) do return list_value(new_list())
    d, ok := v.(^Dict)
    if !ok do return fail(c, "Can only get item pairs from a mapping.")
    out := new_list(len(d.keys))
    if out == nil do return Undefined{}
    for key, i in d.keys do append(&out.items, tuple(key, d.values[i]))
    return out
}

@(private="file")
filter_join :: proc(c: ^Call) -> Value {
    if !check_args(c, "join", {"value", "d", "attribute"}) do return Undefined{}
    items, ok := items_of(c, arg(c, 0, "value"))
    if !ok do return Undefined{}
    sep := arg(c, 1, "d", string(""))
    attribute := arg(c, 2, "attribute", None{})
    if !is_none(attribute) {
        mapped, merr := make([]Value, len(items))
        if merr != nil do return Undefined{}
        for item, i in items do mapped[i] = attribute_getter(c.state, item, attribute)
        items = mapped
    }
    use_markup := false
    if autoescaping(c) {
        use_markup = is_markup(sep)
        for item in items do if is_markup(item) do use_markup = true
    }
    // The joined text is sized first, and allocated once.
    parts, perr := make([]string, len(items))
    if perr != nil do return Undefined{}
    total := 0
    for item, i in items {
        parts[i] = string(escape(item)) if use_markup else to_string(item)
        total += len(parts[i])
    }
    glue := string(escape(sep)) if use_markup else to_string(sep)
    seps, ok_seps := reserve_bytes(c.state, max(len(items) - 1, 0), len(glue))
    if !ok_seps do return Undefined{}
    b := strings.builder_make()
    size, sized := sum_bytes(c.state, total, seps)
    if !sized || !reserve_text(c.state, &b, size) do return Undefined{}
    for part, i in parts {
        if i > 0 do strings.write_string(&b, glue)
        strings.write_string(&b, part)
    }
    if use_markup do return Markup(strings.to_string(b))
    return strings.to_string(b)
}

@(private="file")
filter_list :: proc(c: ^Call) -> Value {
    items, ok := items_of(c, arg(c, 0, "value"))
    if !ok do return Undefined{}
    return list_value(list_of(items))
}

@(private="file")
filter_map :: proc(c: ^Call) -> Value {
    s := c.state
    items, ok := items_of(c, arg(c, 0, "value"))
    if !ok do return Undefined{}
    out := new_list(len(items))
    if out == nil do return Undefined{}
    if attribute, has := find_keyword(c.kwargs, "attribute"); has {
        default := arg(c, -1, "default", Undefined{})
        for item in items {
            append(&out.items, attribute_getter(s, item, attribute, default))
            if s.failed do return Undefined{}
        }
        return out
    }
    if len(c.args) < 2 do return fail(c, "map requires a filter argument")
    name := to_string(c.args[1])
    for item in items {
        args := make([dynamic]Value, 0, len(c.args) - 1)
        append(&args, item)
        append(&args, ..c.args[2:])
        v := call_filter(s, name, args[:], c.kwargs)
        if s.failed do return Undefined{}
        append(&out.items, v)
    }
    return out
}

@(private="file")
filter_minmax :: proc(c: ^Call) -> Value {
    names := []string{"value", "case_sensitive", "attribute"}
    if !check_args(c, c.name, names) do return Undefined{}
    s := c.state
    items, ok := items_of(c, arg(c, 0, "value"))
    if !ok do return Undefined{}
    if len(items) == 0 {
        return Undefined{hint = "No aggregated item, sequence was empty."}
    }
    attribute := arg(c, 2, "attribute", None{})
    lower := !truthy(arg(c, 1, "case_sensitive", false))
    best := 0
    best_key := attribute_getter(s, items[0], attribute, {}, lower)
    for item, i in items[1:] {
        key := attribute_getter(s, item, attribute, {}, lower)
        order, cmp_ok := compare_values(key, best_key)
        if !cmp_ok {
            return fail(c, "'<' not supported between instances of '%s' and '%s'",
                type_name(key), type_name(best_key))
        }
        if (c.name == "max" && order == 1) || (c.name == "min" && order == -1) {
            best, best_key = i + 1, key
        }
    }
    return items[best]
}

@(private="file")
filter_random :: proc(c: ^Call) -> Value {
    items, ok := items_of(c, arg(c, 0, "seq"))
    if !ok do return Undefined{}
    if len(items) == 0 do return Undefined{hint = "No random item, sequence was empty."}
    return items[random_below(c.state, len(items))]
}

// filter_select implements select, reject, selectattr and rejectattr.
@(private="file")
filter_select :: proc(c: ^Call) -> Value {
    s := c.state
    items, ok := items_of(c, arg(c, 0, "value"))
    if !ok do return Undefined{}
    by_attr := strings.has_suffix(c.name, "attr")
    want := strings.has_prefix(c.name, "select")
    first := 2 if by_attr else 1
    if by_attr && len(c.args) < 2 do return fail(c, "Missing parameter for attribute name")
    out := new_list()
    if out == nil do return Undefined{}
    for item in items {
        v := item
        if by_attr do v = attribute_getter(s, item, c.args[1])
        passed: bool
        if len(c.args) > first {
            args := make([dynamic]Value, 0, len(c.args))
            append(&args, v)
            append(&args, ..c.args[first + 1:])
            passed = call_test(s, to_string(c.args[first]), args[:], c.kwargs)
        } else {
            passed = is_true(s, v)
        }
        if s.failed do return Undefined{}
        if passed == want do append(&out.items, item)
    }
    return out
}

@(private="file")
filter_reverse :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "value")
    if text, ok := key_string(v); ok {
        r := runes_of(text)
        for i in 0 ..< len(r) / 2 do r[i], r[len(r) - 1 - i] = r[len(r) - 1 - i], r[i]
        out := strings.builder_make()
        for x in r do strings.write_rune(&out, x)
        if is_markup(v) do return Markup(strings.to_string(out))
        return strings.to_string(out)
    }
    items, ok := items_of(c, v)
    if !ok do return fail(c, "argument must be iterable")
    out := new_list(len(items))
    if out == nil do return Undefined{}
    #reverse for item in items do append(&out.items, item)
    return out
}

@(private="file")
filter_slice :: proc(c: ^Call) -> Value {
    if !check_args(c, "slice", {"value", "slices", "fill_with"}, 2) do return Undefined{}
    items, ok := items_of(c, arg(c, 0, "value"))
    if !ok do return Undefined{}
    slices, _ := arg_int(c, 1, "slices", 1)
    if slices <= 0 do return fail(c, "slices must be positive")
    fill := arg(c, 2, "fill_with", None{})
    n := len(items)
    per := n / int(slices)
    extra := n % int(slices)
    offset := 0
    if _, fits := reserve_bytes(c.state, int(slices), size_of(Value)); !fits do return Undefined{}
    out := new_list(int(slices))
    if out == nil do return Undefined{}
    for i in 0 ..< int(slices) {
        start := offset + i * per
        if i < extra do offset += 1
        end := offset + (i + 1) * per
        part := list_of(items[start:end])
        if part == nil do return Undefined{}
        if !is_none(fill) && i >= extra do append(&part.items, fill)
        append(&out.items, part)
    }
    return out
}

@(private="file")
filter_sort :: proc(c: ^Call) -> Value {
    names := []string{"value", "reverse", "case_sensitive", "attribute"}
    if !check_args(c, "sort", names) do return Undefined{}
    s := c.state
    items, ok := items_of(c, arg(c, 0, "value"))
    if !ok do return Undefined{}
    attribute := arg(c, 3, "attribute", None{})
    reverse := truthy(arg(c, 1, "reverse", false))
    case_sensitive := truthy(arg(c, 2, "case_sensitive", false))
    if is_none(attribute) {
        sorted, sorted_ok := sort_values(s, items, reverse, case_sensitive, nil)
        if !sorted_ok do return Undefined{}
        return list_value(list_of(sorted))
    }
    parts := strings.split(to_string(attribute), ",")
    keys, kerr := make([]Value, len(items))
    if kerr != nil do return Undefined{}
    for item, i in items {
        key := new_list(len(parts), true)
        if key == nil do return Undefined{}
        for part in parts {
            k := attribute_getter(s, item, strings.trim_space(part), {}, !case_sensitive)
            append(&key.items, k)
        }
        keys[i] = key
    }
    sorted, sorted_ok := sort_values(s, items, reverse, true, keys)
    if !sorted_ok do return Undefined{}
    return list_value(list_of(sorted))
}

@(private="file")
filter_sum :: proc(c: ^Call) -> Value {
    if !check_args(c, "sum", {"iterable", "attribute", "start"}) do return Undefined{}
    s := c.state
    items, ok := items_of(c, arg(c, 0, "iterable"))
    if !ok do return Undefined{}
    attribute := arg(c, 1, "attribute", None{})
    total := arg(c, 2, "start", i64(0))
    for item in items {
        v := attribute_getter(s, item, attribute)
        total = binary_op(s, "+", total, v)
        if s.failed do return Undefined{}
    }
    return total
}

@(private="file")
filter_unique :: proc(c: ^Call) -> Value {
    names := []string{"value", "case_sensitive", "attribute"}
    if !check_args(c, "unique", names) do return Undefined{}
    s := c.state
    items, ok := items_of(c, arg(c, 0, "value"))
    if !ok do return Undefined{}
    attribute := arg(c, 2, "attribute", None{})
    lower := !truthy(arg(c, 1, "case_sensitive", false))
    seen := make([dynamic]Value)
    out := new_list()
    if out == nil do return Undefined{}
    outer: for item in items {
        key := attribute_getter(s, item, attribute, {}, lower)
        for k in seen do if values_equal(k, key) do continue outer
        append(&seen, key)
        append(&out.items, item)
    }
    return out
}

// ---------------------------------------------------------------------------------------
// Sorting: a stable merge sort that reports incomparable values as errors.

@(private="file")
Sorter :: struct {
    s:       ^State,
    keys:    []Value,
    reverse: bool,
    failed:  bool,
}

// sort_values sorts items by keys (the items themselves when keys is nil). Strings are
// compared case-insensitively unless case_sensitive is set.
sort_values :: proc(s: ^State, items: []Value, reverse, case_sensitive: bool,
    keys: []Value) -> ([]Value, bool) {
    k := keys if keys != nil else items
    order, ok := sort_order(s, k, reverse, case_sensitive)
    if !ok do return nil, false
    out, err := make([]Value, len(items))
    if err != nil do return nil, false
    for index, i in order do out[i] = items[index]
    return out, true
}

sort_order :: proc(s: ^State, keys: []Value, reverse, case_sensitive: bool) -> ([]int, bool) {
    k := keys
    if !case_sensitive {
        folded, err := make([]Value, len(keys))
        if err != nil do return nil, false
        for key, i in keys do folded[i] = fold_case(key)
        k = folded
    }
    order, oerr := make([]int, len(k))
    tmp, terr := make([]int, len(k))
    if oerr != nil || terr != nil do return nil, false
    for i in 0 ..< len(order) do order[i] = i
    sorter := Sorter{s = s, keys = k, reverse = reverse}
    merge_sort(&sorter, order, tmp)
    if sorter.failed do return nil, false
    return order, true
}

// fold_case lowercases strings (also inside tuples) for case-insensitive comparisons,
// down to MAX_VALUE_DEPTH (a list may contain itself).
fold_case :: proc(v: Value, depth := 0) -> Value {
    #partial switch x in v {
    case string: return to_lower(x)
    case Markup: return to_lower(string(x))
    case ^List:
        if depth >= MAX_VALUE_DEPTH do return v
        out := new_list(len(x.items), x.tuple)
        if out == nil do return v
        for item in x.items do append(&out.items, fold_case(item, depth + 1))
        return out
    }
    return v
}

@(private="file")
less :: proc(sorter: ^Sorter, a, b: int) -> bool {
    if sorter.failed do return false
    x, y := sorter.keys[a], sorter.keys[b]
    if sorter.reverse do x, y = y, x
    order, ok := compare_values(x, y)
    if !ok {
        sorter.failed = true
        runtime_error(sorter.s, .Type, "'<' not supported between instances of '%s' and '%s'",
            type_name(x), type_name(y))
        return false
    }
    return order == -1
}

@(private="file")
merge_sort :: proc(sorter: ^Sorter, order, tmp: []int) {
    n := len(order)
    if n < 2 do return
    mid := n / 2
    merge_sort(sorter, order[:mid], tmp[:mid])
    merge_sort(sorter, order[mid:], tmp[mid:])
    i, j, k := 0, mid, 0
    for i < mid && j < n {
        if less(sorter, order[j], order[i]) {
            tmp[k] = order[j]
            j += 1
        } else {
            tmp[k] = order[i]
            i += 1
        }
        k += 1
    }
    for i < mid { tmp[k] = order[i]; i += 1; k += 1 }
    for j < n { tmp[k] = order[j]; j += 1; k += 1 }
    copy(order, tmp[:n])
}

@(private="file")
GROUP_FIELDS := [2]string{"grouper", "list"}
