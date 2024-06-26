const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("common.zig");
const cpu = @import("cpu.zig");
const disassembler = @import("disassembler.zig");

const Commands = enum { hexdump, disassemble, emulate };

fn print_usage() !void {
    try std.io.getStdOut().writer().writeAll(
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

    const rom = common.read_rom(gpa, rom_path) catch return;
    defer gpa.free(rom);

    switch (command) {
        .hexdump => try disassembler.hexdump(std.io.getStdOut().writer(), rom, 0),
        .disassemble => {
            var disassembly = try disassembler.disassemble(gpa, rom, 0x0);
            defer disassembly.deinit();
            try disassembler.print_disassembly(&disassembly);
        },
        .emulate => {
            var state: cpu.State = .{
                .registers = .{},
                .memory = rom,
            };
            cpu.execute(&state);
        },
    }
}
