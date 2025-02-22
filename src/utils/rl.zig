//! Utility functions for raylib.

const std = @import("std");
const rl = @import("raylib");
const m = @import("../math/mod.zig");

/// Loads a texture from a path using a zig string rather than a C string.
pub fn loadTexture(allocator: std.mem.Allocator, path: []const u8) !rl.Texture {
    const texture_path = try allocator.dupeZ(u8, path);
    defer allocator.free(texture_path);
    return rl.loadTexture(texture_path);
}

/// Creates a raylib vector from a zalgebra vector.
pub fn vec2(v: m.Vec2) rl.Vector2 {
    return rl.Vector2{ .x = v.x(), .y = v.y() };
}

/// Creates a zalgebra vector from a raylib vector.
pub fn toVec2(v: rl.Vector2) m.Vec2 {
    return m.Vec2.new(v.x, v.y);
}
