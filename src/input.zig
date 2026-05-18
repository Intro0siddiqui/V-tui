/// Vtui Input Module - Keyboard and mouse event handling
const std = @import("std");

/// Keyboard modifiers
pub const Mods = struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    logo: bool = false, // Super/Command key

    pub fn format(
        self: Mods,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        var first = true;
        if (self.shift) {
            if (!first) try writer.writeAll("+");
            try writer.writeAll("Shift");
            first = false;
        }
        if (self.ctrl) {
            if (!first) try writer.writeAll("+");
            try writer.writeAll("Ctrl");
            first = false;
        }
        if (self.alt) {
            if (!first) try writer.writeAll("+");
            try writer.writeAll("Alt");
            first = false;
        }
        if (self.logo) {
            if (!first) try writer.writeAll("+");
            try writer.writeAll("Logo");
            first = false;
        }
    }

    pub fn ctrlPressed(self: Mods) bool {
        return self.ctrl;
    }

    pub fn altPressed(self: Mods) bool {
        return self.alt;
    }

    pub fn shiftPressed(self: Mods) bool {
        return self.shift;
    }

    pub fn logoPressed(self: Mods) bool {
        return self.logo;
    }
};

/// Key action (press, release, repeat)
pub const KeyAction = enum {
    press,
    release,
    repeat,
};

/// Key codes (based on W3C standard)
pub const KeyCode = enum {
    Unknown,
    // Alphabet
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    // Numbers
    Num0,
    Num1,
    Num2,
    Num3,
    Num4,
    Num5,
    Num6,
    Num7,
    Num8,
    Num9,
    // Function keys
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    // Special keys
    Escape,
    Backspace,
    Tab,
    Enter,
    Space,
    // Modifiers
    ShiftLeft,
    ShiftRight,
    ControlLeft,
    ControlRight,
    AltLeft,
    AltRight,
    MetaLeft,
    MetaRight,
    // Arrow keys
    ArrowUp,
    ArrowDown,
    ArrowLeft,
    ArrowRight,
    // Navigation
    Home,
    End,
    PageUp,
    PageDown,
    Insert,
    Delete,
    // Punctuation
    Colon,
    Semicolon,
    Comma,
    Period,
    Slash,
    Backslash,
    LeftBracket,
    RightBracket,
    Quote,
    Backquote,
    Minus,
    Equal,
    // Lock keys
    CapsLock,
    NumLock,
    ScrollLock,
    // Media keys
    PrintScreen,
    Pause,
};

/// Convert KeyCode to ANSI escape sequence
pub fn keyCodeToAnsi(code: KeyCode, mods: Mods) ?[]const u8 {
    // Arrow keys
    return switch (code) {
        .ArrowUp => "\x1b[A",
        .ArrowDown => "\x1b[B",
        .ArrowRight => "\x1b[C",
        .ArrowLeft => "\x1b[D",
        .Home => if (mods.shift) "\x1b[1;2H" else "\x1b[H",
        .End => if (mods.shift) "\x1b[1;2F" else "\x1b[F",
        .PageUp => if (mods.shift) "\x1b[1;2S" else "\x1b[S",
        .PageDown => if (mods.shift) "\x1b[1;2T" else "\x1b[T",
        .Insert => "\x1b[2~",
        .Delete => "\x1b[3~",
        .F1 => "\x1bOP",
        .F2 => "\x1bOQ",
        .F3 => "\x1bOR",
        .F4 => "\x1bOS",
        .F5 => "\x1b[15~",
        .F6 => "\x1b[17~",
        .F7 => "\x1b[18~",
        .F8 => "\x1b[19~",
        .F9 => "\x1b[20~",
        .F10 => "\x1b[21~",
        .F11 => "\x1b[23~",
        .F12 => "\x1b[24~",
        else => null,
    };
}

/// Convert ASCII character to ANSI sequence with modifiers
pub fn charToAnsi(ch: u8, mods: Mods) ?[]const u8 {
    // Ctrl+letter combinations
    if (mods.ctrl and !mods.alt and !mods.logo) {
        // Ctrl+A through Ctrl+Z
        if (ch >= 'a' and ch <= 'z') {
            const ctrl_ch = ch - 'a' + 1;
            return &[_]u8{ctrl_ch};
        }
        // Ctrl+[@[\]^_ (0-31)
        if (ch >= '@' and ch <= '_') {
            return &[_]u8{ch - '@'};
        }
    }

    // Alt+letter combinations (generate escape sequences)
    if (mods.alt and !mods.ctrl) {
        // Alt key typically sends escape before the character
        // Return as string - need to handle this differently
        return null; // Will be handled separately
    }

    return null; // No special sequence needed
}

/// Mouse event
pub const MouseEvent = struct {
    x: i32,
    y: i32,
    button: MouseButton,
    action: MouseAction,
    mods: Mods,
    scroll_delta: i32 = 0,
};

pub const MouseButton = enum {
    Left,
    Middle,
    Right,
    None,
};

pub const MouseAction = enum {
    Press,
    Release,
    Move,
    Scroll,
};

/// Convert mouse event to ANSI sequence
pub fn mouseEventToAnsi(event: MouseEvent) ?[]const u8 {
    const button_code = switch (event.button) {
        .Left => 0,
        .Middle => 1,
        .Right => 2,
        .None => 3,
    };

    const _action_code = switch (event.action) {
        .Press => 0,
        .Release => 1,
        .Move => 2,
        .Scroll => 3,
    };

    // X10 mouse reporting
    const x = event.x + 1;
    const y = event.y + 1;
    const button_byte = @as(u8, @intCast(button_code + _action_code * 32 + 32));
    const x_byte = @as(u8, @intCast(x + 32));
    const y_byte = @as(u8, @intCast(y + 32));

    return &[_]u8{ '\x1b', '[', 'M', button_byte, x_byte, y_byte };
}

pub const KeyEvent = struct {
    code: KeyCode,
    action: KeyAction,
    mods: Mods,
    utf8: []const u8 = "",
};

/// Keymap for converting X11 keysyms to KeyCode
pub const Keymap = struct {
    pub fn fromX11Keysym(keysym: u32) KeyCode {
        return switch (keysym) {
            // ASCII letters
            0x41 => .A,
            0x42 => .B,
            0x43 => .C,
            0x44 => .D,
            0x45 => .E,
            0x46 => .F,
            0x47 => .G,
            0x48 => .H,
            0x49 => .I,
            0x4a => .J,
            0x4b => .K,
            0x4c => .L,
            0x4d => .M,
            0x4e => .N,
            0x4f => .O,
            0x50 => .P,
            0x51 => .Q,
            0x52 => .R,
            0x53 => .S,
            0x54 => .T,
            0x55 => .U,
            0x56 => .V,
            0x57 => .W,
            0x58 => .X,
            0x59 => .Y,
            0x5a => .Z,
            // Lowercase letters
            0x61 => .A,
            0x62 => .B,
            0x63 => .C,
            0x64 => .D,
            0x65 => .E,
            0x66 => .F,
            0x67 => .G,
            0x68 => .H,
            0x69 => .I,
            0x6a => .J,
            0x6b => .K,
            0x6c => .L,
            0x6d => .M,
            0x6e => .N,
            0x6f => .O,
            0x70 => .P,
            0x71 => .Q,
            0x72 => .R,
            0x73 => .S,
            0x74 => .T,
            0x75 => .U,
            0x76 => .V,
            0x77 => .W,
            0x78 => .X,
            0x79 => .Y,
            0x7a => .Z,
            // Numbers
            0x30 => .Num0,
            0x31 => .Num1,
            0x32 => .Num2,
            0x33 => .Num3,
            0x34 => .Num4,
            0x35 => .Num5,
            0x36 => .Num6,
            0x37 => .Num7,
            0x38 => .Num8,
            0x39 => .Num9,
            // Function keys (XK_F1-F12 are 0xffbe-0xffc9)
            0xffbe => .F1,
            0xffbf => .F2,
            0xffc0 => .F3,
            0xffc1 => .F4,
            0xffc2 => .F5,
            0xffc3 => .F6,
            0xffc4 => .F7,
            0xffc5 => .F8,
            0xffc6 => .F9,
            0xffc7 => .F10,
            0xffc8 => .F11,
            0xffc9 => .F12,
            // Special keys
            0xff1b => .Escape, // XK_Escape
            0xff08 => .Backspace, // XK_BackSpace
            0xff09 => .Tab, // XK_Tab
            0xff0d => .Enter, // XK_Return
            0x20 => .Space, // XK_space
            // Arrow keys
            0xff51 => .ArrowLeft, // XK_Left
            0xff52 => .ArrowUp, // XK_Up
            0xff53 => .ArrowRight, // XK_Right
            0xff54 => .ArrowDown, // XK_Down
            // Navigation keys
            0xff50 => .Home, // XK_Home
            0xff57 => .End, // XK_End
            0xff55 => .PageUp, // XK_Page_Up
            0xff56 => .PageDown, // XK_Page_Down
            0xff63 => .Insert, // XK_Insert
            0xffff => .Delete, // XK_Delete
            // Modifier keys
            0xffe1 => .ShiftLeft, // XK_Shift_L
            0xffe2 => .ShiftRight, // XK_Shift_R
            0xffe3 => .ControlLeft, // XK_Control_L
            0xffe4 => .ControlRight, // XK_Control_R
            0xffe9 => .AltLeft, // XK_Alt_L
            0xffea => .AltRight, // XK_Alt_R
            // Punctuation
            0x3b => .Semicolon, // ;
            0x2c => .Comma, // ,
            0x2e => .Period, // .
            0x2f => .Slash, // /
            0x5c => .Backslash, // \
            0x5b => .LeftBracket, // [
            0x5d => .RightBracket, // ]
            0x27 => .Quote, // '
            0x60 => .Backquote, // `
            0x2d => .Minus, // -
            0x3d => .Equal, // =
            0x3a => .Colon, // :
            // Lock keys
            0xffe5 => .CapsLock, // XK_Caps_Lock
            0xff7f => .NumLock, // XK_Num_Lock
            0xff14 => .ScrollLock, // XK_Scroll_Lock
            // Print screen and pause
            0xff61 => .PrintScreen, // XK_Print
            0xff13 => .Pause, // XK_Pause
            else => .Unknown,
        };
    }
};
