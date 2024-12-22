const std = @import("std");
const zemscripten = @import("zemscripten");

const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub fn build(b: *std.Build) !void {
    const options = Options{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };

    if (options.target.result.isWasm()) {
        try buildWasm(b, options);
    } else {
        try buildNative(b, options);
    }
}

fn buildNative(b: *std.Build, options: Options) !void {
    const exe = b.addExecutable(.{
        .name = "zig-mario",
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .link_libc = true,
    });
    b.installArtifact(exe);

    // Add dependencies to the executable.
    addDependencies(b, exe, options);

    // Run executable.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Declare executable tests.
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Run tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn buildWasm(b: *std.Build, options: Options) !void {
    const install_dir = "web";
    const emsdk_dep = b.dependency("emsdk", .{});

    const wasm = b.addStaticLibrary(.{
        .name = "index",
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });

    // When compiling for WASM, make sure to set `sysroot` before raylib
    // dependency is loaded.
    b.sysroot = zemscripten.emsdkPath(emsdk_dep, "");

    // Add dependencies to wasm library.
    addDependencies(b, wasm, options);
    const zemscripten_dep = b.dependency("zemscripten", .{});
    wasm.root_module.addImport("zemscripten", zemscripten_dep.module("root"));

    const shell_file_path: ?[]const u8 = if (options.optimize == .Debug)
        null
    else
        zemscripten.minimalShellFilePath(zemscripten_dep);
    var emcc_settings = zemscripten.emccDefaultSettings(b.allocator, .{ .optimize = options.optimize });
    // Raylib requires some of the following settings to be set in order to
    // successfully compile for WASM.
    try emcc_settings.put("ALLOW_MEMORY_GROWTH", "1");
    try emcc_settings.put("FULL-ES3", "1");
    try emcc_settings.put("USE_GLFW", "3");
    try emcc_settings.put("ASYNCIFY", "1");
    var emcc_step = zemscripten.emccStep(
        b,
        emsdk_dep,
        wasm,
        .{
            .optimize = options.optimize,
            .flags = zemscripten.emccDefaultFlags(b.allocator, options.optimize),
            .settings = emcc_settings,
            .use_preload_plugins = true,
            .embed_paths = &.{},
            .preload_paths = &.{},
            .install_dir = .{ .custom = install_dir },
            .shell_file_path = shell_file_path,
        },
    );

    emcc_step.dependOn(zemscripten.activateEmsdkStep(b, emsdk_dep, "3.1.70"));
    b.getInstallStep().dependOn(emcc_step);

    const emrun_step = zemscripten.emrunStep(
        b,
        emsdk_dep,
        b.getInstallPath(.{ .custom = install_dir }, "index.html"),
        &.{},
    );
    emrun_step.dependOn(emcc_step);
    b.step("emrun", "Build and open the web app locally using emrun").dependOn(emrun_step);
}

fn addDependencies(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    options: Options,
) void {
    // Dependencies
    const zalgebra_dep = b.dependency("zalgebra", options);
    const zalgebra_mod = zalgebra_dep.module("zalgebra");
    const entt_dep = b.dependency("entt", options);
    const zbox2d_dep = b.dependency("zbox2d", options);
    const raylib_dep = b.dependency("raylib-zig", options);
    const raylib_mod = raylib_dep.module("raylib");

    // Add dependencies as imports.
    artifact.root_module.addImport("zalgebra", zalgebra_mod);
    artifact.root_module.addImport("entt", entt_dep.module("zig-ecs"));
    artifact.root_module.addImport("zbox2d", zbox2d_dep.module("zbox2d"));
    artifact.root_module.addImport("raylib", raylib_mod);

    // Link libraries.
    artifact.linkLibrary(raylib_dep.artifact("raylib"));
}
