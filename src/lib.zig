// This code is based on https://github.com/nDimensional/zig-sqlite/blob/e9723002da03b46d4c9f030e2998c66a3d89cc11/src/sqlite.zig
const c = @import("c");
const std = @import("std");

/// Most of these are direct representations of SQLite errors https://sqlite.org/c3ref/c_abort.html. Some of them aren't errors; they're statuses used internally. Original descriptions are given in quotes.
pub const Error = error{
    /// "Generic error"; such as an SQL syntax error
    Error,
    /// "Internal logic error in SQLite" or zigqlite
    Internal,
    /// "Access permission denied"
    Permission,
    /// "Callback routine requested an abort"
    Abort,
    /// "The database file is locked"
    Busy,
    /// "A table in the database is locked"
    Locked,
    /// "A `malloc()` failed"
    OutOfMemory,
    /// "Attempt to write a readonly database"
    Readonly,
    /// "Operation terminated by `sqlite3_interrupt()`"
    Interrupt,
    /// "Some kind of disk I/O error occurred"
    Io,
    /// "The database disk image is malformed"
    Corrupt,
    /// "Unknown opcode in `sqlite3_file_control()`"
    NotFound,
    /// "Insertion failed because database is full"
    Full,
    /// "Unable to open the database file"
    CantOpen,
    /// "Database lock protocol error"
    Protocol,
    /// "Internal use only"
    Empty,
    /// "The database schema changed"
    Schema,
    /// "String or BLOB exceeds size limit"
    TooBig,
    /// "Abort due to constraint violation"
    Constraint,
    /// "Data type mismatch" (applies to both SQLite and zigqlite)
    Mismatch,
    /// "Library used incorrectly" (applies to both SQLite and zigqlite)
    Misuse,
    /// "Uses OS features not supported on host"
    NoLFS,
    /// "Authorization denied"
    Auth,
    /// "Not used"
    Format,
    /// "2nd parameter to `sqlite3_bind()` out of range"
    Range,
    /// "File opened that is not a database file"
    NotADB,
    /// "Notifications from `sqlite3_log()`"
    Notice,
    /// "Warnings from `sqlite3_log()`"
    Warning,
    /// "`sqlite3_step()` has another row ready"
    Row,
    /// "`sqlite3_step()` has finished executing"
    Done,
};

fn getError(err: c_int) Error {
    return switch (err) {
        c.SQLITE_ERROR => Error.Error,
        c.SQLITE_INTERNAL => Error.Internal,
        c.SQLITE_PERM => Error.Permission,
        c.SQLITE_ABORT => Error.Abort,
        c.SQLITE_BUSY => Error.Busy,
        c.SQLITE_LOCKED => Error.Locked,
        c.SQLITE_NOMEM => Error.OutOfMemory,
        c.SQLITE_READONLY => Error.Readonly,
        c.SQLITE_INTERRUPT => Error.Interrupt,
        c.SQLITE_IOERR => Error.Io,
        c.SQLITE_CORRUPT => Error.Corrupt,
        c.SQLITE_NOTFOUND => Error.NotFound,
        c.SQLITE_FULL => Error.Full,
        c.SQLITE_CANTOPEN => Error.CantOpen,
        c.SQLITE_PROTOCOL => Error.Protocol,
        c.SQLITE_EMPTY => Error.Empty,
        c.SQLITE_SCHEMA => Error.Schema,
        c.SQLITE_TOOBIG => Error.TooBig,
        c.SQLITE_CONSTRAINT => Error.Constraint,
        c.SQLITE_MISMATCH => Error.Mismatch,
        c.SQLITE_MISUSE => Error.Misuse,
        c.SQLITE_NOLFS => Error.NoLFS,
        c.SQLITE_AUTH => Error.Auth,
        c.SQLITE_FORMAT => Error.Format,
        c.SQLITE_RANGE => Error.Range,
        c.SQLITE_NOTADB => Error.NotADB,
        c.SQLITE_NOTICE => Error.Notice,
        c.SQLITE_WARNING => Error.Warning,
        c.SQLITE_ROW => Error.Row,
        c.SQLITE_DONE => Error.Done,

        else => Error.Internal,
    };
}

fn checkError(err: c_int) !void {
    if (err != c.SQLITE_OK)
        return getError(err);
}

pub const Database = struct {
    ptr: ?*c.sqlite3,
    allocator: std.mem.Allocator,

    pub const Mode = enum { ReadWrite, ReadOnly };
    pub const Options = struct {
        path: ?[*:0]const u8 = null,
        mode: Mode = .ReadWrite,
        create: bool = true,
    };

    pub fn open(allocator: std.mem.Allocator, options: Options) !Database {
        var ptr: ?*c.sqlite3 = null;

        var flags: c_int = 0;
        switch (options.mode) {
            .ReadOnly => {
                flags |= c.SQLITE_OPEN_READONLY;
            },
            .ReadWrite => {
                flags |= c.SQLITE_OPEN_READWRITE;
                if (options.create and options.path != null) {
                    flags |= c.SQLITE_OPEN_CREATE;
                }
            },
        }

        try checkError(c.sqlite3_open_v2(options.path, &ptr, flags, null));

        return .{
            .allocator = allocator,
            .ptr = ptr,
        };
    }

    /// Must not be in WAL mode. Returns a read-only in-memory database.
    pub fn import(allocator: std.mem.Allocator, data: []const u8) !Database {
        const db = try Database.open(allocator, .{ .mode = .ReadOnly });
        const ptr: [*]u8 = @constCast(data.ptr);
        const len: c_longlong = @intCast(data.len);
        const flags = c.SQLITE_DESERIALIZE_READONLY;
        try checkError(c.sqlite3_deserialize(db.ptr, "main", ptr, len, len, flags));
        return db;
    }

    pub fn close(db: Database) void {
        checkError(c.sqlite3_close_v2(db.ptr)) catch |err| {
            const msg = c.sqlite3_errmsg(db.ptr);
            std.debug.panic("sqlite3_close_v2: {s} {s}", .{ @errorName(err), msg });
        };
    }

    pub fn prepare(db: Database, sql: []const u8) !Statement {
        return try Statement.prepare(db.allocator, db, sql);
    }

    pub fn exec(db: Database, sql: []const u8, params: []const ?Value) !void {
        const stmt = try Statement.prepare(db.allocator, db, sql);
        defer stmt.deinit();

        try stmt.exec(db.allocator, params);
    }
};

pub const Value = union(enum) {
    i32: i32,
    i64: i64,
    f64: f64,
    blob: []const u8,
    text: []const u8,
};

const Statement = struct {
    ptr: ?*c.sqlite3_stmt = null,

    param_list: std.ArrayList(TypeInfo),
    column_list: std.ArrayList(TypeInfo),

    const TypeInfo = struct {
        index: usize,
        name: []const u8,
    };

    const Self = @This();

    pub fn prepare(allocator: std.mem.Allocator, db: Database, sql: []const u8) !Self {
        var stmt = Self{
            .ptr = null,
            .param_list = std.ArrayList(TypeInfo).init(allocator),
            .column_list = std.ArrayList(TypeInfo).init(allocator),
        };

        try checkError(c.sqlite3_prepare_v2(db.ptr, sql.ptr, @intCast(sql.len), &stmt.ptr, null));
        errdefer checkError(c.sqlite3_finalize(stmt.ptr)) catch |err| {
            const msg = c.sqlite3_errmsg(db.ptr);
            std.debug.panic("sqlite3_finalize: {s} {s}", .{ @errorName(err), msg });
        };

        {
            const count = c.sqlite3_bind_parameter_count(stmt.ptr);

            var idx: c_int = 1;
            while (idx <= count) : (idx += 1) {
                const parameter_name = c.sqlite3_bind_parameter_name(stmt.ptr, idx);
                if (parameter_name == null)
                    return error.InvalidParameter;

                const name = std.mem.span(parameter_name);
                if (name.len == 0) {
                    return error.InvalidParameter;
                } else switch (name[0]) {
                    ':', '$', '@' => {},
                    else => return error.InvalidParameter,
                }
                try stmt.param_list.append(.{
                    .name = name,
                    .index = @intCast(idx),
                });
            }
        }

        {
            const count = c.sqlite3_column_count(stmt.ptr);

            var n: c_int = 0;
            while (n < count) : (n += 1) {
                const column_name = c.sqlite3_column_name(stmt.ptr, n);
                if (column_name == null) {
                    return error.OutOfMemory;
                }

                const name = std.mem.span(column_name);
                try stmt.column_list.append(.{
                    .name = name,
                    .index = @intCast(n),
                });
            }
        }

        return stmt;
    }

    pub fn deinit(stmt: Self) void {
        stmt.param_list.deinit();
        stmt.column_list.deinit();

        checkError(c.sqlite3_finalize(stmt.ptr)) catch |err| {
            const db = c.sqlite3_db_handle(stmt.ptr);
            const msg = c.sqlite3_errmsg(db);
            std.debug.panic("sqlite3_finalize: {s} {s}", .{ @errorName(err), msg });
        };
    }

    pub fn reset(stmt: Self) void {
        checkError(c.sqlite3_reset(stmt.ptr)) catch |err| {
            const msg = c.sqlite3_errmsg(c.sqlite3_db_handle(stmt.ptr));
            std.debug.panic("sqlite3_reset: {s} {s}", .{ @errorName(err), msg });
        };

        checkError(c.sqlite3_clear_bindings(stmt.ptr)) catch |err| {
            const msg = c.sqlite3_errmsg(c.sqlite3_db_handle(stmt.ptr));
            std.debug.panic("sqlite3_clear_bindings: {s} {s}", .{ @errorName(err), msg });
        };
    }

    pub fn columnInfo(stmt: Self, idx: usize) !TypeInfo {
        if (idx < stmt.column_list.items.len) {
            return stmt.column_list.items[idx];
        } else return error.InvalidColumnIndex;
    }

    pub fn paramInfo(stmt: Self, idx: usize) !TypeInfo {
        if (idx < stmt.param_list.items.len) {
            return stmt.param_list.items[idx];
        } else return error.InvalidColumnIndex;
    }

    pub inline fn paramSize(stmt: Self) usize {
        return stmt.param_list.items.len;
    }

    pub inline fn columnSize(stmt: Self) usize {
        return stmt.param_list.items.len;
    }

    pub fn exec(stmt: Self, allocator: std.mem.Allocator, params: []const ?Value) !void {
        try stmt.bind(params);
        defer stmt.reset();
        if (try stmt.step(allocator)) |res|
            allocator.free(res);
    }

    pub fn step(stmt: Self, allocator: std.mem.Allocator) !?[]const ?Value {
        switch (c.sqlite3_step(stmt.ptr)) {
            c.SQLITE_ROW => return try stmt.row(allocator),
            c.SQLITE_DONE => return null,
            else => |code| {
                // sqlite3_reset returns the same code we already have
                const rc = c.sqlite3_reset(stmt.ptr);
                if (rc == code) {
                    return getError(code);
                } else {
                    const err = getError(rc);
                    const msg = c.sqlite3_errmsg(c.sqlite3_db_handle(stmt.ptr));
                    std.debug.panic("sqlite3_reset: {s} {s}", .{ @errorName(err), msg });
                }
            },
        }
    }

    pub fn bind(stmt: Self, params: []const ?Value) !void {
        if (stmt.param_list.items.len != params.len)
            return error.InvalidParameterSize;
        for (stmt.param_list.items) |info| {
            if (params[info.index - 1]) |value| {
                switch (value) {
                    .i32 => |v| try stmt.bindInt32(info.index, v),
                    .i64 => |v| try stmt.bindInt64(info.index, v),
                    .f64 => |v| try stmt.bindFloat64(info.index, v),
                    .blob => |v| try stmt.bindBlob(info.index, v),
                    .text => |v| try stmt.bindText(info.index, v),
                }
            } else try stmt.bindNull(info.index);
        }
    }

    fn bindNull(stmt: Self, idx: usize) !void {
        try checkError(c.sqlite3_bind_null(stmt.ptr, @intCast(idx)));
    }

    fn bindInt32(stmt: Self, idx: usize, value: i32) !void {
        try checkError(c.sqlite3_bind_int(stmt.ptr, @intCast(idx), value));
    }

    fn bindInt64(stmt: Self, idx: usize, value: i64) !void {
        try checkError(c.sqlite3_bind_int64(stmt.ptr, @intCast(idx), value));
    }

    fn bindFloat64(stmt: Self, idx: usize, value: f64) !void {
        try checkError(c.sqlite3_bind_double(stmt.ptr, @intCast(idx), value));
    }

    fn bindBlob(stmt: Self, idx: usize, value: []const u8) !void {
        const ptr = value.ptr;
        const len = value.len;
        try checkError(c.sqlite3_bind_blob64(stmt.ptr, @intCast(idx), ptr, @intCast(len), c.SQLITE_STATIC));
    }

    fn bindText(stmt: Self, idx: usize, value: []const u8) !void {
        const ptr = value.ptr;
        const len = value.len;
        try checkError(c.sqlite3_bind_text64(stmt.ptr, @intCast(idx), ptr, @intCast(len), c.SQLITE_STATIC, c.SQLITE_UTF8));
    }

    fn row(stmt: Self, allocator: std.mem.Allocator) ![]?Value {
        var result: []?Value = try allocator.alloc(?Value, stmt.column_list.items.len);

        for (stmt.column_list.items) |info| {
            const idx = info.index;
            switch (c.sqlite3_column_type(stmt.ptr, @intCast(idx))) {
                c.SQLITE_NULL => result[idx] = null,
                c.SQLITE_INTEGER => result[idx] = .{ .i64 = stmt.columnInt64(idx) },
                c.SQLITE_FLOAT => result[idx] = .{ .f64 = stmt.columnFloat64(idx) },
                c.SQLITE_BLOB => result[idx] = .{ .blob = stmt.columnBlob(idx) },
                c.SQLITE_TEXT => result[idx] = .{ .text = stmt.columnText(idx) },
                else => @panic("internal SQLite error"),
            }
        }

        return result;
    }

    inline fn columnInt32(stmt: Self, n: usize) i32 {
        return c.sqlite3_column_int(stmt.ptr, @intCast(n));
    }

    inline fn columnInt64(stmt: Self, n: usize) i64 {
        return c.sqlite3_column_int64(stmt.ptr, @intCast(n));
    }

    inline fn columnFloat64(stmt: Self, n: usize) f64 {
        return c.sqlite3_column_double(stmt.ptr, @intCast(n));
    }

    fn columnBlob(stmt: Self, n: usize) []const u8 {
        const ptr: [*]const u8 = @ptrCast(c.sqlite3_column_blob(stmt.ptr, @intCast(n)));
        const len = c.sqlite3_column_bytes(stmt.ptr, @intCast(n));
        if (len < 0) {
            std.debug.panic("sqlite3_column_bytes: len < 0", .{});
        }
        return ptr[0..@intCast(len)];
    }

    fn columnText(stmt: Self, n: usize) []const u8 {
        const ptr: [*]const u8 = @ptrCast(c.sqlite3_column_text(stmt.ptr, @intCast(n)));
        const len = c.sqlite3_column_bytes(stmt.ptr, @intCast(n));
        if (len < 0) {
            std.debug.panic("sqlite3_column_bytes: len < 0", .{});
        }
        return ptr[0..@intCast(len)];
    }
};

test "Open/Close (memory)" {
    const db = try Database.open(std.testing.allocator, .{});
    defer db.close();
}

test "Insert" {
    const allocator = std.testing.allocator;

    const db = try Database.open(allocator, .{});
    defer db.close();

    try db.exec("CREATE TABLE users(id TEXT PRIMARY KEY, age FLOAT)", &.{});

    {
        const insert = try db.prepare("INSERT INTO users VALUES (:id, :age)");
        defer insert.deinit();

        try insert.exec(allocator, &.{ .{ .text = "a" }, .{ .f64 = 5 } });
        try insert.exec(allocator, &.{ .{ .text = "b" }, .{ .f64 = 7 } });
        try insert.exec(allocator, &.{ .{ .text = "c" }, null });
    }

    {
        const select = try db.prepare("SELECT id, age FROM users");
        defer select.deinit();

        try select.bind(&.{});
        defer select.reset();

        if (try select.step(allocator)) |user| {
            defer allocator.free(user);
            try std.testing.expectEqualSlices(u8, "a", user[0].?.text);
            try std.testing.expectEqual(5, user[1].?.f64);
        } else try std.testing.expect(false);

        if (try select.step(allocator)) |user| {
            defer allocator.free(user);
            try std.testing.expectEqualSlices(u8, "b", user[0].?.text);
            try std.testing.expectEqual(7, user[1].?.f64);
        } else try std.testing.expect(false);

        if (try select.step(allocator)) |user| {
            defer allocator.free(user);
            try std.testing.expectEqualSlices(u8, "c", user[0].?.text);
            try std.testing.expect(user[1] == null);
        } else try std.testing.expect(false);

        try std.testing.expectEqual(null, try select.step(allocator));
    }
}

test "Count" {
    const allocator = std.testing.allocator;

    const db = try Database.open(allocator, .{});
    defer db.close();

    try db.exec("CREATE TABLE users(id TEXT PRIMARY KEY, age FLOAT)", &.{});
    try db.exec("INSERT INTO users VALUES(\"a\", 21)", &.{});
    try db.exec("INSERT INTO users VALUES(\"b\", 23)", &.{});
    try db.exec("INSERT INTO users VALUES(\"c\", NULL)", &.{});

    {
        const select = try db.prepare("SELECT age FROM users");
        defer select.deinit();

        try select.bind(&.{});
        defer select.reset();

        const res = (try select.step(allocator)) orelse return try std.testing.expect(false);
        defer allocator.free(res);

        try std.testing.expectEqualStrings("age", (try select.columnInfo(0)).name);
        try std.testing.expectEqual(21, res[0].?.f64);
    }

    {
        const select = try db.prepare("SELECT count(*) as count FROM users");
        defer select.deinit();

        try select.bind(&.{});
        defer select.reset();

        const res = (try select.step(allocator)) orelse return try std.testing.expect(false);
        defer allocator.free(res);

        try std.testing.expectEqualStrings("count", (try select.columnInfo(0)).name);
        try std.testing.expectEqual(3, res[0].?.i64);
    }
}

test "Example" {
    const allocator = std.testing.allocator;

    const db = try Database.open(allocator, .{});
    defer db.close();

    try db.exec("CREATE TABLE users (id TEXT PRIMARY KEY, age FLOAT)", &.{});

    const insert = try db.prepare("INSERT INTO users VALUES (:id, :age)");
    defer insert.deinit();

    try insert.exec(allocator, &.{ .{ .text = "a" }, .{ .f64 = 21 } });
    try insert.exec(allocator, &.{ .{ .text = "b" }, .{ .f64 = 20 } });
    try insert.exec(allocator, &.{ .{ .text = "c" }, null });

    const select = try db.prepare("SELECT * FROM users WHERE age >= :min");
    defer select.deinit();

    // Get a single row
    {
        try select.bind(&.{.{ .f64 = 0 }});
        defer select.reset();

        if (try select.step(allocator)) |res| {
            defer allocator.free(res);
            // user.id: sqlite.Text
            // user.age: ?f32
            std.log.info("{s} age: {any}", .{ res[0].?.text, res[1] });
        }
    }

    // Iterate over all rows
    {
        try select.bind(&.{.{ .f64 = 0 }});
        defer select.reset();

        while (try select.step(allocator)) |res| {
            defer allocator.free(res);
            std.log.info("{s} age: {any}", .{ res[0].?.text, res[1] });
        }
    }

    // Iterate again, with different params
    {
        try select.bind(&.{.{ .f64 = 21 }});
        defer select.reset();

        while (try select.step(allocator)) |res| {
            defer allocator.free(res);
            std.log.info("{s} age: {any}", .{ res[0].?.text, res[1] });
        }
    }
}

fn open(allocator: std.mem.Allocator, dir: std.fs.Dir, name: []const u8) !Database {
    const path_dir = try dir.realpathAlloc(allocator, ".");
    defer allocator.free(path_dir);

    const path_file = try std.fs.path.joinZ(allocator, &.{ path_dir, name });
    defer allocator.free(path_file);

    return try Database.open(allocator, .{ .path = path_file });
}
test "Deserialize" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db1 = try open(allocator, tmp.dir, "db.sqlite");
    defer db1.close();

    try db1.exec("CREATE TABLE users (id INTEGER PRIMARY KEY)", &.{});
    try db1.exec("INSERT INTO users VALUES (:id)", &.{.{ .i64 = 0 }});
    try db1.exec("INSERT INTO users VALUES (:id)", &.{.{ .i64 = 1 }});

    const file = try tmp.dir.openFile("db.sqlite", .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 4096 * 8);
    defer allocator.free(data);

    const db2 = try Database.import(allocator, data);
    defer db2.close();

    var rows = std.ArrayList(?Value).init(allocator);
    defer rows.deinit();

    const stmt = try db2.prepare("SELECT id FROM users");
    defer stmt.deinit();

    try stmt.bind(&.{});
    defer stmt.reset();

    while (try stmt.step(allocator)) |row| {
        defer allocator.free(row);
        try rows.append(row[0]);
    }

    try std.testing.expectEqual(2, rows.items.len);
    try std.testing.expectEqual(0, rows.items[0].?.i64);
    try std.testing.expectEqual(1, rows.items[1].?.i64);
}
