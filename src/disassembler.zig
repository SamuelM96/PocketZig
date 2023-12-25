const std = @import("std");
const testing = std.testing;

pub fn hexdump(writer: anytype, bytes: []const u8) !void {
    var ascii: [16]u8 = undefined;
    for (bytes, 0..) |byte, i| {
        if (std.ascii.isPrint(byte)) {
            ascii[i % 16] = byte;
        } else {
            ascii[i % 16] = '.';
        }

        if (i % 16 == 0) {
            try writer.print("{x:0>8}: ", .{i});
        }

        try writer.print("{x:0<2}", .{byte});

        if ((i + 1) % 2 == 0) {
            try writer.print(" ", .{});
        }

        if ((i + 1) % 16 == 0) {
            try writer.print(" {s}\n", .{ascii});
        }
    }

    // Padding spaces
    const remainder = 16 - bytes.len % 16;
    if (remainder != 16) {
        const is_odd = remainder % 2;
        for (0..remainder) |i| {
            try writer.print("{s: <2}", .{""});
            if ((i + 1 + is_odd) % 2 == 0) {
                try writer.print(" ", .{});
            }
        }
        try writer.print(" {s}\n", .{ascii[0 .. 16 - remainder]});
    }
}

test "hexdump output single line format" {
    const bytes = [_]u8{ 0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe };
    var buffer: [1024]u8 = undefined;
    var result = std.io.fixedBufferStream(&buffer);
    try hexdump(result.writer(), &bytes);

    try testing.expectEqualSlices(u8, "00000000: dead beef cafe babe                      ........\n", result.getWritten());
}

test "hexdump output multiline format" {
    const bytes = [_]u8{ 0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe, 'H', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', '!' };
    var buffer: [1024]u8 = undefined;
    var result = std.io.fixedBufferStream(&buffer);
    try hexdump(result.writer(), &bytes);

    try testing.expectEqualSlices(u8, "00000000: dead beef cafe babe 4865 6c6c 6f20 776f  ........Hello wo\n00000010: 726c 6421                                rld!\n", result.getWritten());
}

test "hexdump padding with an odd number of bytes" {
    const bytes = [_]u8{ 0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe, 0x41 };
    var buffer: [1024]u8 = undefined;
    var result = std.io.fixedBufferStream(&buffer);
    try hexdump(result.writer(), &bytes);

    try testing.expectEqualSlices(u8, "00000000: dead beef cafe babe 41                   ........A\n", result.getWritten());
}
