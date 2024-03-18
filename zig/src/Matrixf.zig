const std = @import("std");
const File = std.fs.File;

fn charOfHead(comptime T: type) comptime_int {
    const info: std.builtin.Type = comptime @typeInfo(T);
    return switch (info) {
        .Float => 'F', // 70
        .Int => switch (info.Int.signedness) {
            .signed => 'I', // 73
            .unsigned => 'U', // 85
        },
        else => @compileError("Invalid type: " ++ @typeName(T)),
    };
}

fn charOfBits(comptime T: type) comptime_int {
    const info: std.builtin.Type = comptime @typeInfo(T);
    return switch (info) {
        .Float => info.Float.bits,
        .Int => info.Int.bits,
        else => unreachable,
    };
}

const MatInfo = struct {
    nrow: usize,
    ncol: usize,
};

const ReadError = error{
    HeaderFormatError,
    BuffTypeError,
    BuffSizeError,
    ReadRowError,
};

pub fn Matrixf(comptime T: type) type {
    const head: comptime_int = comptime charOfHead(T);
    const bits: comptime_int = comptime charOfBits(T);
    const size: comptime_int = comptime @sizeOf(T);

    return struct {
        header: [7]u8 = undefined,

        fn writeRow(data: []T, file: *const File, bytes: usize) !void {
            const ptr: [*]u8 = @ptrCast(@alignCast(data.ptr));
            try file.writeAll(ptr[0..bytes]);
            return;
        }

        fn writeMat(self: *@This(), file: *const File, data: [][]T, nrow: u16, ncol: u16) !void {
            inline for (&self.header, .{
                head,
                bits,
                @as(u8, @truncate(nrow >> 8)),
                @as(u8, @truncate(nrow)),
                @as(u8, @truncate(ncol >> 8)),
                @as(u8, @truncate(ncol)),
                0x0a,
            }) |*ptr, val| ptr.* = val;

            try file.writeAll(&self.header);

            const bytes: usize = size * ncol;
            for (data) |row| try writeRow(row, file, bytes);
            return;
        }

        fn checkBuffer(buff: [][]T) !MatInfo {
            const nrow: usize = buff.len;
            const ncol: usize = buff[0].len;

            for (1..nrow) |i| if (buff[i].len != ncol) return error.BuffSizeError;

            return .{ .nrow = nrow, .ncol = ncol };
        }

        fn checkHeader(header: *[7]u8, file: *const File, info: *const MatInfo) !void {
            const read: usize = try file.readAll(header);
            if (read != 7 or header[6] != 0x0a) return error.HeaderFormatError;

            if (header[0] != head or header[1] != bits) return error.BuffTypeError;

            const nrow: u16 = (@as(u16, header[2]) << 8) | header[3];
            if (nrow != info.nrow) return error.BuffSizeError;

            const ncol: u16 = (@as(u16, header[4]) << 8) | header[5];
            if (ncol != info.ncol) return error.BuffSizeError;

            return;
        }

        // This function can be spawned by threads.
        fn readRow(buff: []T, file: *const File, bytes: usize) !void {
            const ptr: [*]u8 = @ptrCast(@alignCast(buff.ptr));
            if (file.readAll(ptr[0..bytes])) |read| {
                if (read != bytes) return error.ReadRowError;
            } else |err| return err;
            return;
        }

        // This function can utilize multithreading.
        fn readMat(self: *@This(), buff: [][]T, file: *const File) !void {
            const info: MatInfo = try checkBuffer(buff);
            try checkHeader(&self.header, file, &info);
            // if (try file.getPos() != 7) unreachable;
            const bytes: usize = size * info.ncol;
            for (buff) |row| try readRow(row, file, bytes);
            return;
        }
    };
}

test "MatrixIO" {
    const nrow: comptime_int = 4;
    const ncol: comptime_int = 3;
    const size: comptime_int = nrow * ncol * @sizeOf(f64) + nrow * 2 * @sizeOf(usize);
    const page: std.mem.Allocator = std.testing.allocator;

    const buff_ex: []u8 = try page.alloc(u8, size);
    errdefer page.free(buff_ex);
    defer page.free(buff_ex);

    var fba_ex = std.heap.FixedBufferAllocator.init(buff_ex);
    const allocator_ex: std.mem.Allocator = fba_ex.allocator();

    const exported: [][]f64 = blk: {
        const tmp: [][]f64 = try allocator_ex.alloc([]f64, nrow);
        for (tmp) |*row| row.* = try allocator_ex.alloc(f64, ncol);
        break :blk tmp;
    };

    inline for (exported[0], .{ 4.0, 3.0, 1.0 }) |*ptr, val| ptr.* = val;
    inline for (exported[1], .{ 3.0, 7.0, 0.0 }) |*ptr, val| ptr.* = val;
    inline for (exported[2], .{ 2.0, 5.0, 3.0 }) |*ptr, val| ptr.* = val;
    inline for (exported[3], .{ 1.0, 1.0, 2.0 }) |*ptr, val| ptr.* = val;

    const file = try std.fs.cwd().createFile(
        "junk_file.mat",
        .{ .read = true },
    );

    var io: Matrixf(f64) = .{};
    try io.writeMat(&file, exported, 4, 3);

    const buff_im: []u8 = try page.alloc(u8, size);
    errdefer page.free(buff_im);
    defer page.free(buff_im);

    var fba_im = std.heap.FixedBufferAllocator.init(buff_im);
    const allocator_im: std.mem.Allocator = fba_im.allocator();

    const imported: [][]f64 = blk: {
        const tmp: [][]f64 = try allocator_im.alloc([]f64, nrow);
        for (tmp) |*row| row.* = try allocator_im.alloc(f64, ncol);
        break :blk tmp;
    };

    try file.seekTo(0);
    try io.readMat(imported, &file);

    for (exported, imported, 0..) |row_ex, row_im, i| {
        for (row_ex, row_im, 0..) |val_ex, val_im, j| {
            std.testing.expectEqual(val_ex, val_im) catch |err| {
                std.debug.print(
                    "{any} @ ({d}, {d}): val_ex = {d} vs. val_im = {d}\n",
                    .{ err, i, j, val_ex, val_im },
                );
            };
        }
    }
}
