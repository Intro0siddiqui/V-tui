const std = @import("std");
const SixelParser = @import("sixel.zig").SixelParser;
const Renderer = @import("renderer.zig").Renderer;
const Grid = @import("grid.zig").Grid;
const savePPM = @import("renderer.zig").savePPM;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sw = 800;
    const sh = 600;
    var renderer = try Renderer.init(sw, sh, .{}, allocator);
    defer renderer.deinit();

    var grid = try Grid.init(allocator, 50, 30);
    defer grid.deinit(allocator);
    grid.setCellDimensions(16, 20);

    var parser = SixelParser.init(allocator);
    defer parser.deinit();

    // Test sequence: Transparency (P2=1) and 2:1 aspect ratio
    // Red 16x16 logical square -> 16x32 physical pixels
    const trans_sixel = "\x1bPq;1;#0;2;100;0;0~~~~~~#0?!6~~~~~~#0~~~~~~\x1b\\";
    
    parser.reset();
    for (trans_sixel) |c| {
        if (parser.put(c)) break;
    }

    if (parser.createImage(5, 5, 16, 20)) |image| {
        try grid.addImage(image);
    }

    const buffer = try allocator.alloc(u8, sw * sh * 4);
    defer allocator.free(buffer);
    @memset(buffer, 0x7F); // Fill with gray background to see transparency

    renderer.render(&grid, buffer);
    try savePPM(buffer, sw, sh, sw * 4, "test_transparency.ppm");
    std.debug.print("Saved test_transparency.ppm\n", .{});
}
