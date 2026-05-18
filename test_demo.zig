const std = @import("std");
const Window = @import("src/window.zig").Window;
const Grid = @import("src/grid.zig").Grid;
const Parser = @import("src/parser.zig").Parser;
const Renderer = @import("src/renderer.zig").Renderer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var grid = try Grid.init(gpa.allocator(), 80, 24);
    defer grid.deinit(gpa.allocator());
    
    var parser: Parser = .{};
    parser.parse("Vtui Demo\n\x1b[31mRed\x1b[0m \x1b[32mGreen\x1b[0m\nStatus: \x1b[32mOK\x1b[0m\n", &grid);

    var window = try Window.init(gpa.allocator(), 80 * 16, 24 * 16);
    defer window.deinit();
    
    var renderer = Renderer.init(80 * 16, 24 * 16, .{});
    renderer.render(&grid, window.pixels);
    window.draw();
    
    std.debug.print("Demo window opened. Exiting in 3s...\n", .{});
    std.Thread.sleep(3 * std.time.ns_per_s);
}
