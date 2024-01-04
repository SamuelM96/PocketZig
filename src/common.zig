const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn read_rom(allocator: Allocator, rom_path: []const u8) ![]u8 {
    const file = std.fs.cwd().openFile(rom_path, .{}) catch |err| {
        std.log.err("could not open file: {s}\n", .{@errorName(err)});
        return err;
    };
    defer file.close();

    return file.readToEndAlloc(allocator, 1_000_000_000) catch |err| {
        std.log.err("could not read file: {s}\n", .{@errorName(err)});
        return err;
    };
}
