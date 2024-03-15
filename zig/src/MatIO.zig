const std = @import("std");
const builtin = std.builtin;
const fs = std.fs;
const debug = std.debug;
const testing = std.testing;

pub fn MatIO(comptime T: type) type {
    const info: builtin.Type = @typeInfo(T);

    const head_0: comptime_int = switch (info) {
        .Int => switch (info.Int.signedness) {
            .signed => 'I', // 73
            .unsigned => 'U', // 85
        },
        .Float => 'F', // 70
        else => @compileError("MatIO( " ++ @typeName(T) ++ " ) is not supported."),
    };

    const head_1: comptime_int = switch (info) {
        .Int => info.Int.bits,
        .Float => info.Float.bits,
        else => unreachable,
    };

    return struct {
        header: [7]u8,

        fn init() @This() {
            return .{
                .header = .{ head_0, head_1, 0x00, 0x00, 0x00, 0x00, 0x0a },
            };
        }
    };
}

test "MatIO" {
    {
        const io = MatIO(u16).init();
        try testing.expectEqual(io.header[0], 85);
        try testing.expectEqual(io.header[1], 16);
    }
    {
        const io = MatIO(i32).init();
        try testing.expectEqual(io.header[0], 73);
        try testing.expectEqual(io.header[1], 32);
    }
    {
        const io = MatIO(f64).init();
        try testing.expectEqual(io.header[0], 70);
        try testing.expectEqual(io.header[1], 64);
    }
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
