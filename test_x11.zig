const std = @import("std");
const Window = @import("src/window.zig").Window;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var window = try Window.init(gpa.allocator(), 800, 600);
    defer window.deinit();
    
    // Fill with Red color to test if window rendering works
    for (0..600) |y| {
        for (0..800) |x| {
            const idx = (y * 800 + x) * 4;
            window.pixels[idx] = 0;     // B
            window.pixels[idx+1] = 0;   // G
            window.pixels[idx+2] = 255; // R
            window.pixels[idx+3] = 255; // A
        }
    }
    
    window.draw();
    std.debug.print("Window opened. Drawing RED. Exiting in 3s...\n", .{});
    
    std.Thread.sleep(3 * std.time.ns_per_s);
}
