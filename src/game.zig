const std = @import("std");
const entt = @import("entt");
const m = @import("math/mod.zig");
const application = @import("application.zig");
const comp = @import("components.zig");
const Timer = @import("timer.zig").Timer;

const GameState = enum {
    ready,
    paused,
    playing,
    won,
    lost,
    gameover,
};

pub const GameEntities = struct {
    const Self = @This();

    reg: *entt.Registry,
    player: ?entt.Entity,

    pub fn new(reg: *entt.Registry) Self {
        return Self{ .player = null, .reg = reg };
    }

    pub fn clear(self: *Self) void {
        self.player = null;
    }

    /// Get the player entity.
    /// Creates the player entity if it doe not yet exist.
    pub fn getPlayer(self: *Self) entt.Entity {
        if (self.player == null) {
            self.player = self.reg.create();
        }
        return self.player.?;
    }

    /// Returns the players center position.
    pub fn getPlayerCenter(self: *Self) m.Vec2 {
        const player = self.getPlayer();
        const pos = self.reg.get(comp.Position, player);
        const shape = self.reg.get(comp.Shape, player);
        return pos.toVec2().add(shape.getSize().scale(0.5));
    }
};

/// Contains all game related state.
pub const Game = struct {
    const Self = @This();

    state: GameState,
    app: *application.Application,
    config: *application.ApplicationConfig,
    reg: *entt.Registry,
    debug_mode: bool,

    entities: GameEntities,
    score: u32,
    lives: u8,
    /// Tracks the time elapsed since the the player started the game.
    /// When the player pauses the game, the timer is also paused.
    timer: Timer,

    pub fn new(
        app: *application.Application,
        reg: *entt.Registry,
    ) Self {
        return Self{
            .state = .ready,
            .app = app,
            .config = &app.config,
            .reg = reg,
            .debug_mode = false,
            .entities = GameEntities.new(reg),
            .score = 0,
            .lives = 3,
            .timer = Timer.new(),
        };
    }

    pub fn isPlaying(self: *const Self) bool {
        return self.state == .playing;
    }

    pub fn start(self: *Self) void {
        self.state = .playing;
        self.timer.reset();
        self.lives = 3;
        self.score = 0;
    }

    pub fn pause(self: *Self) void {
        self.state = .paused;
    }

    pub fn loose(self: *Self) void {
        self.lives -= 1;
        self.state = .lost;
        if (self.lives == 0) {
            gameover(self);
        }
    }

    pub fn win(self: *Self) void {
        self.state = .won;
    }

    pub fn gameover(self: *Self) void {
        self.state = .gameover;
    }

    pub fn toggleDebugMode(self: *Self) void {
        self.debug_mode = !self.debug_mode;
    }
};
