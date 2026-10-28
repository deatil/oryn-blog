package jinja

import "core:mem"
import "core:os"
import "core:strings"

// Loader_Proc returns the source of a template, allocated with allocator.
Loader_Proc :: #type proc(user: rawptr, name: string, allocator: mem.Allocator) -> (
    source: string, found: bool)

// Loader is a procedure plus its data. destroy, when set, is called by
// destroy_environment.
Loader :: struct {
    procedure: Loader_Proc,
    user:      rawptr,
    destroy:   proc(user: rawptr),
}

// memory_loader serves templates from a map the host owns (name -> source).
memory_loader :: proc(sources: ^map[string]string) -> Loader {
    load :: proc(user: rawptr, name: string, allocator: mem.Allocator) -> (string, bool) {
        sources := (^map[string]string)(user)
        source, ok := sources[name]
        if !ok do return "", false
        return strings.clone(source, allocator), true
    }
    return Loader{procedure = load, user = sources}
}

@(private="file")
File_System_Loader :: struct {
    directories: []string,
    allocator:   mem.Allocator,
}

// filesystem_loader serves templates from directories, searched in order; the first
// match wins. Names use "/" and may not climb out of a directory with "..". The loader
// copies directories with context.allocator and frees them when its environment is
// destroyed (Loader.destroy). When that allocator refuses the copy, the loader finds
// nothing.
filesystem_loader :: proc(directories: []string) -> Loader {
    fs := new(File_System_Loader)
    if fs == nil do return Loader{procedure = find_nothing}
    fs.allocator = context.allocator
    list, err := make([]string, len(directories))
    if err == nil {
        fs.directories = list
        for dir, i in directories do fs.directories[i] = strings.clone(dir)
    }
    destroy :: proc(user: rawptr) {
        fs := (^File_System_Loader)(user)
        context.allocator = fs.allocator
        for dir in fs.directories do delete(dir)
        delete(fs.directories)
        free(fs)
    }
    return Loader{procedure = load_file, user = fs, destroy = destroy}
}

@(private="file")
find_nothing :: proc(user: rawptr, name: string, allocator: mem.Allocator) -> (string, bool) {
    return "", false
}

@(private="file")
load_file :: proc(user: rawptr, name: string, allocator: mem.Allocator) -> (string, bool) {
    fs := (^File_System_Loader)(user)
    pieces, ok := split_template_path(name, context.allocator)
    defer delete(pieces)
    if !ok do return "", false
    relative := strings.join(pieces, "/")
    defer delete(relative)
    for dir in fs.directories {
        path := strings.concatenate({dir, "/", relative})
        defer delete(path)
        if !os.is_file(path) do continue
        data, err := os.read_entire_file(path, allocator)
        if err != nil do continue
        return string(data), true
    }
    return "", false
}

// split_template_path splits "a/b.html" into pieces, refusing ".." and backslashes.
@(private)
split_template_path :: proc(name: string, allocator: mem.Allocator) -> ([]string, bool) {
    pieces := make([dynamic]string, allocator)
    rest := name
    for piece in strings.split_iterator(&rest, "/") {
        if piece == ".." || strings.contains_rune(piece, '\\') do return pieces[:], false
        if piece == "" || piece == "." do continue
        append(&pieces, piece)
    }
    return pieces[:], len(pieces) > 0
}
