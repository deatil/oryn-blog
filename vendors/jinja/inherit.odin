#+private
package jinja

import "core:fmt"
import "core:strings"

// render_in_context runs a template (and the templates it extends) in ctx, writing to
// the current output.
render_in_context :: proc(s: ^State, ctx: ^Context, t: ^Compiled) {
    saved_ctx, saved_tpl, saved_escape := s.ctx, s.current, s.autoescape
    defer s.ctx, s.current, s.autoescape = saved_ctx, saved_tpl, saved_escape
    s.ctx, s.current, s.autoescape = ctx, t, t.autoescape
    ctx.template = t
    ctx.top_out = s.out
    register_blocks(ctx, t)
    exec_body(s, ctx.root, t.body)
    for ctx.parent != nil && !s.failed {
        parent := ctx.parent
        ctx.parent = nil
        ctx.template = parent
        s.current, s.autoescape = parent, parent.autoescape
        exec_body(s, ctx.root, parent.body)
    }
}

new_context :: proc(root: ^Scope) -> ^Context {
    ctx := new(Context)
    if ctx != nil do ctx.root = root // nil: refused, and the render stopped.
    return ctx
}

register_blocks :: #force_no_inline proc(ctx: ^Context, t: ^Compiled) {
    for name, node in t.blocks {
        refs, ok := &ctx.blocks[name]
        if !ok {
            ctx.blocks[name] = make([dynamic]Block_Ref)
            refs, ok = &ctx.blocks[name]
            if !ok do continue // refused, and the render stopped.
        }
        append(refs, Block_Ref{node = node, template = t})
    }
}

// load_for_render loads a template by name while rendering (parsed into the
// environment's memory so it can be cached).
load_for_render :: proc(s: ^State, name: string) -> (^Compiled, Error) {
    return load_compiled(s.env, name)
}

template_names :: proc(s: ^State, v: Value) -> ([]string, bool) {
    #partial switch x in v {
    case string, Markup:
        names, err := make([]string, 1)
        if err != nil do return nil, false
        names[0], _ = key_string(v)
        return names, true
    case ^List:
        names := make([dynamic]string, 0, len(x.items))
        for item in x.items do append(&names, to_string(item))
        return names[:], true
    case Undefined:
        undefined_error(s, x)
        return nil, false
    }
    runtime_error(s, .Type, "template name must be a string, not %s", type_name(v))
    return nil, false
}

// select_template loads the first template of names that exists.
select_template :: proc(s: ^State, names: []string, ignore_missing: bool) -> ^Compiled {
    for name in names {
        t, err := load_for_render(s, name)
        if err.kind == .None do return t
        if err.kind != .Not_Found {
            if !s.failed {
                s.failed = true
                s.err = err
            }
            return nil
        }
    }
    if ignore_missing do return nil
    if len(names) == 1 {
        runtime_error(s, .Not_Found, "template %s not found", repr(names[0]))
    } else {
        runtime_error(s, .Not_Found, "none of the templates given were found: %s",
            strings.join(names, ", "))
    }
    return nil
}

exec_extends :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    ctx := s.ctx
    if ctx.parent != nil {
        runtime_error(s, .Runtime, "extended multiple times")
        return .Error
    }
    parent := find_template(s, scope, n, false)
    if parent == nil do return .Error
    ctx.parent = parent
    register_blocks(ctx, parent)
    return .Normal
}

// find_template finds the template that an extends, include or import tag names, or nil
// when there is none (an error unless ignore_missing).
find_template :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node,
    ignore_missing: bool) -> ^Compiled {
    v := eval(s, scope, n.a)
    if s.failed do return nil
    names, ok := template_names(s, v)
    if !ok do return nil
    return select_template(s, names, ignore_missing)
}

// ---------------------------------------------------------------------------------------
// Blocks

exec_block_tag :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    ctx := s.ctx
    if ctx.parent != nil && s.out == ctx.top_out do return .Normal
    parent_scope := scope if .Scoped in n.flags else ctx.root
    render_block(s, n.text, 0, parent_scope)
    return .Normal
}

Block_Reference :: struct {
    name:  string,
    level: int,
    scope: ^Scope,
    ctx:   ^Context,
}

render_block :: proc(s: ^State, name: string, level: int, parent_scope: ^Scope) {
    ref, inner := block_scope(s, name, level, parent_scope)
    if inner == nil do return
    saved_tpl, saved_escape := s.current, s.autoescape
    s.current, s.autoescape = ref.template, ref.template.autoescape
    exec_body(s, inner, ref.node.body)
    s.current, s.autoescape = saved_tpl, saved_escape
}

// block_scope finds level of the block called name and makes the scope its body runs
// in, where super() renders the next level.
block_scope :: #force_no_inline proc(s: ^State, name: string, level: int,
    parent_scope: ^Scope) -> (Block_Ref, ^Scope) {
    refs := s.ctx.blocks[name]
    if level >= len(refs) {
        runtime_error(s, .Runtime, "there is no parent block called %s.", repr(name))
        return {}, nil
    }
    ref := refs[level]
    if .Required in ref.node.flags {
        runtime_error(s, .Runtime, "Required block %s not found.", repr(name))
        return {}, nil
    }
    inner := new_scope(parent_scope)
    if inner == nil do return {}, nil
    if level + 1 < len(refs) {
        r := new(Block_Reference)
        if r == nil do return {}, nil
        r^ = Block_Reference{name = name, level = level + 1, scope = parent_scope, ctx = s.ctx}
        inner.vars["super"] = function("super", call_block_reference, r)
    } else {
        inner.vars["super"] = Undefined{name = "super", hint = fmt.aprintf(
            "there is no parent block called %s.", repr(name))}
    }
    return ref, inner
}

// call_block_reference renders a block into a string: super() and self.name().
call_block_reference :: proc(c: ^Call) -> Value {
    s := c.state
    r := (^Block_Reference)(c.user)
    if !enter_depth(s) do return Undefined{}
    defer s.depth -= 1
    saved_ctx := s.ctx
    s.ctx = r.ctx
    saved := begin_capture(s)
    render_block(s, r.name, r.level, r.scope)
    text := end_capture(s, saved)
    s.ctx = saved_ctx
    return captured(s, text)
}

// self_reference builds the `self` object: one callable per block.
self_reference :: proc(s: ^State) -> Value {
    d := new_dict(.Module)
    if d == nil do return Undefined{}
    d.name = s.ctx.template.name if s.ctx.template != nil else ""
    for name in s.ctx.blocks {
        r := new(Block_Reference)
        if r == nil do return Undefined{}
        r^ = Block_Reference{name = name, level = 0, scope = s.ctx.root, ctx = s.ctx}
        dict_set(d, name, function(name, call_block_reference, r))
    }
    return d
}

// ---------------------------------------------------------------------------------------
// Include and import

exec_include :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    if s.ctx.parent != nil && s.out == s.ctx.top_out do return .Normal
    t := find_template(s, scope, n, .Ignore_Missing in n.flags)
    if t == nil || !enter_depth(s) do return .Normal // missing and ignored, or failed
    defer s.depth -= 1
    ctx := template_context(scope, n)
    if ctx == nil do return .Error
    render_in_context(s, ctx, t)
    return .Normal
}

// template_context is the context an included or imported template renders in, which
// sees the includer's variables when n says "with context".
template_context :: proc(scope: ^Scope, n: ^Node) -> ^Context {
    root := new_scope(scope if .With_Context in n.flags else nil)
    if root == nil do return nil
    return new_context(root)
}

exec_import :: proc(s: ^State, scope: ^Scope, n: ^Node) -> Flow {
    t := find_template(s, scope, n, false)
    if t == nil || !enter_depth(s) do return .Error
    defer s.depth -= 1
    ctx := template_context(scope, n)
    if ctx == nil do return .Error
    saved := begin_capture(s)
    render_in_context(s, ctx, t)
    end_capture(s, saved)
    if !s.failed do bind_module(s, scope, n, t, ctx.root)
    return .Normal
}

// bind_module makes the module an import tag imports from the variables an imported
// template defined (root), and binds it, or the names imported from it, in scope.
bind_module :: #force_no_inline proc(s: ^State, scope: ^Scope, n: ^Node, t: ^Compiled,
    root: ^Scope) {
    module := new_dict(.Module)
    if module == nil do return
    module.name = t.name
    for key, value in root.vars {
        if !strings.has_prefix(key, "_") do dict_set(module, key, value)
    }
    if n.kind == .Import {
        scope.vars[n.text] = module
        return
    }
    for name, i in n.names {
        value, found := dict_get(module, name)
        if !found {
            value = Undefined{name = name, hint = fmt.aprintf(
                "the template %s (imported on line %d) does not export the requested name %s",
                repr(t.name), n.line, repr(name))}
        }
        scope.vars[n.aliases[i]] = value
    }
}
