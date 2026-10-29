#+private
package jinja

// The parser and the renderer are recursive descent: a nested bracket, operator chain or
// tag is a nested call, and so is a macro call, an include or a recursive loop. Three
// limits keep hostile templates from overflowing the thread's stack:
//
// - Options.max_nesting bounds how deep a template's syntax nests (brackets, unary and
//   binary operator chains, filters, attribute chains, elif chains and nested tags), so
//   every tree the parser builds, and every walk over it, has a bounded depth. It is the
//   same on every platform: a template that parses on one parses on all.
// - Options.max_recursion bounds how deep macro calls, includes, blocks and recursive
//   loops nest while rendering. It too is the same on every platform, and it is the limit
//   an ordinary template meets: the default stack budget holds DEFAULT_MAX_RECURSION
//   levels with room to spare (see below).
// - Options.stack_bytes bounds the machine stack itself. The first public call on an
//   environment (render, load_template, evaluate, ...) records its frame address; the
//   parser and the evaluator stop with a Limit error once the stack has grown more than
//   stack_bytes below it. This is the backstop for what depth counts cannot see, such as
//   max_recursion macros each evaluating deeply nested expressions, whatever the
//   compiler's frame sizes.
//
// For max_nesting and max_recursion to come first, a level of nesting or recursion must
// cost little stack at every optimization level. A level passes through a handful of
// procedures (for recursion exec_body, exec_if, exec_output, eval, eval_cond, eval_call
// and call_macro; for a bracket parse_primary, parse_tuple, parse_or, ..., parse_unary),
// each on the stack once per level, so each keeps a small frame: it does its part,
// recurses, and leaves everything else (binding arguments, building messages, setting up
// a loop, gathering a tuple) to a helper marked #force_no_inline, which returns before
// the recursion goes deeper and which no optimizer folds into the caller's frame. eval
// and exec_body dispatch through tables (EVAL, EXEC) for the same reason, and the parser
// reads tokens through pointers rather than copies.
//
// Measured on x86-64 Linux and arm64 macOS, a level of a macro calling itself, a
// recursive loop, an include or a call block then takes at most about 1.1 KiB in an
// optimized build (-o:minimal, the default, or -o:speed), so DEFAULT_MAX_RECURSION levels
// fit in half the default budget, and at most about 1.9 KiB in an unoptimized one
// (-o:none, as -debug builds), leaving a quarter of it. A bracket takes at most about
// 1.7 KiB and 2.8 KiB, so DEFAULT_MAX_NESTING levels take at most a third and a half of
// it. AddressSanitizer's redzones make frames up to four times larger, and the budget
// grows with them (ASAN_FRAME_SCALE). nesting_test.odin checks both limits, and the
// margin, on every platform.
//
// Values have no syntax, so walks over nested lists and dicts (repr, equality, tojson)
// stop at MAX_VALUE_DEPTH instead; a list that contains itself is the usual case.

// DEFAULT_MAX_NESTING is how deep a template's syntax may nest when
// Options.max_nesting is 0.
DEFAULT_MAX_NESTING :: 100

// DEFAULT_MAX_RECURSION is how deep macros, includes, blocks and recursive loops may
// nest when Options.max_recursion is 0.
DEFAULT_MAX_RECURSION :: 200

// DEFAULT_STACK_BYTES is the stack parsing and rendering may use when
// Options.stack_bytes is 0. It fits a 1 MiB thread (the smallest default of the
// supported platforms) with room for the caller and for leaf work, and holds
// DEFAULT_MAX_RECURSION levels of recursion with room to spare.
DEFAULT_STACK_BYTES :: (512 << 10) * ASAN_FRAME_SCALE

// ASAN_FRAME_SCALE is how much larger AddressSanitizer's redzones make each frame, so a
// build with -sanitize:address nests as deep within the budget as any other; 1 otherwise.
@(private)
ASAN_FRAME_SCALE :: 4 when .Address in ODIN_SANITIZER_FLAGS else 1

// MAX_VALUE_DEPTH is how deep repr, equality, ordering and tojson follow nested values.
MAX_VALUE_DEPTH :: 200

Stack_Guard :: struct {
    base:  uintptr,
    limit: uintptr,
}

// begin_stack starts the environment's guard at the caller's frame, unless an outer call
// on the same environment already did (a render that loads an included template).
// started says whether end_stack must stop it.
@(no_sanitize_address)
begin_stack :: proc "contextless" (env: ^Environment) -> (started: bool) {
    if env.stack.base != 0 do return false
    here: u8
    budget := env.options.stack_bytes if env.options.stack_bytes > 0 else DEFAULT_STACK_BYTES
    env.stack = {base = uintptr(&here), limit = uintptr(budget)}
    return true
}

end_stack :: proc "contextless" (env: ^Environment, started: bool) {
    if started do env.stack = {}
}

// stack_exhausted reports whether the caller's frame lies more than the budget away from
// where the guard started. A zero guard is never exhausted.
@(require_results, no_sanitize_address)
stack_exhausted :: proc "contextless" (g: Stack_Guard) -> bool {
    if g.base == 0 do return false
    here: u8
    at := uintptr(&here) // the frame's address measures the stack; nothing reads it.
    used := g.base - at if g.base >= at else at - g.base
    return used >= g.limit
}

// stack_error stops a render whose recursion (macros, includes, recursive loops and the
// expressions within them) would take the stack past Options.stack_bytes. It is out of
// line so that eval and exec, which call it, keep their frames small.
stack_error :: #force_no_inline proc(s: ^State) {
    runtime_error(s, .Limit, "the template recurses too deeply for the stack budget of " +
        "%d bytes (macros, includes, recursive loops and nested expressions)",
        s.env.stack.limit)
    set_hint(s, "Make the recursion shallower or the expressions within it simpler, or " +
        "raise Options.stack_bytes and render on a thread with that much more stack.")
}
