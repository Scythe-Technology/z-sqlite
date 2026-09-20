const std = @import("std");

const THREADSAFE = enum {
    SINGLETHREAD,
    MULTITHREAD,
    SERIALIZED,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var flags: std.ArrayList([]const u8) = .empty;
    defer flags.deinit(b.allocator);

    try switch (b.option(THREADSAFE, "SQLITE_THREADSAFE", "SQLITE_THREADSAFE") orelse .SINGLETHREAD) {
        .SINGLETHREAD => flags.append(b.allocator, "-DSQLITE_THREADSAFE=0"),
        .SERIALIZED => flags.append(b.allocator, "-DSQLITE_THREADSAFE=1"),
        .MULTITHREAD => flags.append(b.allocator, "-DSQLITE_THREADSAFE=2"),
    };

    if (b.option(bool, "SQLITE_ENABLE_COLUMN_METADATA", "When enabled, SQLite includes some additional APIs that provide convenient access to meta-data about tables and queries.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_COLUMN_METADATA");

    if (b.option(bool, "SQLITE_OMIT_LOAD_EXTENSION", "When enabled, the load_extension() SQL function is omitted from the build.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_OMIT_LOAD_EXTENSION");

    if (b.option(bool, "SQLITE_OMIT_DEPRECATED", "When enabled, deprecated SQLite features are omitted from the build.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_OMIT_DEPRECATED");

    if (b.option(bool, "SQLITE_OMIT_TRACE", "When enabled, the trace() SQL function is omitted from the build.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_OMIT_TRACE");

    if (b.option(bool, "SQLITE_OMIT_COMPILEOPTION_DIAGS", "When enabled, the compile option diagnostics are omitted from the build.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_OMIT_COMPILEOPTION_DIAGS");

    const MAX_VARIABLE = b.option(u32, "SQLITE_MAX_VARIABLE_NUMBER", "") orelse 32766;
    try flags.append(b.allocator, try std.fmt.allocPrint(b.allocator, "-DSQLITE_MAX_VARIABLE_NUMBER={d}", .{MAX_VARIABLE}));

    if (b.option(bool, "SQLITE_ENABLE_DBSTAT_VTAB", "This option enables the dbstat virtual table.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_DBSTAT_VTAB");

    if (b.option(bool, "SQLITE_ENABLE_FTS3", "When enabled, versions 3 and 4 of the full-text search engine are added to the build automatically.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_FTS3");

    if (b.option(bool, "SQLITE_ENABLE_FTS3_PARENTHESIS", "This option modifies the query pattern parser in FTS3 such that it supports operators AND and NOT (in addition to the usual OR and NEAR) and also allows query expressions to contain nested parenthesis.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_FTS3_PARENTHESIS");

    if (b.option(bool, "SQLITE_ENABLE_FTS4", "When enabled, versions 3 and 4 of the full-text search engine are added to the build automatically.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_FTS4");

    if (b.option(bool, "SQLITE_ENABLE_FTS5", "When enabled, versions 5 of the full-text search engine (fts5) is added to the build automatically.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_FTS5");

    if (b.option(bool, "SQLITE_ENABLE_GEOPOLY", "When this option is defined in the amalgamation, the Geopoly extension is included in the build.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_GEOPOLY");

    if (b.option(bool, "SQLITE_ENABLE_ICU", "This option causes the International Components for Unicode or \"ICU\" extension to SQLite to be added to the build.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_ICU");

    if (b.option(bool, "SQLITE_ENABLE_MATH_FUNCTIONS", "This macro enables the built-in SQL math functions.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_MATH_FUNCTIONS");

    if (b.option(bool, "SQLITE_ENABLE_RBU", "Enable the code the implements the RBU extension.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_RBU");

    if (b.option(bool, "SQLITE_ENABLE_RTREE", "This option causes SQLite to include support for the R*Tree index extension.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_RTREE");

    if (b.option(bool, "SQLITE_ENABLE_STAT4", "This option adds additional logic to the ANALYZE command and to the query planner that can help SQLite to chose a better query plan under certain situations.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_ENABLE_STAT4");

    if (b.option(bool, "SQLITE_OMIT_DECLTYPE", "SQLITE_OMIT_DECLTYPE") orelse false)
        try flags.append(b.allocator, "-DSQLITE_OMIT_DECLTYPE");

    if (b.option(bool, "SQLITE_OMIT_JSON", "Disable JSON1 extension.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_OMIT_JSON");

    if (b.option(bool, "SQLITE_USE_URI", "This option causes the URI filename process logic to be enabled by default.") orelse false)
        try flags.append(b.allocator, "-DSQLITE_USE_URI");

    const headers = b.addTranslateC(.{
        .root_source_file = b.path("src/c/sqlite3.h"),
        .target = target,
        .optimize = optimize,
    });
    const c_module = headers.createModule();

    const sqlite3_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sqlite3_mod.addCSourceFile(.{
        .file = b.path("src/c/sqlite3.c"),
        .flags = flags.items,
    });
    const sqlite3_lib = b.addLibrary(.{
        .name = "sqlite3",
        .root_module = sqlite3_mod,
    });

    const mod = b.addModule("root", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("c", c_module);
    mod.linkLibrary(sqlite3_lib);

    b.installArtifact(sqlite3_lib);

    const unit_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
