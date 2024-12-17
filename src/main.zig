const std = @import("std");
const rl = @import("raylib");
const entt = @import("entt");
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
    game.player = entities.createRenderable(
        game.reg,
        comp.Position.new(100, 100),
        comp.Shape.rectangle(100, 100),
        comp.Visual.stub(),
        null,
    );

    app.start();
    while (app.isRunning()) {
        handleAppInput(&game);
        systems.beginFrame(rl.Color.black);
        systems.draw(game.reg);
        if (game.debug_mode) {
            systems.drawDebug(game.reg, rl.Color.yellow);
        }
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
