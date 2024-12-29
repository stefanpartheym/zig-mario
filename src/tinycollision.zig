const std = @import("std");
const m = @import("math/mod.zig");

pub const Aabb = struct {
    const Self = @This();

    pos: m.Vec2,
    size: m.Vec2,

    pub fn new(pos: m.Vec2, size: m.Vec2) Self {
        return Self{ .pos = pos, .size = size };
    }

    /// Creates an `Aabb` from the movement of a rectangle.
    /// The result will cover both the origin and the destination rectangles.
    /// Useful for boradphase collision detection.
    pub fn fromMovement(pos: m.Vec2, size: m.Vec2, vel: m.Vec2) Self {
        const dest = pos.add(vel);
        const origin = m.Vec2.new(
            @min(pos.x(), dest.x()),
            @min(pos.y(), dest.y()),
        );
        const corner = m.Vec2.new(
            @max(pos.x(), dest.x()),
            @max(pos.y(), dest.y()),
        );
        return Self{
            .pos = origin,
            .size = corner.add(size).sub(origin),
        };
    }

    /// Checks if this `Aabb` intersects another `Aabb`.
    /// Useful for boradphase collision detection.
    pub fn intersects(self: *const Self, other: Aabb) bool {
        return self.pos.x() < other.pos.x() + other.size.x() and
            self.pos.x() + self.size.x() > other.pos.x() and
            self.pos.y() < other.pos.y() + other.size.y() and
            self.pos.y() + self.size.y() > other.pos.y();
    }
};

pub const CollisionResult = struct {
    const Self = @This();

    /// Indicates if there was a collision.
    hit: bool,
    /// Normal of collision.
    normal: m.Vec2,
    /// Point of contact.
    contact: m.Vec2,
    /// Entry time.
    time: f32,
    /// Remaining time.
    remaining_time: f32,

    pub fn noHit() Self {
        return Self.new(false, m.Vec2.zero(), m.Vec2.zero(), 1, 0);
    }

    pub fn new(hit: bool, normal: m.Vec2, contact: m.Vec2, time: f32, remaining_time: f32) Self {
        return Self{
            .hit = hit,
            .normal = normal,
            .contact = contact,
            .time = time,
            .remaining_time = remaining_time,
        };
    }
};

pub fn rayToAabb(ray_origin: m.Vec2, ray_dir: m.Vec2, target: Aabb) CollisionResult {
    const invdir = m.Vec2.new(1 / ray_dir.x(), 1 / ray_dir.y());
    const target_origin = target.pos.sub(ray_origin);
    // TODO: Multiply by `invdir` to replace division.
    // TODO: Rename `entry` to `near`.
    var entry = m.Vec2.new(
        target_origin.x() / ray_dir.x(),
        target_origin.y() / ray_dir.y(),
    );
    const target_corner = target.pos.sub(ray_origin).add(target.size);
    // TODO: Multiply by `invdir` to replace division.
    // TODO: Rename `exit` to `far`.
    var exit = m.Vec2.new(
        target_corner.x() / ray_dir.x(),
        target_corner.y() / ray_dir.y(),
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

    // No hit, if ray points in opposite direction.
    if (exit_time < 0) {
        return CollisionResult.noHit();
    }

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

    const hit = entry_time >= 0 and entry_time < 1;
    const contact = ray_origin.add(ray_dir.scale(entry_time));
    return CollisionResult.new(
        hit,
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
    const velocity_abs = m.Vec2.new(@abs(velocity.x()), @abs(velocity.y()));
    return velocity.add(velocity_abs.mul(result.normal).scale(result.remaining_time));
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

test "aabbToAabb sliding past bottom right corner" {
    const velocity = m.Vec2.up().negate();
    const origin = Aabb.new(m.Vec2.new(2, 2), m.Vec2.new(1, 1));
    const target = Aabb.new(m.Vec2.zero(), m.Vec2.new(2, 2));
    const result = aabbToAabb(origin, target, velocity);
    try std.testing.expect(!result.hit);
    try std.testing.expectEqual(0, result.normal.x());
    try std.testing.expectEqual(0, result.normal.y());
    try std.testing.expectEqual(0, result.contact.x());
    try std.testing.expectEqual(0, result.contact.y());
    try std.testing.expectEqual(1, result.time);
    try std.testing.expectEqual(0, result.remaining_time);
}

test "aabbToAabb collide with right edge directly (no offset)" {
    const velocity = m.Vec2.left();
    const origin = Aabb.new(m.Vec2.new(2, 1.5), m.Vec2.new(1, 1));
    const target = Aabb.new(m.Vec2.zero(), m.Vec2.new(2, 2));
    const result = aabbToAabb(origin, target, velocity);
    try std.testing.expect(result.hit);
    try std.testing.expectEqual(1, result.normal.x());
    try std.testing.expectEqual(0, result.normal.y());
    try std.testing.expectEqual(2.5, result.contact.x());
    try std.testing.expectEqual(2, result.contact.y());
    try std.testing.expectEqual(0, result.time);
    try std.testing.expectEqual(1, result.remaining_time);
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
    try std.testing.expectEqual(0.5, result.time);
    try std.testing.expectEqual(0.5, result.remaining_time);
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
    try std.testing.expectEqual(0.5, result.time);
    try std.testing.expectEqual(0.5, result.remaining_time);
}

test "aabbToAabb collide with corner" {
    const velocity = m.Vec2.new(2, 2);
    const origin = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const target = Aabb.new(m.Vec2.new(3, 3), m.Vec2.new(2, 2));
    const result = aabbToAabb(origin, target, velocity);
    try std.testing.expect(result.hit);
    try std.testing.expectEqual(0, result.normal.x());
    try std.testing.expectEqual(0, result.normal.y());
    try std.testing.expectEqual(2, result.contact.x());
    try std.testing.expectEqual(2, result.contact.y());
    try std.testing.expectEqual(result.time, 0.5);
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
    try std.testing.expectEqual(0.5, result.time);
    try std.testing.expectEqual(0.5, result.remaining_time);
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
    try std.testing.expectEqual(0.5, result.time);
    try std.testing.expectEqual(0.5, result.remaining_time);
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
    try std.testing.expectEqual(0.5, result.time);
    try std.testing.expectEqual(0.5, result.remaining_time);
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
    try std.testing.expectEqual(0.5, result.time);
    try std.testing.expectEqual(0.5, result.remaining_time);
}
