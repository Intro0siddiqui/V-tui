/// Vtui Grid Module
/// Single source of truth for screen state.
/// Flat array, row-major order. Index = y * width + x.
const std = @import("std");
const assert = std.debug.assert;
const SixelImage = @import("sixel.zig").SixelImage;

/// Cell attributes (bold, underline, etc.)
pub const CellFlags = packed struct {
    bold: bool = false,
    underline: bool = false,
    reverse: bool = false,
    _reserved: u5 = 0,
};

/// Single cell in the grid.
/// 16 bytes total - cache-line friendly.
pub const Cell = struct {
    char: u21 = ' ', // UTF-32 codepoint
    fg: u32 = 0, // Foreground: 0x00RRGGBB
    bg: u32 = 0, // Background: 0x00RRGGBB
    flags: CellFlags = .{},

    pub fn reset(self: *Cell) void {
        self.* = .{};
    }
};

/// Cursor state.
pub const Cursor = struct {
    x: usize = 0,
    y: usize = 0,
    visible: bool = true,
};

/// Default grid dimensions (80x24 VT100 standard).
pub const DEFAULT_WIDTH = 80;
pub const DEFAULT_HEIGHT = 24;

/// Default scrollback buffer size (lines above viewport).
pub const DEFAULT_SCROLLBACK_LINES = 1000;

const SixelMemory = @import("sixel.zig").SixelMemory;

/// The Grid - owns the cell buffer with scrollback support.
pub const Grid = struct {
    width: usize,
    height: usize,
    cells: []Cell, // Visible screen cells
    dirty: []bool, // Dirty flag per cell
    scrollback: []Cell, // Scrollback buffer (circular)
    scrollback_lines: usize, // Number of lines in scrollback
    scrollback_capacity: usize, // Maximum scrollback lines
    scrollback_head: usize, // Index where next line will be written
    cursor: Cursor = .{},
    viewport_offset: usize = 0, // Offset into scrollback for viewing
    images: std.ArrayList(SixelImage), // List of sixel images
    allocator: std.mem.Allocator, // Allocator for images

    sixel_memory: SixelMemory = .{}, // Memory tracking for Sixel images

    cell_width: u32 = 10, // Cell width in pixels (default)
    cell_height: u32 = 20, // Cell height in pixels (default)

    /// Free the grid's allocated memory.
    pub fn deinit(self: *Grid, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
        allocator.free(self.dirty);
        allocator.free(self.scrollback);
        for (self.images.items) |*img| {
            self.sixel_memory.remove(img.getMemorySize());
            img.deinit();
        }
        self.images.deinit(allocator);
    }

    /// Clear the entire grid to default state.
    pub fn clear(self: *Grid) void {
        @memset(self.cells, .{});
        @memset(self.dirty, true);
        @memset(self.scrollback, .{});
        self.cursor = .{};
        self.scrollback_lines = 0;
        self.scrollback_head = 0;
        self.viewport_offset = 0;
        self.clearSixelImages();
    }

    /// Clear all Sixel images from the grid.
    pub fn clearSixelImages(self: *Grid) void {
        for (self.images.items) |*img| {
            self.sixel_memory.remove(img.getMemorySize());
            img.deinit();
        }
        self.images.clearRetainingCapacity();
    }

    /// Get cell at (x, y) in visible screen. Returns null if out of bounds.
    pub fn cellAt(self: *Grid, x: usize, y: usize) ?*Cell {
        if (x >= self.width or y >= self.height) return null;
        return &self.cells[y * self.width + x];
    }

    /// Get cell at (x, y) in scrollback (y is relative to scrollback start).
    /// Returns null if out of bounds.
    pub fn cellAtScrollback(self: *Grid, x: usize, y: usize) ?*Cell {
        if (x >= self.width or y >= self.scrollback_lines) return null;
        const idx = y * self.width + x;
        return &self.scrollback[idx];
    }

    /// Allocate a new grid with given dimensions.
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Grid {
        const cells = try allocator.alloc(Cell, width * height);
        @memset(cells, .{});

        const dirty = try allocator.alloc(bool, width * height);
        @memset(dirty, true);

        // Allocate scrollback buffer
        const scrollback_capacity = DEFAULT_SCROLLBACK_LINES;
        const scrollback = try allocator.alloc(Cell, width * scrollback_capacity);
        @memset(scrollback, .{});

        const images = try std.ArrayList(SixelImage).initCapacity(allocator, 0);

        return .{
            .width = width,
            .height = height,
            .cells = cells,
            .dirty = dirty,
            .scrollback = scrollback,
            .scrollback_lines = 0,
            .scrollback_capacity = scrollback_capacity,
            .scrollback_head = 0,
            .viewport_offset = 0,
            .images = images,
            .allocator = allocator,
        };
    }

    /// Check if there's a Sixel image at the given cell position.
    fn getImageAt(self: *Grid, x: i32, y: i32) ?*SixelImage {
        for (self.images.items) |*img| {
            const img_right = img.x + @as(i32, @intCast(img.cols));
            const img_bottom = img.y + @as(i32, @intCast(img.rows));
            if (x >= img.x and x < img_right and y >= img.y and y < img_bottom) {
                return img;
            }
        }
        return null;
    }

    /// Clear Sixel image at a single cell position.
    pub fn clearSixelAt(self: *Grid, x: u32, y: u32) void {
        const xi = @as(i32, @intCast(x));
        const yi = @as(i32, @intCast(y));
        var i: usize = 0;
        while (i < self.images.items.len) {
            const img = &self.images.items[i];
            const img_right = img.x + @as(i32, @intCast(img.cols));
            const img_bottom = img.y + @as(i32, @intCast(img.rows));
            if (xi >= img.x and xi < img_right and yi >= img.y and yi < img_bottom) {
                self.sixel_memory.remove(img.getMemorySize());
                img.deinit();
                _ = self.images.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Clear Sixel images in a row region.
    pub fn clearSixelInRow(self: *Grid, y: u32, start_x: u32, end_x: u32) void {
        const yi = @as(i32, @intCast(y));
        var i: usize = 0;
        while (i < self.images.items.len) {
            const img = &self.images.items[i];
            const img_bottom = img.y + @as(i32, @intCast(img.rows));
            if (yi >= img.y and yi < img_bottom) {
                const img_right = img.x + @as(i32, @intCast(img.cols));
                const overlap = (start_x < @as(u32, @intCast(img_right))) and
                    (end_x > @as(u32, @intCast(img.x)));
                if (overlap) {
                    self.sixel_memory.remove(img.getMemorySize());
                    img.deinit();
                    _ = self.images.orderedRemove(i);
                    continue;
                }
            }
            i += 1;
        }
    }

    /// Clear Sixel images in a rectangular region.
    pub fn clearSixelInRect(self: *Grid, x: u32, y: u32, width: u32, height: u32) void {
        const xi = @as(i32, @intCast(x));
        const yi = @as(i32, @intCast(y));
        const x_end = xi + @as(i32, @intCast(width));
        const y_end = yi + @as(i32, @intCast(height));

        var i: usize = 0;
        while (i < self.images.items.len) {
            const img = &self.images.items[i];
            const img_right = img.x + @as(i32, @intCast(img.cols));
            const img_bottom = img.y + @as(i32, @intCast(img.rows));

            const overlap = (xi < img_right) and (x_end > img.x) and
                (yi < img_bottom) and (y_end > img.y);

            if (overlap) {
                self.sixel_memory.remove(img.getMemorySize());
                img.deinit();
                _ = self.images.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Set cell at (x, y) with given properties.
    pub fn setCell(self: *Grid, x: usize, y: usize, char: u21, fg: u32, bg: u32, flags: CellFlags) void {
        if (x >= self.width or y >= self.height) return;

        // Clear any Sixel image at this position when writing text
        self.clearSixelAt(@intCast(x), @intCast(y));

        const idx = y * self.width + x;

        // Only mark dirty if the cell actually changed
        const current = self.cells[idx];
        if (current.char == char and current.fg == fg and current.bg == bg and
            std.meta.eql(current.flags, flags)) return;

        self.cells[idx] = .{
            .char = char,
            .fg = fg,
            .bg = bg,
            .flags = flags,
        };
        self.dirty[idx] = true;
    }

    /// Write a character at cursor position and advance cursor.
    pub fn writeChar(self: *Grid, char: u21, fg: u32, bg: u32, flags: CellFlags) void {
        if (self.cursor.x >= self.width) {
            // Wrap to next line
            self.cursor.x = 0;
            self.cursor.y += 1;
        }
        if (self.cursor.y >= self.height) {
            // Scroll the screen up
            self.scrollUp(1);
            self.cursor.y = self.height - 1;
        }
        self.setCell(self.cursor.x, self.cursor.y, char, fg, bg, flags);
        self.cursor.x += 1;
    }

    /// Scroll the visible screen up by n lines (moving content to scrollback).
    ///
    /// Sixel Image Handling (Option B - Destroy):
    /// - Images that scroll out of the visible viewport are destroyed
    /// - Images that partially scroll out (spanning the scroll boundary) are also destroyed
    /// - This is simpler and acceptable for MVP; scrollback preservation would require
    ///   tracking images separately in a scrollback buffer
    pub fn scrollUp(self: *Grid, lines: usize) void {
        if (lines == 0) return;

        // Save top lines to scrollback
        for (0..lines) |line| {
            const start_idx = line * self.width;
            const end_idx = start_idx + self.width;

            // Add to circular scrollback buffer
            const dest_idx = self.scrollback_head * self.width;
            @memcpy(self.scrollback[dest_idx..][0..self.width], self.cells[start_idx..end_idx]);

            // Update scrollback state
            self.scrollback_head = (self.scrollback_head + 1) % self.scrollback_capacity;
            self.scrollback_lines = @min(self.scrollback_lines + 1, self.scrollback_capacity);
        }

        // Shift remaining lines up in visible screen
        const remaining_lines = self.height - lines;
        for (0..remaining_lines) |i| {
            const src_idx = (i + lines) * self.width;
            const dest_idx = i * self.width;
            @memcpy(self.cells[dest_idx..][0..self.width], self.cells[src_idx..][0..self.width]);
        }

        // Clear bottom lines
        for (remaining_lines..self.height) |i| {
            const start_idx = i * self.width;
            @memset(self.cells[start_idx..][0..self.width], Cell{});
        }

        // Update Sixel image positions during scroll
        // Images are sorted by their position, so we can efficiently remove/adjust
        self.scrollSixelImages(@intCast(lines));

        // When scrolling, everything in the visible area is potentially changed/moved
        @memset(self.dirty, true);
    }

    /// Handle Sixel images during scroll - moves images with text or destroys them.
    ///
    /// This implements Option B (destroy on scroll out):
    /// - Images entirely above the scroll line: destroyed
    /// - Images spanning the scroll line (partially visible): destroyed
    /// - Images entirely below the scroll line: move up by `rows`
    ///
    /// Images that scroll off-screen are deallocated to free memory.
    /// For scrollback preservation (Option A), images would need to be tracked
    /// in a separate data structure alongside the scrollback cell buffer.
    pub fn scrollSixelImages(self: *Grid, rows: u32) void {
        var i: usize = 0;
        while (i < self.images.items.len) {
            var img = &self.images.items[i];
            const img_bottom = img.y + @as(i32, @intCast(img.rows));

            if (img_bottom <= 0) {
                // Image is entirely above the visible area (negative Y after scroll)
                self.sixel_memory.remove(img.getMemorySize());
                img.deinit();
                _ = self.images.orderedRemove(i);
            } else if (img.y < 0 and img_bottom > 0) {
                // Image spans the scroll boundary (partially visible after scroll)
                // This is a partial scroll - destroy for simplicity
                self.sixel_memory.remove(img.getMemorySize());
                img.deinit();
                _ = self.images.orderedRemove(i);
            } else if (img.y < @as(i32, @intCast(rows))) {
                // Image's top is at or above the scroll line
                // The entire image (or its visible portion) has scrolled off screen
                self.sixel_memory.remove(img.getMemorySize());
                img.deinit();
                _ = self.images.orderedRemove(i);
            } else {
                // Image is entirely below the scroll line - just adjust position
                img.y -= @as(i32, @intCast(rows));
                i += 1;
            }
        }
    }

    /// Scroll the visible screen down by n lines (from scrollback).
    pub fn scrollDown(self: *Grid, lines: usize) void {
        if (lines == 0 or self.scrollback_lines == 0) return;

        const lines_to_scroll = @min(lines, self.scrollback_lines);
        const new_offset = self.viewport_offset + lines_to_scroll;
        self.viewport_offset = @min(new_offset, self.scrollback_lines);
    }

    /// Move cursor to absolute position.
    pub fn moveCursor(self: *Grid, x: usize, y: usize) void {
        const old_x = self.cursor.x;
        const old_y = self.cursor.y;
        self.cursor.x = @min(x, self.width - 1);
        self.cursor.y = @min(y, self.height - 1);

        if (old_x != self.cursor.x or old_y != self.cursor.y) {
            if (old_x < self.width and old_y < self.height) {
                self.dirty[old_y * self.width + old_x] = true;
            }
            self.dirty[self.cursor.y * self.width + self.cursor.x] = true;
        }
    }

    /// Move cursor home (0, 0).
    pub fn cursorHome(self: *Grid) void {
        self.moveCursor(0, 0);
    }

    /// Clear from cursor to end of screen.
    pub fn clearToEndOfScreen(self: *Grid) void {
        // Clear Sixel images in the cleared region
        const start_x: u32 = @intCast(self.cursor.x);
        const start_y: u32 = @intCast(self.cursor.y);
        self.clearSixelInRow(start_y, start_x, @intCast(self.width));

        // Clear remaining rows
        if (start_y + 1 < self.height) {
            self.clearSixelInRect(0, start_y + 1, @intCast(self.width), @intCast(self.height - start_y - 1));
        }

        // Clear from cursor to end of current line
        var x = self.cursor.x;
        while (x < self.width) : (x += 1) {
            self.setCell(x, self.cursor.y, ' ', 0, 0, .{});
        }
        // Clear remaining lines
        var y = self.cursor.y + 1;
        while (y < self.height) : (y += 1) {
            var cx: usize = 0;
            while (cx < self.width) : (cx += 1) {
                self.setCell(cx, y, ' ', 0, 0, .{});
            }
        }
    }

    /// Clear from cursor to end of line.
    pub fn clearToEndOfLine(self: *Grid) void {
        const start_x: u32 = @intCast(self.cursor.x);
        const y: u32 = @intCast(self.cursor.y);
        // Clear Sixel images in the cleared region
        self.clearSixelInRow(y, start_x, @intCast(self.width));
        var x = self.cursor.x;
        while (x < self.width) : (x += 1) {
            self.setCell(x, self.cursor.y, ' ', 0, 0, .{});
        }
    }

    /// Clear entire screen.
    pub fn clearScreen(self: *Grid) void {
        @memset(self.cells, .{});
        @memset(self.dirty, true);
        // Clear all Sixel images when clearing the screen
        self.clearSixelImages();
    }

    /// Mark all cells as dirty (force full redraw).
    pub fn markAllDirty(self: *Grid) void {
        @memset(self.dirty, true);
    }

    /// Clear all dirty flags.
    pub fn clearDirty(self: *Grid) void {
        @memset(self.dirty, false);
    }

    /// Get total lines including scrollback.
    pub fn getTotalLines(self: *Grid) usize {
        return self.height + self.scrollback_lines;
    }

    /// Resize the grid to new dimensions.
    pub fn resize(self: *Grid, allocator: std.mem.Allocator, new_width: usize, new_height: usize) !void {
        if (new_width == self.width and new_height == self.height) return;

        const new_cells = try allocator.alloc(Cell, new_width * new_height);
        @memset(new_cells, .{});

        const new_dirty = try allocator.alloc(bool, new_width * new_height);
        @memset(new_dirty, true);

        // Copy old content to new buffer
        const min_width = @min(self.width, new_width);
        const min_height = @min(self.height, new_height);

        for (0..min_height) |y| {
            const old_idx = y * self.width;
            const new_idx = y * new_width;
            @memcpy(new_cells[new_idx..][0..min_width], self.cells[old_idx..][0..min_width]);
        }

        allocator.free(self.cells);
        allocator.free(self.dirty);
        self.cells = new_cells;
        self.dirty = new_dirty;

        // Also need to resize scrollback if width changed
        if (new_width != self.width) {
            const new_scrollback = try allocator.alloc(Cell, new_width * self.scrollback_capacity);
            @memset(new_scrollback, .{});

            // We could try to copy scrollback too, but for now just clear it to keep it simple
            // and avoid complex circular buffer re-indexing.
            allocator.free(self.scrollback);
            self.scrollback = new_scrollback;
            self.scrollback_lines = 0;
            self.scrollback_head = 0;
            self.viewport_offset = 0;
        }

        self.width = new_width;
        self.height = new_height;

        // Ensure cursor is within bounds
        self.cursor.x = @min(self.cursor.x, self.width - 1);
        self.cursor.y = @min(self.cursor.y, self.height - 1);
    }

    /// Check if we have scrollback content to view.
    pub fn hasScrollback(self: *Grid) bool {
        return self.scrollback_lines > 0 and self.viewport_offset > 0;
    }

    /// Add a sixel image to the grid.
    /// If a new image overlaps with an existing one at the same position,
    /// the existing image is replaced (new one wins).
    pub fn addImage(self: *Grid, image: SixelImage) !void {
        // Check for overlapping images at the same position
        // and remove them (new image replaces old)
        const img_x = image.x;
        const img_y = image.y;
        var i: usize = 0;
        while (i < self.images.items.len) {
            const existing = &self.images.items[i];
            // Check if they start at the same position
            if (existing.x == img_x and existing.y == img_y) {
                self.sixel_memory.remove(existing.getMemorySize());
                existing.deinit();
                _ = self.images.orderedRemove(i);
                continue;
            }
            i += 1;
        }
        // Track memory for new image
        self.sixel_memory.add(image.getMemorySize());
        try self.images.append(self.allocator, image);
    }

    /// Get Sixel memory tracking info.
    pub fn getSixelMemory(self: *Grid) SixelMemory {
        return self.sixel_memory;
    }

    /// Reset Sixel state and memory (for terminal reset CSI !p).
    pub fn resetSixel(self: *Grid) void {
        self.clearSixelImages();
        self.sixel_memory.reset();
    }

    /// Set cell dimensions (typically called from renderer).
    pub fn setCellDimensions(self: *Grid, width: u32, height: u32) void {
        self.cell_width = width;
        self.cell_height = height;
    }

    /// Get cell dimensions.
    pub fn getCellDimensions(self: *Grid) struct { width: u32, height: u32 } {
        return .{ .width = self.cell_width, .height = self.cell_height };
    }
};

test "Grid basic operations" {
    const allocator = std.testing.allocator;
    var grid = try Grid.init(allocator, 80, 24);
    defer grid.deinit(allocator);

    // Test cell setting
    grid.setCell(0, 0, 'A', 0xFF0000, 0x000000, .{ .bold = true });
    const cell = grid.cellAt(0, 0).?;
    try std.testing.expectEqual('A', cell.char);
    try std.testing.expectEqual(0xFF0000, cell.fg);
    try std.testing.expectEqual(true, cell.flags.bold);

    // Test cursor movement
    grid.cursorHome();
    try std.testing.expectEqual(0, grid.cursor.x);
    try std.testing.expectEqual(0, grid.cursor.y);

    grid.moveCursor(10, 5);
    try std.testing.expectEqual(10, grid.cursor.x);
    try std.testing.expectEqual(5, grid.cursor.y);

    // Test clear
    grid.clear();
    try std.testing.expectEqual(0, grid.cursor.x);
    try std.testing.expectEqual(0, grid.cursor.y);
}

test "Grid scrollback" {
    const allocator = std.testing.allocator;
    var grid = try Grid.init(allocator, 80, 24);
    defer grid.deinit(allocator);

    // Fill the screen with content
    for (0..24) |y| {
        for (0..80) |x| {
            grid.setCell(x, y, 'A', 0xFFFFFF, 0x000000, .{});
        }
    }

    // Scroll up - should add to scrollback
    grid.scrollUp(1);
    try std.testing.expectEqual(1, grid.scrollback_lines);

    // Scroll more
    grid.scrollUp(5);
    try std.testing.expectEqual(6, grid.scrollback_lines);

    // Check scrollback content is accessible
    const sb_cell = grid.cellAtScrollback(0, 0);
    try std.testing.expect(sb_cell != null);
    try std.testing.expectEqual('A', sb_cell.?.char);
}
