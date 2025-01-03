const std = @import("std");
const rl = @import("raylib");
const entt = @import("entt");
const paa = @import("paa.zig");
const m = @import("math/mod.zig");
const u = @import("utils/mod.zig");
const graphics = @import("graphics/mod.zig");
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
    const tileset_texture = try u.rl.loadTexture(alloc.allocator(), tileset.image_path);
    defer tileset_texture.unload();
    const player_texture = try u.rl.loadTexture(alloc.allocator(), "./assets/player.atlas.png");
    defer player_texture.unload();
    var player_atlas = try graphics.sprites.AnimatedSpriteSheet.initFromGrid(alloc.allocator(), 4, 4, "player");
    defer player_atlas.deinit();

    var camera = rl.Camera2D{
        .target = .{ .x = 0, .y = 0 },
        .offset = .{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = app.getDpiFactor().x(),
    };

    try reset(&game, &tilemap, tileset, &tileset_texture, &player_texture, &player_atlas);

    while (app.isRunning()) {
        const delta_time = rl.getFrameTime();
        // Input
        handleAppInput(&game);
        handlePlayerInput(&game, delta_time);

        // Physics
        applyGravity(game.reg, 20, delta_time);
        applyDrag(game.reg, 10, delta_time);
        try handleCollision(game.reg, alloc.allocator());
        updatePosition(game.reg);

        // Graphics
        updateCamera(&game, &camera);
        systems.updateAnimations(game.reg);
        systems.beginFrame(rl.getColor(0x202640ff));
        // Camera mode
        {
            camera.begin();
            systems.draw(game.reg);
            if (game.debug_mode) {
                systems.debugDraw(game.reg, rl.Color.yellow);
            }
            camera.end();
        }
        // Default mode
        if (game.debug_mode) systems.debugDrawFps();
        systems.endFrame();
    }
}

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

    if (rl.isKeyPressed(.key_f2)) {
        spawnDebugBox(game.reg);
    }
}

//------------------------------------------------------------------------------
// Game
//------------------------------------------------------------------------------

fn handlePlayerInput(game: *Game, delta_time: f32) void {
    const reg = game.reg;
    const player_entity = game.entities.getPlayer();
    const collision = reg.get(comp.Collision, player_entity);
    const speed = reg.get(comp.Speed, player_entity);
    var player = reg.get(comp.Player, player_entity);
    var vel = reg.get(comp.Velocity, player_entity);
    var visual = reg.get(comp.Visual, player_entity);

    const scaled_speed = speed.toVec2().scale(delta_time);
    const last_animation = visual.animation.definition;
    var next_animation = comp.Visual.AnimationDefinition{
        .name = "player0",
        .speed = 1.5,
        .flip_x = last_animation.flip_x,
    };

    if (rl.isKeyDown(.key_h) or rl.isKeyDown(.key_left)) {
        vel.value.xMut().* += -scaled_speed.x();
        next_animation = .{ .name = "player1", .speed = 8, .flip_x = true };
    } else if (rl.isKeyDown(.key_l) or rl.isKeyDown(.key_right)) {
        vel.value.xMut().* += scaled_speed.x();
        next_animation = .{ .name = "player1", .speed = 8, .flip_x = false };
    }

    if (!collision.grounded) {
        next_animation = .{ .name = "player2", .speed = 3, .flip_x = next_animation.flip_x };
    }

    // Change animation.
    visual.animation.changeAnimation(next_animation);

    if (rl.isKeyDown(.key_space)) {
        if (player.jump_timer.state <= 0.04) {
            player.jump_timer.update(delta_time);
            vel.value.yMut().* -= scaled_speed.y();
        }
    } else if (rl.isKeyUp(.key_space) and vel.value.y() == 0) {
        player.jump_timer.reset();
    }
}

/// Update the camera to follow the player if a certain threshold is reached.
fn updateCamera(game: *Game, camera: *rl.Camera2D) void {
    const threshold = m.Vec2.new(0.3, 0.3);
    const display = m.Vec2.new(
        @as(f32, @floatFromInt(rl.getRenderWidth())),
        @as(f32, @floatFromInt(rl.getRenderHeight())),
    );
    const target = game.entities.getPlayerCenter();

    // Update camera offset.
    const camera_offset = m.Vec2.one().sub(threshold).scale(0.5).mul(display);
    camera.offset = u.rl.vec2(camera_offset);

    // Update camera target.
    const world_min = rl.getScreenToWorld2D(u.rl.vec2(m.Vec2.one().sub(threshold).scale(0.5).mul(display)), camera.*);
    const world_max = rl.getScreenToWorld2D(u.rl.vec2(m.Vec2.one().add(threshold).scale(0.5).mul(display)), camera.*);
    if (target.x() < world_min.x) camera.target.x = target.x();
    if (target.y() < world_min.y) camera.target.y = target.y();
    if (target.x() > world_max.x) camera.target.x = world_min.x + (target.x() - world_max.x);
    if (target.y() > world_max.y) camera.target.y = world_min.y + (target.y() - world_max.y);
}

/// Reset game state.
fn reset(
    game: *Game,
    tilemap: *const tiled.Tilemap,
    tileset: *const tiled.Tileset,
    tileset_texture: *const rl.Texture,
    player_texture: *const rl.Texture,
    player_atlas: *graphics.sprites.AnimatedSpriteSheet,
) !void {
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
            if (!layer.visible or layer.type != .tilelayer) continue;
            var x: usize = 0;
            var y: usize = 0;
            for (layer.tiles) |tile_id| {
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
                        reg.add(entity, comp.Collision.new(shape.getSize()));
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
        const player_spawn_object = try tilemap.data.getObject("player_spawn");
        const spawn_pos = m.Vec2.new(
            @floatFromInt(player_spawn_object.x),
            @floatFromInt(player_spawn_object.y),
        );
        const player = game.entities.getPlayer();
        const pos = comp.Position.fromVec2(spawn_pos);
        const shape = comp.Shape.rectangle(39, 48);
        entities.setRenderable(
            reg,
            player,
            pos,
            shape,
            comp.Visual.animation(player_texture, player_atlas, .{ .name = "player0", .speed = 1.5 }),
            comp.VisualLayer.new(1),
        );
        entities.setMovable(
            reg,
            player,
            comp.Speed.new(60, 225),
        );
        reg.add(player, comp.Player.new());
        reg.add(player, comp.Collision.new(shape.getSize()));
        reg.add(player, comp.Gravity.new());
    }
}

/// Spawn a small box at current mouse position for debugging purposes.
fn spawnDebugBox(reg: *entt.Registry) void {
    const entity = reg.create();
    const pos = rl.getMousePosition();
    const shape = comp.Shape.rectangle(25, 25);
    entities.setRenderable(
        reg,
        entity,
        comp.Position.new(pos.x, pos.y),
        shape,
        comp.Visual.stub(),
        comp.VisualLayer.new(1),
    );
    reg.add(entity, comp.Velocity.new());
    reg.add(entity, comp.Collision.new(shape.getSize()));
    reg.add(entity, comp.Gravity.new());
}

//------------------------------------------------------------------------------
// Physics
//------------------------------------------------------------------------------

fn handleCollision(reg: *entt.Registry, allocator: std.mem.Allocator) !void {
    const BroadphaseCollision = struct {
        aabb: coll.Aabb,
        result: coll.CollisionResult,
    };

    var view = reg.view(.{ comp.Position, comp.Velocity, comp.Collision }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const pos = view.get(comp.Position, entity);
        var collision = view.get(comp.Collision, entity);
        var vel = view.get(comp.Velocity, entity);
        const aabb = coll.Aabb.new(pos.toVec2(), collision.aabb_size);
        const broadphase_aabb = coll.Aabb.fromMovement(pos.toVec2(), collision.aabb_size, vel.value);

        // Reset grounded flag.
        collision.grounded = false;

        var collisions = std.ArrayList(BroadphaseCollision).init(allocator);
        defer collisions.deinit();

        // Perform broadphase collision detection.
        var collider_view = reg.view(.{ comp.Position, comp.Collision }, .{});
        var collider_it = collider_view.entityIterator();
        while (collider_it.next()) |collider| {
            if (collider == entity) continue;
            const collider_pos = collider_view.get(comp.Position, collider);
            const collider_size = collider_view.get(comp.Collision, collider).aabb_size;
            const collider_aabb = coll.Aabb.new(collider_pos.toVec2(), collider_size);
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
        for (collisions.items) |broadphase_result| {
            const result = coll.aabbToAabb(aabb, broadphase_result.aabb, vel.value);
            if (result.hit) {
                vel.value = coll.resolveCollision(result, vel.value);
                // Set grounded flag, if entity collided with normal facing
                // upwards.
                if (result.normal.y() < 0) {
                    collision.grounded = true;
                }
            }
        }
    }
}

/// Apply gravity to all relevant entities.
fn applyGravity(reg: *entt.Registry, force: f32, delta_time: f32) void {
    var view = reg.view(.{ comp.Velocity, comp.Gravity }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const gravity = view.get(comp.Gravity, entity);
        const gravity_amount = force * gravity.factor * delta_time;
        var vel = view.get(comp.Velocity, entity);
        vel.value = vel.value.add(m.Vec2.new(0, gravity_amount));
    }
}

/// Apply horizontal drag to all entities with a velocity component.
fn applyDrag(reg: *entt.Registry, force: f32, delta_time: f32) void {
    var view = reg.view(.{comp.Velocity}, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        var vel = view.get(entity);
        const drag_amount = -force * vel.value.x() * delta_time;
        vel.value = vel.value.add(m.Vec2.new(drag_amount, 0));
        if (@abs(vel.value.x()) < 0.01) vel.value.xMut().* = 0;
    }
}

/// Update entities position based on their velocity.
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
