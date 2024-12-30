const rl = @import("raylib");
const entt = @import("entt");
const comp = @import("components.zig");
const m = @import("math/mod.zig");

//-----------------------------------------------------------------------------
// Misc
//-----------------------------------------------------------------------------

pub fn updateLifetimes(reg: *entt.Registry) void {
    const delta_time = rl.getFrameTime();
    var view = reg.view(.{comp.Lifetime}, .{});
    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        var lifetime = view.get(entity);
        lifetime.update(delta_time);
        if (lifetime.dead()) {
            reg.destroy(entity);
        }
    }
}

pub fn updateAnimations(reg: *entt.Registry) void {
    const delta_time = rl.getFrameTime();
    var view = reg.view(.{comp.Visual}, .{});
    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        var visual = view.get(entity);
        if (visual.* == .animation) {
            visual.animation.playing_animation.tick(delta_time);
        }
    }
}

//-----------------------------------------------------------------------------
// Drawing
//-----------------------------------------------------------------------------

pub fn beginFrame(clear_color: ?rl.Color) void {
    rl.beginDrawing();
    rl.clearBackground(clear_color orelse rl.Color.blank);
}

pub fn endFrame() void {
    rl.endDrawing();
}

/// Draw entity shape AABB's.
pub fn debugDraw(reg: *entt.Registry, color: rl.Color) void {
    var view = reg.view(.{ comp.Position, comp.Shape, comp.Visual }, .{});
    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        var pos = view.getConst(comp.Position, entity);
        const shape = view.getConst(comp.Shape, entity);
        if (shape == .circle) {
            pos.x -= shape.getWidth() / 2;
            pos.y -= shape.getHeight() / 2;
        }
        const shape_aabb = comp.Shape.rectangle(shape.getWidth(), shape.getHeight());
        // Draw entity AABB outline.
        drawEntity(
            pos,
            shape_aabb,
            comp.Visual.color(color, true),
        );
        // If entity is collidable, draw the collision AABB with a slight alpha.
        if (reg.has(comp.Collision, entity)) {
            drawEntity(
                pos,
                shape_aabb,
                comp.Visual.color(color.alpha(0.25), false),
            );
        }
    }
}

/// Draw FPS
pub fn debugDrawFps() void {
    rl.drawFPS(10, 10);
}

pub fn draw(reg: *entt.Registry) void {
    const SortContext = struct {
        /// Compare function to sort entities by their `VisualLayer`.
        fn sort(r: *entt.Registry, a: entt.Entity, b: entt.Entity) bool {
            const a_layer = r.tryGet(comp.VisualLayer, a);
            const b_layer = r.tryGet(comp.VisualLayer, b);
            if (a_layer != null and b_layer != null) {
                return a_layer.?.value > b_layer.?.value;
            } else if (a_layer != null) {
                return true;
            } else {
                return false;
            }
        }
    };

    var group = reg.group(.{ comp.Position, comp.Shape, comp.Visual }, .{}, .{});
    // Sort entities based on their `VisualLayer`.
    group.sort(entt.Entity, reg, SortContext.sort);
    var iter = group.entityIterator();
    while (iter.next()) |entity| {
        const pos = group.getConst(comp.Position, entity);
        const shape = group.getConst(comp.Shape, entity);
        const visual = group.getConst(comp.Visual, entity);
        drawEntity(pos, shape, visual);
    }
}

fn drawEntity(pos: comp.Position, shape: comp.Shape, visual: comp.Visual) void {
    switch (visual) {
        .stub => drawStub(pos, shape),
        .color => drawShape(pos, shape, visual.color.value, visual.color.outline),
        .sprite => drawSprite(
            .{
                .x = pos.x,
                .y = pos.y,
                .width = shape.getWidth(),
                .height = shape.getHeight(),
            },
            visual.sprite.rect,
            visual.sprite.texture.*,
        ),
        .animation => {
            var anim = visual.animation.playing_animation;
            const frame = anim.getCurrentFrame();
            const frames: f32 = @floatFromInt(visual.animation.playing_animation.animation.frames.len);
            const texture_width = @as(f32, @floatFromInt(visual.animation.texture.width));
            const texture_height = @as(f32, @floatFromInt(visual.animation.texture.height));
            const source_rect = m.Rect{
                .x = texture_width * frame.region.u * texture_width / frames,
                .y = texture_height * frame.region.v * texture_height / frames,
                .width = texture_width / frames,
                .height = texture_height,
            };
            drawSprite(
                .{
                    .x = pos.x,
                    .y = pos.y,
                    .width = shape.getWidth(),
                    .height = shape.getHeight(),
                },
                source_rect,
                visual.animation.texture.*,
            );
        },
    }
}

/// Draw  a stub shape.
/// TODO: Make visual appearance more noticeable.
pub fn drawStub(pos: comp.Position, shape: comp.Shape) void {
    drawShape(pos, shape, rl.Color.magenta, false);
}

/// Draw a sprite.
pub fn drawSprite(target: m.Rect, source: m.Rect, texture: rl.Texture) void {
    texture.drawPro(
        .{
            .x = source.x,
            .y = source.y,
            .width = source.width,
            .height = source.height,
        },
        .{
            .x = target.x,
            .y = target.y,
            .width = target.width,
            .height = target.height,
        },
        .{ .x = 0, .y = 0 },
        0,
        rl.Color.white,
    );
}

/// Generic drawing function to be used for `stub` and `color` visuals.
pub fn drawShape(pos: comp.Position, shape: comp.Shape, color: rl.Color, outline: bool) void {
    const p = .{ .x = pos.x, .y = pos.y };
    switch (shape) {
        .triangle => {
            const v1 = .{
                .x = p.x + shape.triangle.v1.x(),
                .y = p.y + shape.triangle.v1.y(),
            };
            const v2 = .{
                .x = p.x + shape.triangle.v2.x(),
                .y = p.y + shape.triangle.v2.y(),
            };
            const v3 = .{
                .x = p.x + shape.triangle.v3.x(),
                .y = p.y + shape.triangle.v3.y(),
            };
            if (outline) {
                rl.drawTriangleLines(v1, v2, v3, color);
            } else {
                rl.drawTriangle(v1, v2, v3, color);
            }
        },
        .rectangle => {
            const size = .{ .x = shape.rectangle.width, .y = shape.rectangle.height };
            if (outline) {
                // NOTE: The `drawRectangleLines` function draws the outlined
                // rectangle incorrectly. Hence, drawing the lines individually.
                const v1 = .{ .x = p.x, .y = p.y };
                const v2 = .{ .x = p.x + size.x, .y = p.y };
                const v3 = .{ .x = p.x + size.x, .y = p.y + size.y };
                const v4 = .{ .x = p.x, .y = p.y + size.y };
                rl.drawLineV(v1, v2, color);
                rl.drawLineV(v2, v3, color);
                rl.drawLineV(v3, v4, color);
                rl.drawLineV(v4, v1, color);
            } else {
                rl.drawRectangleV(p, size, color);
            }
        },
        .circle => {
            if (outline) {
                rl.drawCircleLinesV(p, shape.circle.radius, color);
            } else {
                rl.drawCircleV(p, shape.circle.radius, color);
            }
        },
    }
}
