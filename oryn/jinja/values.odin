package jinja

import "base:intrinsics"
import "core:mem"
import "core:strings"

// Undefined is what a missing variable, attribute or item evaluates to. The fields only
// feed the error message produced when the value is used in a way Jinja forbids.
Undefined :: struct {
    name:  string, // the missing variable or attribute
    owner: string, // "dict object" when an attribute or item was missing
    hint:  string, // a complete message that replaces the generated one
}

// None is Jinja's none / None.
None :: struct {}

// Markup is a string that is already safe HTML: autoescaping leaves it alone.
Markup :: distinct string

// Value is every value a template can see. The zero value is Undefined.
Value :: union #no_nil {
    Undefined,
    None,
    bool,
    i64,
    f64,
    string,
    Markup,
    ^List,
    ^Dict,
    ^Callable,
    ^Loop,
    ^Cycler,
}

// List is a list, or a tuple when tuple is set. fields names the items of a named tuple
// (the groups made by groupby), which can then also be read as attributes. allocator
// owns the list: its items grow there, and what a template stores in the list is copied
// there when the render ends (see Memory in the README).
List :: struct {
    items:     [dynamic]Value,
    tuple:     bool,
    fields:    []string,
    allocator: mem.Allocator,
}

Dict_Kind :: enum u8 {
    Dict,      // a plain dict
    Namespace, // namespace(): the only object whose attributes templates may assign
    Module,    // the result of {% import %}: exported macros and variables
}

// Dict is an insertion-ordered dictionary. String keys are indexed; other keys are
// compared with Python equality (1 == 1.0 == True). allocator owns the dict as it owns
// a List.
Dict :: struct {
    keys:      [dynamic]Value,
    values:    [dynamic]Value,
    index:     map[string]int,
    kind:      Dict_Kind,
    name:      string, // the template name of a module
    allocator: mem.Allocator,
}

// Keyword is one keyword argument of a call.
Keyword :: struct {
    name:  string,
    value: Value,
}

// Call is what a native procedure receives: the positional and keyword arguments (for a
// filter or test, args[0] is the value being filtered or tested), the user pointer given
// at registration, and the receiver of a bound method.
Call :: struct {
    args:   []Value,
    kwargs: []Keyword,
    user:   rawptr,
    self:   Value,
    name:   string,
    state:  ^State,
}

// Native is the one signature of every filter, test, global function and method written
// in Odin. Report errors with fail(call, ...) and return anything.
Native :: #type proc(call: ^Call) -> Value

// Callable is a function value: a native procedure (optionally bound to self) or a macro.
Callable :: struct {
    name:      string,
    procedure: Native,
    user:      rawptr,
    self:      Value,
    macro:     ^Macro,
}

// Loop is the special `loop` variable of a for loop.
Loop :: struct {
    items:     []Value,
    index0:    int,
    depth0:    int,
    last_seen: Value, // for loop.changed()
    changed:   bool,  // whether changed() was called before
    recurse:   ^Recursion, // set in a recursive loop
}

// Cycler is the object made by the cycler() global.
Cycler :: struct {
    items: []Value,
    pos:   int,
}

// ---------------------------------------------------------------------------------------
// Building values

// str makes a string value; the value borrows s.
str :: proc(s: string) -> Value { return s }
// integer makes an integer value (int would shadow Odin's type).
integer :: proc(i: i64) -> Value { return i }
// float makes a floating-point value.
float :: proc(f: f64) -> Value { return f }
// boolean makes a boolean value.
boolean :: proc(b: bool) -> Value { return b }
// none makes Python's None.
none :: proc() -> Value { return None{} }
// undefined makes an undefined value; name, borrowed, is what error messages call it.
undefined :: proc(name := "") -> Value { return Undefined{name = name} }
// markup makes a string value that is safe HTML, which autoescaping leaves alone; the
// value borrows s.
markup :: proc(s: string) -> Value { return Markup(s) }

// list makes a list holding the given values, allocated with context.allocator; when it
// refuses the memory, the result is Undefined.
list :: proc(items: ..Value) -> Value {
    return list_value(list_of(items))
}

// tuple makes a tuple holding the given values, allocated as list allocates.
tuple :: proc(items: ..Value) -> Value {
    return list_value(list_of(items, true))
}

// dict makes an empty dict, allocated with context.allocator (Undefined when it refuses
// the memory); fill it with set().
dict :: proc() -> Value {
    if d := new_dict(.Dict); d != nil do return d
    return Undefined{}
}

// function wraps a native procedure as a callable value for globals or context data,
// allocated with context.allocator (Undefined when it refuses the memory); name and user
// are borrowed.
function :: proc(name: string, procedure: Native, user: rawptr = nil) -> Value {
    c := new(Callable)
    if c == nil do return Undefined{}
    c^ = Callable{name = name, procedure = procedure, user = user}
    return c
}

// set stores value under the string key in a dict value, growing it with the dict's own
// allocator; nothing happens when d is not a dict or that allocator refuses.
set :: proc(d: Value, key: string, value: Value) {
    if p, ok := d.(^Dict); ok do dict_set(p, key, value)
}

// set_key stores value under any key in a dict value.
set_key :: proc(d: Value, key: Value, value: Value) {
    if p, ok := d.(^Dict); ok do dict_set(p, key, value)
}

// get reads a string key from a dict value; missing keys give Undefined.
get :: proc(d: Value, key: string) -> Value {
    if p, ok := d.(^Dict); ok {
        if v, found := dict_get(p, key); found do return v
    }
    return Undefined{name = key}
}

// keys returns the string keys of a dict value, in insertion order, in a slice allocated
// with allocator that the caller owns; the keys borrow the dict.
keys :: proc(d: Value, allocator := context.allocator) -> []string {
    p, ok := d.(^Dict)
    if !ok do return nil
    out := make([dynamic]string, 0, len(p.keys), allocator)
    for k in p.keys do if s, is_string := k.(string); is_string do append(&out, s)
    return out[:]
}

// append_value adds values to the end of a list value, growing it with the list's own
// allocator; nothing happens when l is not a list or that allocator refuses.
append_value :: proc(l: Value, items: ..Value) {
    if p, ok := l.(^List); ok do list_append(p, items)
}

// length is the number of items of a list or dict, or of runes of a string.
length :: proc(v: Value) -> int {
    #partial switch x in v {
    case string: return strings.rune_count(x)
    case Markup: return strings.rune_count(string(x))
    case ^List: return len(x.items)
    case ^Dict: return len(x.keys)
    }
    return 0
}

// ---------------------------------------------------------------------------------------
// Internal helpers

// new_dict, new_list and list_of return nil when memory is refused (the render's guard
// has stopped it): check before using the result, or wrap it with list_value.
@(private)
new_dict :: proc(kind: Dict_Kind) -> ^Dict {
    d := new(Dict)
    if d != nil do d.kind, d.allocator = kind, context.allocator
    return d
}

// new_list makes a list with room for capacity items: a list whose items cannot be
// held is refused as a whole (nil), so that appending them later cannot fail halfway.
@(private)
new_list :: proc(capacity := 0, tuple := false) -> ^List {
    l := new(List)
    if l == nil do return nil
    items, err := make([dynamic]Value, 0, capacity)
    if err != nil do return nil
    l.items, l.tuple, l.allocator = items, tuple, context.allocator
    return l
}

// owned_by is the allocator a container names as its owner, or context.allocator for a
// container that names none (a List{} or Dict{} made by hand).
@(private)
owned_by :: proc(owner: mem.Allocator) -> mem.Allocator {
    return owner if owner.procedure != nil else context.allocator
}

// list_append appends items to l in l's own memory, all of them or none (false). items
// may be l's own: they are read from where the growth moved them.
@(private)
list_append :: proc(l: ^List, items: []Value) -> bool {
    if len(items) == 0 do return true
    context.allocator = owned_by(l.allocator)
    start := -1 // where items begin in l's own storage, when they are l's.
    base, at := uintptr(raw_data(l.items)), uintptr(raw_data(items))
    if len(l.items) > 0 && at >= base && at < base + uintptr(len(l.items) * size_of(Value)) {
        start = int(at - base) / size_of(Value)
    }
    total, over := intrinsics.overflow_add(len(l.items), len(items))
    if over do return false
    if total > cap(l.items) {
        room := max(total, cap(l.items) * 2 if cap(l.items) < max(int) / 2 else total)
        if err := reserve(&l.items, room); err != nil || cap(l.items) < total do return false
    }
    append(&l.items, ..(items if start < 0 else l.items[start:][:len(items)]))
    return true
}

@(private)
list_of :: proc(items: []Value, tuple := false) -> ^List {
    l := new_list(len(items), tuple)
    if l != nil do append(&l.items, ..items)
    return l
}

// list_value is l as a value, or Undefined when l is nil: a value never holds nil.
@(private)
list_value :: proc(l: ^List) -> Value {
    if l == nil do return Undefined{}
    return l
}

@(private)
dict_value :: proc(d: ^Dict) -> Value {
    if d == nil do return Undefined{}
    return d
}

// key_string returns the index key of string-like keys.
@(private)
key_string :: proc(key: Value) -> (string, bool) {
    #partial switch k in key {
    case string: return k, true
    case Markup: return string(k), true
    }
    return "", false
}

@(private)
dict_find :: proc(d: ^Dict, key: Value) -> int {
    if s, ok := key_string(key); ok {
        if i, found := d.index[s]; found do return i
        return -1
    }
    for k, i in d.keys {
        if _, is_str := key_string(k); is_str do continue
        if values_equal(k, key) do return i
    }
    return -1
}

@(private)
dict_get :: proc(d: ^Dict, key: Value) -> (Value, bool) {
    i := dict_find(d, key)
    if i < 0 do return Undefined{}, false
    return d.values[i], true
}

// dict_set adds or replaces an entry. Keys, values, and the index stay in step: an
// entry whose memory is refused is not added at all.
@(private)
dict_set :: proc(d: ^Dict, key: Value, value: Value) {
    if d == nil do return
    context.allocator = owned_by(d.allocator)
    i := dict_find(d, key)
    if i >= 0 {
        d.values[i] = value
        return
    }
    n := len(d.keys)
    if _, err := append(&d.keys, key); err != nil do return
    if _, err := append(&d.values, value); err != nil {
        resize(&d.keys, n)
        return
    }
    if s, ok := key_string(key); ok {
        d.index[s] = n
        if s not_in d.index {
            resize(&d.keys, n)
            resize(&d.values, n)
        }
    }
}

@(private)
dict_remove :: proc(d: ^Dict, key: Value) -> (Value, bool) {
    i := dict_find(d, key)
    if i < 0 do return Undefined{}, false
    v := d.values[i]
    ordered_remove(&d.keys, i)
    ordered_remove(&d.values, i)
    dict_reindex(d)
    return v, true
}

// dict_reindex builds the index of d's string keys again, in d's own memory; false when
// that memory refuses it (the dict then holds no entries). An index cleared and filled
// with no more keys than it had takes nothing new.
@(private)
dict_reindex :: proc(d: ^Dict) -> bool {
    context.allocator = owned_by(d.allocator)
    clear(&d.index)
    for k, j in d.keys {
        s, ok := key_string(k)
        if !ok do continue
        d.index[s] = j
        if s not_in d.index {
            clear(&d.keys)
            clear(&d.values)
            clear(&d.index)
            return false
        }
    }
    return true
}

@(private)
dict_copy :: proc(d: ^Dict, kind: Dict_Kind = .Dict) -> ^Dict {
    out := new_dict(kind)
    if out == nil do return nil
    for k, i in d.keys do dict_set(out, k, d.values[i])
    return out
}

// is_undefined reports an undefined value.
is_undefined :: proc(v: Value) -> bool {
    _, ok := v.(Undefined)
    return ok
}

// is_none reports None.
is_none :: proc(v: Value) -> bool {
    _, ok := v.(None)
    return ok
}

@(private)
is_stringish :: proc(v: Value) -> bool {
    #partial switch _ in v {
    case string, Markup: return true
    }
    return false
}

// is_markup reports a safe-HTML string.
is_markup :: proc(v: Value) -> bool {
    _, ok := v.(Markup)
    return ok
}

// type_name is the Python type name used in Jinja's error messages.
type_name :: proc(v: Value) -> string {
    switch x in v {
    case Undefined: return "Undefined"
    case None: return "NoneType"
    case bool: return "bool"
    case i64: return "int"
    case f64: return "float"
    case string: return "str"
    case Markup: return "Markup"
    case ^List: return "tuple" if x.tuple else "list"
    case ^Dict:
        switch x.kind {
        case .Dict: return "dict"
        case .Namespace: return "Namespace"
        case .Module: return "TemplateModule"
        }
    case ^Callable:
        if x.macro != nil do return "Macro"
        return "builtin_function_or_method" if is_undefined(x.self) else "method"
    case ^Loop: return "LoopContext"
    case ^Cycler: return "Cycler"
    }
    return "object"
}

// object_name is how Jinja names a value that lacks an attribute: "'dict object'".
@(private)
object_name :: proc(v: Value) -> string {
    if is_none(v) do return "None"
    return strings.concatenate({type_name(v), " object"})
}
