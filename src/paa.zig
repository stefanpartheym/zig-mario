//! paa - Platform agnostic allocator
//! Agnostic allocator frontend, that chooses the appropriate allocator backend
//! based on the host platform.
//! The `GeneralPurposeAllocator` will cause OOM errors for web builds. In such
//! cases the C allocator must be used instead.
//! see: [https://github.com/ziglang/zig/issues/19072](https://github.com/ziglang/zig/issues/19072)

const std = @import("std");

const Self = @This();
const name = @typeName(Self);
const Gpa = std.heap.GeneralPurposeAllocator(.{});

gpa: ?Gpa,
alt_allocator: ?std.mem.Allocator,

pub fn init() Self {
    const builtin = @import("builtin");
    // Pick the allocator to use depending on platform.
    if (builtin.os.tag == .wasi or builtin.os.tag == .emscripten) {
        return Self{
            .gpa = null,
            .alt_allocator = std.heap.c_allocator,
        };
    } else {
        return Self{
            .gpa = Gpa{},
            .alt_allocator = null,
        };
    }
}

pub fn deinit(self: *Self) void {
    if (self.gpa) |*gpa| {
        const result = gpa.deinit();
        if (result == .leak) {
            std.debug.print("[WARNING] " ++ name ++ ": Memory leaks detected.", .{});
        }
    }
}

pub fn allocator(self: *Self) std.mem.Allocator {
    if (self.gpa) |*gpa| {
        return gpa.allocator();
    } else if (self.alt_allocator) |alt_allocator| {
        return alt_allocator;
    } else {
        @panic("No allocator backend available: " ++ name ++ " possibly not initialized.");
    }
}
