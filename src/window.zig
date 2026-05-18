const std = @import("std");
const input = @import("input.zig");

const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/keysym.h");
    @cInclude("X11/extensions/XShm.h");
    @cInclude("sys/ipc.h");
    @cInclude("sys/shm.h");
});

pub const Window = struct {
    display: *c.Display,
    window: c.Window,
    gc: c.GC,
    image: *c.XImage,
    width: u32,
    height: u32,
    pixels: []u8,
    allocator: std.mem.Allocator,
    shminfo: *c.XShmSegmentInfo,
    use_shm: bool,

    pub const Size = struct { w: u32, h: u32 };

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Window {
        _ = c.XInitThreads();
        const display = c.XOpenDisplay(null) orelse return error.XOpenDisplayFailed;
        const screen = c.DefaultScreen(display);
        const root = c.RootWindow(display, screen);

        const window = c.XCreateSimpleWindow(
            display,
            root,
            0,
            0,
            width,
            height,
            0,
            c.BlackPixel(display, screen),
            c.BlackPixel(display, screen),
        );

        _ = c.XStoreName(display, window, "Vtui Engine");

        _ = c.XSelectInput(display, window, c.ExposureMask | c.KeyPressMask | c.StructureNotifyMask);
        _ = c.XMapWindow(display, window);

        const gc = c.XCreateGC(display, window, 0, null);

        const screen_visual = c.DefaultVisual(display, screen);
        const screen_depth = c.DefaultDepth(display, screen);

        var use_shm = false;
        const shminfo = try allocator.create(c.XShmSegmentInfo);
        @memset(std.mem.asBytes(shminfo), 0);

        var image: ?*c.XImage = null;
        var pixels: []u8 = &[_]u8{};

        if (c.XShmQueryExtension(display) != 0) {
            image = c.XShmCreateImage(
                display,
                screen_visual,
                @intCast(screen_depth),
                c.ZPixmap,
                null,
                shminfo,
                width,
                height,
            );

            if (image) |img| {
                const size = @as(usize, @intCast(img.*.bytes_per_line)) * height;
                shminfo.shmid = c.shmget(c.IPC_PRIVATE, size, c.IPC_CREAT | 0o600);
                if (shminfo.shmid != -1) {
                    shminfo.shmaddr = @ptrCast(c.shmat(shminfo.shmid, null, 0));
                    if (@intFromPtr(shminfo.shmaddr) != @as(usize, @bitCast(@as(isize, -1)))) {
                        img.*.data = @ptrCast(shminfo.shmaddr);
                        shminfo.readOnly = 0;
                        if (c.XShmAttach(display, shminfo) != 0) {
                            _ = c.XSync(display, 0);
                            use_shm = true;
                            pixels = @as([*]u8, @ptrCast(img.*.data))[0..size];
                        } else {
                            _ = c.shmdt(shminfo.shmaddr);
                            _ = c.shmctl(shminfo.shmid, c.IPC_RMID, null);
                        }
                    } else {
                        _ = c.shmctl(shminfo.shmid, c.IPC_RMID, null);
                    }
                }
                if (!use_shm) {
                    if (img.*.f.destroy_image) |destroy_fn| {
                        _ = destroy_fn(img);
                    }
                    image = null;
                }
            }
        }

        if (!use_shm) {
            std.debug.print("Using standard XImage\n", .{});
            const stride = (width * 4 + 3) & ~@as(u32, 3);
            pixels = try allocator.alloc(u8, @as(usize, stride) * height);
            @memset(pixels, 0);

            image = c.XCreateImage(
                display,
                screen_visual,
                @intCast(screen_depth),
                c.ZPixmap,
                0,
                @ptrCast(pixels.ptr),
                width,
                height,
                32,
                @intCast(stride),
            ) orelse return error.XCreateImageFailed;
        } else {
            std.debug.print("Using MIT-SHM (Shared Memory Address: {*}\n", .{shminfo.shmaddr});
        }

        _ = c.XFlush(display);

        return Window{
            .display = display,
            .window = window,
            .gc = gc,
            .image = image.?,
            .width = width,
            .height = height,
            .pixels = pixels,
            .allocator = allocator,
            .shminfo = shminfo,
            .use_shm = use_shm,
        };
    }

    pub fn deinit(self: *Window) void {
        if (self.use_shm) {
            _ = c.XShmDetach(self.display, self.shminfo);
            if (self.image.*.f.destroy_image) |destroy_fn| {
                _ = destroy_fn(self.image);
            }
            _ = c.shmdt(self.shminfo.shmaddr);
            _ = c.shmctl(self.shminfo.shmid, c.IPC_RMID, null);
        } else {
            self.image.*.data = null;
            if (self.image.*.f.destroy_image) |destroy_fn| {
                _ = destroy_fn(self.image);
            }
            self.allocator.free(self.pixels);
        }
        self.allocator.destroy(self.shminfo);
        _ = c.XFreeGC(self.display, self.gc);
        _ = c.XDestroyWindow(self.display, self.window);
        _ = c.XCloseDisplay(self.display);
    }

    pub fn draw(self: *Window) void {
        if (self.use_shm) {
            _ = c.XShmPutImage(
                self.display,
                self.window,
                self.gc,
                self.image,
                0,
                0,
                0,
                0,
                self.width,
                self.height,
                0,
            );
        } else {
            _ = c.XPutImage(
                self.display,
                self.window,
                self.gc,
                self.image,
                0,
                0,
                0,
                0,
                self.width,
                self.height,
            );
        }
        _ = c.XFlush(self.display);
    }

    pub fn resize(self: *Window, new_width: u32, new_height: u32) !void {
        if (new_width == self.width and new_height == self.height) return;

        const screen = c.DefaultScreen(self.display);
        const screen_visual = c.DefaultVisual(self.display, screen);
        const screen_depth = c.DefaultDepth(self.display, screen);

        if (self.use_shm) {
            _ = c.XShmDetach(self.display, self.shminfo);
            if (self.image.*.f.destroy_image) |destroy_fn| {
                _ = destroy_fn(self.image);
            }
            _ = c.shmdt(self.shminfo.shmaddr);
            _ = c.shmctl(self.shminfo.shmid, c.IPC_RMID, null);
        } else {
            self.image.*.data = null;
            if (self.image.*.f.destroy_image) |destroy_fn| {
                _ = destroy_fn(self.image);
            }
            self.allocator.free(self.pixels);
        }

        var success = false;
        var new_image: ?*c.XImage = null;
        var new_pixels: []u8 = &[_]u8{};

        if (self.use_shm) {
            new_image = c.XShmCreateImage(
                self.display,
                screen_visual,
                @intCast(screen_depth),
                c.ZPixmap,
                null,
                self.shminfo,
                new_width,
                new_height,
            );
            if (new_image) |img| {
                const size = @as(usize, @intCast(img.*.bytes_per_line)) * new_height;
                self.shminfo.shmid = c.shmget(c.IPC_PRIVATE, size, c.IPC_CREAT | 0o600);
                if (self.shminfo.shmid != -1) {
                    self.shminfo.shmaddr = @ptrCast(c.shmat(self.shminfo.shmid, null, 0));
                    if (@intFromPtr(self.shminfo.shmaddr) != @as(usize, @bitCast(@as(isize, -1)))) {
                        img.*.data = @ptrCast(self.shminfo.shmaddr);
                        self.shminfo.readOnly = 0;
                        if (c.XShmAttach(self.display, self.shminfo) != 0) {
                            _ = c.XSync(self.display, 0);
                            new_pixels = @as([*]u8, @ptrCast(img.*.data))[0..size];
                            success = true;
                        } else {
                            _ = c.shmdt(self.shminfo.shmaddr);
                            _ = c.shmctl(self.shminfo.shmid, c.IPC_RMID, null);
                        }
                    } else {
                        _ = c.shmctl(self.shminfo.shmid, c.IPC_RMID, null);
                    }
                }
                if (!success) {
                    if (img.*.f.destroy_image) |destroy_fn| {
                        _ = destroy_fn(img);
                    }
                }
            }
        }

        if (!success) {
            self.use_shm = false;
            const stride = (new_width * 4 + 3) & ~@as(u32, 3);
            new_pixels = try self.allocator.alloc(u8, @as(usize, stride) * new_height);
            @memset(new_pixels, 0);

            new_image = c.XCreateImage(
                self.display,
                screen_visual,
                @intCast(screen_depth),
                c.ZPixmap,
                0,
                @ptrCast(new_pixels.ptr),
                new_width,
                new_height,
                32,
                @intCast(stride),
            ) orelse {
                self.allocator.free(new_pixels);
                return error.XCreateImageFailed;
            };
        }

        self.pixels = new_pixels;
        self.image = new_image.?;
        self.width = new_width;
        self.height = new_height;
    }

    pub fn getFd(self: *Window) std.posix.fd_t {
        return c.ConnectionNumber(self.display);
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        _ = c.XStoreName(self.display, self.window, @ptrCast(title.ptr));
        _ = c.XFlush(self.display);
    }

    pub fn handleEvents(self: *Window, ctx: anytype, pty_write_fn: *const fn (ctx: @TypeOf(ctx), data: []const u8) void) ?Size {
        var event: c.XEvent = undefined;
        var new_size: ?Size = null;

        while (c.XPending(self.display) > 0) {
            _ = c.XNextEvent(self.display, &event);

            switch (event.type) {
                c.Expose => {
                    self.draw();
                },
                c.ConfigureNotify => {
                    const ce = event.xconfigure;
                    if (@as(u32, @intCast(ce.width)) != self.width or @as(u32, @intCast(ce.height)) != self.height) {
                        new_size = .{ .w = @intCast(ce.width), .h = @intCast(ce.height) };
                    }
                },
                c.KeyPress => {
                    self.handleKeyPress(&event.xkey, ctx, pty_write_fn);
                },
                else => {},
            }
        }
        return new_size;
    }

    fn handleKeyPress(self: *Window, key_event: *c.XKeyEvent, ctx: anytype, pty_write_fn: *const fn (ctx: @TypeOf(ctx), data: []const u8) void) void {
        _ = self;
        var keysym: c.KeySym = undefined;
        var buf: [32]u8 = undefined;
        const len = c.XLookupString(key_event, &buf, buf.len, &keysym, null);

        var mods: input.Mods = .{};
        mods.shift = (key_event.state & c.ShiftMask) != 0;
        mods.ctrl = (key_event.state & c.ControlMask) != 0;
        mods.alt = (key_event.state & c.Mod1Mask) != 0;
        mods.logo = (key_event.state & c.Mod4Mask) != 0;

        const keycode = input.Keymap.fromX11Keysym(@intCast(keysym));

        if (input.keyCodeToAnsi(keycode, mods)) |ansi_seq| {
            pty_write_fn(ctx, ansi_seq);
            return;
        }

        if (len > 0) {
            const ch = buf[0];

            if (mods.ctrl and !mods.alt and !mods.logo and len == 1) {
                if (ch >= 'a' and ch <= 'z') {
                    const ctrl_ch = ch - 'a' + 1;
                    pty_write_fn(ctx, &[_]u8{ctrl_ch});
                    return;
                }
                if (ch >= 'A' and ch <= 'Z') {
                    const ctrl_ch = ch - 'A' + 1;
                    pty_write_fn(ctx, &[_]u8{ctrl_ch});
                    return;
                }
            }

            if (mods.alt and !mods.ctrl and !mods.logo and len == 1) {
                pty_write_fn(ctx, &[_]u8{ '\x1b', ch });
                return;
            }

            pty_write_fn(ctx, buf[0..@intCast(len)]);
        } else {
            switch (keysym) {
                c.XK_Escape => pty_write_fn(ctx, "\x1b"),
                c.XK_BackSpace => pty_write_fn(ctx, "\x7f"),
                c.XK_Return => pty_write_fn(ctx, "\r"),
                c.XK_Linefeed => pty_write_fn(ctx, "\n"),
                c.XK_Tab => pty_write_fn(ctx, "\t"),
                c.XK_KP_Enter => pty_write_fn(ctx, "\r"),
                c.XK_KP_0 => pty_write_fn(ctx, "0"),
                c.XK_KP_1 => pty_write_fn(ctx, "1"),
                c.XK_KP_2 => pty_write_fn(ctx, "2"),
                c.XK_KP_3 => pty_write_fn(ctx, "3"),
                c.XK_KP_4 => pty_write_fn(ctx, "4"),
                c.XK_KP_5 => pty_write_fn(ctx, "5"),
                c.XK_KP_6 => pty_write_fn(ctx, "6"),
                c.XK_KP_7 => pty_write_fn(ctx, "7"),
                c.XK_KP_8 => pty_write_fn(ctx, "8"),
                c.XK_KP_9 => pty_write_fn(ctx, "9"),
                c.XK_KP_Decimal => pty_write_fn(ctx, "."),
                c.XK_KP_Add => pty_write_fn(ctx, "+"),
                c.XK_KP_Subtract => pty_write_fn(ctx, "-"),
                c.XK_KP_Multiply => pty_write_fn(ctx, "*"),
                c.XK_KP_Divide => pty_write_fn(ctx, "/"),
                else => {},
            }
        }
    }
};
