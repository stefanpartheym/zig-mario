const std = @import("std");
const m = @import("math/mod.zig");

/// Axis-aligned bounding box.
pub const Aabb = struct {
    const Self = @This();

    pos: m.Vec2,
    size: m.Vec2,

    pub fn new(pos: m.Vec2, size: m.Vec2) Self {
        return Self{ .pos = pos, .size = size };
    }

    /// Creates an `Aabb` from the movement of a rectangle.
    /// The result will cover both the origin and the destination rectangles.
    /// Useful for broadphase collision detection.
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
    /// Useful for broadphase collision detection.
    pub fn intersects(self: *const Self, other: Aabb) bool {
        return self.pos.x() < other.pos.x() + other.size.x() and
            self.pos.x() + self.size.x() > other.pos.x() and
            self.pos.y() < other.pos.y() + other.size.y() and
            self.pos.y() + self.size.y() > other.pos.y();
    }

    pub fn eql(self: *const Self, other: Aabb) bool {
        return self.pos.eql(other.pos) and self.size.eql(other.size);
    }
};

pub const CollisionResult = struct {
    const Self = @This();

    /// Indicates if there was a collision.
    hit: bool,
    /// Contact normal.
    /// Indicates in which direction a potential collision should be resolved.
    normal: m.Vec2,
    /// Point of contact.
    contact: m.Vec2,
    /// Entry time.
    time: f32,
    /// Remaining time.
    remaining_time: f32,

    /// Creates a `CollisionResult` that indicates, that the target has been
    /// missed and has not been collided with.
    pub fn miss() Self {
        return Self.new(false, m.Vec2.zero(), m.Vec2.zero(), 1, 0);
    }

    pub fn new(
        hit: bool,
        normal: m.Vec2,
        contact: m.Vec2,
        time: f32,
        remaining_time: f32,
    ) Self {
        return Self{
            .hit = hit,
            .normal = normal,
            .contact = contact,
            .time = time,
            .remaining_time = remaining_time,
        };
    }
};

pub fn rayToAabb(
    /// Origin of the ray.
    ray_origin: m.Vec2,
    /// Direction of the ray.
    ray_dir: m.Vec2,
    /// Target to check for collision.
    target: Aabb,
) CollisionResult {
    // Calculate inverse direction to avoid subsequent divisions.
    const invdir = m.Vec2.new(1 / ray_dir.x(), 1 / ray_dir.y());
    // Calculate near and far contact points.
    const target_origin = target.pos.sub(ray_origin);
    var near = target_origin.mul(invdir);
    const target_corner = target.pos.sub(ray_origin).add(target.size);
    var far = target_corner.mul(invdir);

    // Check for NaN values in case of multiplying infinity by 0.
    const isNan = std.math.isNan;
    if (isNan(near.x()) or isNan(near.y()) or isNan(far.x()) or isNan(far.y())) {
        return CollisionResult.miss();
    }

    // Swap near and far components to account for negative ray directions.
    if (near.x() > far.x()) {
        const temp = near.x();
        near.xMut().* = far.x();
        far.xMut().* = temp;
    }
    if (near.y() > far.y()) {
        const temp = near.y();
        near.yMut().* = far.y();
        far.yMut().* = temp;
    }

    // No collision, if near components are greater (or equal) than far components.
    if (near.x() >= far.y() or near.y() >= far.x()) {
        return CollisionResult.miss();
    }

    const entry_time = @max(near.x(), near.y());
    const exit_time = @min(far.x(), far.y());

    // No collision, if ray points away from target.
    if (exit_time < 0) {
        return CollisionResult.miss();
    }

    // Calculate collision normal.
    const normal = if (near.x() > near.y())
        if (ray_dir.x() < 0)
            m.Vec2.new(1, 0)
        else
            m.Vec2.new(-1, 0)
    else if (near.x() < near.y())
        if (ray_dir.y() < 0)
            m.Vec2.new(0, 1)
        else
            m.Vec2.new(0, -1)
    else
        // If near.x and far.y are equal, ray intersects target diagonally.
        // This case is still considered a hit. However, return normal (0,0) to
        // make the resolution algorithm not change the velocity.
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

/// Check for collision between two `Aabb` objects.
pub fn aabbToAabb(origin: Aabb, target: Aabb, velocity: m.Vec2) CollisionResult {
    // Do not check collision if velocity is zero.
    if (velocity.eql(m.Vec2.zero())) {
        return CollisionResult.miss();
    }
    // Expand target by half the size of the origin.
    const origin_half_size = origin.size.scale(0.5);
    const expanded_target = Aabb.new(
        target.pos.sub(origin_half_size),
        target.size.add(origin.size),
    );
    // Get ray origin by the origins center point.
    const ray_origin = origin.pos.add(origin_half_size);
    // Perform collision detection.
    return rayToAabb(ray_origin, velocity, expanded_target);
}

/// Resolve collision.
pub fn resolveCollision(result: CollisionResult, velocity: m.Vec2) m.Vec2 {
    // Make sure function is only called for actual hits.
    std.debug.assert(result.hit);
    const dotprod = velocity.dot(result.normal);
    return velocity.sub(result.normal.scale(dotprod).scale(result.remaining_time));
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

test "resolveCollision: push velocity back to contact point" {
    const velocity = m.Vec2.new(1, 0);
    const origin = Aabb.new(m.Vec2.zero(), m.Vec2.new(1, 1));
    const target = Aabb.new(m.Vec2.new(1.5, 0), m.Vec2.new(1, 1));
    const result = aabbToAabb(origin, target, velocity);
    const resolved_velocity = resolveCollision(result, velocity);
    try std.testing.expectEqual(0.5, resolved_velocity.x());
    try std.testing.expectEqual(0, resolved_velocity.y());
}

test "aabbToAabb: sliding past bottom right corner" {
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

test "aabbToAabb: collide with right edge directly (no offset)" {
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

test "aabbToAabb: collide with left edge directly" {
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

test "aabbToAabb: collide with bottom edge directly" {
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

test "aabbToAabb: collide with corner" {
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

test "rayToAabb: collide with top edge" {
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

test "rayToAabb: collide with left edge" {
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

test "rayToAabb: collide with right edge" {
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

test "rayToAabb: collide with corner" {
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
