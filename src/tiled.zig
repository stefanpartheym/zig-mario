const std = @import("std");
const m = @import("math/mod.zig");

pub const TilemapError = error{
    NoSuchTileset,
    NoSuchObject,
    InvalidLayerType,
};

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
        const buffer = try allocator.alloc(u8, @intCast(size));
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

    allocator: std.mem.Allocator,
    cwd: []const u8,
    data: TilemapData,
    parse_result: std.json.Parsed(ParsedTilemapData),
    tilesets: std.AutoHashMap(u32, Tileset),

    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, @intCast(size));
        defer allocator.free(buffer);
        _ = try file.readAll(buffer);
        const result = try std.json.parseFromSlice(
            ParsedTilemapData,
            allocator,
            buffer,
            .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
            },
        );
        errdefer result.deinit();
        return Self{
            .cwd = std.fs.path.dirname(path).?,
            .allocator = allocator,
            .data = try TilemapData.fromParsed(allocator, &result.value),
            .parse_result = result,
            .tilesets = std.AutoHashMap(u32, Tileset).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var tileset_it = self.tilesets.valueIterator();
        while (tileset_it.next()) |tileset| {
            tileset.deinit();
        }
        self.data.deinit();
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

pub const TilemapData = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    tilewidth: u32,
    tileheight: u32,
    layers: []Layer,
    tilesets: []TilesetRef,
    /// Access objects of all layers by name.
    objects: std.StringHashMap(*const Object),

    pub fn fromParsed(allocator: std.mem.Allocator, data: *const ParsedTilemapData) !Self {
        var self = Self{
            .allocator = allocator,
            .width = data.width,
            .height = data.height,
            .tilewidth = data.tilewidth,
            .tileheight = data.tileheight,
            .layers = try allocator.alloc(Layer, data.layers.len),
            .tilesets = data.tilesets,
            .objects = std.StringHashMap(*const Object).init(allocator),
        };

        for (data.layers, 0..) |parsed_layer, i| {
            const layer_type = if (std.mem.eql(u8, parsed_layer.type, "tilelayer"))
                TilemapLayerType.tilelayer
            else if (std.mem.eql(u8, parsed_layer.type, "objectgroup"))
                TilemapLayerType.objectgroup
            else
                return TilemapError.InvalidLayerType;

            var layer = Layer{
                .id = parsed_layer.id,
                .type = layer_type,
                .name = parsed_layer.name,
                .visible = parsed_layer.visible,
                .opacity = parsed_layer.opacity,
                .width = parsed_layer.width,
                .height = parsed_layer.height,
                .x = parsed_layer.x,
                .y = parsed_layer.y,
                .tiles = &[_]u32{},
                .objects = &[_]Object{},
            };

            switch (layer_type) {
                .objectgroup => {
                    layer.objects = parsed_layer.objects.?;
                    // Add all objects to the object map.
                    for (layer.objects) |*object| {
                        try self.objects.put(object.name, object);
                    }
                },
                .tilelayer => layer.tiles = parsed_layer.data.?,
            }

            self.layers[i] = layer;
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.objects.deinit();
        self.allocator.free(self.layers);
    }

    /// Access object of any layers by its name.
    pub fn getObject(self: *const Self, name: []const u8) !*const Object {
        if (self.objects.get(name)) |object| {
            return object;
        } else {
            return TilemapError.NoSuchObject;
        }
    }
};

const ParsedTilemapData = struct {
    width: u32,
    height: u32,
    tilewidth: u32,
    tileheight: u32,
    layers: []ParsedLayer,
    tilesets: []TilesetRef,
};

const ParsedLayer = struct {
    id: u32,
    type: []const u8,
    name: []const u8,
    visible: bool,
    opacity: f32,
    width: u32 = 0,
    height: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,
    /// `data` is only set if layer is of type tilelayer.
    data: ?[]u32 = null,
    /// `objects` is only set if layer is of type objectgroup.
    objects: ?[]Object = null,
};

pub const TilemapLayerType = enum { tilelayer, objectgroup };

const Layer = struct {
    id: u32,
    type: TilemapLayerType,
    name: []const u8,
    visible: bool,
    opacity: f32,
    width: u32,
    height: u32,
    x: u32,
    y: u32,
    tiles: []u32,
    objects: []Object,
};

const Object = struct {
    id: u32,
    type: []const u8,
    name: []const u8,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    rotation: f32,
    visible: bool,
};

pub const TilesetRef = struct {
    firstgid: u32,
    source: []const u8,
};
