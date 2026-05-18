const std = @import("std");

pub fn main() !void {
    var ring = try std.os.linux.IoUring.init(32, 0);
    defer ring.deinit();

    const sqe = try ring.get_sqe();
    sqe.prep_poll_add(0, std.posix.POLL.IN);
    sqe.user_data = 1;

    _ = try ring.submit_and_wait(1);

    const cqe = try ring.copy_cqe();
    std.debug.print("CQE res: {d}\n", .{cqe.res});
}
