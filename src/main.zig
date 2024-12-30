const std = @import("std");
const rl = @import("raylib");
const entt = @import("entt");
const m = @import("math/mod.zig");
const paa = @import("paa.zig");
const rlhelper = @import("rlhelper.zig");
const application = @import("application.zig");
const Game = @import("game.zig").Game;
const tiled = @import("tiled.zig");
const entities = @import("entities.zig");
const comp = @import("components.zig");
const systems = @import("systems.zig");
const coll = @import("collision.zig");

pub fn main() !void {
    var alloc = paa.init();
    defer alloc.deinit();

    var app = application.Application.init(
        alloc.allocator(),
        application.ApplicationConfig{
            .title = "zig-mario",
            .display = .{
                .width = 960,
                .height = 640,
                .high_dpi = true,
                .target_fps = 60,
            },
        },
    );
    defer app.deinit();

    var reg = entt.Registry.init(alloc.allocator());
    defer reg.deinit();

    var game = Game.new(&app, &reg);
    app.start();

    var tilemap = try tiled.Tilemap.fromFile(alloc.allocator(), "./assets/map/map.tmj");
    defer tilemap.deinit();
    const tileset = try tilemap.getTileset(1);
    const tileset_texture = try rlhelper.loadTexture(alloc.allocator(), tileset.image_path);

    reset(&game, &tilemap, tileset, &tileset_texture);

    while (app.isRunning()) {
        const delta_time = rl.getFrameTime();
        handleAppInput(&game);
        handlePlayerInput(&game, delta_time);
        applyGravity(game.reg, 9.81, delta_time);
        try handleCollision(game.reg, alloc.allocator());
        updatePosition(game.reg);
        systems.beginFrame(rl.Color.black);
        systems.draw(game.reg);
        if (game.debug_mode) {
            systems.debugDraw(game.reg, rl.Color.yellow);
            systems.debugDrawFps();
        }
        systems.endFrame();
    }
}

//------------------------------------------------------------------------------
// App
//------------------------------------------------------------------------------

fn handleAppInput(game: *Game) void {
    if (rl.windowShouldClose() or
        rl.isKeyPressed(rl.KeyboardKey.key_escape) or
        rl.isKeyPressed(rl.KeyboardKey.key_q))
    {
        game.app.shutdown();
    }

    if (rl.isKeyPressed(rl.KeyboardKey.key_f1)) {
        game.toggleDebugMode();
    }
}

//------------------------------------------------------------------------------
// Game
//------------------------------------------------------------------------------

fn handlePlayerInput(game: *Game, delta_time: f32) void {
    const reg = game.reg;
    const player_entity = game.getPlayer();
    const speed = reg.get(comp.Speed, player_entity);
    var player = reg.get(comp.Player, player_entity);
    var vel = reg.get(comp.Velocity, player_entity);

    // Reset velocity at the beginning of each frame.
    vel.value.xMut().* = 0;

    var direction = if (rl.isKeyDown(rl.KeyboardKey.key_h) or rl.isKeyDown(rl.KeyboardKey.key_left))
        m.Vec2.left()
    else if (rl.isKeyDown(rl.KeyboardKey.key_l) or rl.isKeyDown(rl.KeyboardKey.key_right))
        m.Vec2.right()
    else
        m.Vec2.zero();

    if (rl.isKeyDown(.key_space)) {
        if (player.jump_timer.state <= 0.025) {
            player.jump_timer.update(delta_time);
            direction.yMut().* = m.Vec2.up().negate().y();
        }
    } else if (rl.isKeyUp(.key_space)) {
        player.jump_timer.reset();
    }

    const scaled_speed = speed.toVec2().mul(direction).scale(delta_time);
    vel.value = vel.value.add(scaled_speed);
}

fn reset(
    game: *Game,
    tilemap: *const tiled.Tilemap,
    tileset: *const tiled.Tileset,
    tileset_texture: *const rl.Texture,
) void {
    const reg = game.reg;

    // Clear entity references.
    game.entities.clear();

    // Delete all entities.
    var it = reg.entities();
    while (it.next()) |entity| {
        reg.destroy(entity);
    }

    // Setup tilemap.
    {
        for (tilemap.data.layers) |layer| {
            if (!layer.visible) continue;
            var x: usize = 0;
            var y: usize = 0;
            for (layer.data) |tile_id| {
                // Skip empty tiles.
                if (tile_id != 0) {
                    const entity = reg.create();
                    const pos = comp.Position.new(
                        @floatFromInt(x * tilemap.data.tilewidth),
                        @floatFromInt(y * tilemap.data.tileheight),
                    );
                    const shape = comp.Shape.rectangle(
                        @floatFromInt(tilemap.data.tilewidth),
                        @floatFromInt(tilemap.data.tileheight),
                    );
                    entities.setRenderable(
                        reg,
                        entity,
                        pos,
                        shape,
                        comp.Visual.sprite(tileset_texture, tileset.getSpriteRect(tile_id)),
                        null,
                    );
                    // Add collision for first layer only.
                    if (layer.id < 2) {
                        reg.add(entity, comp.Collision.new());
                    }
                }

                // Update next tile position.
                x += 1;
                if (x >= tilemap.data.width) {
                    x = 0;
                    y += 1;
                }
            }
        }
    }

    // Setup new player entity.
    {
        const player = game.getPlayer();
        const spawn_pos = m.Vec2.new(50, 50);
        const pos = comp.Position.fromVec2(spawn_pos);
        const shape = comp.Shape.rectangle(40, 60);
        entities.setRenderable(
            reg,
            player,
            pos,
            shape,
            comp.Visual.stub(),
            comp.VisualLayer.new(1),
        );
        entities.setMovable(
            reg,
            player,
            comp.Speed.new(300, 300),
        );
        reg.add(player, comp.Player.new());
        reg.add(player, comp.Collision.new());
        reg.add(player, comp.Gravity.new());
    }
}

//------------------------------------------------------------------------------
// Physics
//------------------------------------------------------------------------------

fn handleCollision(reg: *entt.Registry, allocator: std.mem.Allocator) !void {
    const BroadphaseCollision = struct {
        aabb: coll.Aabb,
        result: coll.CollisionResult,
    };

    var view = reg.view(.{ comp.Position, comp.Shape, comp.Velocity, comp.Collision }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const pos = view.get(comp.Position, entity);
        const shape = view.get(comp.Shape, entity);
        var vel = view.get(comp.Velocity, entity);
        const aabb = coll.Aabb.new(pos.toVec2(), shape.getSize());
        const broadphase_aabb = coll.Aabb.fromMovement(pos.toVec2(), shape.getSize(), vel.value);

        var collisions = std.ArrayList(BroadphaseCollision).init(allocator);
        defer collisions.deinit();

        // Perform broadphase collision detection.
        var collider_view = reg.view(.{ comp.Position, comp.Shape, comp.Collision }, .{});
        var collider_it = collider_view.entityIterator();
        while (collider_it.next()) |collider| {
            if (collider == entity) continue;
            const collider_pos = collider_view.get(comp.Position, collider);
            const collider_size = collider_view.get(comp.Shape, collider);
            const collider_aabb = coll.Aabb.new(collider_pos.toVec2(), collider_size.getSize());
            if (broadphase_aabb.intersects(collider_aabb)) {
                const result = coll.aabbToAabb(aabb, collider_aabb, vel.value);
                if (result.hit) {
                    try collisions.append(.{
                        .aabb = collider_aabb,
                        .result = result,
                    });
                }
            }
        }

        // Sort collisions by time to resolve nearest collision first.
        const SortContext = struct {
            /// Compare function to sort collision results by time.
            fn sort(_: void, lhs: BroadphaseCollision, rhs: BroadphaseCollision) bool {
                return lhs.result.time < rhs.result.time;
            }
        };
        std.sort.insertion(BroadphaseCollision, collisions.items, {}, SortContext.sort);

        // Resolve collisions in order.
        for (collisions.items) |collision| {
            const result = coll.aabbToAabb(aabb, collision.aabb, vel.value);
            if (result.hit) {
                vel.value = coll.resolveCollision(result, vel.value);
            }
        }
    }
}

fn applyGravity(reg: *entt.Registry, force: f32, delta_time: f32) void {
    var view = reg.view(.{ comp.Velocity, comp.Gravity }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const gravity = view.get(comp.Gravity, entity);
        var vel = view.get(comp.Velocity, entity);
        vel.value = vel.value.add(m.Vec2.new(0, force * 1.5 * delta_time * gravity.factor));
    }
}

fn updatePosition(reg: *entt.Registry) void {
    var view = reg.view(.{ comp.Position, comp.Velocity }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const vel = view.getConst(comp.Velocity, entity);
        var pos = view.get(comp.Position, entity);
        pos.x += vel.value.x();
        pos.y += vel.value.y();
    }
}
