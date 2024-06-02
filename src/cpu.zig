const std = @import("std");
const testing = std.testing;

const HostEndianness = @import("builtin").target.cpu.arch.endian();

const Registers = switch (HostEndianness) {
    .big => Registers8BitBig,
    .little => Registers8BitLittle,
};

const Registers8BitLittle = packed struct {
    F: FlagsRegister = .{},
    A: u8 = 0,
    C: u8 = 0,
    B: u8 = 0,
    E: u8 = 0,
    D: u8 = 0,
    L: u8 = 0,
    H: u8 = 0,
    PC: u16 = 0,
    SP: u16 = 0,
};
const Registers8BitBig = packed struct {
    A: u8 = 0,
    F: FlagsRegister = 0,
    B: u8 = 0,
    C: u8 = 0,
    D: u8 = 0,
    E: u8 = 0,
    H: u8 = 0,
    L: u8 = 0,
    PC: u16 = 0,
    SP: u16 = 0,
};

const FlagsRegister = packed struct(u8) {
    _unused: u4 = 0,
    Z: bool = false, // Zero flag
    N: bool = false, // Subtraction flag (BCD)
    H: u1 = 0, // Half Carry flag (BCD)
    C: u1 = 0, // Carry flag

    inline fn from(i: u8) FlagsRegister {
        return @bitCast(i);
    }

    inline fn to(self: FlagsRegister) u8 {
        return @bitCast(self);
    }
};

const Registers16Bit = packed struct {
    AF: u16 = 0,
    BC: u16 = 0,
    DE: u16 = 0,
    HL: u16 = 0,
    PC: u16 = 0,
    SP: u16 = 0,
};

pub fn dumpRegisters(registers: Registers) void {
    std.debug.print("PC: {b:0>16}\n", .{registers.PC});
    std.debug.print("SP: {b:0>16}\n", .{registers.SP});
    std.debug.print("                ZNHC\n", .{});
    std.debug.print("A: {b:0>8}, F: {b:0>8}\n", .{ registers.A, registers.F.to() });
    std.debug.print("B: {b:0>8}, C: {b:0>8}\n", .{ registers.B, registers.C });
    std.debug.print("D: {b:0>8}, E: {b:0>8}\n", .{ registers.D, registers.E });
    std.debug.print("H: {b:0>8}, L: {b:0>8}\n", .{ registers.H, registers.L });
}

test "casting between 16-bit registers to 8-bit" {
    var registers8: Registers = .{};
    var registers16: *Registers16Bit = @ptrCast(&registers8);

    const high = 0b11101000;
    const low = 0b00100111;

    registers16.AF = (@as(u16, high) << 8) | low;

    try testing.expectEqual(registers8.A, high);
    try testing.expectEqual(registers8.F.to(), low);

    const value = switch (HostEndianness) {
        .big => 0xDEAD,
        .little => 0xADDE,
    };
    registers8.A = @truncate(value >> 8);
    registers8.F = FlagsRegister.from(@truncate(value));
    try testing.expectEqual(registers16.AF, value);
}
