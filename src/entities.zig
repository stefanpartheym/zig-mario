//! This file provides common entity factories.
const entt = @import("entt");
const comp = @import("components.zig");

/// Adds (or replaces) all necessary components for the entity to be renderable.
pub fn setRenderable(
    reg: *entt.Registry,
    entity: entt.Entity,
    position: comp.Position,
    shape: comp.Shape,
    visual: comp.Visual,
    visual_layer_opt: ?comp.VisualLayer,
) void {
    reg.addOrReplace(entity, position);
    reg.addOrReplace(entity, shape);
    reg.addOrReplace(entity, visual);
    if (visual_layer_opt) |visual_layer| reg.add(entity, visual_layer);
}

/// Adds (or replaces) all necessary components for the entity to be movable.
pub fn setMovable(
    reg: *entt.Registry,
    entity: entt.Entity,
    speed: comp.Speed,
    velocity: comp.Velocity,
) void {
    reg.addOrReplace(entity, speed);
    reg.addOrReplace(entity, velocity);
}
