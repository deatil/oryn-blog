#+private
package jinja

import "core:mem"
import "core:strings"

// Templates may store values in lists and dicts that are not the render's own: those
// of the context and the globals, or those an earlier render kept
// (`{% do items.append(x) %}`, `d.update(...)`, `{% set ns.a = x %}`). What a render
// builds lives in its scratch arena, and what a template spells out lives in the
// environment's arena; both go before those containers do.
//
// So a container is owned by the allocator it names (List.allocator, Dict.allocator).
// A render notes each container not its own before storing in it (note_store), and when
// it ends, before its arena is freed, copies what the noted containers hold of either
// arena into each container's own allocator (adopt_stores). Until then the values are
// shared as Jinja shares them: a list appended and then changed shows the change, and
// the copy is of the final state. Shared values are copied once per owner, so they stay
// shared, and cycles stay cycles. A macro, a joiner or a block reference cannot outlive
// its render: its copy is a function that fails with an error saying so.

// note_store notes that the template is about to store values in container. It returns
// false, the render having failed, when it cannot be noted: nothing may be stored then.
note_store :: proc(s: ^State, container: Value) -> bool {
    if s.failed do return false
    p: rawptr
    #partial switch c in container {
    case ^List:
        if c.allocator.procedure == nil do c.allocator = s.caller
        p = c
    case ^Dict:
        if c.allocator.procedure == nil do c.allocator = s.caller
        p = c
    case: return true
    }
    if arena_holds(s.scratch, p) || p in s.stored do return true
    s.stored[p] = container
    if p not_in s.stored {
        if !s.failed do memory_failure(s)
        return false
    }
    return true
}

// adopt_stores copies what the noted containers hold of the render's and the
// environment's memory into the containers' own. A value its container's allocator
// refuses is replaced with Undefined, so that no container keeps a view into freed
// memory, and the render fails with a Memory error.
adopt_stores :: proc(s: ^State) {
    if len(s.stored) == 0 do return
    a := Adoption{local = {s.scratch, s.env.arena}}
    for _, container in s.stored {
        #partial switch c in container {
        case ^List: adopt_slots(&a, c.items[:], c.allocator)
        case ^Dict:
            adopt_slots(&a, c.keys[:], c.allocator)
            adopt_slots(&a, c.values[:], c.allocator)
            if !dict_reindex(c) do a.failed = true
        }
        drain(&a)
    }
    if a.failed && !s.failed {
        runtime_error(s, .Memory, "The values this template stored in the lists and " +
            "dicts it was given need more memory than their allocator gives.")
        set_hint(s, "Store less in them, or give the allocator that made them more memory.")
    }
}

@(private = "file")
Adoption :: struct {
    local:   [2]^Arena,           // memory that ends before the containers do.
    copies:  map[Copy_Key]Value,  // the copy of each local value, per owner.
    pending: [dynamic]Pending,    // copies whose slots still hold local values.
    failed:  bool,                // a copy was refused, and its value replaced.
}

@(private = "file")
Copy_Key :: struct {
    value, owner: rawptr,
}

@(private = "file")
Pending :: struct {
    copy:  Value,
    owner: mem.Allocator,
}

@(private = "file")
is_local :: proc(a: ^Adoption, p: rawptr) -> bool {
    return arena_holds(a.local[0], p) || arena_holds(a.local[1], p)
}

@(private = "file")
adopt_slots :: proc(a: ^Adoption, slots: []Value, owner: mem.Allocator) {
    for &v in slots do v = adopt_value(a, v, owner)
}

// drain fills the slots of the copies made so far, which may make more; a loop, not a
// recursion, so that values nested however deep are copied on a small stack.
@(private = "file")
drain :: proc(a: ^Adoption) {
    for len(a.pending) > 0 {
        p := pop(&a.pending)
        #partial switch x in p.copy {
        case ^List: adopt_slots(a, x.items[:], p.owner)
        case ^Dict:
            adopt_slots(a, x.keys[:], p.owner)
            adopt_slots(a, x.values[:], p.owner)
            if !dict_reindex(x) do a.failed = true
        case ^Callable: x.self = adopt_value(a, x.self, p.owner)
        case ^Loop:
            adopt_slots(a, x.items, p.owner)
            x.last_seen = adopt_value(a, x.last_seen, p.owner)
        case ^Cycler: adopt_slots(a, x.items, p.owner)
        }
    }
}

// adopt_text is s in owner's memory when it is in local memory; ok is false when owner
// refuses the copy.
@(private = "file")
adopt_text :: proc(a: ^Adoption, s: string, owner: mem.Allocator) -> (string, bool) {
    if len(s) == 0 do return "", true
    if !is_local(a, raw_data(s)) do return s, true
    out, err := strings.clone(s, owner)
    if err != nil {
        a.failed = true
        return "", false
    }
    return out, true
}

// adopt_value is v with nothing in local memory: v itself, or its copy in owner's
// memory, whose slots drain fills; Undefined when owner refuses the copy.
@(private = "file")
adopt_value :: proc(a: ^Adoption, v: Value, owner: mem.Allocator) -> Value {
    p: rawptr
    switch x in v {
    case None, bool, i64, f64: return v
    case string:
        text, ok := adopt_text(a, x, owner)
        return text if ok else Value(Undefined{})
    case Markup:
        text, ok := adopt_text(a, string(x), owner)
        return Markup(text) if ok else Value(Undefined{})
    case Undefined:
        name, _ := adopt_text(a, x.name, owner)
        owner_name, _ := adopt_text(a, x.owner, owner)
        hint, _ := adopt_text(a, x.hint, owner)
        return Undefined{name = name, owner = owner_name, hint = hint}
    case ^List: p = x
    case ^Dict: p = x
    case ^Callable: p = x
    case ^Loop: p = x
    case ^Cycler: p = x
    }
    if !is_local(a, p) do return v
    key := Copy_Key{p, owner.data}
    if copy, found := a.copies[key]; found do return copy
    copy := shell(a, v, owner)
    if is_undefined(copy) {
        a.failed = true
        return copy
    }
    a.copies[key] = copy
    _, err := append(&a.pending, Pending{copy, owner})
    if key not_in a.copies || err != nil {
        // Without the table a cycle would be copied forever, and without the pending
        // entry the copy would keep its local slots: the copy is emptied instead.
        a.failed = true
        clear_slots(copy)
    }
    return copy
}

// clear_slots empties a copy whose slots cannot be filled.
@(private = "file")
clear_slots :: proc(v: Value) {
    #partial switch x in v {
    case ^List: clear(&x.items)
    case ^Dict:
        clear(&x.keys)
        clear(&x.values)
        clear(&x.index)
    case ^Callable: x.self = Undefined{}
    case ^Loop:
        for &item in x.items do item = Undefined{}
        x.last_seen = Undefined{}
    case ^Cycler: for &item in x.items do item = Undefined{}
    }
}

// shell copies a local container into owner's memory, its slots still those of the
// original; Undefined when owner refuses it.
@(private = "file")
shell :: proc(a: ^Adoption, v: Value, owner: mem.Allocator) -> Value {
    context.allocator = owner
    #partial switch x in v {
    case ^List:
        l := new(List)
        items, err := make([dynamic]Value, len(x.items))
        if l == nil || err != nil do return Undefined{}
        copy(items[:], x.items[:])
        l^ = List{items = items, tuple = x.tuple, allocator = owner}
        if len(x.fields) > 0 {
            fields, ferr := make([]string, len(x.fields))
            if ferr != nil do return Undefined{}
            for f, i in x.fields do fields[i], _ = adopt_text(a, f, owner)
            l.fields = fields
        }
        return l
    case ^Dict:
        d := new(Dict)
        keys, kerr := make([dynamic]Value, len(x.keys))
        values, verr := make([dynamic]Value, len(x.values))
        if d == nil || kerr != nil || verr != nil do return Undefined{}
        copy(keys[:], x.keys[:])
        copy(values[:], x.values[:])
        name, _ := adopt_text(a, x.name, owner)
        d^ = Dict{keys = keys, values = values, kind = x.kind, name = name, allocator = owner}
        return d
    case ^Callable: return shell_callable(a, x, owner)
    case ^Loop:
        l := new(Loop)
        items, err := make([]Value, len(x.items))
        if l == nil || err != nil do return Undefined{}
        copy(items, x.items)
        l^ = Loop{items = items, index0 = x.index0, depth0 = x.depth0,
            last_seen = x.last_seen, changed = x.changed}
        return l
    case ^Cycler:
        c := new(Cycler)
        items, err := make([]Value, len(x.items))
        if c == nil || err != nil do return Undefined{}
        copy(items, x.items)
        c^ = Cycler{items = items, pos = x.pos}
        return c
    }
    return Undefined{}
}

// shell_callable copies a function. A macro, or a native whose data is the render's
// (a joiner, a block reference), becomes ended_callable under the same name.
@(private = "file")
shell_callable :: proc(a: ^Adoption, x: ^Callable, owner: mem.Allocator) -> Value {
    c := new(Callable, owner)
    if c == nil do return Undefined{}
    name, _ := adopt_text(a, x.name, owner)
    if x.macro != nil || is_local(a, x.user) {
        c^ = Callable{name = name, procedure = ended_callable}
    } else {
        c^ = Callable{name = name, procedure = x.procedure, user = x.user, self = x.self}
    }
    return c
}

// ended_callable is a macro, or a function of a render, kept past its render.
@(private = "file")
ended_callable :: proc(c: ^Call) -> Value {
    fail(c, "%s was made by a render that has ended, so it cannot be called any more.",
        repr(c.name))
    set_hint(c.state, "Call it during the render that makes it. To share a macro between " +
        "templates, import it: {%% from 'macros.html' import %s %%}", c.name)
    return Undefined{}
}
