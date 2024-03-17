const std = @import("std");
const builtin = std.builtin;
const fs = std.fs;
const debug = std.debug;
const testing = std.testing;

const File = std.fs.File;

const Array = @import("./array.zig").Array;

const MatrixIO = struct {
    header: [7]u8 = undefined,

    fn getHeadChar(comptime T: type) comptime_int {
        const info: builtin.Type = comptime @typeInfo(T);
        return switch (info) {
            .Float => 'F', // 70
            .Int => switch (info.Int.signedness) {
                .signed => 'I', // 73
                .unsigned => 'U', // 85
            },
            else => @compileError("Invalid type: " ++ @typeName(T)),
        };
    }

    fn getBitsChar(comptime T: type) comptime_int {
        const info: builtin.Type = comptime @typeInfo(T);
        return switch (info) {
            .Float => info.Float.bits,
            .Int => info.Int.bits,
            else => unreachable,
        };
    }

    fn writeRow(
        // self: *MatrixIO,
        comptime T: type,
        data: []T,
        size: usize,
        file: *const File,
    ) !void {
        const ptr: [*]u8 = @ptrCast(@alignCast(data.ptr));
        try file.writeAll(ptr[0..size]);
        return;
    }

    fn write(
        self: *MatrixIO,
        comptime T: type,
        nrow: u16,
        ncol: u16,
        data: [][]T,
        file: *const File,
    ) !void {
        const head: comptime_int = comptime getHeadChar(T);
        const bits: comptime_int = comptime getBitsChar(T);
        const size: comptime_int = comptime @sizeOf(T);

        self.header[0] = head;
        self.header[1] = bits;
        self.header[2] = @truncate(nrow >> 4);
        self.header[3] = @truncate(nrow & 0xff);
        self.header[4] = @truncate(ncol >> 4);
        self.header[5] = @truncate(ncol & 0xff);
        self.header[6] = 0x0a;

        try file.writeAll(&self.header);

        const bytes: usize = size * ncol;
        for (data) |row| try writeRow(T, row, bytes, file);
        return;
    }

    const ReadError = error{
        HeaderFormatMismatch,
        BufferTypeMismatch,
        BufferSizeMismatch,
        ReadRowFail,
    };

    // This function can be spawned by threads.
    fn readRow(
        // self: *MatrixIO,
        comptime T: type,
        buff: []T,
        size: usize,
        file: File,
    ) !void {
        const ptr: [*]u8 = @ptrCast(@alignCast(buff.ptr));
        if (file.readAll(ptr[0..size])) |bytes_read| {
            if (bytes_read != size) return ReadError.ReadRowFail;
        } else |err| return err;
        return;
    }

    // This function can utilize multithreading.
    fn read(
        self: *MatrixIO,
        comptime T: type,
        // buff: [][]T,
        file: File,
    ) !void {
        {
            const temp: usize = try file.readAll(&self.header);
            if (temp != 7 or self.header[6] != 0x0a) {
                return ReadError.HeaderFormatMismatch;
            }
        }

        const head: comptime_int = comptime getHeadChar(T);
        const bits: comptime_int = comptime getBitsChar(T);

        if (self.header[0] != head or self.header[1] != bits) {
            return ReadError.BufferTypeMismatch;
        }
    }
};

test "MatrixIO" {
    const ArrF64: Array = .{ .allocator = std.testing.allocator };
    const mat: [][]f64 = try ArrF64.matrix(4, 3);
    errdefer ArrF64.free(mat);

    inline for (.{ 4.0, 3.0, 1.0 }, mat[0]) |v, *p| p.* = v;
    inline for (.{ 3.0, 7.0, 0.0 }, mat[1]) |v, *p| p.* = v;
    inline for (.{ 2.0, 5.0, 3.0 }, mat[2]) |v, *p| p.* = v;
    inline for (.{ 1.0, 1.0, 2.0 }, mat[3]) |v, *p| p.* = v;

    const file = try std.fs.cwd().createFile(
        "junk_file.mat",
        .{ .read = true },
    );

    defer {
        ArrF64.free(mat);
        file.close();
    }

    var io: MatrixIO = .{};
    try io.write(f64, 4, 3, mat, &file);
}

test "write file" {
    const file = try std.fs.cwd().createFile(
        "junk_file.mat",
        .{ .read = true },
    );
    defer file.close();

    var header: [7]u8 = undefined;
    header[0] = 'F';
    header[1] = 0x40;
    header[2] = 0x00;
    header[3] = 0x02;
    header[4] = 0x00;
    header[5] = 0x03;
    header[6] = 0x0a;

    try file.writeAll(&header);
    // const bytes_write = try file.write(&header);
    // const max_count = switch (builtin.os.tag) {
    //     .linux => 0x7ffff000,
    //     .macos, .ios, .watchos, .tvos => math.maxInt(i32),
    //     else => math.maxInt(isize),
    // };
    // while (true) {
    //     const rc = system.write(fd, bytes.ptr, @min(bytes.len, max_count));

    const dat_size: comptime_int = 16;

    const dat_write: []f64 = try testing.allocator.alloc(f64, dat_size);
    errdefer testing.allocator.free(dat_write);
    defer testing.allocator.free(dat_write);

    for (dat_write, 0..) |*p, i| p.* = 1.01 * @as(f64, @floatFromInt(i));
    {
        const ptr: [*]u8 = @ptrCast(@alignCast(dat_write.ptr));
        try file.writeAll(ptr[0 .. @sizeOf(f64) * dat_size]);
    }

    var buffer: [7]u8 = undefined;
    try file.seekTo(0);
    const bytes_read = try file.readAll(&buffer);
    // const bytes_read = try file.read(&buffer);
    // const max_count = switch (builtin.os.tag) {
    //     .linux => 0x7ffff000,
    //     .macos, .ios, .watchos, .tvos => math.maxInt(i32),
    //     else => math.maxInt(isize),
    // };
    // while (true) {
    //     const rc = system.read(fd, buf.ptr, @min(buf.len, max_count));

    try testing.expectEqual(7, bytes_read);
    try testing.expect(std.mem.eql(u8, &header, &buffer));

    const dat_read: []f64 = try testing.allocator.alloc(f64, dat_size);
    errdefer testing.allocator.free(dat_read);
    defer testing.allocator.free(dat_read);

    {
        const ptr: [*]u8 = @ptrCast(@alignCast(dat_read.ptr));
        _ = try file.readAll(ptr[0 .. @sizeOf(f64) * dat_size]);
    }

    try testing.expect(std.mem.eql(f64, dat_write, dat_read));
}
