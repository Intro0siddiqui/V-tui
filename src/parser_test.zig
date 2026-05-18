const std = @import("std");
const Parser = @import("src/parser.zig").Parser;
const Grid = @import("src/grid.zig").Grid;

test "Parser OSC 0 - set window and icon title" {
    var grid = try Grid.init(std.testing.allocator, 80, 24);
    defer grid.deinit(std.testing.allocator);

    var parser: Parser = .{};
    parser.parse("\x1b]0;Test Window Title\x07", &grid);

    try std.testing.expectEqualStrings("Test Window Title", parser.getWindowTitle());
    try std.testing.expectEqualStrings("Test Window Title", parser.getIconTitle());
    try std.testing.expect(parser.hasTitleChanged());
}

test "Parser OSC 1 - set icon title" {
    var grid = try Grid.init(std.testing.allocator, 80, 24);
    defer grid.deinit(std.testing.allocator);

    var parser: Parser = .{};
    parser.parse("\x1b]1;Test Icon Title\x07", &grid);

    try std.testing.expectEqualStrings("", parser.getWindowTitle());
    try std.testing.expectEqualStrings("Test Icon Title", parser.getIconTitle());
    try std.testing.expect(parser.hasTitleChanged());
}

test "Parser OSC 2 - set window title" {
    var grid = try Grid.init(std.testing.allocator, 80, 24);
    defer grid.deinit(std.testing.allocator);

    var parser: Parser = .{};
    parser.parse("\x1b]2;Test Window Title\x07", &grid);

    try std.testing.expectEqualStrings("Test Window Title", parser.getWindowTitle());
    try std.testing.expectEqualStrings("", parser.getIconTitle());
    try std.testing.expect(parser.hasTitleChanged());
}

test "Parser OSC with ST terminator (ESC\\)" {
    var grid = try Grid.init(std.testing.allocator, 80, 24);
    defer grid.deinit(std.testing.allocator);

    var parser: Parser = .{};
    parser.parse("\x1b]0;ST Terminated Title\x1b\\", &grid);

    try std.testing.expectEqualStrings("ST Terminated Title", parser.getWindowTitle());
    try std.testing.expect(parser.hasTitleChanged());
}

test "Parser OSC title changed flag" {
    var grid = try Grid.init(std.testing.allocator, 80, 24);
    defer grid.deinit(std.testing.allocator);

    var parser: Parser = .{};
    parser.parse("\x1b]2;First Title\x07", &grid);
    try std.testing.expect(parser.hasTitleChanged());

    parser.resetTitleChanged();
    try std.testing.expect(!parser.hasTitleChanged());

    parser.parse("\x1b]2;Second Title\x07", &grid);
    try std.testing.expect(parser.hasTitleChanged());
}

test "Parser OSC UTF-8 title" {
    var grid = try Grid.init(std.testing.allocator, 80, 24);
    defer grid.deinit(std.testing.allocator);

    var parser: Parser = .{};
    // UTF-8 string: "日本語のタイトル"
    parser.parse("\x1b]2;\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e\xe3\x81\xae\xe3\x82\xbf\xe3\x82\xa4\xe3\x83\x88\xe3\x83\xab\x07", &grid);

    // Should preserve the raw UTF-8 bytes
    try std.testing.expect(parser.getWindowTitle().len > 0);
}

test "Parser OSC title buffer truncation" {
    var grid = try Grid.init(std.testing.allocator, 80, 24);
    defer grid.deinit(std.testing.allocator);

    var parser: Parser = .{};

    // Create a title longer than the buffer (255 bytes)
    var long_title = std.ArrayList(u8).init(std.testing.allocator);
    defer long_title.deinit();

    try long_title.appendSlice("\x1b]2;");
    var i: usize = 0;
    while (i < 300) : (i += 1) {
        try long_title.append('A');
    }
    try long_title.append(0x07);

    parser.parse(long_title.items, &grid);

    try std.testing.expectEqual(255, parser.getWindowTitle().len);
    for (parser.getWindowTitle()) |c| {
        try std.testing.expectEqual('A', c);
    }
}

test "Parser multiple OSC commands" {
    var grid = try Grid.init(std.testing.allocator, 80, 24);
    defer grid.deinit(std.testing.allocator);

    var parser: Parser = .{};
    parser.parse("\x1b]1;Icon\x07\x1b]2;Window\x07", &grid);

    try std.testing.expectEqualStrings("Icon", parser.getIconTitle());
    try std.testing.expectEqualStrings("Window", parser.getWindowTitle());
}
