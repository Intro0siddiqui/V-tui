/// Vtui Renderer Module
/// Glyph atlas-based software blitter with dynamic glyph loading.
const std = @import("std");
const Grid = @import("grid.zig").Grid;
const Cell = @import("grid.zig").Cell;
const Font = @import("font.zig").Font;
const ShapedText = @import("font.zig").ShapedText;
const ShapedGlyph = @import("font.zig").ShapedGlyph;
const SixelImage = @import("sixel.zig").SixelImage;

const ATLAS_SIZE: usize = 512;
const GLYPH_SIZE: usize = 16;
const GLYPHS_PER_ROW: usize = ATLAS_SIZE / GLYPH_SIZE;

pub const GlyphPos = struct { x: u8, y: u8 };

pub const GlyphKey = struct {
    face_index: u8,
    glyph_index: u32,
};

pub const GlyphAtlas = struct {
    pixels: []u8,
    glyph_pos: std.AutoHashMap(GlyphKey, GlyphPos),
    font: ?*Font = null,
    allocator: std.mem.Allocator,
    next_slot: usize = 32, // Start after ASCII control chars
    free_slots: std.ArrayListAligned(usize, null),

    pub fn init(allocator: std.mem.Allocator) !GlyphAtlas {
        const pixels = try allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE * 4);
        @memset(pixels, 0);

        const num_slots = GLYPHS_PER_ROW * GLYPHS_PER_ROW - 32;
        var free_slots = try std.ArrayListAligned(usize, null).initCapacity(allocator, num_slots);
        // Pre-populate free slots (slots 0-31 are reserved)
        var i: usize = 32;
        while (i < GLYPHS_PER_ROW * GLYPHS_PER_ROW) : (i += 1) {
            free_slots.appendAssumeCapacity(i);
        }

        const self = GlyphAtlas{
            .pixels = pixels,
            .glyph_pos = std.AutoHashMap(GlyphKey, GlyphPos).init(allocator),
            .allocator = allocator,
            .free_slots = free_slots,
        };

        // Note: buildBasicFont is called in setFont when a font is available
        return self;
    }

    pub fn deinit(self: *GlyphAtlas) void {
        self.allocator.free(self.pixels);
        self.glyph_pos.deinit();
        self.free_slots.deinit(self.allocator);
    }

    pub fn setFont(self: *GlyphAtlas, font: *Font) void {
        self.font = font;
        // Re-build basic font with real glyphs
        self.glyph_pos.clearRetainingCapacity();
        // Reset slots
        self.free_slots.clearRetainingCapacity();
        var i: usize = 32;
        while (i < GLYPHS_PER_ROW * GLYPHS_PER_ROW) : (i += 1) {
            self.free_slots.appendAssumeCapacity(i);
        }
        @memset(self.pixels, 0);
        self.buildBasicFont() catch {};
    }

    fn buildBasicFont(self: *GlyphAtlas) !void {
        // Build ASCII printable characters (32-126)
        // For now, assume they are in face 0 and map directly (simplification)
        if (self.font) |font| {
            if (font.faces.items.len > 0) {
                for (32..127) |codepoint| {
                    // Get the glyph index for this codepoint in the primary font
                    const face = &font.faces.items[0];
                    const glyph_index = face.getGlyphIndex(@intCast(codepoint));
                    if (glyph_index != 0) {
                        self.loadGlyphByIndex(0, @intCast(glyph_index)) catch {};
                    }
                }
            }
        }
    }

    fn loadGlyph(self: *GlyphAtlas, codepoint: u21) !void {
        // If already loaded, return early
        if (self.glyph_pos.contains(codepoint)) return;

        // Find a free slot
        if (self.free_slots.items.len == 0) {
            return error.AtlasFull;
        }

        const slot_idx = self.free_slots.pop().?;
        const row = slot_idx / GLYPHS_PER_ROW;
        const col = slot_idx % GLYPHS_PER_ROW;

        const glyph_x = col * GLYPH_SIZE;
        const glyph_y = row * GLYPH_SIZE;

        // Check if it's a Braille character (U+2800 - U+28FF)
        if (codepoint >= 0x2800 and codepoint <= 0x28FF) {
            self.drawBraille(glyph_x, glyph_y, codepoint);
        } else if (self.font) |font| {
            const glyph = font.getGlyph(codepoint) catch {
                // Fallback to square
                self.drawFallbackSquare(glyph_x, glyph_y, codepoint);
                try self.glyph_pos.put(codepoint, .{ .x = @intCast(col), .y = @intCast(row) });
                return;
            };
            defer font.releaseGlyph(glyph);

            // Skip empty glyphs
            if (glyph.width == 0 or glyph.height == 0) {
                self.drawFallbackSquare(glyph_x, glyph_y, codepoint);
                try self.glyph_pos.put(codepoint, .{ .x = @intCast(col), .y = @intCast(row) });
                return;
            }

            // Copy glyph bitmap to atlas with bearing adjustment
            const baseline: i32 = 12; // Standard terminal baseline
            const start_x: i32 = glyph.bearing_x;
            const start_y: i32 = baseline - glyph.bearing_y;

            // Calculate stride based on glyph type
            const stride = if (glyph.is_lcd) glyph.width * 3 else glyph.width;
            const pixel_stride = if (glyph.is_lcd) @as(usize, 3) else @as(usize, 1);

            for (0..glyph.height) |gy| {
                const py_signed = start_y + @as(i32, @intCast(gy));
                if (py_signed < 0 or py_signed >= GLYPH_SIZE) continue;
                const py = glyph_y + @as(usize, @intCast(py_signed));

                for (0..glyph.width) |gx| {
                    const px_signed = start_x + @as(i32, @intCast(gx));
                    if (px_signed < 0 or px_signed >= GLYPH_SIZE) continue;
                    const px = glyph_x + @as(usize, @intCast(px_signed));

                    const idx = (py * ATLAS_SIZE + px) * 4;
                    const src_idx = gy * stride + gx * pixel_stride;

                    if (glyph.is_color) {
                        // BGRA from FreeType
                        self.pixels[idx] = glyph.bitmap[src_idx]; // B
                        self.pixels[idx + 1] = glyph.bitmap[src_idx + 1]; // G
                        self.pixels[idx + 2] = glyph.bitmap[src_idx + 2]; // R
                        self.pixels[idx + 3] = 255; // Signal for Color
                    } else if (glyph.is_lcd) {
                        // Sub-pixel alphas
                        self.pixels[idx] = glyph.bitmap[src_idx + 2]; // B alpha
                        self.pixels[idx + 1] = glyph.bitmap[src_idx + 1]; // G alpha
                        self.pixels[idx + 2] = glyph.bitmap[src_idx]; // R alpha
                        self.pixels[idx + 3] = 254; // Signal for LCD
                    } else {
                        // Grayscale alpha
                        const alpha = glyph.bitmap[src_idx];
                        self.pixels[idx] = alpha;
                        self.pixels[idx + 1] = alpha;
                        self.pixels[idx + 2] = alpha;
                        self.pixels[idx + 3] = @min(alpha, @as(u8, 253)); // Signal for Grayscale
                    }
                }
            }
        } else {
            self.drawFallbackSquare(glyph_x, glyph_y, codepoint);
        }

        try self.glyph_pos.put(codepoint, .{ .x = @intCast(col), .y = @intCast(row) });
    }

    fn loadGlyphByIndex(self: *GlyphAtlas, face_index: usize, glyph_index: u32) !void {
        const key = GlyphKey{ .face_index = @intCast(face_index), .glyph_index = glyph_index };
        // If already loaded, return early
        if (self.glyph_pos.contains(key)) return;

        // Find a free slot
        if (self.free_slots.items.len == 0) {
            return error.AtlasFull;
        }

        const slot_idx = self.free_slots.pop().?;
        const row = slot_idx / GLYPHS_PER_ROW;
        const col = slot_idx % GLYPHS_PER_ROW;

        const glyph_x = col * GLYPH_SIZE;
        const glyph_y = row * GLYPH_SIZE;

        if (self.font) |font| {
            // Use getGlyphByIndex to load the glyph directly
            const glyph = font.getGlyphByIndex(face_index, glyph_index) catch {
                // Fallback to square if loading fails
                self.drawFallbackSquare(glyph_x, glyph_y, ' ');
                try self.glyph_pos.put(key, .{ .x = @intCast(col), .y = @intCast(row) });
                return;
            };
            defer font.releaseGlyph(glyph);

            // Skip empty glyphs
            if (glyph.width == 0 or glyph.height == 0) {
                self.drawFallbackSquare(glyph_x, glyph_y, ' ');
                try self.glyph_pos.put(key, .{ .x = @intCast(col), .y = @intCast(row) });
                return;
            }

            // Copy glyph bitmap to atlas with bearing adjustment
            const baseline: i32 = 12; // Standard terminal baseline
            const start_x: i32 = glyph.bearing_x;
            const start_y: i32 = baseline - glyph.bearing_y;

            // Calculate stride based on glyph type
            const stride = if (glyph.is_lcd) glyph.width * 3 else glyph.width;
            const pixel_stride = if (glyph.is_lcd) @as(usize, 3) else @as(usize, 1);

            for (0..glyph.height) |gy| {
                const py_signed = start_y + @as(i32, @intCast(gy));
                if (py_signed < 0 or py_signed >= GLYPH_SIZE) continue;
                const py = glyph_y + @as(usize, @intCast(py_signed));

                for (0..glyph.width) |gx| {
                    const px_signed = start_x + @as(i32, @intCast(gx));
                    if (px_signed < 0 or px_signed >= GLYPH_SIZE) continue;
                    const px = glyph_x + @as(usize, @intCast(px_signed));

                    const idx = (py * ATLAS_SIZE + px) * 4;
                    const src_idx = gy * stride + gx * pixel_stride;

                    if (glyph.is_color) {
                        // BGRA from FreeType
                        self.pixels[idx] = glyph.bitmap[src_idx]; // B
                        self.pixels[idx + 1] = glyph.bitmap[src_idx + 1]; // G
                        self.pixels[idx + 2] = glyph.bitmap[src_idx + 2]; // R
                        self.pixels[idx + 3] = 255; // Signal for Color
                    } else if (glyph.is_lcd) {
                        // Sub-pixel alphas
                        self.pixels[idx] = glyph.bitmap[src_idx + 2]; // B alpha
                        self.pixels[idx + 1] = glyph.bitmap[src_idx + 1]; // G alpha
                        self.pixels[idx + 2] = glyph.bitmap[src_idx]; // R alpha
                        self.pixels[idx + 3] = 254; // Signal for LCD
                    } else {
                        // Grayscale alpha
                        const alpha = glyph.bitmap[src_idx];
                        self.pixels[idx] = alpha;
                        self.pixels[idx + 1] = alpha;
                        self.pixels[idx + 2] = alpha;
                        self.pixels[idx + 3] = @min(alpha, @as(u8, 253)); // Signal for Grayscale
                    }
                }
            }
        } else {
            self.drawFallbackSquare(glyph_x, glyph_y, ' ');
        }

        try self.glyph_pos.put(key, .{ .x = @intCast(col), .y = @intCast(row) });
    }

    fn drawBraille(self: *GlyphAtlas, x: usize, y: usize, codepoint: u21) void {
        const pattern: u8 = @intCast(codepoint - 0x2800);
        // Braille dot layout (8 dots):
        // 1 4
        // 2 5
        // 3 6
        // 7 8
        const dots = [8][2]u8{
            .{ 4, 3 }, .{ 4, 6 }, .{ 4, 9 }, // 1, 2, 3
            .{ 10, 3 }, .{ 10, 6 }, .{ 10, 9 }, // 4, 5, 6
            .{ 4, 12 }, .{ 10, 12 }, // 7, 8
        };

        for (dots, 0..) |dot, i| {
            if ((pattern >> @intCast(i)) & 1 == 1) {
                // Draw a 2x2 dot
                for (0..2) |dy| {
                    for (0..2) |dx| {
                        const px = x + dot[0] + dx;
                        const py = y + dot[1] + dy;
                        const idx = (py * ATLAS_SIZE + px) * 4;
                        self.pixels[idx] = 255;
                        self.pixels[idx + 1] = 255;
                        self.pixels[idx + 2] = 255;
                        self.pixels[idx + 3] = 255;
                    }
                }
            }
        }
    }

    fn drawFallbackSquare(self: *GlyphAtlas, x: usize, y: usize, codepoint: u21) void {
        // std.debug.print("drawFallbackSquare: codepoint={d} at ({d}, {d})\n", .{ codepoint, x, y });
        if (codepoint == ' ') return;
        for (0..GLYPH_SIZE) |gy| {
            for (0..GLYPH_SIZE) |gx| {
                const px = x + gx;
                const py = y + gy;
                const idx = (py * ATLAS_SIZE + px) * 4;
                const is_border = gx == 0 or gx == GLYPH_SIZE - 1 or gy == 0 or gy == GLYPH_SIZE - 1;
                const alpha: u8 = if (is_border) 200 else 0;
                self.pixels[idx] = 255;
                self.pixels[idx + 1] = 255;
                self.pixels[idx + 2] = 255;
                self.pixels[idx + 3] = alpha;
            }
        }
    }

    fn getPixelPattern(self: *GlyphAtlas, codepoint: usize, x: usize, y: usize) u8 {
        _ = self;
        _ = codepoint;
        _ = x;
        _ = y;
        return 0;
    }

    pub fn getGlyphOffset(self: *GlyphAtlas, face_index: u8, glyph_index: u32) ?usize {
        const key = GlyphKey{ .face_index = face_index, .glyph_index = glyph_index };
        const pos = self.glyph_pos.get(key) orelse {
            // Try to load glyph on demand
            if (self.loadGlyphByIndex(face_index, glyph_index)) {
                return self.getGlyphOffset(face_index, glyph_index);
            } else |_| {
                return null;
            }
        };
        const px: usize = @as(usize, pos.x) * GLYPH_SIZE;
        const py: usize = @as(usize, pos.y) * GLYPH_SIZE;
        return py * ATLAS_SIZE * 4 + px * 4;
    }
};

pub const RendererConfig = struct { font_width: u32 = 16, font_height: u32 = 16, scale: u32 = 1 };

pub const Renderer = struct {
    atlas: GlyphAtlas,
    config: RendererConfig,
    screen_width: usize,
    screen_height: usize,
    stride: usize,
    allocator: std.mem.Allocator,

    cell_width: usize = 16,
    cell_height: usize = 16,

    pub fn init(width: usize, height: usize, config: RendererConfig, allocator: std.mem.Allocator) !Renderer {
        return .{
            .atlas = try GlyphAtlas.init(allocator),
            .config = config,
            .screen_width = width,
            .screen_height = height,
            .stride = width * 4,
            .allocator = allocator,
            .cell_width = config.font_width,
            .cell_height = config.font_height,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.atlas.deinit();
    }

    pub fn resize(self: *Renderer, new_width: usize, new_height: usize) void {
        self.screen_width = new_width;
        self.screen_height = new_height;
        self.stride = new_width * 4;
    }

    pub fn resizeCells(self: *Renderer, cell_width: usize, cell_height: usize) void {
        self.cell_width = cell_width;
        self.cell_height = cell_height;
        self.config.font_width = @intCast(cell_width);
        self.config.font_height = @intCast(cell_height);
    }

    pub fn setStride(self: *Renderer, stride: usize) void {
        self.stride = stride;
    }

    pub fn setFont(self: *Renderer, font: *Font) void {
        self.atlas.setFont(font);
    }

    pub fn render(self: *Renderer, grid: *Grid, buffer: []u8) void {
        const fw = self.config.font_width;
        const fh = self.config.font_height;
        _ = self.config.scale;

        // If cursor is visible, ensure its cell is marked dirty so it's redrawn
        // (This clears the old XOR'd cursor)
        if (grid.cursor.visible) {
            const cursor_idx = grid.cursor.y * grid.width + grid.cursor.x;
            if (cursor_idx < grid.dirty.len) {
                grid.dirty[cursor_idx] = true;
            }
        }

        // Render Sixel images BEFORE text (they act as background)
        for (grid.images.items) |*image| {
            self.blitSixelImage(buffer, image, fw, fh);
        }

        var y: usize = 0;
        var blit_count: usize = 0;

        while (y < grid.height) : (y += 1) {
            var x: usize = 0;
            while (x < grid.width) : (x += 1) {
                const idx = y * grid.width + x;
                if (!grid.dirty[idx]) continue;

                blit_count += 1;
                const cell = grid.cellAt(x, y) orelse continue;

                // Try to shape text at current position
                const shape_result = self.shapeTextAt(grid, x, y);
                if (shape_result) |result| {
                    defer result.shaped.deinit();

                    // Render shaped glyphs
                    var x_pos = x * fw;
                    for (result.shaped.glyphs) |glyph| {
                        // HarfBuzz returns positions in 26.6 fixed point (1/64th of a pixel)
                        const x_offset_px = @divFloor(glyph.x_offset, 64);
                        const y_offset_px = @divFloor(glyph.y_offset, 64);
                        const x_advance_px = @divFloor(glyph.x_advance, 64);

                        self.blitGlyph(
                            buffer,
                            cell.fg,
                            cell.bg,
                            x_pos,
                            y * fh,
                            0, // face_index (primary font)
                            glyph.glyph_index,
                            @as(i32, @intCast(x_offset_px)),
                            @as(i32, @intCast(y_offset_px)),
                        );

                        // Advance by glyph width (in pixels)
                        x_pos += @as(usize, @intCast(@max(x_advance_px, 0)));
                    }

                    // Mark the consumed cells as not dirty (since we rendered them)
                    for (0..result.cells_consumed) |offset| {
                        grid.dirty[(y * grid.width) + (x + offset)] = false;
                    }

                    // Skip over cells that were processed
                    x += result.cells_consumed - 1;
                } else {
                    // Render individual glyph (fallback when no font or shaping fails)
                    if (self.atlas.font) |font| {
                        const glyph_index = font.faces.items[0].getGlyphIndex(cell.char);
                        if (glyph_index != 0) {
                            if (cell.char == 'R') {
                                // std.debug.print("Blitting 'R' at ({d}, {d}) glyph_index={d}\n", .{ x, y, glyph_index });
                            }
                            self.blitGlyph(
                                buffer,
                                cell.fg,
                                cell.bg,
                                x * fw,
                                y * fh,
                                0,
                                glyph_index,
                                0,
                                0,
                            );
                        }
                    }
                    // Clear dirty flag for this single cell
                    grid.dirty[idx] = false;
                }
            }
        }

        if (blit_count > 0) {
            // std.debug.print("Blitted {d} cells\n", .{blit_count});
        }

        if (grid.cursor.visible) {
            self.blitCursor(buffer, grid.cursor.x * fw, grid.cursor.y * fh);
        }
    }

    fn blitSixelImage(self: *Renderer, buffer: []u8, image: *SixelImage, cell_width: usize, cell_height: usize) void {
        const start_x_px = @as(usize, @intCast(image.x)) * cell_width;
        const start_y_px = @as(usize, @intCast(image.y)) * cell_height;

        const img_cell_width = image.cell_width;
        const img_cell_height = image.cell_height;

        const need_scale = img_cell_width != cell_width or img_cell_height != cell_height;

        if (need_scale) {
            self.blitSixelImageScaled(buffer, image, start_x_px, start_y_px, cell_width, cell_height);
        } else {
            self.blitSixelImageDirect(buffer, image, start_x_px, start_y_px);
        }
    }

    fn blitSixelImageDirect(self: *Renderer, buffer: []u8, image: *SixelImage, start_x: usize, start_y: usize) void {
        const sw = self.screen_width;
        const sh = self.screen_height;
        const img_w = image.width;
        const img_h = image.height;

        for (0..img_h) |row| {
            const dst_y = start_y + row;
            if (dst_y >= sh) break;

            const src_row_start = row * img_w;
            const dst_row_start = dst_y * sw;

            var col: usize = 0;
            // SIMD path for 8 pixels at a time (32 bytes)
            while (col + 8 <= img_w and start_x + col + 8 <= sw) : (col += 8) {
                const src_idx = src_row_start + col;
                const dst_idx = (dst_row_start + start_x + col) * 4;

                const src_ptr: [*]const u32 = @ptrCast(image.data[src_idx..].ptr);
                const src_vec: @Vector(8, u32) = @as(*const @Vector(8, u32), @ptrCast(@alignCast(src_ptr))).*;

                // Check if any pixels are non-transparent (alpha != 0)
                const alpha_vec = src_vec >> @as(@Vector(8, u32), @splat(24));
                if (@reduce(.Or, alpha_vec != @as(@Vector(8, u32), @splat(0)))) {
                    const dst_ptr: [*]u32 = @ptrCast(@alignCast(buffer[dst_idx..].ptr));
                    // For now, simple overwrite for non-transparent pixels (Sixel transparency is usually binary)
                    // In a more complex renderer, we'd do full alpha blending here.
                    // But for stand-alone standalone, we often just want the Sixel to win.
                    
                    // Selective mask: only overwrite where src alpha != 0
                    const mask = alpha_vec != @as(@Vector(8, u32), @splat(0));
                    @as(*@Vector(8, u32), @ptrCast(@alignCast(dst_ptr))).* = @select(u32, mask, src_vec, @as(*@Vector(8, u32), @ptrCast(@alignCast(dst_ptr))).*);
                }
            }

            // Fallback for remaining pixels
            while (col < img_w) : (col += 1) {
                const src_idx = src_row_start + col;
                const pixel = image.data[src_idx];

                if ((pixel >> 24) == 0) continue;

                const dst_x = start_x + col;
                if (dst_x >= sw) continue;

                const dst_idx = (dst_row_start + dst_x) * 4;
                if (dst_idx + 3 < buffer.len) {
                    const ptr: [*]u32 = @ptrCast(@alignCast(buffer[dst_idx..].ptr));
                    ptr[0] = pixel;
                }
            }
        }
    }

    fn blitSixelImageScaled(
        self: *Renderer,
        buffer: []u8,
        image: *SixelImage,
        start_x: usize,
        start_y: usize,
        cell_width: usize,
        cell_height: usize,
    ) void {
        const img_px_width = image.width;
        const img_px_height = image.height;

        const target_px_width = @as(u32, @intCast(image.cols)) * @as(u32, @intCast(cell_width));
        const target_px_height = @as(u32, @intCast(image.rows)) * @as(u32, @intCast(cell_height));

        if (target_px_width == 0 or target_px_height == 0) return;

        const scale_x: f32 = @as(f32, @floatFromInt(img_px_width)) / @as(f32, @floatFromInt(target_px_width));
        const scale_y: f32 = @as(f32, @floatFromInt(img_px_height)) / @as(f32, @floatFromInt(target_px_height));

        const max_target_width = @min(target_px_width, self.screen_width - start_x);
        const max_target_height = @min(target_px_height, self.screen_height - start_y);

        for (0..max_target_height) |target_row| {
            const src_row_f = @as(f32, @floatFromInt(target_row)) * scale_y;
            const src_row = @as(u32, @intFromFloat(src_row_f));
            if (src_row >= img_px_height) continue;

            const dst_y = start_y + target_row;
            if (dst_y >= self.screen_height) break;

            const dst_row_start = dst_y * self.screen_width;

            for (0..max_target_width) |target_col| {
                const src_col_f = @as(f32, @floatFromInt(target_col)) * scale_x;
                const src_col = @as(u32, @intFromFloat(src_col_f));
                if (src_col >= img_px_width) continue;

                const src_idx = src_row * img_px_width + src_col;
                const pixel = image.data[src_idx];

                if ((pixel >> 24) == 0) continue;

                const dst_x = start_x + target_col;
                const dst_idx = (dst_row_start + dst_x) * 4;

                if (dst_idx + 3 < buffer.len) {
                    const ptr: [*]u32 = @ptrCast(@alignCast(buffer[dst_idx..].ptr));
                    ptr[0] = pixel;
                }
            }
        }
    }

    fn shapeTextAt(self: *Renderer, grid: *Grid, x: usize, y: usize) ?struct { shaped: ShapedText, cells_consumed: usize } {
        _ = self;
        _ = grid;
        _ = x;
        _ = y;
        return null;
    }

    fn blitGlyph(self: *Renderer, buffer: []u8, fg_color: u32, bg_color: u32, dst_x: usize, dst_y: usize, face_index: u8, glyph_index: u32, x_offset: i32, y_offset: i32) void {
        std.debug.print("blitGlyph called: dst=({d},{d}) fg=0x{X} bg=0x{X}\n", .{ dst_x, dst_y, fg_color, bg_color });
        const fw = self.config.font_width;
        const fh = self.config.font_height;

        self.fillRect(buffer, dst_x, dst_y, fw, fh, bg_color);

        const glyph_offset = self.atlas.getGlyphOffset(face_index, glyph_index) orelse return;

        // Apply offsets to the destination position
        const final_dst_x = @as(isize, @intCast(dst_x)) + x_offset;
        const final_dst_y = @as(isize, @intCast(dst_y)) + y_offset;

        // SIMD-optimized blending for 16-pixel wide cells
        if (fw == 16) {
            const fg_b: u16 = @intCast(fg_color & 0xFF);
            const fg_g: u16 = @intCast((fg_color >> 8) & 0xFF);
            const fg_r: u16 = @intCast((fg_color >> 16) & 0xFF);

            const fgb_vec: @Vector(16, u16) = @splat(fg_b);
            const fgg_vec: @Vector(16, u16) = @splat(fg_g);
            const fgr_vec: @Vector(16, u16) = @splat(fg_r);
            const v255: @Vector(16, u16) = @splat(255);

            for (0..fh) |gy| {
                const py = @as(isize, @intCast(gy)) + final_dst_y;
                if (py < 0 or py >= @as(isize, @intCast(self.screen_height))) continue;

                const atlas_idx = glyph_offset + (gy * ATLAS_SIZE) * 4;
                const dst_idx = @as(usize, @intCast(py)) * self.stride + @as(usize, @intCast(final_dst_x)) * 4;

                // Ensure we don't go out of bounds
                if (dst_idx + 16 * 4 > buffer.len) continue;
                if (atlas_idx + 16 * 4 > self.atlas.pixels.len) continue;

                // Check signal byte of first pixel to decide mode
                const a_signal = self.atlas.pixels[atlas_idx + 3];
                if (a_signal == 0) {
                    // Optimization: Check if entire row is empty
                    // ... (could use @reduce here)
                }

                if (a_signal == 255) {
                    // Color Emoji SIMD
                    const ptr_dst: [*]align(1) u32 = @ptrCast(buffer[dst_idx..].ptr);
                    const ptr_src: [*]align(1) u32 = @ptrCast(self.atlas.pixels[atlas_idx..].ptr);
                    @as(*align(1) @Vector(16, u32), @ptrCast(ptr_dst)).* = @as(*align(1) @Vector(16, u32), @ptrCast(ptr_src)).*;
                    continue;
                }

                // Sub-pixel or Grayscale SIMD
                var alpha_r: @Vector(16, u16) = undefined;
                var alpha_g: @Vector(16, u16) = undefined;
                var alpha_b: @Vector(16, u16) = undefined;

                inline for (0..16) |i| {
                    const base = atlas_idx + i * 4;
                    alpha_b[i] = self.atlas.pixels[base];
                    alpha_g[i] = self.atlas.pixels[base + 1];
                    alpha_r[i] = self.atlas.pixels[base + 2];
                }

                const inv_alpha_r = v255 - alpha_r;
                const inv_alpha_g = v255 - alpha_g;
                const inv_alpha_b = v255 - alpha_b;

                // Get current pixels (already filled with BG)
                const ptr: [*]align(1) u32 = @ptrCast(buffer[dst_idx..].ptr);

                var bg_b: @Vector(16, u16) = undefined;
                var bg_g: @Vector(16, u16) = undefined;
                var bg_r: @Vector(16, u16) = undefined;

                inline for (0..16) |i| {
                    const p = ptr[i];
                    bg_b[i] = @intCast(p & 0xFF);
                    bg_g[i] = @intCast((p >> 8) & 0xFF);
                    bg_r[i] = @intCast((p >> 16) & 0xFF);
                }

                // Blend: (FG * Alpha + BG * (255 - Alpha)) / 255
                const out_b = (fgb_vec * alpha_b + bg_b * inv_alpha_b) / v255;
                const out_g = (fgg_vec * alpha_g + bg_g * inv_alpha_g) / v255;
                const out_r = (fgr_vec * alpha_r + bg_r * inv_alpha_r) / v255;

                inline for (0..16) |i| {
                    ptr[i] = @as(u32, @intCast(out_b[i])) |
                        (@as(u32, @intCast(out_g[i])) << 8) |
                        (@as(u32, @intCast(out_r[i])) << 16) |
                        (@as(u32, 255) << 24);
                }
            }
        } else {
            // Fallback for non-16 wide fonts
            const fg_r: u32 = (fg_color >> 16) & 0xFF;
            const fg_g: u32 = (fg_color >> 8) & 0xFF;
            const fg_b: u32 = fg_color & 0xFF;

            for (0..fh) |gy| {
                const py = @as(isize, @intCast(gy)) + final_dst_y;
                if (py < 0 or py >= @as(isize, @intCast(self.screen_height))) continue;
                for (0..fw) |gx| {
                    const px = @as(isize, @intCast(gx)) + final_dst_x;
                    if (px < 0 or px >= @as(isize, @intCast(self.screen_width))) continue;

                    const atlas_idx = glyph_offset + (gy * ATLAS_SIZE + gx) * 4;
                    const a_signal = self.atlas.pixels[atlas_idx + 3];

                    if (a_signal == 0) continue;

                    const dst_idx = @as(usize, @intCast(py)) * self.stride + @as(usize, @intCast(px)) * 4;

                    if (a_signal == 255) {
                        // Solid Color (Emoji)
                        buffer[dst_idx] = self.atlas.pixels[atlas_idx];
                        buffer[dst_idx + 1] = self.atlas.pixels[atlas_idx + 1];
                        buffer[dst_idx + 2] = self.atlas.pixels[atlas_idx + 2];
                        buffer[dst_idx + 3] = 255;
                    } else {
                        // Grayscale or LCD
                        const alpha_r = self.atlas.pixels[atlas_idx + 2];
                        const alpha_g = self.atlas.pixels[atlas_idx + 1];
                        const alpha_b = self.atlas.pixels[atlas_idx];

                        const bg_b = buffer[dst_idx];
                        const bg_g = buffer[dst_idx + 1];
                        const bg_r = buffer[dst_idx + 2];

                        buffer[dst_idx] = @intCast((fg_b * alpha_b + @as(u32, bg_b) * (255 - alpha_b)) / 255);
                        buffer[dst_idx + 1] = @intCast((fg_g * alpha_g + @as(u32, bg_g) * (255 - alpha_g)) / 255);
                        buffer[dst_idx + 2] = @intCast((fg_r * alpha_r + @as(u32, bg_r) * (255 - alpha_r)) / 255);
                        buffer[dst_idx + 3] = 255;
                    }
                }
            }
        }
    }

    fn blitCursor(self: *Renderer, buffer: []u8, dst_x: usize, dst_y: usize) void {
        const fw = self.config.font_width;
        const fh = self.config.font_height;

        if (fw == 16) {
            const v_xor: @Vector(16, u32) = @splat(0x00FFFFFF);
            for (0..fh) |gy| {
                if (dst_y + gy >= self.screen_height) break;
                const idx = (dst_y + gy) * self.stride + dst_x * 4;
                const ptr: [*]align(1) u32 = @ptrCast(buffer[idx..].ptr);
                var vec: @Vector(16, u32) = undefined;
                inline for (0..16) |i| {
                    vec[i] = ptr[i];
                }
                vec = vec ^ v_xor;
                inline for (0..16) |i| {
                    ptr[i] = vec[i];
                }
            }
        } else {
            for (0..fh) |gy| {
                if (dst_y + gy >= self.screen_height) break;
                for (0..fw) |gx| {
                    if (dst_x + gx >= self.screen_width) break;
                    const idx = (dst_y + gy) * self.stride + (dst_x + gx) * 4;
                    buffer[idx] = 255 - buffer[idx];
                    buffer[idx + 1] = 255 - buffer[idx + 1];
                    buffer[idx + 2] = 255 - buffer[idx + 2];
                }
            }
        }
    }

    fn fillRect(self: *Renderer, buffer: []u8, x: usize, y: usize, w: usize, h: usize, color: u32) void {
        const b: u8 = @intCast(color & 0xFF);
        const g: u8 = @intCast((color >> 8) & 0xFF);
        const r: u8 = @intCast((color >> 16) & 0xFF);
        const a: u8 = 255;

        // Create a single pixel (4 bytes)
        const pixel = [4]u8{ b, g, r, a };
        const pixel_u32: u32 = @bitCast(pixel);

        if (w == 16) {
            const v_pixel: @Vector(16, u32) = @splat(pixel_u32);
            for (0..h) |dy| {
                if (y + dy >= self.screen_height) break;
                const row_start = (y + dy) * self.stride + x * 4;
                const ptr: [*]align(1) u32 = @ptrCast(buffer[row_start..].ptr);
                @as(*align(1) @Vector(16, u32), @ptrCast(ptr)).* = v_pixel;
            }
        } else {
            for (0..h) |dy| {
                if (y + dy >= self.screen_height) break;
                const row_start = (y + dy) * self.stride + x * 4;
                const ptr: [*]align(1) u32 = @ptrCast(buffer[row_start..].ptr);
                for (0..w) |dx| {
                    if (x + dx >= self.screen_width) break;
                    ptr[dx] = pixel_u32;
                }
            }
        }
    }
};

/// Save RGBA buffer as PPM image file (P6 format).
pub fn savePPM(buffer: []const u8, width: usize, height: usize, stride: usize, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var header: [64]u8 = undefined;
    const header_len = std.fmt.bufPrint(&header, "P6\n{d} {d}\n255\n", .{ width, height }) catch |err| {
        std.debug.print("Failed to format PPM header: {}\n", .{err});
        return err;
    };
    try file.writeAll(header_len);

    // Write RGB pixels (3 bytes per pixel)
    var rgb_buf = try std.heap.page_allocator.alloc(u8, width * 3);
    defer std.heap.page_allocator.free(rgb_buf);

    for (0..height) |y| {
        const row_start = y * stride;
        for (0..width) |x| {
            const px_idx = row_start + x * 4;
            rgb_buf[x * 3] = buffer[px_idx + 2]; // R
            rgb_buf[x * 3 + 1] = buffer[px_idx + 1]; // G
            rgb_buf[x * 3 + 2] = buffer[px_idx]; // B
        }
        try file.writeAll(rgb_buf);
    }
}

test "Renderer basic operations" {
    var grid = try Grid.init(std.testing.allocator, 80, 24);
    defer grid.deinit(std.testing.allocator);
    var renderer = try Renderer.init(1280, 384, .{}, std.testing.allocator);
    defer renderer.deinit();
    grid.setCell(0, 0, 'A', 0xFF0000, 0x000000, .{});
    const buffer_size = renderer.screen_width * renderer.screen_height * 4;
    const buffer = try std.testing.allocator.alloc(u8, buffer_size);
    defer std.testing.allocator.free(buffer);
    renderer.render(&grid, buffer);
    var has_pixels = false;
    for (buffer) |p| {
        if (p > 0) {
            has_pixels = true;
            break;
        }
    }
    try std.testing.expect(has_pixels);
}
