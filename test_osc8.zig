const std = @import("std");
const Parser = @import("src/parser.zig").Parser;
const Grid = @import("src/grid.zig").Grid;

test "OSC 8 - start hyperlink with id and uri" {
    const allocator = std.testing.allocator;
    var parser = Parser{};
    var grid = try Grid.init(allocator, 80, 24);
    defer grid.deinit(allocator);

    // Test OSC 8 start hyperlink
    const start_hyperlink = "\x1B]8;id=test-link;https://example.com/\x07";
    parser.parse(start_hyperlink, &grid);

    try std.testing.expect(parser.isHyperlinkActive());
    try std.testing.expectEqualStrings("test-link", parser.getHyperlinkId());
    try std.testing.expectEqualStrings("https://example.com/", parser.getHyperlinkUri());
    try std.testing.expect(parser.hasHyperlinkChanged());
}

test "OSC 8 - start hyperlink with just uri" {
    const allocator = std.testing.allocator;
    var parser = Parser{};
    var grid = try Grid.init(allocator, 80, 24);
    defer grid.deinit(allocator);

    // Test OSC 8 start hyperlink without id
    const start_hyperlink = "\x1B]8;;https://github.com\x07";
    parser.parse(start_hyperlink, &grid);

    try std.testing.expect(parser.isHyperlinkActive());
    try std.testing.expectEqual(0, parser.getHyperlinkId().len);
    try std.testing.expectEqualStrings("https://github.com", parser.getHyperlinkUri());
    try std.testing.expect(parser.hasHyperlinkChanged());
}

test "OSC 8 - end hyperlink" {
    const allocator = std.testing.allocator;
    var parser = Parser{};
    var grid = try Grid.init(allocator, 80, 24);
    defer grid.deinit(allocator);

    // Start hyperlink first
    const start_hyperlink = "\x1B]8;id=mylink;https://example.org\x07";
    parser.parse(start_hyperlink, &grid);

    // Then end it
    const end_hyperlink = "\x1B]8;;\x07";
    parser.parse(end_hyperlink, &grid);

    try std.testing.expect(!parser.isHyperlinkActive());
    try std.testing.expectEqual(0, parser.getHyperlinkUri().len);
    try std.testing.expectEqual(0, parser.getHyperlinkId().len);
    try std.testing.expect(parser.hasHyperlinkChanged());
}

test "OSC 8 - with ST terminator" {
    const allocator = std.testing.allocator;
    var parser = Parser{};
    var grid = try Grid.init(allocator, 80, 24);
    defer grid.deinit(allocator);

    // Test OSC 8 with ST terminator (ESC\)
    const start_hyperlink = "\x1B]8;id=st-test;https://test.com\x1B\\";
    parser.parse(start_hyperlink, &grid);

    try std.testing.expect(parser.isHyperlinkActive());
    try std.testing.expectEqualStrings("st-test", parser.getHyperlinkId());
    try std.testing.expectEqualStrings("https://test.com", parser.getHyperlinkUri());
}

test "OSC 8 - reset hyperlink changed flag" {
    const allocator = std.testing.allocator;
    var parser = Parser{};
    var grid = try Grid.init(allocator, 80, 24);
    defer grid.deinit(allocator);

    const start_hyperlink = "\x1B]8;;https://example.com\x07";
    parser.parse(start_hyperlink, &grid);

    parser.resetHyperlinkChanged();
    try std.testing.expect(!parser.hasHyperlinkChanged());
}
