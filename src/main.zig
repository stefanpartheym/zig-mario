const std = @import("std");
const rl = @import("raylib");
const zb = @import("zbox2d");
const entt = @import("entt");
const m = @import("math/mod.zig");
const paa = @import("paa.zig");
const application = @import("application.zig");
const Game = @import("game.zig").Game;
const entities = @import("entities.zig");
const comp = @import("components.zig");
const systems = @import("systems.zig");

pub fn main() !void {
    var alloc = paa.init();
    defer alloc.deinit();

    var app = application.Application.init(
        alloc.allocator(),
        application.ApplicationConfig{
            .title = "zig-mario",
            .display = .{
                .width = 800,
                .height = 600,
                .high_dpi = true,
                .target_fps = 60,
            },
        },
    );
    defer app.deinit();

    var reg = entt.Registry.init(alloc.allocator());
    defer reg.deinit();

    var game = Game.new(&app, &reg);
    reset(&game);

    app.start();
    while (app.isRunning()) {
        const delta_time = rl.getFrameTime();
        handleAppInput(&game);
        handlePlayerInput(&game, delta_time);
        applyGravity(game.reg, 9.81, delta_time);
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
    const player = game.getPlayer();
    const speed = reg.getConst(comp.Speed, player);
    const scaled_speed = speed.x * delta_time;
    var vel = reg.get(comp.Velocity, player);
    var movement = reg.get(comp.Movement, player);

    vel.x = 0;
    movement.update(.none);

    if (rl.isKeyDown(rl.KeyboardKey.key_h) or
        rl.isKeyDown(rl.KeyboardKey.key_left))
    {
        vel.x -= scaled_speed;
        movement.update(.left);
    } else if (rl.isKeyDown(rl.KeyboardKey.key_l) or
        rl.isKeyDown(rl.KeyboardKey.key_right))
    {
        vel.x += scaled_speed;
        movement.update(.right);
    }
}

fn reset(game: *Game) void {
    const reg = game.reg;

    // Clear entity references.
    game.entities.clear();

    // Delete all entities.
    var it = reg.entities();
    while (it.next()) |entity| {
        reg.destroy(entity);
    }

    // Setup new player entity.
    {
        const player = game.getPlayer();
        const spawn_pos = m.Vec2.new(50, 50);
        entities.setRenderable(
            reg,
            player,
            comp.Position.fromVec2(spawn_pos),
            comp.Shape.rectangle(40, 60),
            comp.Visual.stub(),
            comp.VisualLayer.new(1),
        );
        entities.setMovable(
            reg,
            player,
            comp.Speed.uniform(350),
        );
        reg.add(player, comp.Collision.new());
        reg.add(player, comp.Gravity.new());
    }

    // Setup map.
    {
        const ground1 = reg.create();
        const ground_height = 60;
        entities.setRenderable(
            reg,
            ground1,
            comp.Position.new(0, game.config.getDisplayHeight() - ground_height),
            comp.Shape.rectangle(600, ground_height),
            comp.Visual.color(rl.Color.dark_brown, false),
            null,
        );
        reg.add(ground1, comp.Collision.new());
        const wall1 = reg.create();
        const wall_height = 200;
        entities.setRenderable(
            reg,
            wall1,
            comp.Position.new(400, game.config.getDisplayHeight() - wall_height),
            comp.Shape.rectangle(40, wall_height),
            comp.Visual.color(rl.Color.dark_gray, false),
            null,
        );
        reg.add(wall1, comp.Collision.new());
    }
}

//------------------------------------------------------------------------------
// Physics
//------------------------------------------------------------------------------

fn applyGravity(reg: *entt.Registry, force: f32, delta_time: f32) void {
    var view = reg.view(.{ comp.Velocity, comp.Gravity }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const gravity = view.get(comp.Gravity, entity);
        var vel = view.get(comp.Velocity, entity);
        vel.y += force * delta_time * gravity.factor;
    }
}

fn updatePosition(reg: *entt.Registry) void {
    var view = reg.view(.{ comp.Position, comp.Velocity }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const vel = view.getConst(comp.Velocity, entity);
        var pos = view.get(comp.Position, entity);
        pos.x += vel.x;
        pos.y += vel.y;
    }
}
