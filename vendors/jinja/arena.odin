#+private
package jinja

import "base:intrinsics"
import "core:mem"

// Arena is the block arena that holds an environment's templates and a render's
// scratch values. It takes blocks from its backing allocator and frees them all at once.
// Unlike core:mem's Dynamic_Arena, it keeps no side arrays and a block its backing
// refuses leaves it as it was: the request fails with .Out_Of_Memory, and the next one
// is tried afresh. (A Dynamic_Arena whose block allocation fails keeps a nil current
// block with a full block's room, so its next allocation returns an address near zero.)
//
// Small requests are carved from the current block (blocks). A request of more than a
// quarter block gets a block of its own (large), which is freed and resized on its own,
// so the growing buffer of a long output is not kept once per size it passed through.
Arena :: struct {
    backing:    mem.Allocator,
    blocks:     ^Arena_Block, // the current block first; older ones follow.
    large:      ^Arena_Block, // blocks of one request each.
    block_size: int,
}

// Arena_Block heads a block, at the start of the memory it describes: whole is the block
// as the backing gave it, and data its room after the header. Requests are carved from
// data through bounds-checked slices; addresses are only read, to align a request and to
// tell whose memory a pointer is.
Arena_Block :: struct {
    next:  ^Arena_Block,
    whole: []u8,
    data:  []u8,
    used:  int, // data bytes handed out.
    last:  int, // offset of the last request, for resizing it in place.
}

ARENA_BLOCK_SIZE :: 64 << 10
ARENA_HEADER :: (size_of(Arena_Block) + 15) &~ 15

arena_init :: proc(a: ^Arena, backing: mem.Allocator, block_size := ARENA_BLOCK_SIZE) {
    a^ = Arena{backing = backing, block_size = block_size}
}

arena_allocator :: proc(a: ^Arena) -> mem.Allocator {
    return {procedure = arena_proc, data = a}
}

// arena_destroy frees every block; the arena may be used again.
arena_destroy :: proc(a: ^Arena) {
    free_chain(a, a.blocks)
    free_chain(a, a.large)
    a.blocks, a.large = nil, nil
}

@(private = "file")
free_chain :: proc(a: ^Arena, first: ^Arena_Block) {
    for b := first; b != nil; {
        next := b.next
        _ = mem.free_bytes(b.whole, a.backing)
        b = next
    }
}

// arena_holds reports whether p points into a block of the arena (nil holds nothing).
arena_holds :: proc(a: ^Arena, p: rawptr) -> bool {
    if a == nil || p == nil do return false
    for chain in ([2]^Arena_Block{a.blocks, a.large}) {
        for b := chain; b != nil; b = b.next do if block_holds(b, p) do return true
    }
    return false
}

// block_holds reports whether p points into b's data: an address compared, not used.
@(private = "file")
block_holds :: proc(b: ^Arena_Block, p: rawptr) -> bool {
    start, at := uintptr(raw_data(b.data)), uintptr(p)
    return at >= start && at - start < uintptr(max(len(b.data), 1))
}

// aligned is the offset from start of data at which an address aligned to align falls.
@(private = "file")
aligned :: proc(data: []u8, start, align: int) -> int {
    base := uintptr(raw_data(data))
    return int(mem.align_forward_uintptr(base + uintptr(start), uintptr(align)) - base)
}

// new_block takes a block of at least size data bytes from the backing, or nil.
@(private = "file")
new_block :: proc(a: ^Arena, size: int) -> ^Arena_Block {
    total, over := intrinsics.overflow_add(size, ARENA_HEADER)
    if over do return nil
    raw, err := mem.alloc_bytes(total, 16, a.backing)
    if err != nil || len(raw) < total do return nil
    b := (^Arena_Block)(raw_data(raw)) // the header, at the start of its block.
    b^ = Arena_Block{whole = raw, data = raw[ARENA_HEADER:], last = -1}
    return b
}

@(private = "file")
arena_alloc :: proc(a: ^Arena, size, alignment: int) -> ([]u8, mem.Allocator_Error) {
    align := max(alignment, 1)
    if size < 0 || align > 16 && size > max(int) - align do return nil, .Invalid_Argument
    if size > a.block_size / 4 {
        b := new_block(a, size + (align if align > 16 else 0))
        if b == nil do return nil, .Out_Of_Memory
        b.next, a.large = a.large, b
        b.used = len(b.data)
        return b.data[aligned(b.data, 0, align):][:size], nil
    }
    if b := a.blocks; b != nil {
        if out, ok := carve(b, size, align); ok do return out, nil
    }
    b := new_block(a, a.block_size)
    if b == nil do return nil, .Out_Of_Memory
    b.next, a.blocks = a.blocks, b
    out, _ := carve(b, size, align)
    return out, nil
}

// carve hands out size bytes of b's free room, aligned, or ok = false when it is short.
@(private = "file")
carve :: proc(b: ^Arena_Block, size, align: int) -> ([]u8, bool) {
    offset := aligned(b.data, b.used, align)
    if offset > len(b.data) || size > len(b.data) - offset do return nil, false
    b.last = offset
    b.used = offset + size
    out := b.data[offset:][:size]
    mem.zero_slice(out) // room a shrink gave back.
    return out, true
}

// large_block finds the block of its own that holds old, and the link to it.
@(private = "file")
large_block :: proc(a: ^Arena, old: rawptr) -> (^Arena_Block, ^^Arena_Block) {
    link := &a.large
    for b := a.large; b != nil; b = b.next {
        if block_holds(b, old) do return b, link
        link = &b.next
    }
    return nil, nil
}

@(private = "file")
arena_resize :: proc(a: ^Arena, old: rawptr, old_size, size, alignment: int,
    zero: bool) -> ([]u8, mem.Allocator_Error) {
    if old == nil do return arena_alloc(a, size, alignment)
    if size == 0 {
        arena_free(a, old)
        return nil, nil
    }
    if b := a.blocks; b != nil && b.last >= 0 && b.last < len(b.data) &&
       raw_data(b.data[b.last:]) == old && size <= len(b.data) - b.last {
        b.used = b.last + size
        out := b.data[b.last:][:size]
        if zero && size > old_size do mem.zero_slice(out[old_size:])
        return out, nil
    }
    out, err := arena_alloc(a, size, alignment)
    if err != nil do return nil, err
    copy(out, mem.byte_slice(old, min(old_size, size)))
    arena_free(a, old)
    return out, nil
}

// arena_free gives back a block of its own; memory carved from a shared block stays
// until the arena is destroyed.
@(private = "file")
arena_free :: proc(a: ^Arena, old: rawptr) {
    if old == nil || a.large == nil do return
    b, link := large_block(a, old)
    if b == nil do return
    link^ = b.next
    _ = mem.free_bytes(b.whole, a.backing)
}

@(private = "file")
arena_proc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
    old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]u8,
    mem.Allocator_Error) {
    a := (^Arena)(data)
    switch mode {
    case .Alloc, .Alloc_Non_Zeroed:
        return arena_alloc(a, size, alignment) // blocks come zeroed and are never reused.
    case .Resize, .Resize_Non_Zeroed:
        return arena_resize(a, old_memory, old_size, size, alignment, mode == .Resize)
    case .Free:
        arena_free(a, old_memory)
    case .Free_All:
        arena_destroy(a)
    case .Query_Features:
        set := (^mem.Allocator_Mode_Set)(old_memory)
        if set != nil {
            set^ = {.Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed, .Free, .Free_All,
                .Query_Features}
        }
        return nil, nil
    case .Query_Info:
        return nil, .Mode_Not_Implemented
    }
    return nil, nil
}
