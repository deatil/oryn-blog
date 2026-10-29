package jinja

import "core:fmt"
import "core:mem"
import "core:strings"

Undefined_Mode :: enum u8 {
    Default,   // renders as "", fails on attribute access, calls and arithmetic
    Strict,    // fails on every use except `is defined` and |default
    Chainable, // like Default, but attributes of undefined are undefined too
    Debug,     // like Default, but renders as {{ name }}
}

Options :: struct {
    autoescape:            bool,
    // When set, templates whose names end with one of these (".html") autoescape and
    // others do not, like select_autoescape(); `autoescape` is then ignored.
    autoescape_extensions: []string,
    trim_blocks:           bool,
    lstrip_blocks:         bool,
    keep_trailing_newline: bool,
    undefined:             Undefined_Mode,
    loader:                Loader,
    max_recursion:         int, // nested macros, includes and recursive loops; 0 means 200
    max_iterations:        int, // loop iterations per render; 0 means 10,000,000
    // Bytes per render, and per value a render builds (a repetition, padding, a join),
    // checked before the value is allocated; 0 means unlimited.
    max_output:            int,
    max_nesting:           int, // how deep template syntax nests; 0 means 100
    stack_bytes:           int, // machine stack parsing and rendering may use; 0 means 512 KiB
    random_seed:           u64, // seeds |random and lipsum(); renders are deterministic
}

@(private)
Registered :: struct {
    procedure: Native,
    user:      rawptr,
}

// Environment holds options, filters, tests, globals and the template cache. Its own
// memory (parsed templates, tables) comes from an arena freed by destroy_environment.
Environment :: struct {
    options:       Options,
    filters:       map[string]Registered,
    tests:         map[string]Registered,
    globals:       map[string]Value,
    cache:         map[string]^Compiled,
    arena:         ^Arena,
    allocator:     mem.Allocator,
    backing:       mem.Allocator,
    stack:         Stack_Guard, // started by the outermost call on the environment
    // Set when the environment's memory could not hold its tables: every template it
    // parses then fails with a Memory error.
    out_of_memory: bool,
}

// Template is a handle to a parsed template.
Template :: struct {
    env:      ^Environment,
    compiled: ^Compiled,
    name:     string,
}

// create_environment makes an environment with options, zero fields taking their
// defaults. It keeps its own arena, backed by context.allocator, for parsed templates
// and registrations; destroy_environment frees it. When that memory cannot hold the
// environment's tables, out_of_memory is set and every parse fails with a Memory error.
create_environment :: proc(options: Options = {}) -> Environment {
    env := Environment{options = options, backing = context.allocator}
    if env.options.max_recursion <= 0 do env.options.max_recursion = DEFAULT_MAX_RECURSION
    if env.options.max_iterations <= 0 do env.options.max_iterations = 10_000_000
    if env.options.max_nesting <= 0 do env.options.max_nesting = DEFAULT_MAX_NESTING
    arena, err := new(Arena)
    if err != nil {
        env.allocator, env.out_of_memory = refusing_allocator(), true
        return env
    }
    arena_init(arena, context.allocator)
    env.arena = arena
    // The tables keep the allocator they were made with, so the guard that watches the
    // setup lives in the arena, as long as they do.
    guard, gerr := new(Guard, arena_allocator(arena))
    if gerr != nil {
        env.allocator, env.out_of_memory = refusing_allocator(), true
        return env
    }
    guard^ = Guard{backing = arena_allocator(arena), doing = "Setting up"}
    env.allocator = guard_allocator(guard)
    context.allocator = env.allocator
    env.filters = make(map[string]Registered)
    env.tests = make(map[string]Registered)
    env.globals = make(map[string]Value)
    env.cache = make(map[string]^Compiled)
    register_filters(&env)
    register_tests(&env)
    register_globals(&env)
    env.out_of_memory = guard.refused > 0
    return env
}

// destroy_environment frees the environment's arena, with every template parsed in it,
// and its loader's state (Loader.destroy).
destroy_environment :: proc(env: ^Environment) {
    if env.options.loader.destroy != nil do env.options.loader.destroy(env.options.loader.user)
    if env.arena != nil {
        arena_destroy(env.arena)
        mem.free_with_size(env.arena, size_of(Arena), env.backing)
    }
    env^ = {}
}

// add_filter registers a filter: call.args[0] is the filtered value. The environment
// copies name into its arena; user is borrowed until destroy_environment.
add_filter :: proc(env: ^Environment, name: string, procedure: Native, user: rawptr = nil) {
    if key, err := strings.clone(name, env.allocator); err == nil {
        env.filters[key] = Registered{procedure, user}
    }
}

// add_test registers a test: call.args[0] is the tested value; return a bool. The
// environment copies name into its arena; user is borrowed until destroy_environment.
add_test :: proc(env: ^Environment, name: string, procedure: Native, user: rawptr = nil) {
    if key, err := strings.clone(name, env.allocator); err == nil {
        env.tests[key] = Registered{procedure, user}
    }
}

// add_global makes a value visible to every template. The environment copies name into
// its arena; the value is borrowed and must outlive renders.
add_global :: proc(env: ^Environment, name: string, value: Value) {
    if key, err := strings.clone(name, env.allocator); err == nil do env.globals[key] = value
}

// add_function registers a native procedure as a global function, allocated in the
// environment's arena; user is borrowed until destroy_environment.
add_function :: proc(env: ^Environment, name: string, procedure: Native, user: rawptr = nil) {
    context.allocator = env.allocator
    add_global(env, name, function(strings.clone(name), procedure, user))
}

// clear_cache forgets parsed templates so the next load reads them again.
clear_cache :: proc(env: ^Environment) {
    clear(&env.cache)
}

@(private)
template_autoescape :: proc(env: ^Environment, name: string) -> bool {
    if len(env.options.autoescape_extensions) == 0 do return env.options.autoescape
    for ext in env.options.autoescape_extensions {
        if strings.has_suffix(name, ext) do return true
    }
    return false
}

@(private)
lex_options :: proc(env: ^Environment) -> Lex_Options {
    return Lex_Options{trim_blocks = env.options.trim_blocks,
        lstrip_blocks = env.options.lstrip_blocks,
        keep_trailing_newline = env.options.keep_trailing_newline}
}

@(private)
parse_memory :: proc(name: string) -> Error {
    return Error{kind = .Memory, template = name, message = MEMORY_MESSAGE,
        hint = MEMORY_HINT_PARSE}
}

// parse_guarded parses source into the environment's arena under a guard: a refusal
// is a Memory error, whose message is copied into the arena (keep_memory_message).
@(private)
parse_guarded :: proc(env: ^Environment, source, name: string) -> (^Compiled, Error) {
    if env.out_of_memory do return nil, parse_memory(name)
    guard := Guard{backing = env.allocator, doing = "Parsing"}
    context.allocator = guard_allocator(&guard)
    t, err := parse(env, source, name, &guard)
    return t, keep_memory_message(err, env.allocator)
}

// load_compiled finds a template in the cache or loads, parses and caches it.
@(private)
load_compiled :: proc(env: ^Environment, name: string) -> (^Compiled, Error) {
    if t, ok := env.cache[name]; ok do return t, {}
    if env.options.loader.procedure == nil {
        return nil, Error{kind = .Not_Found, template = name,
            message = fmt.aprintf("template %s not found (no loader)", repr(name))}
    }
    source, found := env.options.loader.procedure(env.options.loader.user, name,
        env.allocator)
    if !found {
        return nil, Error{kind = .Not_Found, template = name,
            message = fmt.aprintf("template %s not found", repr(name))}
    }
    key, kerr := strings.clone(name, env.allocator)
    if kerr != nil do return nil, parse_memory(name)
    t, err := parse_guarded(env, source, key)
    if err.kind != .None do return nil, err
    t.autoescape = template_autoescape(env, name)
    env.cache[key] = t
    return t, {}
}

// load_template loads a template through the environment's loader, cached in the
// environment's arena until destroy_environment (or clear_cache). An error is allocated
// with context.allocator; the caller frees it with destroy_error.
load_template :: proc(env: ^Environment, name: string) -> (Template, Error) {
    started := begin_stack(env)
    defer end_stack(env, started)
    t, err := load_compiled(env, name)
    if err.kind != .None do return {}, clone_error(err, context.allocator)
    return Template{env = env, compiled = t, name = t.name}, {}
}

// parse_template parses source directly (not cached; not visible to includes). The
// template lives in the environment's arena, which copies source; an error is allocated
// with context.allocator (destroy_error).
parse_template :: proc(env: ^Environment, name, source: string) -> (Template, Error) {
    started := begin_stack(env)
    defer end_stack(env, started)
    caller := context.allocator
    own_source, serr := strings.clone(source, env.allocator)
    own_name, nerr := strings.clone(name, env.allocator)
    if serr != nil || nerr != nil do return {}, clone_error(parse_memory(name), caller)
    t, err := parse_guarded(env, own_source, own_name)
    if err.kind != .None do return {}, clone_error(err, caller)
    t.autoescape = template_autoescape(env, name)
    return Template{env = env, compiled = t, name = t.name}, {}
}

// add_template parses source and caches it under name, so that extends, include and
// import find it without a loader. An error is allocated with context.allocator
// (destroy_error).
add_template :: proc(env: ^Environment, name, source: string) -> Error {
    t, err := parse_template(env, name, source)
    if err.kind != .None do return err
    env.cache[t.name] = t.compiled
    return {}
}

// render renders a template with ctx (a dict value, or Undefined for none). The result
// and any error message are allocated with context.allocator; everything else lives in
// a scratch arena freed before returning. When that allocator refuses memory the render
// stops with a Memory error at the line it was rendering.
render :: proc(t: ^Template, ctx: Value = {}) -> (string, Error) {
    if t.compiled == nil do return "", Error{kind = .Runtime, message = "template not loaded"}
    started := begin_stack(t.env)
    defer end_stack(t.env, started)
    caller := context.allocator
    scratch: Arena
    arena_init(&scratch, caller)
    defer arena_destroy(&scratch)
    guard := Guard{backing = arena_allocator(&scratch), doing = "Rendering"}
    context.allocator = guard_allocator(&guard)
    text, err := render_compiled(t.env, t.compiled, ctx, &guard, &scratch, caller)
    return finish_render(t.compiled.name, text, err, caller)
}

// render_source parses and renders source in one call (nothing is cached), in a scratch
// arena it frees before returning. The output, and an error, are allocated with
// context.allocator; the caller owns them.
render_source :: proc(env: ^Environment, source: string, ctx: Value = {},
    name := "<template>") -> (string, Error) {
    started := begin_stack(env)
    defer end_stack(env, started)
    caller := context.allocator
    scratch: Arena
    arena_init(&scratch, caller)
    defer arena_destroy(&scratch)
    guard := Guard{backing = arena_allocator(&scratch), doing = "Parsing"}
    context.allocator = guard_allocator(&guard)
    t, err := parse(env, source, name, &guard)
    if err.kind != .None do return "", clone_error(err, caller)
    t.autoescape = template_autoescape(env, name)
    guard.doing = "Rendering"
    text, rerr := render_compiled(env, t, ctx, &guard, &scratch, caller)
    return finish_render(name, text, rerr, caller)
}

// finish_render copies a render's output, or its error, into the caller's allocator
// before the render's arena goes; output the caller's memory cannot hold is a Memory
// error.
@(private)
finish_render :: proc(name, text: string, err: Error, caller: mem.Allocator) -> (string,
    Error) {
    if err.kind != .None do return "", clone_error(err, caller)
    out, cerr := strings.clone(text, caller)
    if cerr == nil do return out, {}
    return "", clone_error(Error{kind = .Memory, template = name,
        message = "The rendered output is more than the memory it may use can keep.",
        hint = MEMORY_HINT_RENDER}, caller)
}

@(private)
new_state :: proc(env: ^Environment, out: ^strings.Builder, guard: ^Guard) -> State {
    seed := env.options.random_seed
    if seed == 0 do seed = 0x853c49e6748fea9b
    return State{env = env, out = out, rng = seed, guard = guard}
}

// render_compiled renders t under the render's guard. scratch is the arena the guard
// takes from, freed after the render, and caller the allocator of the call that renders.
// However the render ends, the lists and dicts not its own that it stored values in get
// their copies first (adopt_stores).
@(private)
render_compiled :: proc(env: ^Environment, t: ^Compiled, ctx: Value, guard: ^Guard,
    scratch: ^Arena, caller: mem.Allocator) -> (string, Error) {
    out := strings.builder_make()
    s := new_state(env, &out, guard)
    s.scratch, s.caller = scratch, caller
    guard.state = &s
    defer guard.state = nil
    outer := rendering
    rendering = &s
    defer rendering = outer
    s.current = t
    root := new_scope(nil)
    render_ctx := new_context(root)
    if root == nil || render_ctx == nil do return "", s.err
    #partial switch d in ctx {
    case ^Dict: root.dict = d
    case Undefined:
    case:
        return "", Error{kind = .Type, template = t.name, message = "context must be a dict"}
    }
    render_in_context(&s, render_ctx, t)
    adopt_stores(&s)
    if s.failed do return "", s.err
    return strings.to_string(out), {}
}

// rendering is the render running on this thread, the innermost one; see render_position.
@(private, thread_local)
rendering: ^State

// render_position is where the render running on this thread is: its template's name,
// the line being rendered, and that line's text; false when none runs. A host asked
// about a render while it runs, as when the render's allocator asks what to do about
// memory, names the place with it. The strings borrow the template.
render_position :: proc() -> (template: string, line: int, excerpt: string, ok: bool) {
    s := rendering
    if s == nil || s.current == nil do return "", 0, "", false
    return s.current.name, s.line, source_line(s.current.source, s.line), true
}

// evaluate evaluates one expression against ctx (Jinja's compile_expression). The value
// and an error's message are allocated with context.allocator, the caller's; the lists
// and dicts of the value grow through a small allocator record kept there too. When
// that allocator refuses memory the error is a Memory error.
evaluate :: proc(env: ^Environment, expression: string, ctx: Value = {}) -> (Value, Error) {
    started := begin_stack(env)
    defer end_stack(env, started)
    caller := context.allocator
    guard, gerr := new(Guard, caller)
    if gerr != nil do return Undefined{}, clone_error(parse_memory("<expression>"), caller)
    guard^ = Guard{backing = caller, doing = "Parsing"}
    context.allocator = guard_allocator(guard)
    n, err := parse_expression_source(env, expression, "<expression>", guard)
    if err.kind != .None do return Undefined{}, keep_memory_message(err, caller)
    out := strings.builder_make()
    guard.doing = "Rendering"
    s := new_state(env, &out, guard)
    s.caller = caller
    guard.state = &s
    defer guard.state = nil
    root := new_scope(nil)
    if root != nil {
        if d, ok := ctx.(^Dict); ok do root.dict = d
        s.ctx = new_context(root)
    }
    if s.ctx == nil do return Undefined{}, keep_memory_message(s.err, caller)
    s.autoescape = env.options.autoescape
    v := eval(&s, root, n)
    adopt_stores(&s)
    if s.failed do return Undefined{}, keep_memory_message(s.err, caller)
    return v, {}
}
