/// Vtui Async I/O Module - io_uring based async I/O
const std = @import("std");
const posix = std.posix;

pub const IoUring = struct {
    ring: std.os.linux.IoUring,
    allocator: std.mem.Allocator,

    pub fn init(entries: u32, flags: u32) !IoUring {
        const ring = try std.os.linux.IoUring.init(@intCast(entries), flags);
        return IoUring{
            .ring = ring,
            .allocator = std.heap.page_allocator,
        };
    }

    pub fn deinit(self: *IoUring) void {
        self.ring.deinit();
    }

    /// Submit a poll operation for a file descriptor
    pub fn pollAdd(self: *IoUring, fd: posix.fd_t, events: u32, user_data: u64) !void {
        const sqe = try self.ring.get_sqe();
        sqe.prep_poll_add(@intCast(fd), events);
        sqe.user_data = user_data;
    }

    /// Submit a read operation
    pub fn read(self: *IoUring, fd: posix.fd_t, buffer: []u8, offset: u64, user_data: u64) !void {
        const sqe = try self.ring.get_sqe();
        sqe.prep_read(@intCast(fd), buffer, offset);
        sqe.user_data = user_data;
    }

    /// Submit a write operation
    pub fn write(self: *IoUring, fd: posix.fd_t, buffer: []const u8, offset: u64, user_data: u64) !void {
        const sqe = try self.ring.get_sqe();
        sqe.prep_write(@intCast(fd), buffer, offset);
        sqe.user_data = user_data;
    }

    /// Submit pending operations and wait for completion
    pub fn submitAndWait(self: *IoUring, min_completions: u32) !usize {
        const res = try self.ring.submit_and_wait(min_completions);
        return @intCast(res);
    }

    /// Get a completion queue entry
    pub fn copyCqe(self: *IoUring) !std.os.linux.io_uring_cqe {
        return self.ring.copy_cqe();
    }

    /// Try to get a completion queue entry without blocking
    pub fn peekCqe(self: *IoUring) ?std.os.linux.io_uring_cqe {
        if (self.ring.cq_ready() > 0) {
            return self.ring.copy_cqe() catch null;
        }
        return null;
    }

    /// Wait for a specific user_data completion
    pub fn waitCqe(self: *IoUring, user_data: u64) !std.os.linux.io_uring_cqe {
        while (true) {
            if (self.peekCqe()) |cqe| {
                if (cqe.user_data == user_data) {
                    return cqe;
                }
            }
            _ = try self.submitAndWait(1);
        }
    }
};

/// Async I/O context for PTY operations
pub const AsyncPty = struct {
    pty_fd: posix.fd_t,
    ring: IoUring,
    read_buffer: []u8,
    read_user_data: u64 = 1,
    write_user_data: u64 = 2,

    pub fn init(pty_fd: posix.fd_t, buffer_size: usize) !AsyncPty {
        var ring = try IoUring.init(32, 0);
        errdefer ring.deinit();

        const buffer = try std.heap.page_allocator.alloc(u8, buffer_size);

        return AsyncPty{
            .pty_fd = pty_fd,
            .ring = ring,
            .read_buffer = buffer,
        };
    }

    pub fn deinit(self: *AsyncPty) void {
        self.ring.deinit();
        std.heap.page_allocator.free(self.read_buffer);
    }

    /// Start an async read operation
    pub fn startRead(self: *AsyncPty) !void {
        try self.ring.pollAdd(self.pty_fd, posix.POLL.IN, self.read_user_data);
    }

    /// Check for available data and read it
    pub fn tryRead(self: *AsyncPty) !?usize {
        if (self.ring.peekCqe()) |cqe| {
            if (cqe.user_data == self.read_user_data and cqe.res > 0) {
                // Data is available, read it
                const n = posix.read(self.pty_fd, self.read_buffer) catch 0;
                // Re-queue the poll for next read
                try self.ring.pollAdd(self.pty_fd, posix.POLL.IN, self.read_user_data);
                return @intCast(n);
            }
        }
        return null;
    }

    /// Write data to PTY (synchronous for simplicity)
    pub fn write(self: *AsyncPty, data: []const u8) !usize {
        return posix.write(self.pty_fd, data);
    }

    /// Get the read buffer
    pub fn getReadBuffer(self: *AsyncPty) []u8 {
        return self.read_buffer;
    }
};
