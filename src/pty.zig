/// Vtui PTY Module - Linux PTY and process spawning
const std = @import("std");
const posix = std.posix;

const c = @cImport({
    @cInclude("pty.h");
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
    @cInclude("fcntl.h");
});

pub const winsize = extern struct {
    ws_row: u16 = 24,
    ws_col: u16 = 80,
    ws_xpixel: u16 = 0,
    ws_ypixel: u16 = 0,
};

pub const Pty = struct {
    master: posix.fd_t,
    slave: posix.fd_t,

    pub const OpenError = error{OpenFailed};

    pub fn open(size: winsize) OpenError!Pty {
        var size_copy = size;
        var master_fd: posix.fd_t = undefined;
        var slave_fd: posix.fd_t = undefined;

        if (c.openpty(&master_fd, &slave_fd, null, null, @ptrCast(&size_copy)) < 0) {
            return error.OpenFailed;
        }
        errdefer {
            posix.close(master_fd);
            posix.close(slave_fd);
        }

        const flags = posix.fcntl(master_fd, posix.F.GETFD, 0) catch 0;
        _ = posix.fcntl(master_fd, posix.F.SETFD, flags | posix.FD_CLOEXEC) catch {};

        // Set non-blocking - required for poll() loop
        const fl = posix.fcntl(master_fd, posix.F.GETFL, 0) catch 0;
        _ = posix.fcntl(master_fd, posix.F.SETFL, fl | c.O_NONBLOCK) catch {};

        // Enable UTF-8 mode in termios
        var attrs: c.termios = undefined;
        if (c.tcgetattr(master_fd, &attrs) == 0) {
            attrs.c_iflag |= c.IUTF8;
            _ = c.tcsetattr(master_fd, c.TCSANOW, &attrs);
        }

        return .{ .master = master_fd, .slave = slave_fd };
    }

    pub fn deinit(self: *Pty) void {
        posix.close(self.master);
        self.* = undefined;
    }

    pub fn getSize(self: Pty) !winsize {
        var ws: winsize = undefined;
        if (c.ioctl(self.master, c.TIOCGWINSZ, @intFromPtr(&ws)) < 0) {
            return error.IoctlFailed;
        }
        return ws;
    }

    pub fn setSize(self: *Pty, size: winsize) !void {
        if (c.ioctl(self.master, c.TIOCSWINSZ, @intFromPtr(&size)) < 0) {
            return error.IoctlFailed;
        }
    }

    pub fn childPreExec(self: Pty) !void {
        // Reset signals to default
        var sa: posix.Sigaction = .{
            .handler = .{ .handler = posix.SIG.DFL },
            .mask = posix.sigemptyset(),
            .flags = 0,
        };
        const signals = [_]u6{
            posix.SIG.HUP,
            posix.SIG.INT,
            posix.SIG.QUIT,
            posix.SIG.ILL,
            posix.SIG.TRAP,
            posix.SIG.ABRT,
            posix.SIG.BUS,
            posix.SIG.FPE,
            posix.SIG.SEGV,
            posix.SIG.PIPE,
            posix.SIG.ALRM,
            posix.SIG.TERM,
            posix.SIG.CHLD,
        };
        for (signals) |sig| {
            posix.sigaction(sig, &sa, null);
        }

        // Reset signal mask
        var mask = posix.sigemptyset();
        posix.sigprocmask(posix.SIG.SETMASK, &mask, null);

        // Create a new session
        if (c.setsid() < 0) return error.ProcessGroupFailed;

        // Set controlling terminal
        if (c.ioctl(self.slave, c.TIOCSCTTY, @as(c_int, 0)) < 0) {
            return error.SetControllingTerminalFailed;
        }

        // Close file descriptors
        posix.close(self.slave);
        posix.close(self.master);
    }
};

pub const SpawnResult = struct {
    pid: posix.pid_t,
    pty: Pty,
};

pub fn spawn(allocator: std.mem.Allocator, cmd: []const u8, args: [][:0]u8) !SpawnResult {
    var argv_strings = try std.ArrayList([:0]u8).initCapacity(allocator, args.len + 1);
    defer {
        for (argv_strings.items) |s| allocator.free(s);
        argv_strings.deinit(allocator);
    }

    const cmd_z = try allocator.dupeZ(u8, cmd);
    argv_strings.appendAssumeCapacity(cmd_z);

    for (args) |arg| {
        const arg_z = try allocator.dupeZ(u8, arg);
        argv_strings.appendAssumeCapacity(arg_z);
    }

    const argv = try allocator.alloc(?[*:0]u8, argv_strings.items.len + 1);
    defer allocator.free(argv);

    for (argv_strings.items, 0..) |s, i| {
        argv[i] = @ptrCast(s.ptr);
    }
    argv[argv_strings.items.len] = null;

    var pty = try Pty.open(.{});
    errdefer pty.deinit();

    const pid = try posix.fork();
    if (pid == 0) {
        // Child process
        _ = posix.dup2(pty.slave, posix.STDIN_FILENO) catch {};
        _ = posix.dup2(pty.slave, posix.STDOUT_FILENO) catch {};
        _ = posix.dup2(pty.slave, posix.STDERR_FILENO) catch {};

        _ = c.setenv("TERM", "xterm-256color", 1);
        _ = c.setenv("COLORTERM", "truecolor", 1);

        pty.childPreExec() catch posix.exit(1);
        _ = c.execvp(argv[0].?, @ptrCast(argv.ptr));
        posix.exit(1);
    }

    // Parent process
    // Close slave in parent after child has duplicated it
    posix.close(pty.slave);
    pty.slave = undefined;

    return .{ .pid = pid, .pty = pty };
}

pub fn read(pty: *Pty, buffer: []u8) !usize {
    return posix.read(pty.master, buffer);
}

pub fn write(pty: *Pty, data: []const u8) !usize {
    return posix.write(pty.master, data);
}

test "PTY open" {
    var pty = try Pty.open(.{});
    defer pty.deinit();
    try std.testing.expect(pty.master > 0);
}
