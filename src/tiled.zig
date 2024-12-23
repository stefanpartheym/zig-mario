const std = @import("std");
const m = @import("math/mod.zig");

pub const Tileset = struct {
    const Self = @This();

    pub const Data = struct {
        columns: u32,
        image: []const u8,
        imageheight: u32,
        imagewidth: u32,
        margin: u32,
        name: []const u8,
        spacing: u32,
        tilecount: u32,
        tiledversion: []const u8,
        tileheight: u32,
        tilewidth: u32,
        type: []const u8,
        version: []const u8,
    };

    allocator: std.mem.Allocator,
    data: Data,
    parse_result: std.json.Parsed(Data),
    image_path: []const u8,

    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, size);
        defer allocator.free(buffer);
        _ = try file.readAll(buffer);
        const result = try std.json.parseFromSlice(
            Data,
            allocator,
            buffer,
            .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
            },
        );
        return Self{
            .allocator = allocator,
            .data = result.value,
            .parse_result = result,
            .image_path = try std.fs.path.join(
                allocator,
                &.{ std.fs.path.dirname(path).?, result.value.image },
            ),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.image_path);
        self.parse_result.deinit();
    }

    pub fn getTilePosition(self: *const Self, tile_id: u32) m.Vec2_usize {
        const tile_index = tile_id - 1;
        return m.Vec2_usize.new(
            tile_index % self.data.columns,
            @divFloor(tile_index, self.data.columns),
        );
    }

    pub fn getSpriteRect(self: *const Self, tile_id: u32) m.Rect {
        const tile_pos = self.getTilePosition(tile_id);
        return m.Rect{
            .x = @floatFromInt(self.data.tilewidth * tile_pos.x()),
            .y = @floatFromInt(self.data.tileheight * tile_pos.y()),
            .width = @floatFromInt(self.data.tilewidth),
            .height = @floatFromInt(self.data.tileheight),
        };
    }
};

pub const Tilemap = struct {
    const Self = @This();

    pub const Data = struct {
        width: u32,
        height: u32,
        tilewidth: u32,
        tileheight: u32,
        layers: []Layer,
        tilesets: []ReferencedTileset,
    };

    const Layer = struct {
        id: u32,
        name: []const u8,
        data: []u32,
        visible: bool,
        opacity: f32,
        width: u32,
        height: u32,
        x: u32,
        y: u32,
    };

    pub const ReferencedTileset = struct {
        firstgid: u32,
        source: []const u8,
    };

    pub const TilemapError = error{
        NoSuchTileset,
    };

    allocator: std.mem.Allocator,
    cwd: []const u8,
    data: Data,
    parse_result: std.json.Parsed(Data),
    tilesets: std.AutoHashMap(u32, Tileset),

    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, size);
        defer allocator.free(buffer);
        _ = try file.readAll(buffer);
        const result = try std.json.parseFromSlice(
            Data,
            allocator,
            buffer,
            .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
            },
        );
        return Self{
            .cwd = std.fs.path.dirname(path).?,
            .allocator = allocator,
            .data = result.value,
            .parse_result = result,
            .tilesets = std.AutoHashMap(u32, Tileset).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var tileset_it = self.tilesets.valueIterator();
        while (tileset_it.next()) |tileset| {
            tileset.deinit();
        }
        self.tilesets.deinit();
        self.parse_result.deinit();
    }

    pub fn getTileset(self: *Self, id: u32) !*const Tileset {
        if (self.tilesets.getPtr(id)) |tileset| {
            return tileset;
        } else {
            const tileset_ref = for (self.data.tilesets) |item| {
                if (item.firstgid == id) {
                    break item;
                }
            } else {
                return TilemapError.NoSuchTileset;
            };
            const path = try std.fs.path.join(self.allocator, &.{ self.cwd, tileset_ref.source });
            defer self.allocator.free(path);
            try self.tilesets.put(id, try Tileset.fromFile(self.allocator, path));
            return self.tilesets.getPtr(id).?;
        }
    }
};
