const std = @import("std");
const Allocator = std.mem.Allocator;

const cpu = @import("cpu.zig");
const disassembler = @import("disassembler.zig");

const Commands = enum {
    const Self = @This();

    hexdump,
    disassemble,
    emulate,

    pub fn help(self: Self) []const u8 {
        return switch (self) {
            .hexdump => "Print a hexdump of a binary",
            .disassemble => "Disassemble a ROM",
            .emulate => "Emulate a ROM",
        };
    }
};

fn print_usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\Usage: PocketZig <command> <rom>
        \\
        \\  <rom>           GameBoy ROM file
        \\
        \\Commands:
        \\
        \\
    );
    inline for (@typeInfo(Commands).Enum.fields) |field| {
        const cmd = @field(Commands, field.name);
        try stdout.print("  {s:<12}    {s}\n", .{ field.name, cmd.help() });
    }
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

    const rom = std.fs.cwd().readFileAlloc(gpa, rom_path, std.math.maxInt(usize)) catch |err| {
        std.log.err("could not read ROM: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
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
