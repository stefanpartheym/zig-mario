//! Helper functions for raylib.

const std = @import("std");
const rl = @import("raylib");

pub fn loadTexture(allocator: std.mem.Allocator, path: []const u8) !rl.Texture {
    const texture_path = try allocator.dupeZ(u8, path);
    defer allocator.free(texture_path);
    return rl.loadTexture(texture_path);
}
