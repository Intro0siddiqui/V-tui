/// Vtui Font Module - FreeType2 based font loading with fallback support
const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/ftmm.h");
    @cInclude("freetype/ftlcdfil.h");
    @cInclude("fontconfig/fontconfig.h");
    @cInclude("harfbuzz/hb.h");
    @cInclude("harfbuzz/hb-ft.h");
});

pub const VariationAxisFlag = enum(u32) {
    hidden = c.FT_VAR_AXIS_FLAG_HIDDEN,
};

pub const VariationAxis = struct {
    tag: u32,
    name: [:0]const u8,
    minimum: f64,
    default_value: f64,
    maximum: f64,
    flags: u32,

    pub fn tagToString(tag: u32) [4]u8 {
        return @as([4]u8, @bitCast(tag));
    }

    pub fn tagFromString(str: []const u8) u32 {
        var tag: [4]u8 = undefined;
        @memcpy(tag[0..str.len], str);
        for (str.len..4) |i| tag[i] = ' ';
        return @as(u32, @bitCast(tag));
    }
};

pub const WeightAxisTag: u32 = VariationAxis.tagFromString("wght");
pub const WidthAxisTag: u32 = VariationAxis.tagFromString("wdth");
pub const SlantAxisTag: u32 = VariationAxis.tagFromString("slnt");
pub const OpticalSizeAxisTag: u32 = VariationAxis.tagFromString("opsz");
pub const ItalicAxisTag: u32 = VariationAxis.tagFromString("ital");

pub const Glyph = struct {
    bitmap: []u8,
    width: u32,
    height: u32,
    advance_x: i32,
    advance_y: i32,
    bearing_x: i32,
    bearing_y: i32,
    is_color: bool = false,
    is_lcd: bool = false,
};

pub const UnicodeBlock = enum {
    ASCII,
    Latin,
    CJK,
    Emoji,
    Symbol,
    Other,
};

pub fn classifyUnicode(codepoint: u21) UnicodeBlock {
    if (codepoint < 0x80) return .ASCII;
    if (codepoint < 0x100) return .Latin;
    if (codepoint >= 0x4E00 and codepoint <= 0x9FFF) return .CJK;
    if (codepoint >= 0x3000 and codepoint <= 0x303F) return .Symbol;
    if (codepoint >= 0x2000 and codepoint <= 0x206F) return .Symbol;
    if (codepoint >= 0x2100 and codepoint <= 0x214F) return .Symbol;
    if (codepoint >= 0x1F300 and codepoint <= 0x1F9FF) return .Emoji;
    if (codepoint >= 0x1F600 and codepoint <= 0x1F64F) return .Emoji;
    if (codepoint >= 0x1F680 and codepoint <= 0x1F6FF) return .Emoji;
    if (codepoint >= 0x2600 and codepoint <= 0x26FF) return .Emoji;
    if (codepoint >= 0x2700 and codepoint <= 0x27BF) return .Symbol;
    return .Other;
}

pub const LigatureType = enum {
    ArrowRight,
    NotEqual,
    Equal,
    LessEqual,
    GreaterEqual,
    Pointer,
    Increment,
    Decrement,
    LogicalAnd,
    LogicalOr,
    ScopeResolution,
    DoubleSemicolon,
    PipeRight,
    ArrowLeft,
    TripleW,
};

pub const LigatureDetector = struct {
    pub const LigatureMatch = struct {
        ligature_type: LigatureType,
        length: u8,
    };

    pub fn detect(text: []const u8) ?LigatureMatch {
        if (text.len < 2) return null;

        const first = text[0];
        const second = text[1];

        if (first == '-' and second == '>') {
            return LigatureMatch{ .ligature_type = .Pointer, .length = 2 };
        }
        if (first == '=' and second == '>') {
            return LigatureMatch{ .ligature_type = .ArrowRight, .length = 2 };
        }
        if (first == '<' and second == '-') {
            return LigatureMatch{ .ligature_type = .ArrowLeft, .length = 2 };
        }
        if (first == '!' and second == '=') {
            return LigatureMatch{ .ligature_type = .NotEqual, .length = 2 };
        }
        if (first == '=' and second == '=') {
            return LigatureMatch{ .ligature_type = .Equal, .length = 2 };
        }
        if (first == '<' and second == '=') {
            return LigatureMatch{ .ligature_type = .LessEqual, .length = 2 };
        }
        if (first == '>' and second == '=') {
            return LigatureMatch{ .ligature_type = .GreaterEqual, .length = 2 };
        }
        if (first == '+' and second == '+') {
            return LigatureMatch{ .ligature_type = .Increment, .length = 2 };
        }
        if (first == '-' and second == '-') {
            return LigatureMatch{ .ligature_type = .Decrement, .length = 2 };
        }
        if (first == '&' and second == '&') {
            return LigatureMatch{ .ligature_type = .LogicalAnd, .length = 2 };
        }
        if (first == '|' and second == '|') {
            return LigatureMatch{ .ligature_type = .LogicalOr, .length = 2 };
        }
        if (first == ':' and second == ':') {
            return LigatureMatch{ .ligature_type = .ScopeResolution, .length = 2 };
        }
        if (first == ';' and second == ';') {
            return LigatureMatch{ .ligature_type = .DoubleSemicolon, .length = 2 };
        }
        if (first == '|' and second == '>') {
            return LigatureMatch{ .ligature_type = .PipeRight, .length = 2 };
        }
        if (text.len >= 3) {
            const third = text[2];
            if (first == 'w' and second == 'w' and third == 'w') {
                return LigatureMatch{ .ligature_type = .TripleW, .length = 3 };
            }
        }

        return null;
    }

    pub fn getCodepoint(ligature_type: LigatureType) u21 {
        return switch (ligature_type) {
            .ArrowRight => 0x21D2,
            .NotEqual => 0x2260,
            .Equal => 0x2264,
            .LessEqual => 0x2264,
            .GreaterEqual => 0x2265,
            .Pointer => 0x2192,
            .Increment => 0x21D1,
            .Decrement => 0x21D3,
            .LogicalAnd => 0x2227,
            .LogicalOr => 0x2228,
            .ScopeResolution => 0x2261,
            .DoubleSemicolon => 0x204F,
            .PipeRight => 0x25B7,
            .ArrowLeft => 0x2190,
            .TripleW => 'w',
        };
    }

    pub fn ligatureExists(ligature_type: LigatureType) bool {
        const cp = getCodepoint(ligature_type);
        return cp != 0;
    }
};

pub const FontFace = struct {
    face: c.FT_Face,
    hb_font: ?*c.hb_font_t,
    path: [:0]const u8,
    size: u32,
    supports_color: bool,
    allocator: std.mem.Allocator,
    library: c.FT_Library,

    pub fn deinit(self: *FontFace) void {
        if (self.hb_font) |hbf| {
            c.hb_font_destroy(hbf);
        }
        _ = c.FT_Done_Face(self.face);
    }

    pub fn getGlyph(self: *FontFace, codepoint: u21) !Glyph {
        const glyph_index = c.FT_Get_Char_Index(self.face, codepoint);
        if (glyph_index == 0) {
            return error.GlyphNotFound;
        }
        return self.getGlyphByIndex(glyph_index);
    }

    pub fn getGlyphByIndex(self: *FontFace, glyph_index: u32) !Glyph {
        // Enable LCD filter for sub-pixel AA
        _ = c.FT_Library_SetLcdFilter(self.library, c.FT_LCD_FILTER_DEFAULT);

        var load_flags: c_int = c.FT_LOAD_DEFAULT;
        if (self.supports_color) {
            load_flags |= c.FT_LOAD_COLOR;
        }

        const error_code = c.FT_Load_Glyph(self.face, glyph_index, load_flags);
        if (error_code != 0) {
            return error.FT_LoadGlyphFailed;
        }

        const render_mode: c.FT_Render_Mode = if (self.supports_color) c.FT_RENDER_MODE_NORMAL else c.FT_RENDER_MODE_LCD;
        const render_error = c.FT_Render_Glyph(self.face.*.glyph, render_mode);
        if (render_error != 0) {
            return error.FT_RenderGlyphFailed;
        }

        const slot = self.face.*.glyph;
        const bitmap = slot.*.bitmap;

        var is_color = false;
        if (self.supports_color and bitmap.pixel_mode == c.FT_PIXEL_MODE_BGRA) {
            is_color = true;
        }

        const is_lcd = bitmap.pixel_mode == c.FT_PIXEL_MODE_LCD;

        // In LCD mode, width is the actual width in pixels,
        // but the buffer contains 3 bytes per pixel (RGB).
        // Freetype's bitmap.width in LCD mode is actually 3 * pixels_wide.
        // Wait, check FreeType docs. "pitch" is bytes per row.
        // For FT_PIXEL_MODE_LCD, each row has width * 3 bytes.
        const width = if (is_lcd) bitmap.width / 3 else bitmap.width;

        const pitch_abs = @as(usize, @intCast(if (bitmap.pitch < 0) -bitmap.pitch else bitmap.pitch));
        const bitmap_size = pitch_abs * @as(usize, @intCast(bitmap.rows));
        const bitmap_data = try self.allocator.alloc(u8, bitmap_size);

        if (bitmap.buffer != null and bitmap_size > 0) {
            @memcpy(bitmap_data, bitmap.buffer[0..bitmap_size]);
        }

        return Glyph{
            .bitmap = bitmap_data,
            .width = @intCast(width),
            .height = @intCast(bitmap.rows),
            .advance_x = @intCast(slot.*.advance.x >> 6),
            .advance_y = @intCast(slot.*.advance.y >> 6),
            .bearing_x = @intCast(slot.*.bitmap_left),
            .bearing_y = @intCast(slot.*.bitmap_top),
            .is_color = is_color,
            .is_lcd = is_lcd,
        };
    }

    pub fn releaseGlyph(self: *FontFace, glyph: Glyph) void {
        self.allocator.free(glyph.bitmap);
    }

    pub fn hasGlyph(self: *FontFace, codepoint: u21) bool {
        const glyph_index = c.FT_Get_Char_Index(self.face, codepoint);
        return glyph_index != 0;
    }

    pub fn getGlyphIndex(self: *FontFace, codepoint: u21) u32 {
        return c.FT_Get_Char_Index(self.face, codepoint);
    }

    pub fn isVariable(self: *FontFace) bool {
        return c.FT_IS_VARIATION(self.face) != 0;
    }

    pub fn getVariationAxes(self: *FontFace) ![]VariationAxis {
        if (!self.isVariable()) {
            return &[_]VariationAxis{};
        }

        var mm_var: [*]c.FT_MM_Var = undefined;
        const error_code = c.FT_Get_MM_Var(self.face, &mm_var);
        if (error_code != 0) {
            return error.FT_GetMMVarFailed;
        }

        defer _ = c.FT_Done_MM_Var(self.library, mm_var);

        const num_axes = mm_var.*.num_axis;
        if (num_axes == 0) {
            return &[_]VariationAxis{};
        }

        var axes = try self.allocator.alloc(VariationAxis, num_axes);

        for (0..num_axes) |i| {
            const axis_ptr = &mm_var.*.axis[i];
            var flags: u32 = 0;
            _ = c.FT_Get_Var_Axis_Flags(mm_var, @intCast(i), &flags);

            const name_str = if (axis_ptr.name) |n| std.mem.sliceTo(n, 0) else "";
            const name_owned = try self.allocator.dupeZ(u8, name_str);

            axes[i] = VariationAxis{
                .tag = axis_ptr.tag,
                .name = name_owned,
                .minimum = @as(f64, @bitCast(axis_ptr.minimum)) / 65536.0,
                .default_value = @as(f64, @bitCast(axis_ptr.def)) / 65536.0,
                .maximum = @as(f64, @bitCast(axis_ptr.maximum)) / 65536.0,
                .flags = flags,
            };
        }

        return axes;
    }

    pub fn setVariation(self: *FontFace, axis_tag: u32, value: f64) !void {
        if (!self.isVariable()) {
            return error.NotVariableFont;
        }

        var mm_var: [*]c.FT_MM_Var = undefined;
        const error_code = c.FT_Get_MM_Var(self.face, &mm_var);
        if (error_code != 0) {
            return error.FT_GetMMVarFailed;
        }

        defer _ = c.FT_Done_MM_Var(self.library, mm_var);

        const num_axes = mm_var.*.num_axis;
        if (num_axes == 0) {
            return error.NoVariationAxes;
        }

        var coords = try self.allocator.alloc(c.FT_Fixed, num_axes);
        defer self.allocator.free(coords);

        const get_error = c.FT_Get_Var_Design_Coordinates(self.face, num_axes, coords.ptr);
        if (get_error != 0) {
            return error.FT_GetVarDesignCoordsFailed;
        }

        var found = false;
        for (0..num_axes) |i| {
            if (mm_var.*.axis[i].tag == axis_tag) {
                coords[i] = @intFromFloat(value * 65536.0);
                found = true;
                break;
            }
        }

        if (!found) {
            return error.AxisNotFound;
        }

        const set_error = c.FT_Set_Var_Design_Coordinates(self.face, num_axes, coords.ptr);
        if (set_error != 0) {
            return error.FT_SetVarDesignCoordsFailed;
        }
    }
};

pub const Font = struct {
    faces: std.ArrayList(FontFace),
    library: c.FT_Library,
    allocator: std.mem.Allocator,
    glyph_cache: std.AutoHashMap(u21, GlyphCacheEntry),
    fallback_fonts: std.ArrayList(FontFace),

    const GlyphCacheEntry = struct {
        glyph: Glyph,
        face_index: usize,
    };

    pub fn init(allocator: std.mem.Allocator) !Font {
        var library: c.FT_Library = undefined;
        const error_code = c.FT_Init_FreeType(&library);
        if (error_code != 0) {
            return error.FT_InitFailed;
        }

        return Font{
            .faces = try std.ArrayList(FontFace).initCapacity(allocator, 0),
            .library = library,
            .allocator = allocator,
            .glyph_cache = std.AutoHashMap(u21, GlyphCacheEntry).init(allocator),
            .fallback_fonts = try std.ArrayList(FontFace).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *Font) void {
        var cache_iter = self.glyph_cache.valueIterator();
        while (cache_iter.next()) |entry| {
            self.faces.items[entry.face_index].releaseGlyph(entry.glyph);
        }
        self.glyph_cache.deinit();

        for (self.faces.items) |*face| {
            face.deinit();
        }
        self.faces.deinit(self.allocator);

        for (self.fallback_fonts.items) |*face| {
            face.deinit();
        }
        self.fallback_fonts.deinit(self.allocator);

        _ = c.FT_Done_FreeType(self.library);
    }

    pub fn addFace(self: *Font, path: [:0]const u8, size: u32) !void {
        var face: c.FT_Face = undefined;
        const error_code = c.FT_New_Face(self.library, path.ptr, 0, &face);
        if (error_code != 0) {
            return error.FT_LoadFaceFailed;
        }

        const size_error = c.FT_Set_Pixel_Sizes(face, @intCast(size), 0);
        if (size_error != 0) {
            _ = c.FT_Done_Face(face);
            return error.FT_SetSizeFailed;
        }

        const supports_color = c.FT_HAS_COLOR(face);

        const face_idx = self.faces.items.len;
        const hb_font = c.hb_ft_font_create(face, null);
        try self.faces.append(self.allocator, .{
            .face = face,
            .hb_font = hb_font,
            .path = path,
            .size = size,
            .supports_color = supports_color,
            .allocator = self.allocator,
            .library = self.library,
        });

        if (supports_color) {
            self.fallback_fonts.append(self.allocator, self.faces.items[face_idx]) catch {};
        }
    }

    pub fn addFallbackFace(self: *Font, path: [:0]const u8, size: u32) !void {
        var face: c.FT_Face = undefined;
        const error_code = c.FT_New_Face(self.library, path.ptr, 0, &face);
        if (error_code != 0) {
            return error.FT_LoadFaceFailed;
        }

        const size_error = c.FT_Set_Pixel_Sizes(face, @intCast(size), 0);
        if (size_error != 0) {
            _ = c.FT_Done_Face(face);
            return error.FT_SetSizeFailed;
        }

        const supports_color = c.FT_HAS_COLOR(face);
        const hb_font = c.hb_ft_font_create(face, null);

        try self.fallback_fonts.append(self.allocator, .{
            .face = face,
            .hb_font = hb_font,
            .path = path,
            .size = size,
            .supports_color = supports_color,
            .allocator = self.allocator,
            .library = self.library,
        });
    }

    pub fn releaseGlyph(self: *Font, glyph: Glyph) void {
        _ = self;
        _ = glyph;
        // Glyphs are cached, so we don't release them immediately
        // They are released in deinit() when the cache is cleared
    }

    pub fn getGlyph(self: *Font, codepoint: u21) !Glyph {
        if (self.glyph_cache.get(codepoint)) |entry| {
            return entry.glyph;
        }

        const block = classifyUnicode(codepoint);

        if (block == .Emoji) {
            for (self.fallback_fonts.items) |*face| {
                if (face.supports_color) {
                    const glyph = face.getGlyph(codepoint) catch continue;
                    if (glyph.width > 0 and glyph.height > 0) {
                        try self.glyph_cache.put(codepoint, .{ .glyph = glyph, .face_index = self.faces.items.len + 1 }); // Signal for fallback
                        return glyph;
                    }
                    face.releaseGlyph(glyph);
                }
            }
        }

        for (self.faces.items, 0..) |*face, idx| {
            const glyph = face.getGlyph(codepoint) catch continue;
            if (glyph.width > 0 and glyph.height > 0) {
                try self.glyph_cache.put(codepoint, .{ .glyph = glyph, .face_index = idx });
                return glyph;
            }
            face.releaseGlyph(glyph);
        }

        for (self.fallback_fonts.items, 0..) |*face, idx| {
            const glyph = face.getGlyph(codepoint) catch continue;
            if (glyph.width > 0 and glyph.height > 0) {
                try self.glyph_cache.put(codepoint, .{ .glyph = glyph, .face_index = self.faces.items.len + idx });
                return glyph;
            }
            face.releaseGlyph(glyph);
        }

        return error.GlyphNotFound;
    }

    pub fn getGlyphByIndex(self: *Font, face_index: usize, glyph_index: u32) !Glyph {
        // For caching glyphs by index, use a negative codepoint (to distinguish from real codepoints)
        // Combine face_index and glyph_index into a single u21 (this is a simplification)
        const cache_key = @as(u21, @truncate(@as(u32, @intCast(face_index)) << 16 | (glyph_index & 0xFFFF)));

        if (self.glyph_cache.get(cache_key)) |entry| {
            return entry.glyph;
        }

        // Check if face_index refers to a fallback font
        if (face_index >= self.faces.items.len) {
            const fallback_idx = face_index - self.faces.items.len;
            if (fallback_idx < self.fallback_fonts.items.len) {
                const glyph = try self.fallback_fonts.items[fallback_idx].getGlyphByIndex(glyph_index);
                try self.glyph_cache.put(cache_key, .{ .glyph = glyph, .face_index = face_index });
                return glyph;
            }
            return error.GlyphNotFound;
        }

        const glyph = try self.faces.items[face_index].getGlyphByIndex(glyph_index);
        try self.glyph_cache.put(cache_key, .{ .glyph = glyph, .face_index = face_index });
        return glyph;
    }

    pub fn shape(self: *Font, text: []const u8) !ShapedText {
        const hb_buffer = c.hb_buffer_create();
        defer c.hb_buffer_destroy(hb_buffer);

        c.hb_buffer_add_utf8(hb_buffer, text.ptr, @intCast(text.len), 0, -1);
        c.hb_buffer_guess_segment_properties(hb_buffer);

        if (self.faces.items.len == 0) return error.NoFontLoaded;
        const face = &self.faces.items[0];
        c.hb_shape(face.hb_font, hb_buffer, null, 0);

        var glyph_count: u32 = 0;
        const glyph_info = c.hb_buffer_get_glyph_infos(hb_buffer, &glyph_count);
        const glyph_pos = c.hb_buffer_get_glyph_positions(hb_buffer, &glyph_count);

        var result = try ShapedText.init(self.allocator, glyph_count);
        for (0..glyph_count) |i| {
            result.glyphs[i] = .{
                .glyph_index = glyph_info[i].codepoint,
                .x_advance = glyph_pos[i].x_advance,
                .y_advance = glyph_pos[i].y_advance,
                .x_offset = glyph_pos[i].x_offset,
                .y_offset = glyph_pos[i].y_offset,
            };
        }

        // Convert HarfBuzz units (1/1000 of em) to pixels
        // For 16px font size: scale = 16 / 1000 = 0.016
        const scale = @as(f32, @floatFromInt(self.faces.items[0].size)) / 1000.0;
        result.toPixels(scale);

        return result;
    }
};

pub const ShapedGlyph = struct {
    glyph_index: u32,
    x_advance: i32,
    y_advance: i32,
    x_offset: i32,
    y_offset: i32,
};

pub const ShapedText = struct {
    glyphs: []ShapedGlyph,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, count: usize) !ShapedText {
        return ShapedText{
            .glyphs = try allocator.alloc(ShapedGlyph, count),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *const ShapedText) void {
        self.allocator.free(self.glyphs);
    }

    /// Convert HarfBuzz units to pixels (divide by 1000)
    pub fn toPixels(self: *ShapedText, scale: f32) void {
        for (self.glyphs) |*g| {
            g.x_advance = @intFromFloat(@as(f32, @floatFromInt(g.x_advance)) * scale);
            g.y_advance = @intFromFloat(@as(f32, @floatFromInt(g.y_advance)) * scale);
            g.x_offset = @intFromFloat(@as(f32, @floatFromInt(g.x_offset)) * scale);
            g.y_offset = @intFromFloat(@as(f32, @floatFromInt(g.y_offset)) * scale);
        }
    }
};

pub fn shapeText(self: *Font, text: []const u8) !ShapedText {
    const hb_buffer = c.hb_buffer_create();
    defer c.hb_buffer_destroy(hb_buffer);

    c.hb_buffer_add_utf8(hb_buffer, text.ptr, @intCast(text.len), 0, -1);
    c.hb_buffer_guess_segment_properties(hb_buffer);

    if (self.faces.items.len == 0) return error.NoFontLoaded;
    const face = &self.faces.items[0];
    c.hb_shape(face.hb_font, hb_buffer, null, 0);

    var glyph_count: u32 = 0;
    const glyph_info = c.hb_buffer_get_glyph_infos(hb_buffer, &glyph_count);
    const glyph_pos = c.hb_buffer_get_glyph_positions(hb_buffer, &glyph_count);

    var result = try ShapedText.init(self.allocator, glyph_count);
    for (0..glyph_count) |i| {
        result.glyphs[i] = .{
            .glyph_index = glyph_info[i].codepoint,
            .x_advance = glyph_pos[i].x_advance,
            .y_advance = glyph_pos[i].y_advance,
            .x_offset = glyph_pos[i].x_offset,
            .y_offset = glyph_pos[i].y_offset,
        };
    }

    // Convert HarfBuzz units (1/1000 of em) to pixels
    // For 16px font size: scale = 16 / 1000 = 0.016
    const scale = @as(f32, @floatFromInt(self.faces.items[0].size)) / 1000.0;
    result.toPixels(scale);

    return result;
}

/// System font discovery - uses fontconfig for system font lookup
pub const FontDiscovery = struct {
    allocator: std.mem.Allocator,
    config: ?*c.FcConfig,

    pub fn init(allocator: std.mem.Allocator) FontDiscovery {
        const config = c.FcInitLoadConfig();
        return FontDiscovery{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *FontDiscovery) void {
        if (self.config) |cfg| {
            c.FcConfigDestroy(cfg);
        }
    }

    pub fn findMonospace(self: *FontDiscovery) ?[:0]const u8 {
        if (self.config) |cfg| {
            const pattern = c.FcPatternCreate();
            defer c.FcPatternDestroy(pattern);

            _ = c.FcPatternAddString(pattern, c.FC_FAMILY, @ptrCast(@as([*c]const u8, "monospace")));

            _ = c.FcConfigSubstitute(cfg, pattern, c.FcMatchPattern);
            c.FcDefaultSubstitute(pattern);

            var result: c.FcResult = undefined;
            const match = c.FcFontMatch(cfg, pattern, &result);
            if (match) |m| {
                defer c.FcPatternDestroy(m);

                var file: [*c]u8 = undefined;
                if (c.FcPatternGetString(m, c.FC_FILE, 0, &file) == c.FcResultMatch) {
                    const path = std.mem.sliceTo(file, 0);
                    const path_owned = self.allocator.dupeZ(u8, path) catch return null;
                    return path_owned;
                }
            }
        }

        const candidates = [_][:0]const u8{
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
            "/usr/share/fonts/Adwaita/AdwaitaMono-Regular.ttf",
            "/usr/share/fonts/TTF/Hack-Regular.ttf",
            "/usr/share/fonts/urw-base35/NimbusMonoPS-Regular.otf",
        };
        for (candidates) |path| {
            const file = std.fs.openFileAbsolute(path, .{}) catch continue;
            file.close();
            return path;
        }
        return null;
    }

    pub fn findForBlock(self: *FontDiscovery, block: UnicodeBlock) ?[:0]const u8 {
        if (self.config) |cfg| {
            const family = switch (block) {
                .Emoji => "emoji",
                .CJK => "sans",
                .Latin => "monospace",
                else => return self.findMonospace(),
            };

            const pattern = c.FcPatternCreate();
            defer c.FcPatternDestroy(pattern);

            _ = c.FcPatternAddString(pattern, c.FC_FAMILY, @ptrCast(family));

            _ = c.FcConfigSubstitute(cfg, pattern, c.FcMatchPattern);
            c.FcDefaultSubstitute(pattern);

            var result: c.FcResult = undefined;
            const match = c.FcFontMatch(cfg, pattern, &result);
            if (match) |m| {
                defer c.FcPatternDestroy(m);

                var file: [*c]u8 = undefined;
                if (c.FcPatternGetString(m, c.FC_FILE, 0, &file) == c.FcResultMatch) {
                    const path = std.mem.sliceTo(file, 0);
                    const path_owned = self.allocator.dupeZ(u8, path) catch return null;
                    return path_owned;
                }
            }
        }

        return switch (block) {
            .Emoji => self.findEmojiFont(),
            .CJK => self.findCJKFont(),
            else => self.findMonospace(),
        };
    }

    fn findEmojiFont(self: *FontDiscovery) ?[:0]const u8 {
        _ = self;
        const candidates = [_][:0]const u8{
            "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
            "/usr/share/fonts/truetype/noto/NotoEmoji-Regular.ttf",
            "/usr/share/fonts/google-noto-emoji/NotoColorEmoji.ttf",
            "/usr/share/fonts/Gargi/Gargi-2.ttf",
        };
        for (candidates) |path| {
            const file = std.fs.openFileAbsolute(path, .{}) catch continue;
            file.close();
            return path;
        }
        return null;
    }

    fn findCJKFont(self: *FontDiscovery) ?[:0]const u8 {
        _ = self;
        const candidates = [_][:0]const u8{
            "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttc",
            "/usr/share/fonts/truetype/arphic/uming.ttc",
        };
        for (candidates) |path| {
            const file = std.fs.openFileAbsolute(path, .{}) catch continue;
            file.close();
            return path;
        }
        return null;
    }

    pub fn findForCodepoint(self: *FontDiscovery, codepoint: u21) ?[:0]const u8 {
        const block = classifyUnicode(codepoint);
        return self.findForBlock(block);
    }

    pub fn buildFontStack(self: *FontDiscovery, base_size: u32, font: *Font) !void {
        if (self.findMonospace()) |mono_path| {
            try font.addFace(mono_path, base_size);
        }

        if (self.findForBlock(.Emoji)) |emoji_path| {
            try font.addFallbackFace(emoji_path, base_size);
        }

        if (self.findForBlock(.CJK)) |cjk_path| {
            try font.addFallbackFace(cjk_path, base_size);
        }
    }
};

test "LigatureDetector arrow right" {
    const match = LigatureDetector.detect("=>");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .ArrowRight);
    try std.testing.expect(match.?.length == 2);
}

test "LigatureDetector not equal" {
    const match = LigatureDetector.detect("!=");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .NotEqual);
}

test "LigatureDetector equal" {
    const match = LigatureDetector.detect("==");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .Equal);
}

test "LigatureDetector less equal" {
    const match = LigatureDetector.detect("<=");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .LessEqual);
}

test "LigatureDetector greater equal" {
    const match = LigatureDetector.detect(">=");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .GreaterEqual);
}

test "LigatureDetector pointer" {
    const match = LigatureDetector.detect("->");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .Pointer);
}

test "LigatureDetector increment" {
    const match = LigatureDetector.detect("++");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .Increment);
}

test "LigatureDetector decrement" {
    const match = LigatureDetector.detect("--");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .Decrement);
}

test "LigatureDetector logical and" {
    const match = LigatureDetector.detect("&&");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .LogicalAnd);
}

test "LigatureDetector logical or" {
    const match = LigatureDetector.detect("||");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .LogicalOr);
}

test "LigatureDetector scope resolution" {
    const match = LigatureDetector.detect("::");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .ScopeResolution);
}

test "LigatureDetector double semicolon" {
    const match = LigatureDetector.detect(";;");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .DoubleSemicolon);
}

test "LigatureDetector pipe right" {
    const match = LigatureDetector.detect("|>");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .PipeRight);
}

test "LigatureDetector arrow left" {
    const match = LigatureDetector.detect("<-");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .ArrowLeft);
}

test "LigatureDetector triple w" {
    const match = LigatureDetector.detect("www");
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.ligature_type == .TripleW);
    try std.testing.expect(match.?.length == 3);
}

test "LigatureDetector no ligature" {
    const match = LigatureDetector.detect("ab");
    try std.testing.expect(match == null);
}

test "LigatureDetector single char" {
    const match = LigatureDetector.detect("a");
    try std.testing.expect(match == null);
}
