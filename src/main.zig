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
const prefabs = @import("prefabs.zig");

const FloatingText = struct {
    pub const score_10: [:0]const u8 = "+10";
    pub const score_20: [:0]const u8 = "+20";
};

const ScoreInfo = struct {
    value: u32,
    text: [:0]const u8,
};

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

    // Start application.
    // Must happen before loading textures and sounds.
    app.start();

    // Load sprites
    var tilemap = try tiled.Tilemap.fromFile(alloc.allocator(), "./assets/map/map.tmj");
    defer tilemap.deinit();
    const tileset = try tilemap.getTileset(1);
    const tileset_texture = try u.rl.loadTexture(alloc.allocator(), tileset.image_path);
    defer tileset_texture.unload();
    const player_texture = try rl.loadTexture("./assets/player.atlas.png");
    defer player_texture.unload();
    var player_atlas = try graphics.sprites.AnimatedSpriteSheet.initFromGrid(alloc.allocator(), 3, 4, "player_");
    defer player_atlas.deinit();
    const enemies_texture = try rl.loadTexture("./assets/enemies.atlas.png");
    defer enemies_texture.unload();
    var enemies_atlas = try graphics.sprites.AnimatedSpriteSheet.initFromGrid(alloc.allocator(), 12, 2, "enemies_");
    defer enemies_atlas.deinit();

    var game = Game.new(&app, &reg);
    game.tilemap = &tilemap;
    game.sprites.tileset_texture = &tileset_texture;
    game.sprites.player_texture = &player_texture;
    game.sprites.player_atlas = &player_atlas;
    game.sprites.enemies_texture = &enemies_texture;
    game.sprites.enemies_atlas = &enemies_atlas;

    // Load sounds
    game.sounds.jump = try rl.loadSound("./assets/sounds/jump.wav");
    defer rl.unloadSound(game.sounds.jump);
    game.sounds.hit = try rl.loadSound("./assets/sounds/hit.wav");
    defer rl.unloadSound(game.sounds.hit);
    game.sounds.die = try rl.loadSound("./assets/sounds/die.wav");
    defer rl.unloadSound(game.sounds.die);
    game.sounds.pickup_coin = try rl.loadSound("./assets/sounds/pickup_coin.wav");
    defer rl.unloadSound(game.sounds.pickup_coin);

    var camera = rl.Camera2D{
        .target = .{ .x = 0, .y = 0 },
        .offset = .{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = app.getDpiFactor().x(),
    };

    try reset(&game);

    var collision_system = systems.collision.CollisionSystem.init(alloc.allocator());
    defer collision_system.deinit();

    while (app.isRunning()) {
        const delta_time = rl.getFrameTime();

        systems.updateLifetimes(game.reg, delta_time);

        // Reset game, if player is dead.
        if (game.entities.isPlayerDead()) try reset(&game);

        // Input
        handleAppInput(&game);
        if (game.entities.isPlayerAlive()) {
            handlePlayerInput(&game, delta_time);
        }

        // AI
        updateEnemies(&game);

        // Physics
        systems.applyGravity(game.reg, 1980 * delta_time);
        systems.clampVelocity(game.reg);
        collision_system.onUpdate();
        try detectCollisions(game.reg, &collision_system, delta_time);
        handleCollisions(&game, &collision_system, delta_time);
        systems.updatePosition(game.reg, delta_time);

        // Graphics
        graphics.camera.updateCameraTarget(
            &camera,
            game.entities.getPlayerCenter(),
            m.Vec2.new(0.3, 0.3),
        );
        systems.updateAnimations(game.reg, delta_time);
        systems.beginFrame(rl.getColor(0x202640ff));
        {
            camera.begin();
            systems.draw(game.reg);
            if (game.debug_mode) {
                systems.debugDraw(game.reg, rl.Color.yellow);
                systems.debugDrawVelocity(game.reg, rl.Color.red, delta_time);
            }
            camera.end();
        }
        drawHud(&game);
        if (game.debug_mode) systems.debugDrawFps();
        systems.endFrame();
    }
}

fn handleAppInput(game: *Game) void {
    if (rl.windowShouldClose() or
        rl.isKeyPressed(.escape) or
        rl.isKeyPressed(.q))
    {
        game.app.shutdown();
    }

    if (rl.isKeyPressed(.f1)) {
        game.toggleDebugMode();
    }

    if (rl.isKeyPressed(.f2)) {
        game.toggleAudio();
    }

    if (rl.isKeyPressed(.r)) {
        reset(game) catch unreachable;
    }

    if (rl.isKeyPressed(.enter)) {
        _ = prefabs.createEnemey2(game.reg, m.Vec2.new(544, 192), game.sprites.enemies_texture, game.sprites.enemies_atlas);
    }
}

//------------------------------------------------------------------------------
// Game
//------------------------------------------------------------------------------

fn handlePlayerInput(game: *Game, delta_time: f32) void {
    const reg = game.reg;
    const player_entity = game.entities.getPlayer();
    const collision = reg.get(comp.Collision, player_entity);
    const speed = reg.get(comp.Speed, player_entity).value;
    var vel = reg.get(comp.Velocity, player_entity);
    var visual = reg.get(comp.Visual, player_entity);

    const last_animation = visual.animation.definition;
    var next_animation = comp.Visual.AnimationDefinition{
        .name = "player_0",
        .speed = 1.5,
        // Inherit flip flag from last animation.
        .flip_x = last_animation.flip_x,
    };

    const accel_factor: f32 = if (collision.grounded()) 4 else 2.5;
    const decel_factor: f32 = if (collision.grounded()) 15 else 0.5;
    const acceleration = speed.x() * accel_factor * delta_time;

    // Move left.
    if (rl.isKeyDown(.h) or rl.isKeyDown(.left)) {
        vel.value.xMut().* = std.math.clamp(vel.value.x() - acceleration, -speed.x(), speed.x());
        next_animation = .{ .name = "player_1", .speed = 10, .flip_x = true };
    }
    // Move right.
    else if (rl.isKeyDown(.l) or rl.isKeyDown(.right)) {
        vel.value.xMut().* = std.math.clamp(vel.value.x() + acceleration, -speed.x(), speed.x());
        next_animation = .{ .name = "player_1", .speed = 10, .flip_x = false };
    }
    // Gradually stop moving.
    else {
        const vel_amount = @abs(vel.value.x());
        const amount = @min(vel_amount, vel_amount * decel_factor * delta_time);
        vel.value.xMut().* -= amount * std.math.sign(vel.value.x());
        if (@abs(vel.value.x()) < 0.01) vel.value.xMut().* = 0;
    }

    // Jump.
    if (rl.isKeyPressed(.space) and vel.value.y() == 0) {
        vel.value.yMut().* = -speed.y();
        game.playSound(game.sounds.jump);
    }

    // Set jump animation if player is in the air.
    if (!collision.grounded()) {
        next_animation = .{
            .name = "player_1",
            .speed = 0,
            // Inherit flip flag from current movement.
            .flip_x = next_animation.flip_x,
            .frame = 1,
        };
    }

    // Change animation.
    visual.animation.changeAnimation(next_animation);
}

/// Reset game state.
fn reset(game: *Game) !void {
    const reg = game.reg;

    // Reset score.
    game.score = 0;

    // Clear entity references.
    game.entities.clear();

    // Delete all entities.
    var it = reg.entities();
    while (it.next()) |entity| {
        reg.destroy(entity);
    }

    const tilemap = game.tilemap;
    const map_size = m.Vec2.new(
        @floatFromInt(tilemap.data.width * tilemap.data.tilewidth),
        @floatFromInt(tilemap.data.height * tilemap.data.tileheight),
    );

    // Setup map boundaries.
    {
        const left = reg.create();
        reg.add(left, comp.Position.new(0, 0));
        reg.add(left, comp.Collision.new(prefabs.CollisionLayer.map, 0, map_size.mul(m.Vec2.new(0, 1))));
        const right = reg.create();
        reg.add(right, comp.Position.new(map_size.x(), 0));
        reg.add(right, comp.Collision.new(prefabs.CollisionLayer.map, 0, map_size.mul(m.Vec2.new(0, 1))));
    }

    // Setup tilemap.
    {
        const tileset = try tilemap.getTileset(1);
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
                        comp.Visual.sprite(game.sprites.tileset_texture, tileset.getSpriteRect(tile_id)),
                        null,
                    );
                    // Add collision for first layer only.
                    if (layer.id < 2) {
                        reg.add(entity, comp.Collision.new(prefabs.CollisionLayer.map, 0, shape.getSize()));
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

    // Setup enemy colliders
    {
        var objects_it = tilemap.data.objects_by_id.valueIterator();
        while (objects_it.next()) |object| {
            if (std.mem.eql(u8, object.*.type, "enemy_collider")) {
                const pos = m.Vec2.new(object.*.x, object.*.y);
                const shape = comp.Shape.rectangle(object.*.width, object.*.height);
                const entity = reg.create();
                reg.add(entity, comp.Position.fromVec2(pos));
                reg.add(entity, shape);
                reg.add(entity, comp.Collision.new(prefabs.CollisionLayer.enemy_colliders, 0, shape.getSize()));
            }
        }
    }

    // Setup player colliders.
    // Player colliding with these will kill the player.
    {
        var objects_it = tilemap.data.objects_by_id.valueIterator();
        while (objects_it.next()) |object| {
            if (std.mem.eql(u8, object.*.type, "player_death")) {
                const pos = m.Vec2.new(object.*.x, object.*.y);
                const shape = comp.Shape.rectangle(object.*.width, object.*.height);
                const entity = reg.create();
                reg.add(entity, comp.DeadlyCollider{});
                reg.add(entity, comp.Position.fromVec2(pos));
                reg.add(entity, shape);
                reg.add(entity, comp.Collision.new(
                    prefabs.CollisionLayer.deadly_colliders,
                    0,
                    shape.getSize(),
                ));
            }
        }
    }

    // Setup new player entity.
    {
        const player_spawn_object = try tilemap.data.getObject("player_spawn");
        const spawn_pos = m.Vec2.new(player_spawn_object.x, player_spawn_object.y);
        prefabs.spawnPlayer(
            game.reg,
            game.entities.getPlayer(),
            spawn_pos,
            game.sprites.player_texture,
            game.sprites.player_atlas,
        );
    }

    // Spawn enemies.
    {
        var objects_it = tilemap.data.objects_by_id.valueIterator();
        while (objects_it.next()) |object| {
            const spawn_pos = m.Vec2.new(object.*.x, object.*.y);
            if (std.mem.eql(u8, object.*.type, "enemy1_spawn")) {
                _ = prefabs.createEnemey1(game.reg, spawn_pos, game.sprites.enemies_texture, game.sprites.enemies_atlas);
            } else if (std.mem.eql(u8, object.*.type, "enemy2_spawn")) {
                _ = prefabs.createEnemey2(game.reg, spawn_pos, game.sprites.enemies_texture, game.sprites.enemies_atlas);
            }
        }
    }

    // Spawn items.
    {
        var objects_it = tilemap.data.objects_by_id.valueIterator();
        while (objects_it.next()) |object| {
            const spawn_pos = m.Vec2.new(object.*.x, object.*.y);
            if (std.mem.eql(u8, object.*.type, "coin")) {
                _ = prefabs.createCoin(game.reg, spawn_pos);
            }
        }
    }
}

fn killPlayer(game: *Game) void {
    game.playSound(game.sounds.die);

    const reg = game.reg;
    const e = game.entities.getPlayer();

    // Add a lifetime component to make the player disappear.
    reg.add(e, comp.Lifetime.new(1));

    // Mark player as killed.
    var player = reg.get(comp.Player, e);
    player.kill();

    // Change collision mask to avoid further collision.
    var collision = reg.get(comp.Collision, e);
    collision.mask = 0;
    collision.layer = prefabs.CollisionLayer.background;

    // Make player bounce before death and stop moving horizontally.
    const speed = reg.get(comp.Speed, e);
    var vel = reg.get(comp.Velocity, e);
    vel.value = m.Vec2.new(0, -speed.value.y() * 0.5);

    // Play death animation.
    var visual = reg.get(comp.Visual, e);
    visual.animation.changeAnimation(.{
        .name = "player_2",
        .speed = 0,
        .loop = false,
        .flip_x = visual.animation.definition.flip_x,
        .padding = visual.animation.definition.padding,
    });
}

fn killEnemy(game: *Game, entity: entt.Entity) void {
    game.playSound(game.sounds.hit);

    const reg = game.reg;

    const enemy = reg.get(comp.Enemy, entity);
    const score_info = switch (enemy.type) {
        .slow => ScoreInfo{ .text = FloatingText.score_10, .value = 10 },
        .fast => ScoreInfo{ .text = FloatingText.score_20, .value = 20 },
    };
    game.updateScore(score_info.value);
    const pos = reg.get(comp.Position, entity);
    _ = prefabs.createFloatingText(game.reg, pos.toVec2(), score_info.text);

    // Add a lifetime component to make the entity disappear
    // after lifetime ended.
    reg.add(entity, comp.Lifetime.new(1));

    // Remove Enemy component to avoid unnecessary updates.
    reg.remove(comp.Enemy, entity);

    // Set velocity to zero.
    var enemy_vel = reg.get(comp.Velocity, entity);
    enemy_vel.value = m.Vec2.zero();

    // Shrink enemy size to half.
    var enemy_shape = reg.get(comp.Shape, entity);
    enemy_shape.rectangle.height *= 0.5;
    var enemy_collision = reg.get(comp.Collision, entity);
    enemy_collision.aabb_size = enemy_collision.aabb_size.mul(m.Vec2.new(1, 0.5));

    // Avoid further collision with player.
    enemy_collision.mask = enemy_collision.mask & ~prefabs.CollisionLayer.player;
    enemy_collision.layer = prefabs.CollisionLayer.background;

    // Freeze animation.
    var enemy_visual = reg.get(comp.Visual, entity);
    enemy_visual.animation.freeze();
}

fn pickupItem(game: *Game, entity: entt.Entity) void {
    const ItemInfo = struct {
        score: ScoreInfo,
        sound: rl.Sound,
    };
    const item = game.reg.getConst(comp.Item, entity);
    const item_info = switch (item.type) {
        .coin => ItemInfo{
            .score = ScoreInfo{ .text = FloatingText.score_20, .value = 20 },
            .sound = game.sounds.pickup_coin,
        },
    };
    game.playSound(item_info.sound);
    game.updateScore(item_info.score.value);
    const pos = game.reg.getConst(comp.Position, entity);
    _ = prefabs.createFloatingText(game.reg, pos.toVec2(), item_info.score.text);
    game.reg.destroy(entity);
}

fn updateEnemies(game: *Game) void {
    const reg = game.reg;
    var view = reg.view(.{ comp.Enemy, comp.Velocity, comp.Speed, comp.Collision }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const speed = view.get(comp.Speed, entity);
        var vel = view.get(comp.Velocity, entity);
        var visual = view.get(comp.Visual, entity);
        const collision = view.get(comp.Collision, entity);
        // Reverse direction if collision occurred on x axis.
        const direction = if (collision.normal.x() == 0) std.math.sign(vel.value.x()) else collision.normal.x();
        const direction_speed = speed.value.mul(m.Vec2.new(direction, 0));
        const flip_x = direction < 0;
        visual.animation.changeAnimation(.{
            .name = visual.animation.definition.name,
            .speed = visual.animation.definition.speed,
            .padding = visual.animation.definition.padding,
            .flip_x = flip_x,
        });
        vel.value.xMut().* = direction_speed.x();
    }
}

//------------------------------------------------------------------------------
// Physics
//------------------------------------------------------------------------------

fn detectCollisions(
    reg: *entt.Registry,
    collision_system: *systems.collision.CollisionSystem,
    delta_time: f32,
) !void {
    const CollisionData = systems.collision.CollisionData;

    var view = reg.view(.{ comp.Position, comp.Velocity, comp.Collision }, .{});
    var it = view.entityIterator();

    // Reset collision state for all dynamic entities.
    while (it.next()) |entity| {
        var collision = view.get(comp.Collision, entity);
        collision.normal = m.Vec2.zero();
    }

    it.reset();

    // Perform collision detection.
    while (it.next()) |entity| {
        collision_system.onEntityCollisionDetection();

        const pos = view.get(comp.Position, entity);
        var collision_comp = view.get(comp.Collision, entity);
        var vel = view.get(comp.Velocity, entity);
        const aabb = coll.Aabb.new(pos.toVec2(), collision_comp.aabb_size);
        const broadphase_aabb = coll.Aabb.fromMovement(pos.toVec2(), collision_comp.aabb_size, vel.value.scale(delta_time));

        // Perform broadphase collision detection.
        var collider_view = reg.view(.{ comp.Position, comp.Collision }, .{});
        var collider_it = collider_view.entityIterator();
        while (collider_it.next()) |collider| {
            // Skip collision check with self.
            if (collider == entity) continue;

            // Skip collision check if entities cannot collide.
            const collider_collision_comp = collider_view.getConst(comp.Collision, collider);
            if (!collision_comp.canCollide(collider_collision_comp)) continue;

            const collider_pos = collider_view.get(comp.Position, collider).toVec2();
            const collider_size = collider_collision_comp.aabb_size;
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
            // Check intersection between broadphase AABBs.
            if (broadphase_aabb.intersects(broadphase_collider_aabb)) {
                const collider_aabb = coll.Aabb.new(collider_pos, collider_size);
                const relative_vel = vel.value.sub(collider_vel).scale(delta_time);
                // Calculate time of impact based on relative velocity.
                const result = coll.aabbToAabb(aabb, collider_aabb, relative_vel);
                try collision_system.buffer.append(CollisionData.new(
                    entity,
                    aabb,
                    collider,
                    collider_aabb,
                    collider_vel,
                    result,
                ));
            }
        }

        // Sort collisions by time to resolve nearest collision first.
        collision_system.sortBuffer();

        // Append collisions in order.
        for (collision_system.buffer.items) |collision| {
            // Skip collisions, that are already in the list.
            if (!collision_system.queue.contains(collision.hash())) {
                try collision_system.queue.append(collision);
            }
        }
    }
}

fn handleCollisions(
    game: *Game,
    collision_system: *systems.collision.CollisionSystem,
    delta_time: f32,
) void {
    const reg = game.reg;
    for (collision_system.queue.items()) |collision| {
        var vel = reg.get(comp.Velocity, collision.entity);
        var collision_comp = reg.get(comp.Collision, collision.entity);
        const relative_vel = vel.value.sub(collision.collider_vel).scale(delta_time);
        const result = coll.aabbToAabb(collision.entity_aabb, collision.collider_aabb, relative_vel);
        if (result.hit) {
            const entity_is_player = reg.has(comp.Player, collision.entity);
            const collider_is_player = reg.has(comp.Player, collision.collider);
            const entity_is_enemy = reg.has(comp.Enemy, collision.entity);
            const collider_is_enemy = reg.has(comp.Enemy, collision.collider);

            const collide_with_enemy = entity_is_enemy or collider_is_enemy;
            const collide_deadly = reg.has(comp.DeadlyCollider, collision.entity) or reg.has(comp.DeadlyCollider, collision.collider);
            const collide_item = reg.has(comp.Item, collision.entity) or reg.has(comp.Item, collision.collider);

            const use_entity_specific_response =
                (entity_is_player or collider_is_player) and
                (collide_with_enemy or collide_deadly or collide_item);

            // Use entity-specific collision response.
            // This is relevant, if the player collides with an enemy, a deadly collider or an item.
            if (use_entity_specific_response) {
                if (collide_with_enemy) {
                    const kill_enemy_normal: f32 = if (collider_is_player) 1 else -1;
                    if (result.normal.y() == kill_enemy_normal) {
                        const enemy_entity = if (entity_is_enemy) collision.entity else collision.collider;
                        killEnemy(game, enemy_entity);
                        // Make player bounce off the top of the enemy.
                        const player = game.entities.getPlayer();
                        const player_speed = reg.get(comp.Speed, player);
                        const player_vel = reg.get(comp.Velocity, player);
                        player_vel.value.yMut().* = -player_speed.value.y() * 0.5;
                    } else {
                        killPlayer(game);
                    }
                } else if (collide_deadly) {
                    killPlayer(game);
                } else if (collide_item) {
                    pickupItem(game, collision.collider);
                }
            }
            // Use default collision response.
            else {
                // Correct velocity to resolve collision.
                vel.value = coll.resolveCollision(result, vel.value);
                // Set collision normals.
                collision_comp.setNormals(result.normal);
                // TODO: Disabled, since we're not handling dynamic vs. dynamic collisions here.
                // // Resolve collision for dynamic collider.
                // if (reg.tryGet(comp.Velocity, collision.entity)) |collider_vel| {
                //     collider_vel.value = coll.resolveCollision(result, collider_vel.value);
                //     var collider_collision = reg.get(comp.Collision, collision.entity);
                //     collider_collision.normal = collision_comp.normal.scale(-1);
                // }
            }
        }
    }
}

fn drawHud(game: *Game) void {
    const alloc = game.app.allocator;

    const score_str = std.fmt.allocPrintZ(alloc, "SCORE: {d}", .{game.score}) catch unreachable;
    defer alloc.free(score_str);

    const font_size = 20;
    rl.drawText(score_str, 10, 10, font_size, rl.Color.ray_white);
}
