const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    // Create the root module
    const root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "vtui",
        .root_module = root_module,
    });
    exe.linkLibC();
    exe.linkSystemLibrary("X11");
    exe.linkSystemLibrary("Xext"); // For MIT-SHM support
    exe.linkSystemLibrary("fontconfig");
    exe.linkSystemLibrary("harfbuzz");

    // Try to link freetype2 if available (optional for font loading)
    _ = b.systemIntegrationOption("freetype", .{});
    exe.linkSystemLibrary2("freetype2", .{ .preferred_link_mode = .dynamic });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the Vtui engine");
    run_step.dependOn(&run_cmd.step);

    const test_sixel_exe = b.addExecutable(.{
        .name = "test-sixel-render",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/test_sixel_rendering.zig"),
        }),
    });
    test_sixel_exe.linkLibC();
    test_sixel_exe.linkSystemLibrary("X11");
    test_sixel_exe.linkSystemLibrary("Xext");
    test_sixel_exe.linkSystemLibrary("fontconfig");
    test_sixel_exe.linkSystemLibrary("harfbuzz");
    test_sixel_exe.linkSystemLibrary2("freetype2", .{ .preferred_link_mode = .dynamic });
    b.installArtifact(test_sixel_exe);

    // Create test module
    const test_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const unit_tests = b.addTest(.{
        .name = "vtui-tests",
        .root_module = test_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
