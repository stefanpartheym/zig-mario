const rl = @import("raylib");

pub fn drawTextCentered(
    text: [*:0]const u8,
    size: i32,
    color: rl.Color,
    display_width: i32,
    display_height: i32,
) void {
    const text_width = rl.measureText(text, size);
    rl.drawText(
        text,
        @divTrunc(display_width, 2) - @divTrunc(text_width, 2),
        @divTrunc(display_height, 2) - @divTrunc(size, 2),
        size,
        color,
    );
}
