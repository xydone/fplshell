const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("fplshell", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const tls = b.dependency("tls", .{
        .target = target,
        .optimize = optimize,
    });

    module.addImport("vaxis", vaxis.module("vaxis"));

    module.addImport("tls", tls.module("tls"));

    const exe = b.addExecutable(.{
        .name = "fplshell",
        .root_module = module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    const exe_unit_tests = b.addTest(.{
        .root_module = module,
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Test code with custom test runner");
    test_step.dependOn(&run_exe_unit_tests.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // add args
    if (b.args) |args| {
        run_cmd.addArgs(args);
        run_exe_unit_tests.addArgs(args);
    }
    const exe_check = b.addExecutable(.{
        .name = "fplshell",
        .root_module = module,
    });

    const check = b.step("check", "Check if fplshell compiles");

    check.dependOn(&exe_check.step);
}
