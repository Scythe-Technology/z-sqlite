const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "z-sqlite-c",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.addCSourceFile(.{ .file = b.path("src/c/sqlite3.c") });

    b.installArtifact(lib);

    const headers = b.addTranslateC(.{
        .root_source_file = b.path("src/c/sqlite3.h"),
        .target = target,
        .optimize = optimize,
    });
    const c_module = headers.createModule();

    c_module.linkLibrary(lib);

    const module = b.addModule("z-sqlite", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("c", c_module);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("c", c_module);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
