//! Contains the `PhysicsModule` to setup the physics world and the `Physics`
//! component to be used on entities.
//! The system `updatePhysics` is used to update the physics world and apply
//! attributes like position, rotation, etc. after the update to the default
//! components like `comp.Position`, etc.

const entt = @import("entt");
const zb = @import("zbox2d");
const comp = @import("components.zig");

/// Physics module.
pub const PhysicsModule = struct {
    const Self = @This();

    world: zb.b2WorldId,

    pub fn init(ppm: f32) Self {
        zb.b2SetLengthUnitsPerMeter(ppm);
        var world_def = zb.b2DefaultWorldDef();
        world_def.gravity.y = 9.81 * ppm;
        return Self{
            .world = zb.b2CreateWorld(&world_def),
        };
    }

    pub fn deinit(self: *const Self) void {
        zb.b2DestroyWorld(self.world);
    }

    pub fn update(self: *const Self, time_step: f32, sub_step_count: u32) void {
        zb.b2World_Step(self.world, time_step, @intCast(sub_step_count));
    }
};

/// Physics component.
pub const Physics = struct {
    const Self = @This();

    body: zb.b2BodyId,
    shape: zb.b2ShapeId,

    pub fn new(
        world: zb.b2WorldId,
        body_type: zb.b2BodyType,
        position: comp.Position,
        shape_comp: comp.Shape,
    ) Self {
        var body_def = zb.b2DefaultBodyDef();
        body_def.type = body_type;
        body_def.position = zb.b2Vec2{ .x = position.x, .y = position.y };
        const body = zb.b2CreateBody(world, @ptrCast(&body_def));
        const polygon = zb.b2MakeBox(shape_comp.getWidth(), shape_comp.getHeight());
        var shape_def = zb.b2DefaultShapeDef();
        shape_def.density = 1.0;
        shape_def.friction = 0.3;
        shape_def.restitution = 0.25;
        const shape = zb.b2CreatePolygonShape(body, &shape_def, &polygon);
        return Self{
            .body = body,
            .shape = shape,
        };
    }
};

/// System for updating the physics world.
pub fn updatePhysics(reg: *entt.Registry, physics_module: *PhysicsModule, delta_time: f32) void {
    physics_module.update(delta_time, 6);
    var view = reg.view(.{ comp.Position, comp.Shape, Physics }, .{});
    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        var pos = view.get(comp.Position, entity);
        const physics = view.get(Physics, entity);
        const physics_pos = zb.b2Body_GetPosition(physics.body);
        pos.x = physics_pos.x;
        pos.y = physics_pos.y;
    }
}
