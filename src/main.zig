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

        // AI
        updateEnemies(&game);

        // Physics
        applyGravity(game.reg, 980 * delta_time);
        applyDrag(game.reg, 10 * delta_time);
        try handleCollision(alloc.allocator(), game.reg, delta_time);
        clampVelocity(game.reg);
        updatePosition(game.reg, delta_time);

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
                systems.debugDrawVelocity(game.reg, rl.Color.red, delta_time);
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
}

//------------------------------------------------------------------------------
// Game
//------------------------------------------------------------------------------

fn handlePlayerInput(game: *Game, delta_time: f32) void {
    const reg = game.reg;
    const player_entity = game.entities.getPlayer();
    const collision = reg.get(comp.Collision, player_entity);
    const speed = reg.get(comp.Speed, player_entity);
    var vel = reg.get(comp.Velocity, player_entity);
    var visual = reg.get(comp.Visual, player_entity);

    const last_animation = visual.animation.definition;
    var next_animation = comp.Visual.AnimationDefinition{
        .name = "player0",
        .speed = 1.5,
        // Inherit flip flag from last animation.
        .flip_x = last_animation.flip_x,
    };

    // Use appropriate speed based on whether the player is on the ground or in
    // the air.
    const speed_value = if (collision.grounded())
        speed.default
    else
        speed.airborne orelse speed.default;

    // Move left.
    if (rl.isKeyDown(.key_h) or rl.isKeyDown(.key_left)) {
        vel.value.xMut().* += -speed_value.x() * delta_time;
        next_animation = .{ .name = "player2", .speed = 8, .flip_x = true };
    }
    // Move right.
    else if (rl.isKeyDown(.key_l) or rl.isKeyDown(.key_right)) {
        vel.value.xMut().* += speed_value.x() * delta_time;
        next_animation = .{ .name = "player2", .speed = 8, .flip_x = false };
    }

    // Jump.
    if (rl.isKeyPressed(.key_space) and vel.value.y() == 0) {
        vel.value.yMut().* = -speed.default.y();
    }

    // Set jump animation if player is in the air.
    if (!collision.grounded()) {
        next_animation = .{
            .name = "player2",
            .speed = 0,
            // Inherit flip flag from current movement.
            .flip_x = next_animation.flip_x,
        };
    }

    // Change animation.
    visual.animation.changeAnimation(next_animation);
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

    const map_size = m.Vec2.new(
        @floatFromInt(tilemap.data.width * tilemap.data.tilewidth),
        @floatFromInt(tilemap.data.height * tilemap.data.tileheight),
    );

    // Setup map boundaries.
    {
        const left = reg.create();
        reg.add(left, comp.Position.new(0, 0));
        reg.add(left, comp.Collision.new(map_size.mul(m.Vec2.new(0, 1))));
        const right = reg.create();
        reg.add(right, comp.Position.new(map_size.x(), 0));
        reg.add(right, comp.Collision.new(map_size.mul(m.Vec2.new(0, 1))));
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
            comp.Speed{
                .default = m.Vec2.new(3000, 600),
                .airborne = m.Vec2.new(300, 0),
            },
            comp.Velocity.default(),
        );
        reg.add(player, comp.Collision.new(shape.getSize()));
        reg.add(player, comp.Gravity.new());
    }

    // Spawn enemy.
    {
        const spawn_pos = m.Vec2.new(448, 512);
        const e = reg.create();
        const shape = comp.Shape.rectangle(32, 32);
        entities.setRenderable(
            reg,
            e,
            comp.Position.fromVec2(spawn_pos),
            shape,
            comp.Visual.stub(),
            comp.VisualLayer.new(1),
        );
        var vel = comp.Velocity.default();
        vel.value.xMut().* = -3000;
        entities.setMovable(
            reg,
            e,
            comp.Speed{
                .default = m.Vec2.new(200, 1000),
                .airborne = m.Vec2.new(100, 0),
            },
            vel,
        );
        reg.add(e, comp.Enemy.new(.goomba));
        reg.add(e, comp.Collision.new(shape.getSize()));
        reg.add(e, comp.Gravity.new());
    }
}

pub fn updateEnemies(game: *Game) void {
    const reg = game.reg;
    var view = reg.view(.{ comp.Enemy, comp.Velocity, comp.Speed, comp.Collision }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const speed = view.get(comp.Speed, entity);
        var vel = view.get(comp.Velocity, entity);
        const collision = view.get(comp.Collision, entity);
        // Reverse direction if collision occurred on x axis.
        const direction = if (collision.normal.x() == 0) std.math.sign(vel.value.x()) else collision.normal.x();
        const direction_speed = speed.default.mul(m.Vec2.new(direction, 0));
        vel.value.xMut().* = direction_speed.x();
    }
}

//------------------------------------------------------------------------------
// Physics
//------------------------------------------------------------------------------

fn handleCollision(allocator: std.mem.Allocator, reg: *entt.Registry, delta_time: f32) !void {
    const BroadphaseCollision = struct {
        entity: entt.Entity,
        aabb: coll.Aabb,
        vel: m.Vec2,
        result: coll.CollisionResult,
    };

    var view = reg.view(.{ comp.Position, comp.Velocity, comp.Collision }, .{});
    var it = view.entityIterator();

    // Reset collision state for all dynamic entities.
    while (it.next()) |entity| {
        var collision = view.get(comp.Collision, entity);
        collision.normal = m.Vec2.zero();
    }

    it.reset();
    // Perform collision detection and response.
    while (it.next()) |entity| {
        const pos = view.get(comp.Position, entity);
        var collision = view.get(comp.Collision, entity);
        var vel = view.get(comp.Velocity, entity);
        const aabb = coll.Aabb.new(pos.toVec2(), collision.aabb_size);
        const broadphase_aabb = coll.Aabb.fromMovement(pos.toVec2(), collision.aabb_size, vel.value.scale(delta_time));

        var collisions = std.ArrayList(BroadphaseCollision).init(allocator);
        defer collisions.deinit();

        // Perform broadphase collision detection.
        var collider_view = reg.view(.{ comp.Position, comp.Collision }, .{});
        var collider_it = collider_view.entityIterator();
        while (collider_it.next()) |collider| {
            if (collider == entity) continue;
            const collider_pos = collider_view.get(comp.Position, collider).toVec2();
            const collider_size = collider_view.get(comp.Collision, collider).aabb_size;
            // Get collider velocity, if available.
            const collider_vel = if (reg.tryGet(comp.Velocity, collider)) |collider_vel_comp|
                collider_vel_comp.value
            else
                m.Vec2.zero();
            // Calculate broadphase collider AABB based on potential movement.
            const broadphase_collider_aabb = coll.Aabb.fromMovement(
                collider_pos,
                collider_size,
                collider_vel.scale(delta_time),
            );
            // Check intersection beween broadphase AABBs.
            if (broadphase_aabb.intersects(broadphase_collider_aabb)) {
                const collider_aabb = coll.Aabb.new(collider_pos, collider_size);
                const relative_vel = vel.value.sub(collider_vel).scale(delta_time);
                // Calculate time of impact based on relative velocity.
                const result = coll.aabbToAabb(aabb, collider_aabb, relative_vel);
                try collisions.append(.{
                    .entity = collider,
                    .aabb = collider_aabb,
                    .result = result,
                    .vel = collider_vel,
                });
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
        for (collisions.items) |collider| {
            const relative_vel = vel.value.sub(collider.vel).scale(delta_time);
            const result = coll.aabbToAabb(aabb, collider.aabb, relative_vel);
            if (result.hit) {
                vel.value = coll.resolveCollision(result, vel.value);
                // Set collision normals.
                if (result.normal.x() != 0) {
                    collision.normal.xMut().* = result.normal.x();
                }
                if (result.normal.y() != 0) {
                    collision.normal.yMut().* = result.normal.y();
                }
                // Resolve collision for dynamic collider.
                if (reg.tryGet(comp.Velocity, collider.entity)) |collider_vel| {
                    collider_vel.value = coll.resolveCollision(result, collider_vel.value);
                    var collider_collision = reg.get(comp.Collision, collider.entity);
                    collider_collision.normal = collision.normal.scale(-1);
                }
            }
        }
    }
}

/// Apply gravity to all relevant entities.
fn applyGravity(reg: *entt.Registry, force: f32) void {
    var view = reg.view(.{ comp.Velocity, comp.Gravity }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const gravity = view.get(comp.Gravity, entity);
        const gravity_amount = force * gravity.factor;
        var vel = view.get(comp.Velocity, entity);
        vel.value.yMut().* += gravity_amount;
    }
}

/// Apply horizontal drag to all currently grounded entities.
fn applyDrag(reg: *entt.Registry, force: f32) void {
    var view = reg.view(.{ comp.Velocity, comp.Collision }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const collision = view.get(comp.Collision, entity);
        if (!collision.grounded()) continue;
        var vel = view.get(comp.Velocity, entity);
        const drag_amount = -force * vel.value.x();
        vel.value.xMut().* += drag_amount;
        if (@abs(vel.value.x()) < 1) vel.value.xMut().* = 0;
    }
}

/// Clamp to terminal velocity.
fn clampVelocity(reg: *entt.Registry) void {
    var view = reg.view(.{comp.Velocity}, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        var vel: *comp.Velocity = view.get(entity);
        const lower = vel.terminal.scale(-1);
        const upper = vel.terminal;
        const vel_clamped = m.Vec2.new(
            std.math.clamp(vel.value.x(), lower.x(), upper.x()),
            std.math.clamp(vel.value.y(), lower.y(), upper.y()),
        );
        vel.value = vel_clamped;
    }
}

/// Update entities position based on their velocity.
fn updatePosition(reg: *entt.Registry, delta_time: f32) void {
    var view = reg.view(.{ comp.Position, comp.Velocity }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const vel = view.getConst(comp.Velocity, entity);
        const vel_scaled = vel.value.scale(delta_time);
        var pos = view.get(comp.Position, entity);
        pos.x += vel_scaled.x();
        pos.y += vel_scaled.y();
    }
}
