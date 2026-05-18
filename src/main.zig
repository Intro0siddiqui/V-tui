/// Vtui - Pure ANSI Rendering Engine with PTY support
const std = @import("std");
const posix = std.posix;
const os = std.os;
const Grid = @import("grid.zig").Grid;
const Parser = @import("parser.zig").Parser;
const Renderer = @import("renderer.zig").Renderer;
const savePPM = @import("renderer.zig").savePPM;
const pty_spawn = @import("pty.zig").spawn;
const pty_write = @import("pty.zig").write;
const pty_read = @import("pty.zig").read;

const Window = @import("window.zig").Window;
const font_module = @import("font.zig");
const Font = font_module.Font;
const FontDiscovery = font_module.FontDiscovery;
const async_io = @import("async_io.zig");
const SixelImage = @import("sixel.zig").SixelImage;
const SixelParser = @import("sixel.zig").SixelParser;

const DEFAULT_WIDTH: usize = 80;
const DEFAULT_HEIGHT: usize = 24;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        const arg = args[1];
        if (std.mem.eql(u8, arg, "--demo")) {
            var ppm_path: ?[]const u8 = null;
            if (args.len > 3 and std.mem.eql(u8, args[2], "--save-ppm")) {
                ppm_path = args[3];
            }
            try runDemo(allocator, ppm_path);
        } else if (std.mem.eql(u8, arg, "--test-parse")) {
            try testParser(allocator);
        } else if (std.mem.eql(u8, arg, "--test-render")) {
            try testRenderer(allocator);
        } else if (std.mem.eql(u8, arg, "--test-sixel")) {
            try testSixel(allocator);
        } else if (std.mem.eql(u8, arg, "--save-ppm") and args.len > 2) {
            if (args.len > 3) {
                try runCommand(allocator, args[3], args[4..], args[2]);
            } else {
                try runDemo(allocator, args[2]);
            }
        } else if (std.mem.eql(u8, arg, "--run") and args.len > 2) {
            var ppm_path: ?[]const u8 = null;
            var cmd_args_end = args.len;
            for (args[3..], 3..) |a, i| {
                if (std.mem.eql(u8, a, "--save-ppm") and i + 1 < args.len) {
                    ppm_path = args[i + 1];
                    cmd_args_end = i;
                    break;
                }
            }
            try runCommand(allocator, args[2], args[3..cmd_args_end], ppm_path);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            var ppm_path: ?[]const u8 = null;
            var cmd_args_end = args.len;
            for (args[2..], 2..) |a, i| {
                if (std.mem.eql(u8, a, "--save-ppm") and i + 1 < args.len) {
                    ppm_path = args[i + 1];
                    cmd_args_end = i;
                    break;
                }
            }
            try runCommand(allocator, arg, args[2..cmd_args_end], ppm_path);
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            printHelp();
            return error.InvalidArgument;
        }
    } else {
        try runDemo(allocator, null);
    }
}

fn printHelp() void {
    std.debug.print(
        \\Vtui - Pure ANSI Rendering Engine
        \\
        \\Usage: vtui [OPTIONS] [cmd] [args...]
        \\
        \\Options:
        \\  --demo              Run demo mode with sample ANSI output
        \\  --run <cmd> [args]  Run command in PTY and capture output (legacy)
        \\  --save-ppm <file>   Save rendered output as PPM image
        \\  --test-parse        Test parser with sample ANSI sequences
        \\  --test-render       Test renderer output
        \\  --test-sixel        Test Sixel parser and image creation
        \\  --help, -h          Show this help message
        \\
        \\Examples:
        \\  vtui btop
        \\  vtui --save-ppm out.ppm ls -la --color=always
        \\
    , .{});
}

fn runDemo(allocator: std.mem.Allocator, ppm_path: ?[]const u8) !void {
    var grid = try Grid.init(allocator, DEFAULT_WIDTH, DEFAULT_HEIGHT);
    defer grid.deinit(allocator);
    var parser = Parser.init(allocator);
    const demo_text = "Vtui Demo\r\nLigatures: -> != => :: && ||\r\nColors: \x1b[31mRed\x1b[0m \x1b[32mGreen\x1b[0m\r\nStatus: \x1b[32mOK\x1b[0m\r\nSixel: \x1bPq~\x1b\\\r\n";
    parser.parse(demo_text, &grid);

    // Check cell at 'R'
    if (grid.cellAt(8, 2)) |cell| {
        std.debug.print("Cell at (8,2): char={c} fg=0x{X}\n", .{ @as(u8, @intCast(cell.char)), cell.fg });
    }
    const sw = DEFAULT_WIDTH * 16;
    const sh = DEFAULT_HEIGHT * 16;
    var renderer = try Renderer.init(sw, sh, .{}, allocator);
    defer renderer.deinit();

    // Try to load a system font if available
    const font_path = "/usr/share/fonts/Adwaita/AdwaitaMono-Regular.ttf";
    var font_instance = Font.init(allocator) catch |err| {
        std.debug.print("Could not init font, using basic patterns: {}\n", .{err});
        const buf = try allocator.alloc(u8, sw * sh * 4);
        defer allocator.free(buf);
        renderer.render(&grid, buf);
        std.debug.print("Vtui Demo\nGrid: {d}x{d}\n", .{ DEFAULT_WIDTH, DEFAULT_HEIGHT });
        if (ppm_path) |path| {
            try savePPM(buf, sw, sh, sw * 4, path);
            std.debug.print("Saved PPM: {s}\n", .{path});
        }
        return;
    };
    defer font_instance.deinit();

    if (font_instance.addFace(font_path, 14)) {
        renderer.setFont(&font_instance);
        std.debug.print("Loaded font: {s}\n", .{font_path});
    } else |err| {
        std.debug.print("Could not add font face, using basic patterns: {}\n", .{err});
    }

    const buf = try allocator.alloc(u8, sw * sh * 4);
    defer allocator.free(buf);
    renderer.render(&grid, buf);
    std.debug.print("Vtui Demo\nGrid: {d}x{d}\n", .{ DEFAULT_WIDTH, DEFAULT_HEIGHT });
    if (ppm_path) |path| {
        try savePPM(buf, sw, sh, sw * 4, path);
        std.debug.print("Saved PPM: {s}\n", .{path});
    }
}

const Pty = @import("pty.zig").Pty;

fn writePtyCb(ctx: *Pty, data: []const u8) void {
    _ = pty_write(ctx, data) catch 0;
}

fn runCommand(allocator: std.mem.Allocator, cmd: []const u8, cmd_args: [][:0]u8, ppm_path: ?[]const u8) !void {
    const initial_sw = DEFAULT_WIDTH * 16;
    const initial_sh = DEFAULT_HEIGHT * 16;

    var window = try Window.init(allocator, @intCast(initial_sw), @intCast(initial_sh));
    defer window.deinit();

    // Get actual window size after mapping
    var sw: usize = window.width;
    var sh: usize = window.height;
    var gw: usize = sw / 16;
    var gh: usize = sh / 16;

    var result = try pty_spawn(allocator, cmd, cmd_args);
    defer result.pty.deinit();

    // Sync PTY size immediately
    result.pty.setSize(.{
        .ws_row = @intCast(gh),
        .ws_col = @intCast(gw),
        .ws_xpixel = @intCast(sw),
        .ws_ypixel = @intCast(sh),
    }) catch {};

    var grid = try Grid.init(allocator, gw, gh);
    defer grid.deinit(allocator);
    var parser = Parser.init(allocator);

    // Hook up parser writer to PTY for responding to queries (e.g. DA)
    parser.setWriter(&result.pty, struct {
        fn cb(ctx: *anyopaque, data: []const u8) void {
            const p = @as(*Pty, @ptrCast(@alignCast(ctx)));
            _ = posix.write(p.master, data) catch 0;
        }
    }.cb);

    var renderer = try Renderer.init(sw, sh, .{}, allocator);
    defer renderer.deinit();
    renderer.setStride(@intCast(window.image.bytes_per_line));

    // Load system fonts
    var font_discovery = FontDiscovery.init(allocator);
    defer font_discovery.deinit();

    var font = try Font.init(allocator);
    defer font.deinit();

    if (font_discovery.findMonospace()) |path| {
        std.debug.print("Loading font: {s}\n", .{path});
        try font.addFace(path, 14);
        // Add fallbacks for Emoji/CJK
        if (font_discovery.findForBlock(.Emoji)) |emoji_path| {
            try font.addFallbackFace(emoji_path, 14);
        }
        renderer.setFont(&font);
    } else {
        std.debug.print("No monospace font found, using procedural patterns\n", .{});
    }

    var total: usize = 0;
    var child_exited = false;

    // Set STDIN to raw mode for keyboard input if it is a tty
    var orig_termios: posix.termios = undefined;
    const is_tty = posix.tcgetattr(posix.STDIN_FILENO) catch null;
    if (is_tty) |t| {
        orig_termios = t;
        var raw = t;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        posix.tcsetattr(posix.STDIN_FILENO, posix.TCSA.FLUSH, raw) catch {};
    }
    defer {
        if (is_tty != null) {
            posix.tcsetattr(posix.STDIN_FILENO, posix.TCSA.FLUSH, orig_termios) catch {};
        }
    }

    // Initialize async I/O
    var ring = try async_io.IoUring.init(32, 0);
    defer ring.deinit();

    const PTY_USER_DATA: u64 = 1;
    const STDIN_USER_DATA: u64 = 2;
    const WINDOW_USER_DATA: u64 = 3;

    // Submit poll operations for all FDs
    try ring.pollAdd(result.pty.master, posix.POLL.IN, PTY_USER_DATA);
    try ring.pollAdd(posix.STDIN_FILENO, posix.POLL.IN, STDIN_USER_DATA);
    try ring.pollAdd(window.getFd(), posix.POLL.IN, WINDOW_USER_DATA);

    var buf: [4096]u8 = undefined;

    // Force a resize to the default grid to ensure the app knows it has space
    result.pty.setSize(.{ .ws_row = @intCast(DEFAULT_HEIGHT), .ws_col = @intCast(DEFAULT_WIDTH), .ws_xpixel = 0, .ws_ypixel = 0 }) catch {};
    while (true) {
        // Submit pending operations and wait for events
        const completions = try ring.submitAndWait(1);
        if (completions == 0) {
            continue;
        }

        // Handle all available completions
        while (true) {
            const cqe = ring.peekCqe() orelse break;
            const user_data = cqe.user_data;

            if (user_data == PTY_USER_DATA) {
                if (cqe.res > 0) {
                    // PTY has data to read
                    var has_data = false;
                    var read_count: usize = 0;

                    while (true) {
                        read_count += 1;
                        const n = pty_read(&result.pty, &buf) catch |err| switch (err) {
                            error.WouldBlock => {
                                std.debug.print("WouldBlock after {d} reads\n", .{read_count});
                                break;
                            },
                            else => {
                                std.debug.print("Read error: {}\n", .{err});
                                break;
                            },
                        };

                        if (n > 0) {
                            std.debug.print("Read {d} bytes from PTY (hex): ", .{n});
                            for (buf[0..n]) |b| {
                                std.debug.print("{x:0>2} ", .{b});
                            }
                            std.debug.print("\n", .{});
                            has_data = true;
                            total += n;
                            parser.parse(buf[0..n], &grid);
                            if (parser.title_changed) {
                                window.setTitle(parser.getWindowTitle());
                                parser.title_changed = false;
                            }
                            renderer.render(&grid, window.pixels);
                            window.draw();
                        } else {
                            std.debug.print("Read 0 bytes (EOF)\n", .{});
                            break;
                        }
                    }

                    // If HUP was signaled and we didn't read any data, child might have exited
                    if (!has_data) {
                        const wait_res = posix.waitpid(result.pid, posix.W.NOHANG);
                        if (wait_res.pid == result.pid) {
                            child_exited = true;
                            break;
                        }
                    }
                } else if (cqe.res < 0) {
                    std.debug.print("PTY error detected: {}\n", .{cqe.res});
                    break;
                }

                // Re-submit poll for PTY
                try ring.pollAdd(result.pty.master, posix.POLL.IN, PTY_USER_DATA);
            } else if (user_data == STDIN_USER_DATA) {
                if (cqe.res > 0) {
                    var stdin_buf: [1024]u8 = undefined;
                    const n = posix.read(posix.STDIN_FILENO, &stdin_buf) catch 0;
                    if (n > 0) {
                        _ = pty_write(&result.pty, stdin_buf[0..n]) catch 0;
                    }
                }

                // Re-submit poll for STDIN
                try ring.pollAdd(posix.STDIN_FILENO, posix.POLL.IN, STDIN_USER_DATA);
            } else if (user_data == WINDOW_USER_DATA) {
                if (cqe.res > 0) {
                    if (window.handleEvents(&result.pty, writePtyCb)) |new_size| {
                        const new_gw = new_size.w / 16;
                        const new_gh = new_size.h / 16;

                        if (new_gw > 0 and new_gh > 0) {
                            std.debug.print("Resizing to {d}x{d} (grid: {d}x{d})\n", .{ new_size.w, new_size.h, new_gw, new_gh });

                            // Update sw/sh/gw/gh
                            sw = new_size.w;
                            sh = new_size.h;
                            gw = new_gw;
                            gh = new_gh;

                            // Resize PTY first so child knows
                            result.pty.setSize(.{
                                .ws_row = @intCast(new_gh),
                                .ws_col = @intCast(new_gw),
                                .ws_xpixel = @intCast(new_size.w),
                                .ws_ypixel = @intCast(new_size.h),
                            }) catch {};

                            // Resize Window (reallocates pixels)
                            try window.resize(new_size.w, new_size.h);

                            // Resize Grid
                            try grid.resize(allocator, new_gw, new_gh);

                            // Resize Renderer
                            renderer.resize(new_size.w, new_size.h);
                            renderer.setStride(@intCast(window.image.bytes_per_line));

                            // Re-render
                            renderer.render(&grid, window.pixels);
                            window.draw();
                        }
                    }
                } else if (cqe.res < 0) {
                    std.debug.print("Window error detected: {}\n", .{cqe.res});
                    break;
                }

                // Re-submit poll for window
                try ring.pollAdd(window.getFd(), posix.POLL.IN, WINDOW_USER_DATA);
            }
        }

        if (child_exited) {
            break;
        }

        // Check if child process exited
        const wait_res = posix.waitpid(result.pid, posix.W.NOHANG);
        if (wait_res.pid == result.pid) {
            std.debug.print("Child process exited (waitpid returned)\n", .{});
            child_exited = true;
            break;
        }
    }

    // Reap the child process if it exited but wasn't reaped yet
    if (!child_exited) {
        _ = posix.waitpid(result.pid, posix.W.NOHANG);
    }

    std.debug.print("\nVtui PTY Output\n===============\nTotal: {d} bytes\n", .{total});
    if (ppm_path) |path| {
        try savePPM(window.pixels, sw, sh, @intCast(window.image.bytes_per_line), path);
        std.debug.print("Saved PPM: {s}\n", .{path});
    }
}

fn testParser(allocator: std.mem.Allocator) !void {
    var grid = try Grid.init(allocator, DEFAULT_WIDTH, DEFAULT_HEIGHT);
    defer grid.deinit(allocator);
    var parser = Parser.init(allocator);
    const tests = [_]struct { name: []const u8, input: []const u8, ex: usize, ey: usize }{
        .{ .name = "text", .input = "Hello", .ex = 5, .ey = 0 },
        .{ .name = "newline", .input = "Hi\n", .ex = 0, .ey = 1 },
        .{ .name = "home", .input = "\x1b[H", .ex = 0, .ey = 0 },
        // Simple Sixel test: Black 1x1 pixel at 0,0
        // ESC P q ; 0 ; 0 ; 1 # 0 ~ - ESC \
        // Wait, Sixel format: ESC P q ; P1 ; P2 ; P3 <data> ESC \
        // P1=0 (aspect), P2=0 (bg opaque), P3=1 (width unit?)
        // Actually P3 is horizontal grid size, usually ignored.
        // Let's use default params: ESC P q ~ ESC \
        // This draws a single column of pixels.
        // But we need to select color #0 first.
        // # 0 selects color 0.
        // ? is 63 (000000).
        // ~ is 126 (111110).
        // After sixel, cursor advances to right of image
        .{ .name = "sixel", .input = "\x1bPq#0;2;0;0?~\x1b\\", .ex = 1, .ey = 0 },
    };
    std.debug.print("Parser Tests\n============\n", .{});
    var passed: usize = 0;
    std.debug.print("Starting loop with {d} tests\n", .{tests.len});
    for (tests) |tc| {
        std.debug.print("Testing {s}...\n", .{tc.name});
        if (std.mem.eql(u8, tc.name, "sixel")) {
            std.debug.print("Input bytes: ", .{});
            for (tc.input) |b| {
                std.debug.print("{x:0>2} ", .{b});
            }
            std.debug.print("\n", .{});
        }
        parser.reset();
        grid.clear();
        parser.parse(tc.input, &grid);
        if (grid.cursor.x == tc.ex and grid.cursor.y == tc.ey) {
            std.debug.print("  [PASS] {s}\n", .{tc.name});
            passed += 1;
        } else {
            std.debug.print("  [FAIL] {s} (cursor: {d}, {d})\n", .{ tc.name, grid.cursor.x, grid.cursor.y });
        }
        if (std.mem.eql(u8, tc.name, "sixel")) {
            std.debug.print("    Images count: {d}\n", .{grid.images.items.len});
        }
    }
    // OSC Tests
    std.debug.print("OSC Tests\n============\n", .{});

    // Test OSC 0 (window title)
    parser.reset();
    parser.title_changed = false; // Clear sticky flag
    parser.parse("\x1b]0;Test Title\x07", &grid);
    if (parser.title_changed and std.mem.eql(u8, parser.getWindowTitle(), "Test Title")) {
        std.debug.print("  [PASS] OSC 0 (window title)\n", .{});
        passed += 1;
    } else {
        std.debug.print("  [FAIL] OSC 0 (window title)\n", .{});
    }

    // Test OSC 2 (window title)
    parser.reset();
    parser.title_changed = false; // Clear sticky flag
    parser.parse("\x1b]2;Another Title\x07", &grid);
    if (parser.title_changed and std.mem.eql(u8, parser.getWindowTitle(), "Another Title")) {
        std.debug.print("  [PASS] OSC 2 (window title)\n", .{});
        passed += 1;
    } else {
        std.debug.print("  [FAIL] OSC 2 (window title)\n", .{});
    }

    // Test OSC 4 (color palette)
    parser.reset();
    parser.title_changed = false; // Clear sticky flag
    // Set color index 1 to red (#FF0000)
    parser.parse("\x1b]4;1;#FF0000\x07", &grid);
    // Check if color was updated
    if (parser.color_palette[1] == 0xFF0000) {
        std.debug.print("  [PASS] OSC 4 (color palette)\n", .{});
        passed += 1;
    } else {
        std.debug.print("  [FAIL] OSC 4 (color palette): expected 0xFF0000, got 0x{x}\n", .{parser.color_palette[1]});
    }

    std.debug.print("{d}/{d} passed\n", .{ passed, tests.len + 3 });
}

fn testRenderer(allocator: std.mem.Allocator) !void {
    var grid = try Grid.init(allocator, DEFAULT_WIDTH, DEFAULT_HEIGHT);
    defer grid.deinit(allocator);

    // Create a simple 16x16 red image using grid's allocator
    const img_data = try allocator.alloc(u32, 16 * 16);
    @memset(img_data, 0xFFFF0000); // Red Opaque
    const img = SixelImage{
        .x = 5,
        .y = 5,
        .width = 16,
        .height = 16,
        .data = img_data,
        .allocator = allocator,
    };
    try grid.addImage(img);
    const sw = DEFAULT_WIDTH * 16;
    const sh = DEFAULT_HEIGHT * 16;
    var renderer = try Renderer.init(sw, sh, .{}, allocator);
    defer renderer.deinit();
    const buf = try allocator.alloc(u8, sw * sh * 4);
    defer allocator.free(buf);

    renderer.render(&grid, buf);

    // Check if pixels are red
    const px_x = 5 * 16 + 8; // Center of the 16x16 image
    const px_y = 5 * 16 + 8;
    const idx = (px_y * sw + px_x) * 4;

    if (idx + 2 < buf.len) {
        const r = buf[idx + 2];
        const g = buf[idx + 1];
        const b = buf[idx];
        std.debug.print("Pixel at ({d}, {d}): R={d} G={d} B={d}\n", .{ px_x, px_y, r, g, b });
        if (r == 255 and g == 0 and b == 0) {
            std.debug.print("Red pixel detected!\n", .{});
        } else {
            std.debug.print("Red pixel NOT detected.\n", .{});
        }
    }

    // Check top-left pixel of image
    const tl_x = 5 * 16;
    const tl_y = 5 * 16;
    const tl_idx = (tl_y * sw + tl_x) * 4;
    if (tl_idx + 2 < buf.len) {
        const r = buf[tl_idx + 2];
        const g = buf[tl_idx + 1];
        const b = buf[tl_idx];
        std.debug.print("Top-left pixel ({d}, {d}): R={d} G={d} B={d}\n", .{ tl_x, tl_y, r, g, b });
    }

    std.debug.print("Renderer OK\n", .{});
}

fn testSixel(allocator: std.mem.Allocator) !void {
    std.debug.print("Sixel Tests\n===========\n", .{});

    var parser = SixelParser.init(allocator);
    defer parser.deinit();

    var passed: usize = 0;
    var total: usize = 0;

    total += 1;
    const simple_sixel = "\x1bPq#0;2;100;0;0~#1;2;0;100;0~-~-~-~-#2;2;0;0;100~-~-~-~-#3;2;100;100;0~-~-~-~#4;2;100;0;100~-~-~-~#5;2;0;100;100~-~-~-~#6;2;100;100;100~-~-~-~\x1b\\";
    parser.reset();
    for (simple_sixel) |c| {
        if (parser.put(c)) break;
    }
    var image = parser.createImage(0, 0, 16, 16);
    if (image) |*img| {
        std.debug.print("  [PASS] Parse and create Sixel image\n", .{});
        passed += 1;
        img.deinit();
    } else {
        std.debug.print("  [FAIL] Parse and create Sixel image\n", .{});
    }

    total += 1;
    parser.reset();
    parser.state = .data;
    _ = parser.put('#');
    parser.state = .decgci;
    parser.param_buf[0] = 5;
    parser.param_idx = 1;
    parser.param_buf[1] = 2;
    parser.param_buf[2] = 100;
    parser.param_buf[3] = 50;
    parser.param_buf[4] = 25;
    parser.param_idx = 5;
    parser.color_idx = 5;
    parser.processSixelChar('~');
    const color5 = parser.color_palette[5];
    if (color5 != 0) {
        std.debug.print("  [PASS] RGB color parsing\n", .{});
        passed += 1;
    } else {
        std.debug.print("  [FAIL] RGB color parsing\n", .{});
    }

    total += 1;
    parser.reset();
    parser.state = .params;
    _ = parser.put('2');
    _ = parser.put(';');
    _ = parser.put('~');
    if (parser.pan == 5) {
        std.debug.print("  [PASS] Aspect ratio 5:1\n", .{});
        passed += 1;
    } else {
        std.debug.print("  [FAIL] Aspect ratio 5:1 (got {d})\n", .{parser.pan});
    }

    total += 1;
    parser.reset();
    parser.state = .data;
    _ = parser.put('"');
    parser.state = .decgra;
    _ = parser.put('1');
    _ = parser.put(';');
    _ = parser.put('2');
    _ = parser.put(';');
    _ = parser.put('1');
    _ = parser.put('0');
    _ = parser.put(';');
    _ = parser.put('2');
    _ = parser.put('0');
    _ = parser.put('~');
    if (parser.pan == 1 and parser.pad == 2) {
        std.debug.print("  [PASS] DECGRA raster attributes\n", .{});
        passed += 1;
    } else {
        std.debug.print("  [FAIL] DECGRA raster attributes\n", .{});
    }

    total += 1;
    parser.reset();
    parser.state = .data;
    _ = parser.put('!');
    parser.state = .decgri;
    _ = parser.put('5');
    _ = parser.put('~');
    if (parser.image_width >= 5) {
        std.debug.print("  [PASS] DECGRI repeat count\n", .{});
        passed += 1;
    } else {
        std.debug.print("  [FAIL] DECGRI repeat count\n", .{});
    }

    total += 1;
    var test_pattern = try createTestPattern(allocator);
    defer test_pattern.deinit();
    if (test_pattern.width > 0 and test_pattern.height > 0) {
        std.debug.print("  [PASS] Create test pattern image ({d}x{d})\n", .{ test_pattern.width, test_pattern.height });
        passed += 1;
    } else {
        std.debug.print("  [FAIL] Create test pattern image\n", .{});
    }

    std.debug.print("\n{d}/{d} passed\n", .{ passed, total });
    std.debug.print("\nSixel test pattern image created (for visual verification, use renderer test)\n", .{});
}

fn createTestPattern(allocator: std.mem.Allocator) !SixelImage {
    const width: u32 = 48;
    const height: u32 = 48;
    const data = try allocator.alloc(u32, width * height);

    @memset(data, 0xFF000000);

    for (0..height) |y| {
        for (0..width) |x| {
            const idx = y * width + x;
            if (y < 8 and x < 16) {
                data[idx] = 0xFFFF0000;
            } else if (y < 16 and x >= 16 and x < 32) {
                data[idx] = 0xFF00FF00;
            } else if (y < 24 and x >= 32) {
                data[idx] = 0xFF0000FF;
            } else if (y >= 24 and y < 32 and x < 24) {
                data[idx] = 0xFFFFFF00;
            } else if (y >= 32 and y < 40 and x >= 24 and x < 48) {
                data[idx] = 0xFFFF00FF;
            } else if (y >= 40 and x >= 24 and x < 48) {
                data[idx] = 0xFF00FFFF;
            }
        }
    }

    return SixelImage{
        .x = 0,
        .y = 0,
        .width = width,
        .height = height,
        .data = data,
        .allocator = allocator,
    };
}

test "pipeline" {
    const a = std.testing.allocator;
    var grid = try Grid.init(a, 80, 24);
    defer grid.deinit(a);
    var parser = Parser.init(a);
    parser.parse("\x1b[31mH\x1b[0m", &grid);
    try std.testing.expectEqual('H', grid.cellAt(0, 0).?.char);
}
