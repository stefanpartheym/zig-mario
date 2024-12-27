const std = @import("std");
const m = @import("math/mod.zig");

pub const Aabb = struct {
    const Self = @This();

    pos: m.Vec2,
    size: m.Vec2,

    pub fn new(pos: m.Vec2, size: m.Vec2) Self {
        return Self{ .pos = pos, .size = size };
    }
};

pub const CollisionResult = struct {
    const Self = @This();

    hit: bool,
    normal: m.Vec2,
    contact: m.Vec2,
    entry_time: f32,
    remaining_time: f32,

    pub fn noHit() Self {
        return Self.new(false, m.Vec2.zero(), m.Vec2.zero(), 0, 0);
    }

    pub fn new(hit: bool, normal: m.Vec2, contact: m.Vec2, entry_time: f32, remaining_time: f32) Self {
        return Self{
            .hit = hit,
            .normal = normal,
            .contact = contact,
            .entry_time = entry_time,
            .remaining_time = remaining_time,
        };
    }
};

pub fn rayToAabb(ray_origin: m.Vec2, ray_dir: m.Vec2, target: Aabb) CollisionResult {
    const invdir = m.Vec2.new(1 / ray_dir.x(), 1 / ray_dir.y());
    const entry_vec = target.pos.sub(ray_origin);
    var entry = m.Vec2.new(
        entry_vec.x() / ray_dir.x(),
        entry_vec.y() / ray_dir.y(),
    );
    const exit_vec = target.pos.add(target.size).sub(ray_origin);
    var exit = m.Vec2.new(
        exit_vec.x() / ray_dir.x(),
        exit_vec.y() / ray_dir.y(),
    );

    if (entry.x() > exit.x()) {
        const temp = entry.x();
        entry.xMut().* = exit.x();
        exit.xMut().* = temp;
    }
    if (entry.y() > exit.y()) {
        const temp = entry.y();
        entry.yMut().* = exit.y();
        exit.yMut().* = temp;
    }

    if (entry.x() > exit.y() or entry.y() > exit.x()) {
        return CollisionResult.noHit();
    }

    const entry_time = @max(entry.x(), entry.y());
    const exit_time = @min(exit.x(), exit.y());

    if (exit_time < 0) {
        return CollisionResult.noHit();
    }

    const contact = ray_origin.add(ray_dir.scale(entry_time));
    const normal = if (entry.x() > entry.y())
        if (invdir.x() < 0)
            m.Vec2.new(1, 0)
        else
            m.Vec2.new(-1, 0)
    else if (entry.x() < entry.y())
        if (invdir.y() < 0)
            m.Vec2.new(0, 1)
        else
            m.Vec2.new(0, -1)
    else
        m.Vec2.zero();

    return CollisionResult.new(
        // TODO: entry_time must not be negative!
        entry_time <= 1 and entry_time >= 0,
        normal,
        contact,
        entry_time,
        1 - entry_time,
    );
}

pub fn aabbToAabb(origin: Aabb, target: Aabb, velocity: m.Vec2) CollisionResult {
    if (velocity.eql(m.Vec2.zero())) {
        return CollisionResult.noHit();
    }
    const origin_half_size = origin.size.scale(0.5);
    const expanded_target = Aabb.new(
        target.pos.sub(origin_half_size),
        target.size.add(origin.size),
    );
    const ray_origin = origin.pos.add(origin_half_size);
    return rayToAabb(ray_origin, velocity, expanded_target);
}

pub fn resolveCollision(result: CollisionResult, velocity: m.Vec2) m.Vec2 {
    if (!result.hit or result.normal.eql(m.Vec2.zero())) {
        return velocity;
    }
    const velocity_abs = m.Vec2.new(@abs(velocity.x()), @abs(velocity.y()));
    return velocity.add(velocity_abs.scale(result.remaining_time).mul(result.normal));
}

test "resolveCollision push velocity back to contact point" {
    const velocity = m.Vec2.new(1, 0);
    const origin = Aabb.new(m.Vec2.zero(), m.Vec2.new(1, 1));
    const target = Aabb.new(m.Vec2.new(1.5, 0), m.Vec2.new(1, 1));
    const result = aabbToAabb(origin, target, velocity);
    const resolved_velocity = resolveCollision(result, velocity);
    try std.testing.expectEqual(0.5, resolved_velocity.x());
    try std.testing.expectEqual(0, resolved_velocity.y());
}

test "aabbToAabb collide with left edge directly" {
    const velocity = m.Vec2.new(1, 0);
    const origin = Aabb.new(m.Vec2.zero(), m.Vec2.new(1, 1));
    const target = Aabb.new(m.Vec2.new(1.5, 0), m.Vec2.new(1, 1));
    const result = aabbToAabb(origin, target, velocity);
    try std.testing.expect(result.hit);
    try std.testing.expectEqual(-1, result.normal.x());
    try std.testing.expectEqual(0, result.normal.y());
    try std.testing.expectEqual(1, result.contact.x());
    try std.testing.expectEqual(0.5, result.contact.y());
    try std.testing.expectEqual(result.entry_time, 0.5);
    try std.testing.expectEqual(result.remaining_time, 0.5);
}

test "aabbToAabb collide with bottom edge directly" {
    const velocity = m.Vec2.new(0, -2);
    const origin = Aabb.new(m.Vec2.new(1, 5), m.Vec2.new(2, 2));
    const target = Aabb.new(m.Vec2.zero(), m.Vec2.new(4, 4));
    const result = aabbToAabb(origin, target, velocity);
    try std.testing.expect(result.hit);
    try std.testing.expectEqual(0, result.normal.x());
    try std.testing.expectEqual(1, result.normal.y());
    try std.testing.expectEqual(2, result.contact.x());
    try std.testing.expectEqual(5, result.contact.y());
    try std.testing.expectEqual(result.entry_time, 0.5);
    try std.testing.expectEqual(result.remaining_time, 0.5);
}

test "aabbToAabb collide with top edge" {
    const velocity = m.Vec2.new(2, 2);
    const origin = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const target = Aabb.new(m.Vec2.new(3, 3), m.Vec2.new(2, 2));
    const result = aabbToAabb(origin, target, velocity);
    try std.testing.expect(result.hit);
    try std.testing.expectEqual(0, result.normal.x());
    try std.testing.expectEqual(0, result.normal.y());
    try std.testing.expectEqual(2, result.contact.x());
    try std.testing.expectEqual(2, result.contact.y());
    try std.testing.expectEqual(result.entry_time, 0.5);
    try std.testing.expectEqual(result.remaining_time, 0.5);
}

test "rayToAabb collide with top edge" {
    const ray_origin = m.Vec2.new(2, 2);
    const ray_dir = m.Vec2.new(8, 4);
    const target = Aabb.new(m.Vec2.new(4, 4), m.Vec2.new(4, 4));
    const result = rayToAabb(ray_origin, ray_dir, target);
    try std.testing.expect(result.hit);
    try std.testing.expectEqual(0, result.normal.x());
    try std.testing.expectEqual(-1, result.normal.y());
    try std.testing.expectEqual(6, result.contact.x());
    try std.testing.expectEqual(4, result.contact.y());
    try std.testing.expectEqual(result.entry_time, 0.5);
    try std.testing.expectEqual(result.remaining_time, 0.5);
}

test "rayToAabb collide with left edge" {
    const ray_origin = m.Vec2.new(0, 1);
    const ray_dir = m.Vec2.new(2, 2);
    const target = Aabb.new(m.Vec2.new(1, 1), m.Vec2.new(2, 2));
    const result = rayToAabb(ray_origin, ray_dir, target);
    try std.testing.expect(result.hit);
    try std.testing.expectEqual(-1, result.normal.x());
    try std.testing.expectEqual(0, result.normal.y());
    try std.testing.expectEqual(1, result.contact.x());
    try std.testing.expectEqual(2, result.contact.y());
    try std.testing.expectEqual(result.entry_time, 0.5);
    try std.testing.expectEqual(result.remaining_time, 0.5);
}

test "rayToAabb collide with right edge" {
    const ray_origin = m.Vec2.new(5, 5);
    const ray_dir = m.Vec2.new(-2, -3);
    const target = Aabb.new(m.Vec2.new(1, 1), m.Vec2.new(3, 3));
    const result = rayToAabb(ray_origin, ray_dir, target);
    try std.testing.expect(result.hit);
    try std.testing.expectEqual(1, result.normal.x());
    try std.testing.expectEqual(0, result.normal.y());
    try std.testing.expectEqual(4, result.contact.x());
    try std.testing.expectEqual(3.5, result.contact.y());
    try std.testing.expectEqual(result.entry_time, 0.5);
    try std.testing.expectEqual(result.remaining_time, 0.5);
}

test "rayToAabb collide with corner" {
    const ray_origin = m.Vec2.new(0, 0);
    const ray_dir = m.Vec2.new(2, 2);
    const target = Aabb.new(m.Vec2.new(1, 1), m.Vec2.new(2, 2));
    const result = rayToAabb(ray_origin, ray_dir, target);
    try std.testing.expect(result.hit);
    try std.testing.expectEqual(0, result.normal.x());
    try std.testing.expectEqual(0, result.normal.y());
    try std.testing.expectEqual(1, result.contact.x());
    try std.testing.expectEqual(1, result.contact.y());
    try std.testing.expectEqual(result.entry_time, 0.5);
    try std.testing.expectEqual(result.remaining_time, 0.5);
}
