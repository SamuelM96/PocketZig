const std = @import("std");
const stdout = std.io.getStdOut().writer();
const Allocator = std.mem.Allocator;

const disassembler = @import("disassembler.zig");

const Commands = enum { hexdump, disassemble, emulate };

fn read_rom(allocator: Allocator, rom_path: []const u8) ![]u8 {
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

fn print_usage() !void {
    try stdout.writeAll(
        \\Usage: PocketZig <command> <rom>
        \\
        \\  <rom>           GameBoy ROM file
        \\
        \\Commands:
        \\
        \\  hexdump         Print a hexdump of a binary
        \\  disassemble     Disassemble a ROM
        \\  emulate         Emulate a ROM
        \\
    );
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    var it = try std.process.argsWithAllocator(gpa);
    defer it.deinit();
    _ = it.skip(); // ignore binary path

    const cmd_str = it.next() orelse return print_usage();
    const command = std.meta.stringToEnum(Commands, cmd_str) orelse return print_usage();
    const rom_path = it.next() orelse return print_usage();

    const rom = read_rom(gpa, rom_path) catch return;
    defer gpa.free(rom);

    switch (command) {
        .hexdump => try disassembler.hexdump(std.io.getStdOut().writer(), rom),
        .disassemble => try disassembler.disassemble(rom),
        .emulate => std.debug.print("Not implemented\n", .{}),
    }
}
