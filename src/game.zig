const std = @import("std");
const rl = @import("raylib");
const entt = @import("entt");
const graphics = @import("graphics/mod.zig");
const m = @import("math/mod.zig");
const application = @import("application.zig");
const comp = @import("components.zig");
const tiled = @import("tiled.zig");
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
            // TODO: Return an error rather than implicitly creating the entity.
            self.player = self.reg.create();
        }
        return self.player.?;
    }

    /// Returns the players center position.
    pub fn getPlayerCenter(self: *Self) m.Vec2 {
        const entity = self.getPlayer();
        const pos = self.reg.get(comp.Position, entity);
        const shape = self.reg.get(comp.Shape, entity);
        return pos.toVec2().add(shape.getSize().scale(0.5));
    }
};

pub const GameSprites = struct {
    tileset_texture: *const rl.Texture = undefined,
    player_texture: *const rl.Texture = undefined,
    player_atlas: *graphics.sprites.AnimatedSpriteSheet = undefined,
    portal_texture: *const rl.Texture = undefined,
    portal_atlas: *graphics.sprites.AnimatedSpriteSheet = undefined,
    enemies_texture: *const rl.Texture = undefined,
    enemies_atlas: *graphics.sprites.AnimatedSpriteSheet = undefined,
    item_coin_texture: *const rl.Texture = undefined,
    item_coin_atlas: *graphics.sprites.AnimatedSpriteSheet = undefined,
    background_layer_1_texture: *const rl.Texture = undefined,
    background_layer_2_texture: *const rl.Texture = undefined,
    background_layer_3_texture: *const rl.Texture = undefined,
    ui_pause: *const rl.Texture = undefined,
    ui_heart: *const rl.Texture = undefined,
    ui_coin: *const rl.Texture = undefined,
};

pub const GameSounds = struct {
    soundtrack: rl.Music = undefined,
    jump: rl.Sound = undefined,
    hit: rl.Sound = undefined,
    die: rl.Sound = undefined,
    portal: rl.Sound = undefined,
    pickup_coin: rl.Sound = undefined,
};

/// Contains all game related state.
pub const Game = struct {
    const Self = @This();

    state: GameState,
    next_state: ?GameState,
    app: *application.Application,
    config: *application.ApplicationConfig,
    reg: *entt.Registry,
    reset_fn: *const fn (self: *Self) anyerror!void,
    restart_fn: *const fn (self: *Self) anyerror!void,

    entities: GameEntities,
    sprites: GameSprites,
    sounds: GameSounds,
    tilemap: *tiled.Tilemap,

    debug_mode: bool,
    audio_enabled: bool,
    score: u32,
    lives: u8,
    /// Tracks the time elapsed since the the player started the game.
    /// When the player pauses the game, the timer is also paused.
    timer: Timer,
    /// Tracks when to change to the next state.
    state_timer: Timer,
    state_delay: f32,

    pub fn new(
        app: *application.Application,
        reg: *entt.Registry,
        reset_fn: fn (self: *Self) anyerror!void,
        restart_fn: fn (self: *Self) anyerror!void,
    ) Self {
        return Self{
            .state = .ready,
            .next_state = null,
            .app = app,
            .config = &app.config,
            .reg = reg,
            .reset_fn = reset_fn,
            .restart_fn = restart_fn,
            .debug_mode = false,
            .audio_enabled = true,
            .entities = GameEntities.new(reg),
            .sprites = GameSprites{},
            .sounds = GameSounds{},
            .tilemap = undefined,
            .score = 0,
            .lives = 3,
            .timer = Timer.new(),
            .state_timer = Timer.new(),
            .state_delay = 0,
        };
    }

    pub fn update(self: *Self, delta: f32) void {
        if (self.next_state) |next_state| {
            self.state_timer.update(delta);
            if (self.state_timer.state >= self.state_delay) {
                self.transition(next_state);
                self.next_state = null;
            }
        }
    }

    pub fn setState(self: *Self, new_state: GameState) void {
        if (self.next_state == null) {
            self.transition(new_state);
            self.next_state = null;
        }
    }

    pub fn changeState(self: *Self, next_state: GameState, delay: f32) void {
        self.next_state = next_state;
        self.state_timer.reset();
        if (delay == 0) {
            self.setState(next_state);
        } else {
            self.state_delay = delay;
        }
    }

    pub fn updateScore(self: *Self, value: u32) void {
        self.score += value;
    }

    pub fn playSound(self: *const Self, sound: rl.Sound) void {
        if (self.audio_enabled) {
            rl.playSound(sound);
        }
    }

    pub fn toggleDebugMode(self: *Self) void {
        self.debug_mode = !self.debug_mode;
    }

    pub fn toggleAudio(self: *Self) void {
        self.audio_enabled = !self.audio_enabled;
    }

    /// Transitions to the next state.
    fn transition(self: *Self, next_state: GameState) void {
        var new_state = next_state;
        switch (self.state) {
            .won, .gameover, .ready => switch (next_state) {
                .playing => {
                    self.timer.reset();
                    self.lives = 3;
                    self.score = 0;
                    // TODO: catch unreachable for now to avoid error handling.
                    self.reset_fn(self) catch unreachable;
                },
                else => @panic("Invalid state transition"),
            },
            .lost => switch (next_state) {
                .playing => {
                    self.timer.reset();
                    // TODO: catch unreachable for now to avoid error handling.
                    self.restart_fn(self) catch unreachable;
                },
                else => @panic("Invalid state transition"),
            },
            .playing => switch (next_state) {
                .paused, .won => {},
                .lost => {
                    self.lives -= 1;
                    if (self.lives == 0) {
                        new_state = .gameover;
                    }
                },
                else => @panic("Invalid state transition"),
            },
            .paused => switch (next_state) {
                .playing => {},
                else => @panic("Invalid state transition"),
            },
        }
        // Apply new state.
        self.state = new_state;
    }
};
