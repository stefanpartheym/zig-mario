const std = @import("std");

const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub fn build(b: *std.Build) void {
    const options: Options = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };

    // Dependencies
    // const foo_dep = b.dependency("foo", options);

    // Executable artifact
    const exe = b.addExecutable(.{
        .name = "zig-mario",
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    b.installArtifact(exe);

    // Add dependencies to the executable.
    // exe.root_module.addImport("foo", foo_dep.module("foo"));

    // Run executable
    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_exe.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_exe.step);

    // Unit test artifact
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });

    // Run unit tests
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
