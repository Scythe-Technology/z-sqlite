const std = @import("std");

const THREADSAFE = enum {
    SINGLETHREAD,
    MULTITHREAD,
    SERIALIZED,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try switch (b.option(THREADSAFE, "SQLITE_THREADSAFE", "SQLITE_THREADSAFE") orelse .SINGLETHREAD) {
        .SINGLETHREAD => flags.append("-DSQLITE_THREADSAFE=0"),
        .SERIALIZED => flags.append("-DSQLITE_THREADSAFE=1"),
        .MULTITHREAD => flags.append("-DSQLITE_THREADSAFE=2"),
    };

    if (b.option(bool, "SQLITE_ENABLE_COLUMN_METADATA", "When enabled, SQLite includes some additional APIs that provide convenient access to meta-data about tables and queries.") orelse false)
        try flags.append("-DSQLITE_ENABLE_COLUMN_METADATA");

    const MAX_VARIABLE = b.option(u32, "SQLITE_MAX_VARIABLE_NUMBER", "") orelse 32766;
    try flags.append(try std.fmt.allocPrint(b.allocator, "-DSQLITE_MAX_VARIABLE_NUMBER={d}", .{MAX_VARIABLE}));

    if (b.option(bool, "SQLITE_ENABLE_DBSTAT_VTAB", "This option enables the dbstat virtual table.") orelse false)
        try flags.append("-DSQLITE_ENABLE_DBSTAT_VTAB");

    if (b.option(bool, "SQLITE_ENABLE_FTS3", "When enabled, versions 3 and 4 of the full-text search engine are added to the build automatically.") orelse false)
        try flags.append("-DSQLITE_ENABLE_FTS3");

    if (b.option(bool, "SQLITE_ENABLE_FTS3_PARENTHESIS", "This option modifies the query pattern parser in FTS3 such that it supports operators AND and NOT (in addition to the usual OR and NEAR) and also allows query expressions to contain nested parenthesis.") orelse false)
        try flags.append("-DSQLITE_ENABLE_FTS3_PARENTHESIS");

    if (b.option(bool, "SQLITE_ENABLE_FTS4", "When enabled, versions 3 and 4 of the full-text search engine are added to the build automatically.") orelse false)
        try flags.append("-DSQLITE_ENABLE_FTS4");

    if (b.option(bool, "SQLITE_ENABLE_FTS5", "When enabled, versions 5 of the full-text search engine (fts5) is added to the build automatically.") orelse false)
        try flags.append("-DSQLITE_ENABLE_FTS5");

    if (b.option(bool, "SQLITE_ENABLE_GEOPOLY", "When this option is defined in the amalgamation, the Geopoly extension is included in the build.") orelse false)
        try flags.append("-DSQLITE_ENABLE_GEOPOLY");

    if (b.option(bool, "SQLITE_ENABLE_ICU", "This option causes the International Components for Unicode or \"ICU\" extension to SQLite to be added to the build.") orelse false)
        try flags.append("-DSQLITE_ENABLE_ICU");

    if (b.option(bool, "SQLITE_ENABLE_MATH_FUNCTIONS", "This macro enables the built-in SQL math functions.") orelse false)
        try flags.append("-DSQLITE_ENABLE_MATH_FUNCTIONS");

    if (b.option(bool, "SQLITE_ENABLE_RBU", "Enable the code the implements the RBU extension.") orelse false)
        try flags.append("-DSQLITE_ENABLE_RBU");

    if (b.option(bool, "SQLITE_ENABLE_RTREE", "This option causes SQLite to include support for the R*Tree index extension.") orelse false)
        try flags.append("-DSQLITE_ENABLE_RTREE");

    if (b.option(bool, "SQLITE_ENABLE_STAT4", "This option adds additional logic to the ANALYZE command and to the query planner that can help SQLite to chose a better query plan under certain situations.") orelse false)
        try flags.append("-DSQLITE_ENABLE_STAT4");

    if (b.option(bool, "SQLITE_OMIT_DECLTYPE", "SQLITE_OMIT_DECLTYPE") orelse false)
        try flags.append("-DSQLITE_OMIT_DECLTYPE");

    if (b.option(bool, "SQLITE_OMIT_JSON", "Disable JSON1 extension.") orelse false)
        try flags.append("-DSQLITE_OMIT_JSON");

    if (b.option(bool, "SQLITE_USE_URI", "This option causes the URI filename process logic to be enabled by default.") orelse false)
        try flags.append("-DSQLITE_USE_URI");

    const lib = b.addStaticLibrary(.{
        .name = "z-sqlite-c",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.addCSourceFile(.{
        .file = b.path("src/c/sqlite3.c"),
        .flags = flags.items,
    });

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
