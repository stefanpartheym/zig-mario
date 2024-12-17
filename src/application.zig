const std = @import("std");
const rl = @import("raylib");

pub const Application = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: ApplicationConfig,
    state: ApplicationState,

    pub fn init(allocator: std.mem.Allocator, config: ApplicationConfig) Self {
        return Self{
            .allocator = allocator,
            .state = .stopped,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn start(self: *Self) void {
        const display = self.config.display;
        rl.setConfigFlags(.{
            .window_highdpi = display.high_dpi,
        });
        rl.setTraceLogLevel(rl.TraceLogLevel.log_warning);
        rl.setTargetFPS(display.target_fps);
        rl.initWindow(
            @intCast(display.width),
            @intCast(display.height),
            self.config.title,
        );

        self.changeState(.running);
    }

    pub fn shutdown(self: *Self) void {
        self.changeState(.shutdown);
    }

    pub fn stop(self: *Self) void {
        rl.closeWindow();
        self.changeState(.stopped);
    }

    pub fn isRunning(self: *const Self) bool {
        return self.state == .running;
    }

    fn changeState(self: *Self, newState: ApplicationState) void {
        self.state = newState;
    }
};

pub const ApplicationState = enum {
    stopped,
    running,
    shutdown,
};

pub const ApplicationConfig = struct {
    const Self = @This();

    title: [:0]const u8,
    display: struct {
        width: u32,
        height: u32,
        target_fps: u8,
        high_dpi: bool,
    },

    pub fn getDisplayWidth(self: *const Self) f32 {
        return @floatFromInt(self.display.width);
    }

    pub fn getDisplayHeight(self: *const Self) f32 {
        return @floatFromInt(self.display.height);
    }
};
