const std = @import("std");

const disassembler = @import("disassembler.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    const file = std.fs.cwd().openFile("test-roms/DMG_ROM.bin", .{}) catch |err| {
        std.log.err("could not open file: {s}\n", .{@errorName(err)});
        return;
    };
    defer file.close();

    const bytes = file.readToEndAlloc(gpa, 100000000) catch |err| {
        std.log.err("could not read file: {s}\n", .{@errorName(err)});
        return;
    };
    defer gpa.free(bytes);

    try disassembler.hexdump(std.io.getStdOut().writer(), bytes);
}
