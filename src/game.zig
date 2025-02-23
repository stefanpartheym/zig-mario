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

    pub fn isPlayerAlive(self: *Self) bool {
        return self.player != null and !self.reg.getConst(comp.Player, self.player.?).dying;
    }

    pub fn isPlayerDying(self: *Self) bool {
        return self.player != null and self.reg.getConst(comp.Player, self.player.?).dying;
    }

    pub fn isPlayerDead(self: *Self) bool {
        return self.player != null and !self.reg.valid(self.player.?);
    }
};

pub const GameSprites = struct {
    tileset_texture: *const rl.Texture = undefined,
    player_texture: *const rl.Texture = undefined,
    player_atlas: *graphics.sprites.AnimatedSpriteSheet = undefined,
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
    pickup_coin: rl.Sound = undefined,
};

/// Contains all game related state.
pub const Game = struct {
    const Self = @This();

    state: GameState,
    app: *application.Application,
    config: *application.ApplicationConfig,
    reg: *entt.Registry,
    debug_mode: bool,
    audio_enabled: bool,

    entities: GameEntities,
    sprites: GameSprites,
    sounds: GameSounds,
    tilemap: *tiled.Tilemap,

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
            .audio_enabled = true,
            .entities = GameEntities.new(reg),
            .sprites = GameSprites{},
            .sounds = GameSounds{},
            .tilemap = undefined,
            .score = 0,
            .lives = 3,
            .timer = Timer.new(),
        };
    }

    pub fn isPlaying(self: *const Self) bool {
        return self.state == .playing;
    }

    pub fn isPaused(self: *const Self) bool {
        return self.state == .paused;
    }

    pub fn playerLost(self: *const Self) bool {
        return self.state == .lost;
    }

    pub fn isGameover(self: *const Self) bool {
        return self.state == .gameover;
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

    pub fn unpause(self: *Self) void {
        self.state = .playing;
    }

    pub fn loose(self: *Self) void {
        self.lives -= 1;
        self.state = .lost;
        if (self.lives == 0) {
            gameover(self);
        }
        // TODO: Score currently reset, but should be kept in the future.
        self.score = 0;
    }

    pub fn win(self: *Self) void {
        self.state = .won;
    }

    pub fn gameover(self: *Self) void {
        self.state = .gameover;
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
};
