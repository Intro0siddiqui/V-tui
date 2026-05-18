/// Vtui ANSI Parser Module
/// Zero-allocation state machine for ANSI escape sequences.
/// Supports: SGR colors, cursor movement, clear commands.
const std = @import("std");
const Grid = @import("grid.zig").Grid;
const CellFlags = @import("grid.zig").CellFlags;
const SixelParser = @import("sixel.zig").SixelParser;
const SixelImage = @import("sixel.zig").SixelImage;

/// Parser state machine states.
pub const State = enum {
    /// Normal text output.
    normal,
    /// Saw ESC, waiting for next char.
    escape,
    /// Saw ESC [, parsing CSI sequence.
    csi,
    /// Parsing numeric parameters.
    param,
    /// Saw ESC ], parsing OSC sequence.
    osc,
    /// Parsing OSC string parameter.
    osc_param,
    /// Waiting for final '\' to complete ST terminator (ESC\)
    osc_st,
    /// Saw ESC P, waiting for DCS final byte.
    dcs,
    /// Parsing Sixel data (after DCS final byte 'q').
    dcs_sixel,
    /// Waiting for final '\' to complete ST terminator for DCS (ESC\)
    dcs_st,
};

/// ANSI Parser - stack-based, zero heap allocation.
pub const Parser = struct {
    state: State = .normal,
    params: [16]u32 = [_]u32{0} ** 16,
    param_count: usize = 0,
    is_secondary: bool = false,

    // OSC state
    osc_num: u32 = 0,
    osc_buffer: [256]u8 = [_]u8{0} ** 256,
    osc_len: usize = 0,

    // UTF-8 state
    utf8_buffer: [4]u8 = [_]u8{0} ** 4,
    utf8_len: u8 = 0,
    utf8_expected: u8 = 0,

    /// Current SGR attributes.
    current_fg: u32 = 0,
    current_bg: u32 = 0,
    current_flags: CellFlags = .{},

    /// Window title and icon title (from OSC 0/1/2).
    window_title_buf: [256]u8 = undefined,
    window_title_len: usize = 0,
    icon_title_buf: [256]u8 = undefined,
    icon_title_len: usize = 0,
    title_changed: bool = false,

    /// Color palette for OSC 4
    color_palette: [256]u32 = [_]u32{0} ** 256,

    /// Current working directory (from OSC 7)
    cwd_buf: [256]u8 = undefined,
    cwd_len: usize = 0,
    cwd_changed: bool = false,

    /// Hyperlink state (from OSC 8)
    hyperlink_uri_buf: [256]u8 = undefined,
    hyperlink_uri_len: usize = 0,
    hyperlink_id_buf: [256]u8 = undefined,
    hyperlink_id_len: usize = 0,
    hyperlink_active: bool = false,
    hyperlink_changed: bool = false,

    /// Clipboard state (from OSC 52)
    clipboard_kind: u8 = 0, // 0 = primary, 1 = clipboard, etc.
    clipboard_data_buf: [1024]u8 = undefined, // Base64 decoded data (1024 bytes max)
    clipboard_data_len: usize = 0,
    clipboard_request: bool = false, // True if this is a paste request (OSC 52 ; <kind> ; ? ST)
    clipboard_changed: bool = false,

    // Sixel state
    allocator: std.mem.Allocator,
    sixel_parser: ?SixelParser = null,

    // Writer for responding to queries
    writer_cb: ?*const fn (ctx: *anyopaque, data: []const u8) void = null,
    writer_ctx: ?*anyopaque = null,

    /// Initialize parser with allocator.
    pub fn init(allocator: std.mem.Allocator) Parser {
        return Parser{
            .allocator = allocator,
            // Other fields use default values
        };
    }

    pub fn setWriter(self: *Parser, ctx: *anyopaque, cb: *const fn (ctx: *anyopaque, data: []const u8) void) void {
        self.writer_cb = cb;
        self.writer_ctx = ctx;
    }

    fn writeBack(self: *Parser, data: []const u8) void {
        if (self.writer_cb) |cb| {
            cb(self.writer_ctx.?, data);
        }
    }

    /// Reset parser state (but keep current SGR attributes).
    pub fn reset(self: *Parser) void {
        self.state = .normal;
        self.params = [_]u32{0} ** 16;
        self.param_count = 0;
        self.is_secondary = false;
        self.osc_num = 0;
        self.osc_len = 0;
        // Don't reset title_changed here - it's a sticky flag
        if (self.sixel_parser) |*sp| {
            sp.reset();
        }
    }

    /// Parse a chunk of bytes and update grid state.
    pub fn parse(self: *Parser, data: []const u8, grid: *Grid) void {
        for (data) |b| {
            self.processByte(b, grid);
        }
    }

    fn processByte(self: *Parser, b: u8, grid: *Grid) void {
        // UTF-8 Handling
        if (self.utf8_expected > 0) {
            self.utf8_buffer[self.utf8_len] = b;
            self.utf8_len += 1;
            if (self.utf8_len == self.utf8_expected) {
                // Decode UTF-8
                const cp = self.decodeUtf8() catch ' ';
                grid.writeChar(cp, self.current_fg, self.current_bg, self.current_flags);
                self.utf8_expected = 0;
                self.utf8_len = 0;
            }
            return;
        }

        if (b & 0x80 != 0) {
            // Start of UTF-8 sequence
            if (b & 0xE0 == 0xC0) {
                self.utf8_expected = 2;
            } else if (b & 0xF0 == 0xE0) {
                self.utf8_expected = 3;
            } else if (b & 0xF8 == 0xF0) {
                self.utf8_expected = 4;
            }
            self.utf8_buffer[0] = b;
            self.utf8_len = 1;
            return;
        }

        switch (self.state) {
            .normal => self.handleNormal(b, grid),
            .escape => self.handleEscape(b, grid),
            .csi => self.handleCsi(b, grid),
            .param => self.handleParam(b, grid),
            .osc => self.handleOsc(b, grid),
            .osc_param => self.handleOscParam(b, grid),
            .osc_st => self.handleOscSt(b, grid),
            .dcs => self.handleDcs(b, grid),
            .dcs_sixel => self.handleDcsSixel(b, grid),
            .dcs_st => self.handleDcsSt(b, grid),
        }
    }

    fn decodeUtf8(self: *Parser) !u21 {
        const buf = self.utf8_buffer[0..self.utf8_len];
        return std.unicode.utf8Decode(buf);
    }

    fn handleNormal(self: *Parser, b: u8, grid: *Grid) void {
        switch (b) {
            0x1B => self.state = .escape,
            '\n' => {
                grid.cursor.x = 0;
                if (grid.cursor.y < grid.height - 1) {
                    grid.cursor.y += 1;
                } else {
                    grid.scrollUp(1);
                }
            },
            '\r' => grid.cursor.x = 0,
            '\t' => {
                const next_tab = (grid.cursor.x / 8 + 1) * 8;
                grid.cursor.x = @min(next_tab, grid.width - 1);
            },
            0x08 => { // Backspace
                if (grid.cursor.x > 0) grid.cursor.x -= 1;
            },
            else => {
                if (b >= 0x20) {
                    grid.writeChar(b, self.current_fg, self.current_bg, self.current_flags);
                }
            },
        }
    }

    fn handleEscape(self: *Parser, b: u8, grid: *Grid) void {
        switch (b) {
            '[' => {
                self.state = .csi;
                self.params = [_]u32{0} ** 16;
                self.param_count = 0;
            },
            ']' => {
                self.state = .osc;
                self.osc_num = 0;
                self.osc_len = 0;
            },
            'P' => {
                // DCS - Device Control String
                self.state = .dcs;
            },
            '(' | ')' => {
                // Ignore charset sequences for now
                self.state = .normal;
            },
            'c' => { // Reset terminal
                grid.clear();
                self.current_fg = 0;
                self.current_bg = 0;
                self.current_flags = .{};
                self.reset();
            },
            else => self.state = .normal,
        }
    }

    fn handleCsi(self: *Parser, b: u8, grid: *Grid) void {
        if (b >= '0' and b <= '9') {
            self.state = .param;
            self.params[self.param_count] = (b - '0');
        } else if (b == ';') {
            if (self.param_count < self.params.len - 1) {
                self.param_count += 1;
                self.params[self.param_count] = 0;
            }
        } else if (b >= 0x40 and b <= 0x7e) {
            // Final byte - execute command
            self.executeCsi(b, grid);
            self.reset();
        } else if (b == '?' or b == '>') {
            if (b == '>') self.is_secondary = true;
        } else {
            // Invalid, reset
            self.reset();
        }
    }

    fn handleParam(self: *Parser, b: u8, grid: *Grid) void {
        if (b >= '0' and b <= '9') {
            if (self.param_count < self.params.len) {
                const val = self.params[self.param_count];
                // Prevent overflow
                if (val < 100000) {
                    self.params[self.param_count] = val * 10 + (b - '0');
                }
            }
        } else if (b == ';') {
            if (self.param_count < self.params.len - 1) {
                self.param_count += 1;
                self.params[self.param_count] = 0;
            }
        } else if (b >= 0x40 and b <= 0x7e) {
            // Final byte
            self.executeCsi(b, grid);
            self.reset();
        } else if (b == ':') {
            // Ignore sub-parameters
        } else {
            self.reset();
        }
    }

    fn handleOsc(self: *Parser, b: u8, grid: *Grid) void {
        _ = grid;
        if (b >= '0' and b <= '9') {
            const val = self.osc_num;
            if (val < 100000) {
                self.osc_num = val * 10 + (b - '0');
            }
        } else if (b == ';') {
            self.state = .osc_param;
        } else if (b == 0x07) {
            self.reset();
        } else {
            self.reset();
        }
    }

    fn handleOscParam(self: *Parser, b: u8, grid: *Grid) void {
        _ = grid;
        if (b == 0x07) { // BEL terminator
            self.executeOsc();
            self.reset();
        } else if (b == 0x1B) { // Start of ST (ESC\) sequence
            // Wait for the final '\'
            self.state = .osc_st;
        } else if (self.osc_len < self.osc_buffer.len) {
            self.osc_buffer[self.osc_len] = b;
            self.osc_len += 1;
        }
    }

    fn handleOscSt(self: *Parser, b: u8, grid: *Grid) void {
        _ = grid;
        if (b == '\\') { // ST terminator complete (ESC\)
            self.executeOsc();
        }
        self.reset();
    }

    fn handleDcs(self: *Parser, b: u8, grid: *Grid) void {
        _ = grid;
        switch (b) {
            'q' => { // Sixel
                if (self.sixel_parser == null) {
                    self.sixel_parser = SixelParser.init(self.allocator);
                }
                self.sixel_parser.?.reset();
                // Feed 'q' to the parser to start the sequence
                _ = self.sixel_parser.?.put('q');
                self.state = .dcs_sixel;
            },
            else => {
                // Unknown DCS final byte, ignore until ST
                self.state = .dcs_sixel; // Just consume data until ST
            },
        }
    }

    fn handleDcsSixel(self: *Parser, b: u8, grid: *Grid) void {
        if (b == 0x1B) { // ESC
            self.state = .dcs_st;
            return;
        }
        if (self.sixel_parser) |*sp| {
            if (sp.put(b)) {
                // Image complete (ST found)
                self.finalizeSixel(grid);
                self.reset();
            }
        }
    }

    fn handleDcsSt(self: *Parser, b: u8, grid: *Grid) void {
        if (b == '\\') { // ST terminator complete (ESC\)
            if (self.sixel_parser) |*sp| {
                // Check if parser was actually active
                // (e.g. if we were ignoring unknown DCS)
                if (sp.data.len > 0 or sp.cursor_x > 0) {
                    self.finalizeSixel(grid);
                }
            }
        }
        self.reset();
    }

    fn finalizeSixel(self: *Parser, grid: *Grid) void {
        if (self.sixel_parser) |*sp| {
            const dims = grid.getCellDimensions();
            if (sp.createImage(@intCast(grid.cursor.x), @intCast(grid.cursor.y), dims.width, dims.height)) |image| {
                // Store image position before adding to grid
                const img_x = image.x;
                const img_cols = image.cols;
                _ = image.rows; // Reserved for future use

                grid.addImage(image) catch {
                    // Handle allocation error
                };

                // Advance cursor after image (standard terminal behavior)
                // Move cursor to the right of the image
                const new_x = img_x + @as(i32, @intCast(img_cols));
                const new_y = image.y;

                // Handle wrapping: if cursor goes past right edge, move to next line
                if (new_x >= @as(i32, @intCast(grid.width))) {
                    // Move to start of next line
                    grid.cursor.x = 0;
                    // Only advance row if the image didn't already trigger a line wrap
                    if (new_y < @as(i32, @intCast(grid.height - 1))) {
                        grid.cursor.y = @intCast(new_y + 1);
                    } else {
                        grid.cursor.y = grid.height - 1;
                    }
                } else {
                    grid.cursor.x = @intCast(new_x);
                    grid.cursor.y = @intCast(new_y);
                }

                // Ensure cursor is within bounds
                if (grid.cursor.x >= grid.width) {
                    grid.cursor.x = grid.width - 1;
                }
                if (grid.cursor.y >= grid.height) {
                    grid.cursor.y = grid.height - 1;
                }
            }
        }
    }

    fn executeOsc(self: *Parser) void {
        const data = self.osc_buffer[0..self.osc_len];
        switch (self.osc_num) {
            0 => { // Set window title and icon title (both to same value)
                const len = @min(data.len, self.window_title_buf.len - 1);
                @memcpy(self.window_title_buf[0..len], data[0..len]);
                self.window_title_buf[len] = 0; // Null-terminate
                self.window_title_len = len;

                const icon_len = @min(data.len, self.icon_title_buf.len - 1);
                @memcpy(self.icon_title_buf[0..icon_len], data[0..icon_len]);
                self.icon_title_buf[icon_len] = 0; // Null-terminate
                self.icon_title_len = icon_len;

                self.title_changed = true;
            },
            1 => { // Set icon title
                const len = @min(data.len, self.icon_title_buf.len - 1);
                @memcpy(self.icon_title_buf[0..len], data[0..len]);
                self.icon_title_buf[len] = 0; // Null-terminate
                self.icon_title_len = len;
                self.title_changed = true;
            },
            2 => { // Set window title
                const len = @min(data.len, self.window_title_buf.len - 1);
                @memcpy(self.window_title_buf[0..len], data[0..len]);
                self.window_title_buf[len] = 0; // Null-terminate
                self.window_title_len = len;
                self.title_changed = true;
            },
            4 => { // Change Color Palette
                // Format: index;rgb or index;#rgb
                // Supports multiple pairs: idx;color;idx;color...
                var it = std.mem.splitScalar(u8, data, ';');
                while (it.next()) |idx_str| {
                    if (it.next()) |color_str| {
                        const idx = std.fmt.parseInt(u8, idx_str, 10) catch 0;
                        var color: u32 = 0;
                        // Parse color string: "rgb:RR/GG/BB" or "#RRGGBB" or just "RR/GG/BB"
                        if (std.mem.startsWith(u8, color_str, "rgb:")) {
                            // rgb:RR/GG/BB
                            var rgb_it = std.mem.splitScalar(u8, color_str[4..], '/');
                            if (rgb_it.next()) |r_str| {
                                if (rgb_it.next()) |g_str| {
                                    if (rgb_it.next()) |b_str| {
                                        const r = std.fmt.parseInt(u8, r_str, 16) catch 0;
                                        const g = std.fmt.parseInt(u8, g_str, 16) catch 0;
                                        const b = std.fmt.parseInt(u8, b_str, 16) catch 0;
                                        color = (@as(u32, r) << 16) | (@as(u32, g) << 8) | b;
                                    }
                                }
                            }
                        } else if (std.mem.startsWith(u8, color_str, "#")) {
                            // #RRGGBB
                            if (color_str.len == 7) {
                                const r = std.fmt.parseInt(u8, color_str[1..3], 16) catch 0;
                                const g = std.fmt.parseInt(u8, color_str[3..5], 16) catch 0;
                                const b = std.fmt.parseInt(u8, color_str[5..7], 16) catch 0;
                                color = (@as(u32, r) << 16) | (@as(u32, g) << 8) | b;
                            }
                        }
                        if (idx < 256) {
                            self.color_palette[idx] = color;
                        }
                    }
                }
            },
            7 => { // Report Current Working Directory (OSC 7)
                // Format: file://<host><path>
                const uri = data;
                // Find path part - starts after "file://" prefix
                if (std.mem.startsWith(u8, uri, "file://")) {
                    const host_path = uri[7..];
                    // Find start of path (after host)
                    const path_start = if (std.mem.indexOfScalar(u8, host_path, '/')) |idx| idx else 0;
                    const path = host_path[path_start..];

                    const len = @min(path.len, self.cwd_buf.len - 1);
                    @memcpy(self.cwd_buf[0..len], path[0..len]);
                    self.cwd_buf[len] = 0; // Null-terminate
                    self.cwd_len = len;
                    self.cwd_changed = true;
                }
            },
            8 => { // Hyperlinks (OSC 8 ; params ; uri)
                // Format: id=<id> ; <uri> ST (start) or ;; ST (end)
                // Split on ';' to extract parameters
                var it = std.mem.splitScalar(u8, data, ';');

                // Get first parameter (id)
                var id: []const u8 = "";
                if (it.next()) |param| {
                    const trimmed = std.mem.trim(u8, param, " \t");
                    // Check if it's id=<id> format
                    if (std.mem.startsWith(u8, trimmed, "id=")) {
                        id = trimmed[3..]; // Skip "id=" prefix
                    } else if (trimmed.len > 0) {
                        id = trimmed; // Just use as-is if no id= prefix
                    }
                }

                // Get second parameter (uri)
                var uri: []const u8 = "";
                if (it.next()) |param| {
                    uri = std.mem.trim(u8, param, " \t");
                }

                if (uri.len > 0) {
                    // Start hyperlink
                    const uri_len = @min(uri.len, self.hyperlink_uri_buf.len - 1);
                    @memcpy(self.hyperlink_uri_buf[0..uri_len], uri[0..uri_len]);
                    self.hyperlink_uri_buf[uri_len] = 0; // Null-terminate
                    self.hyperlink_uri_len = uri_len;

                    const id_len = @min(id.len, self.hyperlink_id_buf.len - 1);
                    @memcpy(self.hyperlink_id_buf[0..id_len], id[0..id_len]);
                    self.hyperlink_id_buf[id_len] = 0; // Null-terminate
                    self.hyperlink_id_len = id_len;

                    self.hyperlink_active = true;
                    self.hyperlink_changed = true;
                } else {
                    // End hyperlink
                    self.hyperlink_active = false;
                    self.hyperlink_changed = true;
                    self.hyperlink_uri_len = 0;
                    self.hyperlink_id_len = 0;
                }
            },
            52 => { // Clipboard (OSC 52 ; <kind> ; <data> ST or OSC 52 ; <kind> ; ? ST)
                // Split on ';' to extract parameters
                var it = std.mem.splitScalar(u8, data, ';');

                // Get clipboard kind (first parameter)
                var kind: u8 = 0;
                if (it.next()) |kind_str| {
                    const trimmed = std.mem.trim(u8, kind_str, " \t");
                    if (trimmed.len > 0) {
                        kind = std.fmt.parseInt(u8, trimmed, 10) catch 0;
                    }
                }

                // Get clipboard data (second parameter)
                if (it.next()) |data_param| {
                    const trimmed = std.mem.trim(u8, data_param, " \t");

                    if (trimmed.len == 1 and trimmed[0] == '?') {
                        // Paste request
                        self.clipboard_kind = kind;
                        self.clipboard_request = true;
                        self.clipboard_changed = true;
                        self.clipboard_data_len = 0;
                    } else if (trimmed.len > 0) {
                        // Copy command - base64 encoded data
                        // Copy command - base64 encoded data
                        const decoded_len = blk: {
                            const decoder = std.base64.standard.Decoder;
                            const max_len = decoder.calcSizeUpperBound(trimmed.len) catch break :blk 0;
                            if (max_len > self.clipboard_data_buf.len) break :blk 0;

                            decoder.decode(self.clipboard_data_buf[0..max_len], trimmed) catch break :blk 0;
                            break :blk decoder.calcSizeForSlice(trimmed) catch max_len;
                        };

                        self.clipboard_kind = kind;
                        self.clipboard_data_len = decoded_len;
                        self.clipboard_request = false;
                        self.clipboard_changed = true;
                    }
                }
            },
            else => {},
        }
    }

    /// Get the current window title.
    pub fn getWindowTitle(self: *Parser) []const u8 {
        return self.window_title_buf[0..self.window_title_len];
    }

    /// Get the current icon title.
    pub fn getIconTitle(self: *Parser) []const u8 {
        return self.icon_title_buf[0..self.icon_title_len];
    }

    /// Check if the title has changed since last call to resetTitleChanged().
    pub fn hasTitleChanged(self: *Parser) bool {
        return self.title_changed;
    }

    /// Reset the title changed flag.
    pub fn resetTitleChanged(self: *Parser) void {
        self.title_changed = false;
    }

    /// Get the current working directory.
    pub fn getCwd(self: *Parser) []const u8 {
        return self.cwd_buf[0..self.cwd_len];
    }

    /// Check if the current working directory has changed since last call to resetCwdChanged().
    pub fn hasCwdChanged(self: *Parser) bool {
        return self.cwd_changed;
    }

    /// Reset the CWD changed flag.
    pub fn resetCwdChanged(self: *Parser) void {
        self.cwd_changed = false;
    }

    /// Get the current hyperlink URI.
    pub fn getHyperlinkUri(self: *Parser) []const u8 {
        return self.hyperlink_uri_buf[0..self.hyperlink_uri_len];
    }

    /// Get the current hyperlink ID.
    pub fn getHyperlinkId(self: *Parser) []const u8 {
        return self.hyperlink_id_buf[0..self.hyperlink_id_len];
    }

    /// Check if a hyperlink is currently active.
    pub fn isHyperlinkActive(self: *Parser) bool {
        return self.hyperlink_active;
    }

    /// Check if the hyperlink state has changed since last call to resetHyperlinkChanged().
    pub fn hasHyperlinkChanged(self: *Parser) bool {
        return self.hyperlink_changed;
    }

    /// Reset the hyperlink changed flag.
    pub fn resetHyperlinkChanged(self: *Parser) void {
        self.hyperlink_changed = false;
    }

    /// Get the clipboard kind (0 = primary, 1 = clipboard, etc.)
    pub fn getClipboardKind(self: *Parser) u8 {
        return self.clipboard_kind;
    }

    /// Get the clipboard data (decoded base64).
    pub fn getClipboardData(self: *Parser) []const u8 {
        return self.clipboard_data_buf[0..self.clipboard_data_len];
    }

    /// Check if this is a clipboard paste request.
    pub fn isClipboardRequest(self: *Parser) bool {
        return self.clipboard_request;
    }

    /// Check if the clipboard state has changed since last call to resetClipboardChanged().
    pub fn hasClipboardChanged(self: *Parser) bool {
        return self.clipboard_changed;
    }

    /// Reset the clipboard changed flag.
    pub fn resetClipboardChanged(self: *Parser) void {
        self.clipboard_changed = false;
    }

    fn executeCsi(self: *Parser, final: u8, grid: *Grid) void {
        const count = if (self.param_count == 0 and self.params[0] == 0) @as(usize, 0) else self.param_count + 1;
        const params = self.params[0..count];

        std.debug.print("CSI: final={c} params=", .{final});
        for (params) |p| std.debug.print("{d} ", .{p});
        std.debug.print("\n", .{});

        switch (final) {
            'm' => self.executeSGR(params, grid),
            'H', 'f' => self.executeCursorPosition(params, grid),
            'A' => self.executeCursorUp(params, grid),
            'B' => self.executeCursorDown(params, grid),
            'C' => self.executeCursorForward(params, grid),
            'D' => self.executeCursorBack(params, grid),
            'G' => self.executeCursorHorizontalAbsolute(params, grid),
            'J' => self.executeEraseDisplay(params, grid),
            'K' => self.executeEraseLine(params, grid),
            'c' => {
                if (self.is_secondary) {
                    // Secondary Device Attributes
                    // Report Vtui version (e.g. 1.0.0)
                    // Format: ESC [ > <id> ; <version> ; <rom_cartridge> c
                    self.writeBack("\x1b[>0;100;0c");
                } else {
                    // Primary Device Attributes (DA)
                    // We report Sixel support (4).
                    // Format: ESC [ ? 62 ; 4 c
                    self.writeBack("\x1b[?62;4c");
                }
            },
            else => {},
        }
    }

    fn executeSGR(self: *Parser, params: []const u32, grid: *Grid) void {
        _ = grid;
        if (params.len == 0 or (params.len == 1 and params[0] == 0)) {
            self.current_fg = 0;
            self.current_bg = 0;
            self.current_flags = .{};
            return;
        }

        var i: usize = 0;
        while (i < params.len) : (i += 1) {
            const code = params[i];
            switch (code) {
                0 => {
                    self.current_fg = 0;
                    self.current_bg = 0;
                    self.current_flags = .{};
                },
                1 => self.current_flags.bold = true,
                4 => self.current_flags.underline = true,
                7 => self.current_flags.reverse = true,
                30...37 => self.current_fg = self.color256(code - 30),
                38 => {
                    if (i + 2 < params.len and params[i + 1] == 5) {
                        self.current_fg = self.color256(params[i + 2]);
                        i += 2;
                    } else if (i + 4 < params.len and params[i + 1] == 2) {
                        self.current_fg = self.truecolor(@intCast(params[i + 2]), @intCast(params[i + 3]), @intCast(params[i + 4]));
                        i += 4;
                    }
                },
                39 => self.current_fg = 0, // Default FG
                40...47 => self.current_bg = self.color256(code - 40),
                48 => {
                    if (i + 2 < params.len and params[i + 1] == 5) {
                        self.current_bg = self.color256(params[i + 2]);
                        i += 2;
                    } else if (i + 4 < params.len and params[i + 1] == 2) {
                        self.current_bg = self.truecolor(@intCast(params[i + 2]), @intCast(params[i + 3]), @intCast(params[i + 4]));
                        i += 4;
                    }
                },
                49 => self.current_bg = 0, // Default BG
                90...97 => self.current_fg = self.color256(code - 90 + 8),
                100...107 => self.current_bg = self.color256(code - 100 + 8),
                else => {},
            }
        }
    }

    fn color256(self: *Parser, index: u32) u32 {
        _ = self;
        if (index < 16) {
            const table = [_]u32{
                0x000000, 0x800000, 0x008000, 0x808000,
                0x000080, 0x800080, 0x008080, 0xc0c0c0,
                0x808080, 0xff0000, 0x00ff00, 0xffff00,
                0x0000ff, 0xff00ff, 0x00ffff, 0xffffff,
            };
            return table[index];
        } else if (index < 232) {
            var i = index - 16;
            const b = i % 6;
            i /= 6;
            const g = i % 6;
            i /= 6;
            const r = i % 6;
            return (r * 51 << 16) | (g * 51 << 8) | (b * 51);
        } else if (index < 256) {
            const level = (index - 232) * 10 + 8;
            return (level << 16) | (level << 8) | level;
        }
        return 0;
    }

    fn truecolor(self: *Parser, r: u16, g: u16, b: u16) u32 {
        _ = self;
        return @as(u32, r & 0xFF) << 16 | @as(u32, g & 0xFF) << 8 | (b & 0xFF);
    }

    fn executeCursorPosition(self: *Parser, params: []const u32, grid: *Grid) void {
        _ = self;
        const row = if (params.len > 0 and params[0] > 0) params[0] - 1 else 0;
        const col = if (params.len > 1 and params[1] > 0) params[1] - 1 else 0;
        grid.moveCursor(col, row);
    }

    fn executeCursorUp(self: *Parser, params: []const u32, grid: *Grid) void {
        _ = self;
        const n = if (params.len > 0 and params[0] > 0) params[0] else 1;
        const cur_y = grid.cursor.y;
        grid.moveCursor(grid.cursor.x, if (cur_y >= n) cur_y - n else 0);
    }

    fn executeCursorDown(self: *Parser, params: []const u32, grid: *Grid) void {
        _ = self;
        const n = if (params.len > 0 and params[0] > 0) params[0] else 1;
        grid.moveCursor(grid.cursor.x, grid.cursor.y + n);
    }

    fn executeCursorForward(self: *Parser, params: []const u32, grid: *Grid) void {
        _ = self;
        const n = if (params.len > 0 and params[0] > 0) params[0] else 1;
        grid.moveCursor(grid.cursor.x + n, grid.cursor.y);
    }

    fn executeCursorBack(self: *Parser, params: []const u32, grid: *Grid) void {
        _ = self;
        const n = if (params.len > 0 and params[0] > 0) params[0] else 1;
        const cur_x = grid.cursor.x;
        grid.moveCursor(if (cur_x >= n) cur_x - n else 0, grid.cursor.y);
    }

    fn executeCursorHorizontalAbsolute(self: *Parser, params: []const u32, grid: *Grid) void {
        _ = self;
        const col = if (params.len > 0 and params[0] > 0) params[0] - 1 else 0;
        grid.moveCursor(col, grid.cursor.y);
    }

    fn executeEraseDisplay(self: *Parser, params: []const u32, grid: *Grid) void {
        _ = self;
        const mode = if (params.len > 0) params[0] else 0;
        switch (mode) {
            0 => grid.clearToEndOfScreen(),
            1, 2 => grid.clearScreen(),
            else => {},
        }
    }

    fn executeEraseLine(self: *Parser, params: []const u32, grid: *Grid) void {
        _ = self;
        const mode = if (params.len > 0) params[0] else 0;
        switch (mode) {
            0 => grid.clearToEndOfLine(),
            1, 2 => {
                const cur_x = grid.cursor.x;
                grid.cursor.x = 0;
                grid.clearToEndOfLine();
                grid.cursor.x = cur_x;
            },
            else => {},
        }
    }
};

test "OSC 52 clipboard operations" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator);
    var grid = try Grid.init(allocator, 80, 24);
    defer grid.deinit(allocator);

    // Test copy command (OSC 52 ; 0 ; SGVsbG8gV29ybGQ= ST)
    const copy_cmd = "\x1B]52;0;SGVsbG8gV29ybGQ=\x07";
    parser.parse(copy_cmd, &grid);
    try std.testing.expect(parser.hasClipboardChanged());
    try std.testing.expectEqual(@as(u8, 0), parser.getClipboardKind());
    try std.testing.expect(!parser.isClipboardRequest());
    try std.testing.expectEqualStrings("Hello World", parser.getClipboardData());

    // Test paste request (OSC 52 ; 1 ; ? ST)
    parser.resetClipboardChanged();
    const paste_cmd = "\x1B]52;1;?\x07";
    parser.parse(paste_cmd, &grid);
    try std.testing.expect(parser.hasClipboardChanged());
    try std.testing.expectEqual(@as(u8, 1), parser.getClipboardKind());
    try std.testing.expect(parser.isClipboardRequest());
    try std.testing.expectEqual(@as(usize, 0), parser.getClipboardData().len);

    // Test copy with base64 data that includes padding
    parser.resetClipboardChanged();
    const copy_cmd_pad = "\x1B]52;2;VGVzdA==\x07";
    parser.parse(copy_cmd_pad, &grid);
    try std.testing.expect(parser.hasClipboardChanged());
    try std.testing.expectEqual(@as(u8, 2), parser.getClipboardKind());
    try std.testing.expect(!parser.isClipboardRequest());
    try std.testing.expectEqualStrings("Test", parser.getClipboardData());

    // Test ST terminator instead of BEL
    parser.resetClipboardChanged();
    const copy_cmd_st = "\x1B]52;3;Zm9vYmFy\x1B\\";
    parser.parse(copy_cmd_st, &grid);
    try std.testing.expect(parser.hasClipboardChanged());
    try std.testing.expectEqual(@as(u8, 3), parser.getClipboardKind());
    try std.testing.expect(!parser.isClipboardRequest());
    try std.testing.expectEqualStrings("foobar", parser.getClipboardData());
}
