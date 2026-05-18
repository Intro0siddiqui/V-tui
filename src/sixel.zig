/// Sixel image support for Vtui.
const std = @import("std");

/// Default Sixel configuration limits (matching foot terminal).
pub const DEFAULT_SIXEL_CONFIG = SixelConfig{
    .max_width = 10000,
    .max_height = 10000,
    .max_colors = 1024,
    .max_images = 100,
    .scrolling = true,
};

/// Sixel configuration with resource limits.
pub const SixelConfig = struct {
    max_width: u32 = 10000,
    max_height: u32 = 10000,
    max_colors: u32 = 1024,
    max_images: u32 = 100,
    scrolling: bool = true,
};

/// Track total memory used by Sixel images.
pub const SixelMemory = struct {
    total_bytes: u64 = 0,
    image_count: u32 = 0,

    pub fn add(self: *SixelMemory, bytes: u64) void {
        self.total_bytes += bytes;
        self.image_count += 1;
    }

    pub fn remove(self: *SixelMemory, bytes: u64) void {
        if (self.total_bytes >= bytes) {
            self.total_bytes -= bytes;
        } else {
            self.total_bytes = 0;
        }
        if (self.image_count > 0) {
            self.image_count -= 1;
        }
    }

    pub fn reset(self: *SixelMemory) void {
        self.total_bytes = 0;
        self.image_count = 0;
    }
};

/// Sixel parser states.
pub const SixelState = enum {
    init,
    params, // Parsing parameters after 'q'
    data, // Parsing Sixel data
    decgra, // DECGRA - Raster Attributes ("pan;pad;width;height")
    decgri, // DECGRI - Graphics Repeat Introducer (!count)
    decgci, // DECGCI - Color Introducer (#idx;...)
};

/// Represents a single Sixel image.
pub const SixelImage = struct {
    x: i32, // Starting column (cell coordinates)
    y: i32, // Starting row (cell coordinates)
    width: u32, // Image width in pixels
    height: u32, // Image height in pixels
    data: []u32, // RGBA pixel data (width * height)
    allocator: std.mem.Allocator,

    cols: u32 = 0, // Width in terminal cells
    rows: u32 = 0, // Height in terminal cells
    cell_width: u32 = 0, // Cell width in pixels when image was created
    cell_height: u32 = 0, // Cell height in pixels when image was created

    pub fn deinit(self: *SixelImage) void {
        self.allocator.free(self.data);
    }

    /// Get memory used by this image in bytes.
    pub fn getMemorySize(self: *const SixelImage) u64 {
        return @as(u64, self.data.len) * 4;
    }
};

/// Sixel parser and builder.
pub const SixelParser = struct {
    state: SixelState = .init,
    color_palette: [256]u32,
    current_color_idx: u8 = 0,
    current_color: u32 = 0xFFFFFFFF, // Default white (ARGB)

    // Configuration and limits
    config: SixelConfig = DEFAULT_SIXEL_CONFIG,
    use_private_palette: bool = true, // Private mode (DECSCL)
    is_transparent: bool = true, // P2 = 1

    // Memory tracking
    memory: SixelMemory = .{},

    // Image building state
    image_width: u32 = 0,
    image_height: u32 = 0,
    alloc_height: u32 = 0,
    data: []u32 = &[_]u32{},
    cursor_x: u32 = 0,
    cursor_y: u32 = 0,
    pan: u32 = 2, // Aspect ratio width (cells per 6 pixels horizontally)
    pad: u32 = 1, // Aspect ratio height (pixel repeat vertically)

    // Parameter parsing
    param_buf: [16]u32 = [_]u32{0} ** 16,
    param_idx: usize = 0,
    current_param: u32 = 0,

    // DECGRI - Repeat count
    repeat_count: u32 = 1,

    // DECGCI - Color index
    color_idx: u8 = 0,

    // DECGRA - Raster attributes stored
    gra_params: [4]u32 = [_]u32{0} ** 4,
    gra_param_idx: usize = 0,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SixelParser {
        var parser = SixelParser{
            .allocator = allocator,
            .color_palette = [_]u32{0} ** 256,
        };
        // Initialize standard sixel color palette (8 colors + duplicates)
        const std_colors = [_]u32{
            0xFF000000, // Black (opaque)
            0xFF800000, // Red
            0xFF008000, // Green
            0xFF808000, // Yellow
            0xFF000080, // Blue
            0xFF800080, // Magenta
            0xFF008080, // Cyan
            0xFFC0C0C0, // White
        };
        for (std_colors, 0..) |color, i| {
            parser.color_palette[i] = color;
        }
        return parser;
    }

    pub fn deinit(self: *SixelParser) void {
        if (self.data.len > 0) {
            self.allocator.free(self.data);
            self.data = &[_]u32{};
        }
    }

    /// Set configuration and limits.
    pub fn setConfig(self: *SixelParser, config: SixelConfig) void {
        self.config = config;
    }

    /// Set private/shared palette mode (DECSCL 61).
    /// When enabled, each Sixel image starts with fresh palette.
    /// When disabled (shared), palette persists between images.
    pub fn setPrivatePalette(self: *SixelParser, private: bool) void {
        self.use_private_palette = private;
    }

    /// Reset palette to defaults (called for new Sixel when using private palette).
    pub fn resetPalette(self: *SixelParser) void {
        const std_colors = [_]u32{
            0xFF000000, // Black
            0xFF800000, // Red
            0xFF008000, // Green
            0xFF808000, // Yellow
            0xFF000080, // Blue
            0xFF800080, // Magenta
            0xFF008080, // Cyan
            0xFFC0C0C0, // White
        };
        for (std_colors, 0..) |color, i| {
            self.color_palette[i] = color;
        }
        // Fill the rest with grayscale
        var i: u8 = 8;
        while (i < 16) : (i += 1) {
            const gray: u8 = @intCast((@as(u16, i - 8) * 255) / 7);
            self.color_palette[i] = 0xFF000000 | (@as(u32, gray) << 16) | (@as(u32, gray) << 8) | gray;
        }
        // Rest as black
        while (i < 255) : (i += 1) {
            self.color_palette[i] = 0xFF000000;
        }
        self.current_color_idx = 0;
        self.current_color = self.color_palette[0];
    }

    /// Check if image dimensions are within limits.
    fn checkLimits(self: *SixelParser, width: u32, height: u32) bool {
        if (width > self.config.max_width or height > self.config.max_height) {
            return false;
        }
        return true;
    }

    /// Get total memory used by current image data.
    fn getCurrentImageSize(self: *SixelParser) u64 {
        return @as(u64, self.image_width) * @as(u64, self.image_height) * 4;
    }

    /// Reset parser state for a new image.
    pub fn reset(self: *SixelParser) void {
        self.state = .init;
        self.current_color_idx = 0;
        self.current_color = self.color_palette[0];
        self.image_width = 0;
        self.image_height = 0;
        self.alloc_height = 0;
        self.is_transparent = true;
        if (self.data.len > 0) {
            self.allocator.free(self.data);
            self.data = &[_]u32{};
        }
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.pan = 2;
        self.pad = 1;
        self.param_idx = 0;
        self.current_param = 0;
        self.repeat_count = 1;
        self.color_idx = 0;
        self.gra_params = [_]u32{0} ** 4;
        self.gra_param_idx = 0;
    }

    /// Process a single byte of Sixel data.
    /// Returns true if the image is complete (ST received).
    pub fn put(self: *SixelParser, c: u8) bool {
        switch (self.state) {
            .init => {
                // Sixel command starts with 'q' usually after DCS params
                // But we handle params in DCS level in parser.zig, so here we might just see 'q'
                // Actually, in foot, `sixel_init` is called with p1, p2, p3.
                // The parser.zig will handle `ESC P q ; ...` and call `sixel_init`.
                // Here we assume `put` is called after init.
                if (c == 'q') {
                    self.state = .params;
                } else if (c >= '?' and c <= '~') {
                    // Direct data start (fallback or specific case)
                    self.state = .data;
                    self.processSixelChar(c);
                }
            },
            .params => {
                if (c >= '0' and c <= '9') {
                    self.current_param = self.current_param * 10 + (c - '0');
                } else if (c == ';') {
                    self.applyParam();
                    self.current_param = 0;
                } else if (c >= '?' and c <= '~') {
                    // Start of data
                    self.applyParam();
                    self.state = .data;
                    self.processSixelChar(c);
                } else {
                    // Ignore other chars (like ' ' or newlines)
                }
            },
            .data => {
                if (c == '\\') {
                    // ST (String Terminator) - End of image
                    return true;
                }
                if (c == 0x1B) {
                    // ESC - could be start of ST (ESC \)
                    // We rely on the main parser to catch ESC \ as ST
                    // But if we see ESC here, it's part of data or escape sequence?
                    // Sixel data shouldn't contain ESC unless it's ST.
                    // If main parser sees ESC, it switches state.
                    // So we shouldn't see ESC here unless it's an error.
                    return false;
                }
                self.processSixelChar(c);
            },
            .decgra => {
                self.processDecgra(c);
            },
            .decgri => {
                self.processDecgri(c);
            },
            .decgci => {
                self.processDecgci(c);
            },
        }
        return false;
    }

    fn applyParam(self: *SixelParser) void {
        // Only first 3 params are used for Sixel init: P1 (pan), P2 (background), P3 (pad)
        // foot's `sixel_init` logic:
        // P1: aspect ratio (0,1->2:1, 2->5:1, 3,4->3:1, 5,6->2:1, 7,8,9->1:1)
        // P2: 0|2 (bg color), 1 (transparent)
        // P3: horizontal grid size (ignored)
        if (self.param_idx < 3) {
            self.param_buf[self.param_idx] = self.current_param;
            self.param_idx += 1;
        }

        // Apply aspect ratio from P1
        if (self.param_idx >= 1) {
            const p1 = self.param_buf[0];
            self.pan = switch (p1) {
                2 => 5, // 5:1 aspect ratio
                3, 4 => 3, // 3:1 aspect ratio
                7, 8, 9 => 1, // 1:1 aspect ratio
                else => 2, // 2:1 aspect ratio (default for 0,1,5,6)
            };
            self.pad = 1;
        }

        // Apply transparency from P2
        if (self.param_idx >= 2) {
            const p2 = self.param_buf[1];
            // 1 = transparent, 0 or 2 = use background color
            self.is_transparent = (p2 == 1);
        }
    }

    pub fn processSixelChar(self: *SixelParser, c: u8) void {
        switch (c) {
            '"' => {
                // DECGRA - Raster Attributes ("pan;pad;width;height")
                self.state = .decgra;
                self.gra_param_idx = 0;
                self.current_param = 0;
            },
            '!' => {
                // DECGRI - Graphics Repeat Introducer
                self.state = .decgri;
                self.repeat_count = 1;
                self.current_param = 0;
            },
            '#' => {
                // DECGCI - Color Introducer
                self.state = .decgci;
                self.color_idx = 0;
                self.current_param = 0;
                self.param_idx = 0;
            },
            '$' => {
                // Carriage return (move to start of row)
                self.cursor_x = 0;
            },
            '-' => {
                // New line (move down by 6 pixels)
                self.cursor_y += 6;
                self.cursor_x = 0;
            },
            '?'...'~' => {
                // Pixel data (6 bits)
                const pixel_data = c - 63;
                self.drawSixel(pixel_data);
                self.cursor_x += 1;
            },
            '\x00'...'\r' => {
                // Ignore whitespace
            },
            else => {
                // Unknown char, ignore or error
            },
        }
    }

    /// Handle DECGRA - Raster Attributes ("pan;pad;width;height")
    fn processDecgra(self: *SixelParser, c: u8) void {
        switch (c) {
            '0'...'9' => {
                self.current_param = self.current_param * 10 + (c - '0');
            },
            ';' => {
                if (self.gra_param_idx < 4) {
                    self.gra_params[self.gra_param_idx] = self.current_param;
                    self.gra_param_idx += 1;
                }
                self.current_param = 0;
            },
            else => {
                // End of DECGRA sequence
                if (self.gra_param_idx < 4) {
                    self.gra_params[self.gra_param_idx] = self.current_param;
                    self.gra_param_idx += 1;
                }

                // Apply raster attributes
                const pan = if (self.gra_params[0] > 0) self.gra_params[0] else 1;
                const pad = if (self.gra_params[1] > 0) self.gra_params[1] else 1;
                const width = self.gra_params[2];
                const height = self.gra_params[3];

                if (self.image_width == 0 and self.image_height == 0) {
                    self.pan = pan;
                    self.pad = pad;
                }

                if (width > 0 and height > 0) {
                    const req_width = width * pad;
                    const req_height = height * pan;
                    if (req_width > 0 and req_height > 0) {
                        self.resizeImage(req_height);
                        if (req_width > self.image_width) {
                            self.resizeImage(self.alloc_height);
                        }
                    }
                }

                // Reset state for next time
                self.current_param = 0;
                self.gra_param_idx = 0;
                self.gra_params = [_]u32{0} ** 4;

                self.state = .data;
                if (c >= '?' and c <= '~') {
                    self.processSixelChar(c);
                }
            },
        }
    }

    /// Handle DECGRI - Graphics Repeat Introducer
    fn processDecgri(self: *SixelParser, c: u8) void {
        switch (c) {
            '0'...'9' => {
                self.current_param = self.current_param * 10 + (c - '0');
                self.repeat_count = self.current_param;
            },
            '?'...'~' => {
                const count = if (self.repeat_count == 0) 1 else self.repeat_count;
                const pixel_data = c - 63;
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    self.drawSixel(pixel_data);
                    self.cursor_x += 1;
                }
                self.current_param = 0;
                self.repeat_count = 0;
                self.state = .data;
            },
            else => {
                self.current_param = 0;
                self.repeat_count = 0;
                self.state = .data;
                self.processSixelChar(c);
            },
        }
    }

    /// Handle DECGCI - Color Introducer (#<idx>;<type>;<params>...)
    fn processDecgci(self: *SixelParser, c: u8) void {
        switch (c) {
            '0'...'9' => {
                self.current_param = self.current_param * 10 + (c - '0');
            },
            ';' => {
                if (self.param_idx < 5) {
                    self.param_buf[self.param_idx] = self.current_param;
                    self.param_idx += 1;
                }
                self.current_param = 0;
            },
            else => {
                // End of DECGCI sequence
                if (self.param_idx < 5) {
                    self.param_buf[self.param_idx] = self.current_param;
                    self.param_idx += 1;
                }

                if (self.param_idx > 0) {
                    self.color_idx = @intCast(@min(self.param_buf[0], 255));

                    var rgb_color: u32 = self.color_palette[self.color_idx];

                    if (self.param_idx >= 5) {
                        const color_type = if (self.param_buf[1] > 0) self.param_buf[1] else 2;
                        const c1 = self.param_buf[2];
                        const c2 = self.param_buf[3];
                        const c3 = self.param_buf[4];

                        if (color_type == 1) {
                            const hue: u32 = @intCast(c1 % 360);
                            const sat: u32 = @intCast(c2 % 100);
                            const lum: u32 = @intCast(c3 % 100);
                            rgb_color = self.hslToRgb(hue, sat, lum);
                        } else {
                            const r: u32 = @intCast(@as(u32, @min(c1, 100)) * 255 / 100);
                            const g: u32 = @intCast(@as(u32, @min(c2, 100)) * 255 / 100);
                            const b: u32 = @intCast(@as(u32, @min(c3, 100)) * 255 / 100);
                            rgb_color = 0xFF000000 | (r << 16) | (g << 8) | b;
                        }
                        self.color_palette[self.color_idx] = rgb_color;
                    }
                    self.current_color = rgb_color;
                }

                // Reset state for next time
                self.current_param = 0;
                self.param_idx = 0;
                self.param_buf = [_]u32{0} ** 16;

                self.state = .data;
                if (c >= '?' and c <= '~') {
                    self.processSixelChar(c);
                }
            },
        }
    }

    /// Convert HSL to RGB color
    fn hslToRgb(self: *SixelParser, hue: u32, sat: u32, lum: u32) u32 {
        // Sixel uses rotated hue: blue=0°, red=120°, green=240°
        // Convert to standard: red=0°, green=120°, blue=240°
        const h = (hue + 240) % 360;
        const s = @as(f32, @floatFromInt(sat)) / 100.0;
        const l = @as(f32, @floatFromInt(lum)) / 100.0;

        if (s == 0) {
            const v: u32 = @intFromFloat(@round(l * 255.0));
            return 0xFF000000 | (v << 16) | (v << 8) | v;
        }

        const q = if (l < 0.5) l * (1 + s) else l + s - l * s;
        const p = 2 * l - q;
        const h_norm = @as(f32, @floatFromInt(h)) / 360.0;

        const r = self.hueToRgb(p, q, h_norm + 1.0 / 3.0);
        const g = self.hueToRgb(p, q, h_norm);
        const b = self.hueToRgb(p, q, h_norm - 1.0 / 3.0);

        const r_val: u32 = @intFromFloat(@round(r * 255.0));
        const g_val: u32 = @intFromFloat(@round(g * 255.0));
        const b_val: u32 = @intFromFloat(@round(b * 255.0));

        return 0xFF000000 | (r_val << 16) | (g_val << 8) | b_val;
    }

    fn hueToRgb(self: *SixelParser, p: f32, q: f32, t: f32) f32 {
        _ = self;
        var tt = t;
        if (tt < 0) tt += 1;
        if (tt > 1) tt -= 1;
        if (tt < 1.0 / 6.0) return p + (q - p) * 6 * tt;
        if (tt < 1.0 / 2.0) return q;
        if (tt < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - tt) * 6;
        return p;
    }

    fn drawSixel(self: *SixelParser, pixel_data: u8) void {
        // Ensure image buffer is large enough
        // cursor_y is the logical top of the 6-pixel sixel
        // The physical height needed is (cursor_y + 6) * pad
        const required_height = (self.cursor_y + 6);
        if (required_height > self.alloc_height) {
            self.resizeImage(required_height);
        }

        // Ensure width is large enough
        if (self.cursor_x >= self.image_width) {
            std.debug.print("Resizing for cursor_x={d} image_width={d}\n", .{self.cursor_x, self.image_width});
            self.resizeImage(self.alloc_height); // Just realloc with new width implied by cursor_x
        }

        // Draw pixels
        // Bit 0 is bottom pixel, Bit 5 is top pixel
        const color = self.current_color;
        var i: u32 = 0;
        while (i < 6) : (i += 1) {
            if (((pixel_data >> @as(u3, @intCast(i))) & 1) != 0) {
                // Set pixel at (cursor_x, cursor_y + i)
                const y = self.cursor_y + i;
                if (y < self.image_height) {
                    const idx = y * self.image_width + self.cursor_x;
                    if (idx < self.data.len) {
                        self.data[idx] = color;
                    }
                }
            }
        }
    }

    fn resizeImage(self: *SixelParser, new_height: u32) void {
        // Calculate new width based on cursor position
        // If cursor_x is 10, we need at least 11 pixels width
        const new_width = @max(self.image_width, self.cursor_x + 1);

        std.debug.print("resizeImage: {d}x{d} -> {d}x{d}\n", .{self.image_width, self.image_height, new_width, new_height});

        const new_size = new_width * new_height;
        const old_data = self.data;
        const old_width = self.image_width;
        const old_height = self.image_height;

        // Allocate new buffer
        var new_buffer = self.allocator.alloc(u32, new_size) catch {
            // Handle allocation failure
            return;
        };

        // Initialize with transparent (or default background)
        // For Sixel, background is usually transparent or based on P2
        if (self.is_transparent) {
            @memset(new_buffer, 0);
        } else {
            @memset(new_buffer, 0xFF000000); // Opaque Black
        }

        // Copy old data
        if (old_data.len > 0) {
            var y: u32 = 0;
            while (y < old_height) : (y += 1) {
                const old_start = y * old_width;
                const new_start = y * new_width;
                @memcpy(new_buffer[new_start .. new_start + old_width], old_data[old_start .. old_start + old_width]);
            }
            self.allocator.free(old_data);
        }

        self.data = new_buffer;
        self.image_width = new_width;
        self.image_height = new_height;
        self.alloc_height = new_height;

        // Update pointer for drawing
        // self.image.p = &self.data[self.cursor_y * self.image_width + self.cursor_x];
    }

    pub fn createImage(self: *SixelParser, start_x: i32, start_y: i32, cell_width: u32, cell_height: u32) ?SixelImage {
        if (self.image_width == 0 or self.image_height == 0) return null;

        // Trim empty rows from bottom
        var trim_height = self.image_height;
        while (trim_height > 0) {
            const row_start = (trim_height - 1) * self.image_width;
            const row_end = row_start + self.image_width;
            var is_empty = true;
            for (self.data[row_start..row_end]) |pixel| {
                if (pixel != 0) {
                    is_empty = false;
                    break;
                }
            }
            if (!is_empty) break;
            trim_height -= 1;
        }

        if (trim_height == 0) return null;

        // Apply aspect ratio (pan/pad)
        // DEC Sixel aspect ratio: P1 = pan/pad
        // Default is 2:1 (pan=2, pad=1)
        const final_width = self.image_width * self.pad;
        const final_height = trim_height * self.pan;

        std.debug.print("Sixel createImage: {d}x{d} (logical) -> {d}x{d} (physical) pan={d} pad={d}\n", .{
            self.image_width, trim_height, final_width, final_height, self.pan, self.pad,
        });

        // Check resource limits (after trimming and scaling)
        if (!self.checkLimits(final_width, final_height)) {
            std.debug.print("Sixel: image exceeds size limits ({d}x{d})\n", .{ final_width, final_height });
            return null;
        }

        // Allocate final image buffer
        const dupe_len = final_width * final_height;
        const image_data = self.allocator.alloc(u32, dupe_len) catch |err| {
            std.debug.print("Sixel: failed to allocate image: {}\n", .{err});
            return null;
        };

        // Scale data using pan/pad
        for (0..final_height) |y| {
            const src_y = y / self.pan;
            const src_row_start = src_y * self.image_width;
            const dst_row_start = y * final_width;
            for (0..final_width) |x| {
                const src_x = x / self.pad;
                image_data[dst_row_start + x] = self.data[src_row_start + src_x];
            }
        }

        // Calculate image dimensions in cells
        const cols = (final_width + cell_width - 1) / cell_width;
        const rows = (final_height + cell_height - 1) / cell_height;

        // Track memory usage
        const image_bytes = @as(u64, dupe_len) * 4;
        self.memory.add(image_bytes);

        const image = SixelImage{
            .x = start_x,
            .y = start_y,
            .width = final_width,
            .height = final_height,
            .data = image_data,
            .allocator = self.allocator,
            .cols = cols,
            .rows = rows,
            .cell_width = cell_width,
            .cell_height = cell_height,
        };

        return image;
    }

    /// Get memory tracking info.
    pub fn getMemory(self: *SixelParser) SixelMemory {
        return self.memory;
    }

    /// Reset all state including memory tracking (for terminal reset).
    pub fn resetAll(self: *SixelParser) void {
        self.reset();
        self.memory.reset();
    }
};

test "SixelParser init" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    try std.testing.expectEqual(@as(u32, 0), parser.image_width);
    try std.testing.expectEqual(@as(u32, 0), parser.image_height);
    try std.testing.expectEqual(@as(u32, 2), parser.pan);
    try std.testing.expectEqual(@as(u32, 1), parser.pad);
    try std.testing.expectEqual(@as(u8, 0), parser.current_color_idx);
}

test "SixelParser reset palette" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.color_palette[0] = 0xFF000000;
    parser.color_palette[1] = 0xFF0000FF;
    parser.color_palette[2] = 0xFF00FF00;

    parser.resetPalette();

    try std.testing.expectEqual(@as(u32, 0xFF000000), parser.color_palette[0]);
    try std.testing.expectEqual(@as(u32, 0xFF800000), parser.color_palette[1]);
    try std.testing.expectEqual(@as(u32, 0xFF008000), parser.color_palette[2]);
    try std.testing.expectEqual(@as(u32, 0xFFC0C0C0), parser.color_palette[7]);
}

test "SixelParser aspect ratio from params" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .params;
    _ = parser.put('0');
    _ = parser.put(';');
    _ = parser.put('1');
    _ = parser.put('~');

    try std.testing.expectEqual(@as(u32, 2), parser.pan);
}

test "SixelParser aspect ratio 5:1" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .params;
    _ = parser.put('2');
    _ = parser.put(';');
    _ = parser.put('~');

    try std.testing.expectEqual(@as(u32, 5), parser.pan);
}

test "SixelParser aspect ratio 3:1" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .params;
    _ = parser.put('3');
    _ = parser.put(';');
    _ = parser.put('~');

    try std.testing.expectEqual(@as(u32, 3), parser.pan);
}

test "SixelParser aspect ratio 1:1" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .params;
    _ = parser.put('7');
    _ = parser.put(';');
    _ = parser.put('~');

    try std.testing.expectEqual(@as(u32, 1), parser.pan);
}

test "SixelParser simple pixel data" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .data;
    _ = parser.put('~');

    try std.testing.expect(parser.image_width > 0);
    try std.testing.expect(parser.image_height >= 6);
}

test "SixelParser color index set" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .data;
    _ = parser.put('#');
    parser.state = .decgci;
    _ = parser.put('2');
    _ = parser.put(';');
    _ = parser.put('2');
    _ = parser.put(';');
    _ = parser.put('1');
    _ = parser.put('0');
    _ = parser.put('0');
    _ = parser.put(';');
    _ = parser.put('0');
    _ = parser.put(';');
    _ = parser.put('0');
    _ = parser.put('~');

    try std.testing.expectEqual(@as(u8, 2), parser.color_idx);
}

test "SixelParser RGB color" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .data;
    _ = parser.put('#');
    parser.state = .decgci;
    parser.param_buf[0] = 3;
    parser.param_idx = 1;
    parser.param_buf[1] = 2;
    parser.param_buf[2] = 100;
    parser.param_buf[3] = 50;
    parser.param_buf[4] = 25;
    parser.param_idx = 5;
    parser.color_idx = 3;
    parser.processSixelChar('~');

    const palette_color = parser.color_palette[3];
    try std.testing.expect(palette_color != 0);
    try std.testing.expectEqual(@as(u32, 0xFF000000), palette_color & 0xFF000000);
}

test "SixelParser HSL color" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .data;
    _ = parser.put('#');
    parser.state = .decgci;
    parser.param_buf[0] = 4;
    parser.param_idx = 1;
    parser.param_buf[1] = 1;
    parser.param_buf[2] = 120;
    parser.param_buf[3] = 100;
    parser.param_buf[4] = 50;
    parser.param_idx = 5;
    parser.color_idx = 4;
    parser.processSixelChar('~');

    const palette_color = parser.color_palette[4];
    try std.testing.expect(palette_color != 0);
}

test "SixelParser repeat count" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .data;
    _ = parser.put('!');
    parser.state = .decgri;
    _ = parser.put('3');
    _ = parser.put('~');

    try std.testing.expect(parser.image_width >= 3);
}

test "SixelParser DECGRA raster attributes" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .data;
    _ = parser.put('"');
    parser.state = .decgra;
    _ = parser.put('2');
    _ = parser.put(';');
    _ = parser.put('2');
    _ = parser.put(';');
    _ = parser.put('1');
    _ = parser.put('0');
    _ = parser.put(';');
    _ = parser.put('2');
    _ = parser.put('0');
    _ = parser.put('~');

    try std.testing.expectEqual(@as(u32, 2), parser.pan);
    try std.testing.expectEqual(@as(u32, 2), parser.pad);
}

test "SixelParser DECGRA with zero values" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .data;
    _ = parser.put('"');
    parser.state = .decgra;
    _ = parser.put('0');
    _ = parser.put(';');
    _ = parser.put('0');
    _ = parser.put(';');
    _ = parser.put('5');
    _ = parser.put(';');
    _ = parser.put('5');
    _ = parser.put('~');

    try std.testing.expectEqual(@as(u32, 1), parser.pan);
    try std.testing.expectEqual(@as(u32, 1), parser.pad);
}

test "SixelParser carriage return and newline" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .data;
    _ = parser.put('~');
    const x_after_first = parser.cursor_x;
    try std.testing.expect(x_after_first > 0);

    _ = parser.put('$');
    try std.testing.expectEqual(@as(u32, 0), parser.cursor_x);

    _ = parser.put('-');
    try std.testing.expect(parser.cursor_y > 0);
}

test "SixelParser memory tracking" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    try std.testing.expectEqual(@as(u64, 0), parser.memory.total_bytes);
    try std.testing.expectEqual(@as(u32, 0), parser.memory.image_count);

    parser.state = .data;
    _ = parser.put('~');
    _ = parser.put('~');
    _ = parser.put('~');
    var img = parser.createImage(0, 0, 16, 16);
    if (img) |*image| {
        defer image.deinit();
        const mem = parser.getMemory();
        try std.testing.expect(mem.total_bytes > 0);
        try std.testing.expect(mem.image_count > 0);
    }
}

test "SixelParser limits check" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    const config = SixelConfig{ .max_width = 100, .max_height = 100 };
    parser.setConfig(config);

    try std.testing.expect(parser.checkLimits(50, 50));
    try std.testing.expect(!parser.checkLimits(150, 50));
    try std.testing.expect(!parser.checkLimits(50, 150));
}

test "SixelParser createImage" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .data;
    _ = parser.put('~');

    var image = parser.createImage(0, 0, 16, 16);
    try std.testing.expect(image != null);
    if (image) |*img| {
        defer img.deinit();
        try std.testing.expect(img.width > 0);
        try std.testing.expect(img.height > 0);
        try std.testing.expectEqual(@as(i32, 0), img.x);
        try std.testing.expectEqual(@as(i32, 0), img.y);
    }
}

test "SixelParser private palette mode" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.setPrivatePalette(true);
    try std.testing.expect(parser.use_private_palette);

    parser.setPrivatePalette(false);
    try std.testing.expect(!parser.use_private_palette);
}

test "SixelParser full sequence parse" {
    const a = std.testing.allocator;
    var parser = SixelParser.init(a);
    defer parser.deinit();

    parser.state = .params;
    _ = parser.put('1');
    _ = parser.put(';');
    _ = parser.put('0');
    _ = parser.put(';');
    _ = parser.put('#');
    parser.state = .decgci;
    _ = parser.put('1');
    _ = parser.put(';');
    _ = parser.put('2');
    _ = parser.put(';');
    _ = parser.put('1');
    _ = parser.put('0');
    _ = parser.put('0');
    _ = parser.put(';');
    _ = parser.put('0');
    _ = parser.put(';');
    _ = parser.put('0');
    _ = parser.put('~');
    _ = parser.put('-');
    _ = parser.put('~');
    _ = parser.put('~');
    _ = parser.put('~');
    _ = parser.put('~');
    _ = parser.put('~');
    const done = parser.put('\\');

    try std.testing.expect(done);
    try std.testing.expect(parser.image_width > 0);
    try std.testing.expect(parser.image_height > 0);
}

test "SixelMemory tracking" {
    var mem = SixelMemory{};

    try std.testing.expectEqual(@as(u64, 0), mem.total_bytes);
    try std.testing.expectEqual(@as(u32, 0), mem.image_count);

    mem.add(1000);
    try std.testing.expectEqual(@as(u64, 1000), mem.total_bytes);
    try std.testing.expectEqual(@as(u32, 1), mem.image_count);

    mem.add(500);
    try std.testing.expectEqual(@as(u64, 1500), mem.total_bytes);
    try std.testing.expectEqual(@as(u32, 2), mem.image_count);

    mem.remove(500);
    try std.testing.expectEqual(@as(u64, 1000), mem.total_bytes);
    try std.testing.expectEqual(@as(u32, 1), mem.image_count);

    mem.remove(2000);
    try std.testing.expectEqual(@as(u64, 0), mem.total_bytes);
    try std.testing.expectEqual(@as(u32, 0), mem.image_count);

    mem.reset();
    try std.testing.expectEqual(@as(u64, 0), mem.total_bytes);
    try std.testing.expectEqual(@as(u32, 0), mem.image_count);
}

test "SixelImage getMemorySize" {
    const a = std.testing.allocator;
    const data = try a.alloc(u32, 100);
    defer a.free(data);

    const image = SixelImage{
        .x = 0,
        .y = 0,
        .width = 10,
        .height = 10,
        .data = data,
        .allocator = a,
    };

    const size = image.getMemorySize();
    try std.testing.expectEqual(@as(u64, 400), size);
}
