const std = @import("std");
const entt = @import("entt");
const rl = @import("raylib");
const m = @import("math/mod.zig");
const graphics = @import("graphics/mod.zig");
const entities = @import("entities.zig");
const comp = @import("components.zig");
const coll = @import("collision.zig");

pub const CollisionLayer = struct {
    pub const background: u32 = 0b00000001;
    pub const map: u32 = 0b00000010;
    pub const enemy_colliders: u32 = 0b00000100;
    pub const deadly_colliders: u32 = 0b00001000;
    pub const player: u32 = 0b10000000;
    pub const enemies: u32 = 0b01000000;
    pub const collectables: u32 = 0b00100000;
};

pub const VisualLayer = struct {
    pub const player: u32 = 1;
    pub const npcs: u32 = 1;
    pub const items: u32 = 1;
    pub const floating_text: u32 = 2;
};

pub fn spawnPlayer(
    reg: *entt.Registry,
    entity: entt.Entity,
    spawn_pos: m.Vec2,
    texture: *const rl.Texture,
    atlas: *graphics.sprites.AnimatedSpriteSheet,
) void {
    const pos = comp.Position.fromVec2(spawn_pos);
    const shape = comp.Shape.rectangle(33, 45);
    entities.setRenderable(
        reg,
        entity,
        pos,
        shape,
        comp.Visual.animation(
            texture,
            atlas,
            .{ .name = "player_0", .speed = 1.5 },
        ),
        comp.VisualLayer.new(VisualLayer.player),
    );
    entities.setMovable(
        reg,
        entity,
        comp.Speed{ .value = m.Vec2.new(250, 850) },
        comp.Velocity{},
    );
    reg.add(
        entity,
        comp.Collision.new(
            CollisionLayer.player,
            CollisionLayer.map | CollisionLayer.enemies | CollisionLayer.collectables | CollisionLayer.deadly_colliders,
            shape.getSize(),
        ),
    );
    reg.add(entity, comp.Gravity.new());
    reg.add(entity, comp.Player.new());
}

pub fn createEnemey(
    reg: *entt.Registry,
    enemy_type: comp.EnemyType,
    spawn_pos: m.Vec2,
    shape: comp.Shape,
    visual: comp.Visual,
    speed: m.Vec2,
) entt.Entity {
    const e = reg.create();
    entities.setRenderable(
        reg,
        e,
        comp.Position.fromVec2(spawn_pos),
        shape,
        visual,
        comp.VisualLayer.new(VisualLayer.npcs),
    );
    entities.setMovable(
        reg,
        e,
        comp.Speed{ .value = speed },
        comp.Velocity{ .value = m.Vec2.new(-3000, 0) },
    );
    reg.add(e, comp.Enemy{ .type = enemy_type });
    reg.add(e, comp.Collision.new(
        CollisionLayer.enemies,
        CollisionLayer.map | CollisionLayer.enemy_colliders | CollisionLayer.player,
        shape.getSize(),
    ));
    reg.add(e, comp.Gravity.new());
    return e;
}

pub fn createCoin(
    reg: *entt.Registry,
    spawn_pos: m.Vec2,
    // texture: *const rl.Texture,
    // atlas: *graphics.sprites.AnimatedSpriteSheet,
) entt.Entity {
    const e = reg.create();
    const shape = comp.Shape.circle(5);
    entities.setRenderable(
        reg,
        e,
        comp.Position.fromVec2(spawn_pos),
        shape,
        comp.Visual.color(rl.Color.gold, false),
        comp.VisualLayer.new(VisualLayer.items),
    );
    reg.add(e, comp.Item{ .type = .coin });
    reg.add(e, comp.Collision.new(
        CollisionLayer.collectables,
        CollisionLayer.player,
        shape.getSize(),
    ));
    return e;
}

pub fn createEnemey1(
    reg: *entt.Registry,
    spawn_pos: m.Vec2,
    texture: *const rl.Texture,
    atlas: *graphics.sprites.AnimatedSpriteSheet,
) entt.Entity {
    return createEnemey(
        reg,
        .slow,
        spawn_pos,
        comp.Shape.rectangle(18 * 3, 10 * 3),
        comp.Visual.animation(
            texture,
            atlas,
            .{
                .name = "enemies_0",
                .speed = 6,
                .padding = m.Vec4.new(0, 10, 2, 10),
            },
        ),
        m.Vec2.new(100, 0),
    );
}

pub fn createEnemey2(
    reg: *entt.Registry,
    spawn_pos: m.Vec2,
    texture: *const rl.Texture,
    atlas: *graphics.sprites.AnimatedSpriteSheet,
) entt.Entity {
    return createEnemey(
        reg,
        .fast,
        spawn_pos,
        comp.Shape.rectangle(15 * 3, 17 * 3),
        comp.Visual.animation(
            texture,
            atlas,
            .{
                .name = "enemies_9",
                .speed = 6,
                .padding = m.Vec4.new(2, 3, 4, 3),
            },
        ),
        m.Vec2.new(150, 0),
    );
}

pub fn createFloatingText(
    reg: *entt.Registry,
    spawn_pos: m.Vec2,
    text: [:0]const u8,
) entt.Entity {
    const e = reg.create();
    entities.setRenderable(
        reg,
        e,
        comp.Position.fromVec2(spawn_pos),
        comp.Shape.rectangle(0, 0),
        comp.Visual.text(text, 14, rl.Color.green),
        comp.VisualLayer.new(VisualLayer.floating_text),
    );
    entities.setMovable(
        reg,
        e,
        comp.Speed{ .value = m.Vec2.zero() },
        comp.Velocity{ .value = m.Vec2.new(0, -150) },
    );
    reg.add(e, comp.Lifetime.new(0.5));
    return e;
}
