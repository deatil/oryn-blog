#+private
package jinja

import "base:intrinsics"
import "core:fmt"
import "core:mem"
import "core:strings"

// A parse or a render works with context.allocator set to a Guard over the memory it
// may use. The guard passes every request on, and when one is refused it records the
// first refusal and stops the work: a render's State fails at once with a Memory error
// at the line being rendered, and a parser fails at its next check (failed). The error's
// message is written into the guard's own buffer, since the allocator that refused
// cannot be asked for more; whoever returns the error past the guard's life copies it
// (clone_error, keep_memory_message).
//
// So no code needs to report a refusal itself: it only has to survive one, by checking
// what new and make return before using it, and by not indexing what an append may not
// have added. Values whose size is known before they are built (a repetition, padding,
// a join) are sized first (reserve_bytes): a size past Options.max_output is a Limit
// error, and otherwise the one allocation of exactly that size is the check, so nothing
// larger than the result is ever asked for.
Guard :: struct {
    backing: mem.Allocator,
    state:   ^State, // the render to stop, or nil while parsing.
    doing:   string, // "Rendering" or "Parsing".
    refused: int,    // bytes of the first refused request; 0 while none was.
    buffer:  [160]u8,
    message: string, // explains the first refusal; borrows buffer.
}

MEMORY_HINT_RENDER :: "Build less at once here: a smaller repetition, padding, join, or " +
    "loop; or give the render more memory."
MEMORY_HINT_PARSE :: "Split the template into smaller ones, or give the parse more memory."
// MEMORY_MESSAGE replaces a memory error's message where it could not be copied.
MEMORY_MESSAGE :: "This template needs more memory than it may use."

guard_allocator :: proc(g: ^Guard) -> mem.Allocator {
    return {procedure = guard_proc, data = g}
}

@(private = "file")
guard_proc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
    old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]u8,
    mem.Allocator_Error) {
    g := (^Guard)(data)
    out, err := g.backing.procedure(g.backing.data, mode, size, alignment, old_memory,
        old_size, loc)
    #partial switch mode {
    case .Alloc, .Alloc_Non_Zeroed:
        if err != nil && size > 0 do refuse(g, size)
    case .Resize, .Resize_Non_Zeroed:
        if err != nil && size > old_size do refuse(g, size - old_size)
    }
    return out, err
}

// refuse records a request of bytes the memory could not hold (max(int): more than
// can be counted), and stops the render the guard watches.
refuse :: proc(g: ^Guard, bytes: int) {
    if g.refused == 0 {
        g.refused = max(bytes, 1)
        amount: [32]u8
        if bytes == max(int) {
            g.message = fmt.bprintf(g.buffer[:], "%s this template needs more memory here " +
                "than can be counted.", g.doing)
        } else {
            g.message = fmt.bprintf(g.buffer[:], "%s this template needs %s more memory " +
                "here than it may use.", g.doing, byte_count(amount[:], bytes))
        }
    }
    if g.state != nil do memory_failure(g.state)
}

// byte_count writes bytes for people into buf, which it borrows.
byte_count :: proc(buf: []u8, bytes: int) -> string {
    switch {
    case bytes >= 1 << 30: return fmt.bprintf(buf, "%.1f GiB", f64(bytes) / (1 << 30))
    case bytes >= 1 << 20: return fmt.bprintf(buf, "%.1f MiB", f64(bytes) / (1 << 20))
    case bytes >= 1 << 10: return fmt.bprintf(buf, "%.1f KiB", f64(bytes) / (1 << 10))
    }
    return fmt.bprintf(buf, "%d bytes", bytes)
}

// memory_failure fails the render with the guard's Memory error at the current line.
memory_failure :: proc(s: ^State) {
    if s.failed do return
    s.failed = true
    name, excerpt := "", ""
    if s.current != nil do name, excerpt = s.current.name, source_line(s.current.source, s.line)
    s.err = Error{kind = .Memory, template = name, line = s.line, excerpt = excerpt,
        message = s.guard.message if s.guard != nil else MEMORY_MESSAGE,
        hint = MEMORY_HINT_RENDER}
}

// parse_memory_error is the Memory error of a parse whose guard refused.
parse_memory_error :: proc(g: ^Guard, line: int) -> Error {
    return Error{kind = .Memory, line = line, message = g.message, hint = MEMORY_HINT_PARSE}
}

// keep_memory_message copies a Memory error's message, which borrows its guard, into
// allocator, or replaces it with MEMORY_MESSAGE when that cannot hold it.
keep_memory_message :: proc(err: Error, allocator: mem.Allocator) -> Error {
    if err.kind != .Memory do return err
    out := err
    copied, cerr := strings.clone(err.message, allocator)
    out.message = copied if cerr == nil else MEMORY_MESSAGE
    return out
}

// reserve_bytes checks a value of count items of size bytes that the render is about to
// build, before anything is allocated: a size that cannot be counted is refused, and
// one past Options.max_output is a Limit error. It returns the byte count.
reserve_bytes :: proc(s: ^State, count, size: int) -> (int, bool) {
    if s.failed do return 0, false
    total, over := intrinsics.overflow_mul(max(count, 0), max(size, 0))
    if over {
        if s.guard != nil do refuse(s.guard, max(int))
        else do runtime_error(s, .Memory, "%s", MEMORY_MESSAGE)
        return 0, false
    }
    limit := s.env.options.max_output
    if limit > 0 && total > limit {
        amount: [32]u8
        runtime_error(s, .Limit, "this expression builds %s, more than the output limit " +
            "of %d bytes", byte_count(amount[:], total), limit)
        set_hint(s, "Build a smaller value here, or raise Options.max_output.")
        return 0, false
    }
    return total, true
}

// sum_bytes adds two byte counts, refusing a sum that cannot be counted.
sum_bytes :: proc(s: ^State, a, b: int) -> (int, bool) {
    total, over := intrinsics.overflow_add(a, b)
    if !over do return total, true
    if s.guard != nil do refuse(s.guard, max(int))
    else do memory_failure(s)
    return 0, false
}

// reserve_text grows b so that extra more bytes fit without another allocation, after
// reserve_bytes checks them; false (the render failed) when they cannot.
reserve_text :: proc(s: ^State, b: ^strings.Builder, extra: int) -> bool {
    more, ok := reserve_bytes(s, extra, 1)
    if !ok do return false
    total, over := intrinsics.overflow_add(len(b.buf), more)
    if over {
        if s.guard != nil do refuse(s.guard, max(int))
        else do memory_failure(s)
        return false
    }
    if total <= cap(b.buf) do return true
    if err := reserve(&b.buf, total); err != nil || cap(b.buf) < total {
        if !s.failed do memory_failure(s)
        return false
    }
    return true
}

// repeat_text is text repeated count times, sized and checked first (reserve_bytes).
repeat_text :: proc(s: ^State, text: string, count: int) -> (string, bool) {
    total, ok := reserve_bytes(s, len(text), count)
    if !ok do return "", false
    if total == 0 do return "", true
    out, err := make([]u8, total)
    if err != nil {
        if !s.failed do memory_failure(s)
        return "", false
    }
    for i := 0; i < total; i += len(text) do copy(out[i:], text)
    return string(out), true
}

// refusing_allocator refuses every request; an environment that could not make its
// arena works in it, so that every parse fails with a Memory error.
refusing_allocator :: proc() -> mem.Allocator {
    return {procedure = proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
        old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]u8,
        mem.Allocator_Error) {
        #partial switch mode {
        case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed: return nil, .Out_Of_Memory
        }
        return nil, nil
    }}
}
