const std = @import("std");
const testing = std.testing;

pub const State = struct {
    registers: Registers,
    memory: []u8,
};

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

const R8 = enum(u3) { B, C, D, E, H, L, HL, A };
const R16 = enum(u2) { BC, DE, HL, SP };
const R16Stk = enum(u2) { BC, DE, HL, AF };
const R16Mem = enum(u2) { BC, DE, HLI, HLD };
const Cond = enum(u2) { NZ, Z, NC, C };

// Based on the assembly output, a function lookup table results in a simple mov + jmp,
// whereas a switch has a lot more boilerplate (godbolt, zig 0.12.0 with -OReleaseFast).
// Not that it matters long term: I want to go down the dynamic recompliation route once
// I learn how it works :D
const FLUT = [0x100]*const fn (*State, u8) void{
    &nop, // 0x00
    &loadImm16IntoR16, // 0x01
    &loadAIntoR16Mem,
    &incR16, // 0x03
    &incR8, // 0x04
    &decR8, // 0x05
    &loadImm8IntoR8, // 0x06
    &rlca, // 0x07
    &loadSPIntoAddr, // 0x08
    &addR16, // 0x09
    &loadR16MemIntoA, // 0x0A
    &decR16, // 0x0B
    &incR8, // 0x0C
    &decR8, // 0x0D
    &loadImm8IntoR8, // 0x0E
    &rrca, // 0x0F
    &stop, // 0x10
    &loadImm16IntoR16, // 0x11
    &loadAIntoR16Mem, // 0x12
    &incR16, // 0x13
    &incR8, // 0x14
    &decR8, // 0x15
    &loadImm8IntoR8, // 0x16
    &rla, // 0x17
    &jumpRelative, // 0x18
    &addR16, // 0x19
    &loadR16MemIntoA, // 0x1A
    &decR16, // 0x1B
    &incR8, // 0x1C
    &decR8, // 0x1D
    &loadImm8IntoR8, // 0x1E
    &rra, // 0x1F
    &jumpRelativeCond, // 0x20
    &loadImm16IntoR16, // 0x21
    &loadAIntoR16Mem, // 0x22
    &incR16, // 0x23
    &incR8, // 0x24
    &decR8, // 0x25
    &loadImm8IntoR8, // 0x26
    &daa, // 0x27
    &jumpRelativeCond, // 0x28
    &addR16, // 0x29
    &loadR16MemIntoA, // 0x2A
    &decR16, // 0x2B
    &incR8, // 0x2C
    &decR8, // 0x2D
    &loadImm8IntoR8, // 0x2E
    &cpl, // 0x2F
    &jumpRelativeCond, // 0x30
    &loadImm16IntoR16, // 0x31
    &loadAIntoR16Mem, // 0x32
    &incR16, // 0x33
    &incR8, // 0x34
    &decR8, // 0x35
    &loadImm8IntoR8, // 0x36
    &scf, // 0x37
    &jumpRelativeCond, // 0x38
    &addR16, // 0x39
    &loadR16MemIntoA, // 0x3A
    &decR16, // 0x3B
    &incR8, // 0x3C
    &decR8, // 0x3D
    &loadImm8IntoR8, // 0x3E
    &ccf, // 0x3F
    &loadRegIntoReg, // 0x40
    &loadRegIntoReg, // 0x41
    &loadRegIntoReg, // 0x42
    &loadRegIntoReg, // 0x43
    &loadRegIntoReg, // 0x44
    &loadRegIntoReg, // 0x45
    &loadRegIntoReg, // 0x46
    &loadRegIntoReg, // 0x47
    &loadRegIntoReg, // 0x48
    &loadRegIntoReg, // 0x49
    &loadRegIntoReg, // 0x4A
    &loadRegIntoReg, // 0x4B
    &loadRegIntoReg, // 0x4C
    &loadRegIntoReg, // 0x4D
    &loadRegIntoReg, // 0x4E
    &loadRegIntoReg, // 0x4F
    &loadRegIntoReg, // 0x50
    &loadRegIntoReg, // 0x51
    &loadRegIntoReg, // 0x52
    &loadRegIntoReg, // 0x53
    &loadRegIntoReg, // 0x54
    &loadRegIntoReg, // 0x55
    &loadRegIntoReg, // 0x56
    &loadRegIntoReg, // 0x57
    &loadRegIntoReg, // 0x58
    &loadRegIntoReg, // 0x59
    &loadRegIntoReg, // 0x5A
    &loadRegIntoReg, // 0x5B
    &loadRegIntoReg, // 0x5C
    &loadRegIntoReg, // 0x5D
    &loadRegIntoReg, // 0x5E
    &loadRegIntoReg, // 0x5F
    &loadRegIntoReg, // 0x60
    &loadRegIntoReg, // 0x61
    &loadRegIntoReg, // 0x62
    &loadRegIntoReg, // 0x63
    &loadRegIntoReg, // 0x64
    &loadRegIntoReg, // 0x65
    &loadRegIntoReg, // 0x66
    &loadRegIntoReg, // 0x67
    &loadRegIntoReg, // 0x68
    &loadRegIntoReg, // 0x69
    &loadRegIntoReg, // 0x6A
    &loadRegIntoReg, // 0x6B
    &loadRegIntoReg, // 0x6C
    &loadRegIntoReg, // 0x6D
    &loadRegIntoReg, // 0x6E
    &loadRegIntoReg, // 0x6F
    &loadRegIntoReg, // 0x70
    &loadRegIntoReg, // 0x71
    &loadRegIntoReg, // 0x72
    &loadRegIntoReg, // 0x73
    &loadRegIntoReg, // 0x74
    &loadRegIntoReg, // 0x75
    &halt, // 0x76
    &loadRegIntoReg, // 0x77
    &loadRegIntoReg, // 0x78
    &loadRegIntoReg, // 0x79
    &loadRegIntoReg, // 0x7A
    &loadRegIntoReg, // 0x7B
    &loadRegIntoReg, // 0x7C
    &loadRegIntoReg, // 0x7D
    &loadRegIntoReg, // 0x7E
    &loadRegIntoReg, // 0x7F
    &addR8, // 0x80
    &addR8, // 0x81
    &addR8, // 0x82
    &addR8, // 0x83
    &addR8, // 0x84
    &addR8, // 0x85
    &addR8, // 0x86
    &addR8, // 0x87
    &addR8, // 0x88
    &addR8, // 0x89
    &addR8, // 0x8A
    &addR8, // 0x8B
    &addR8, // 0x8C
    &addR8, // 0x8D
    &addR8, // 0x8E
    &addR8, // 0x8F
    &subR8, // 0x90
    &subR8, // 0x91
    &subR8, // 0x92
    &subR8, // 0x93
    &subR8, // 0x94
    &subR8, // 0x95
    &subR8, // 0x96
    &subR8, // 0x97
    &subR8, // 0x98
    &subR8, // 0x99
    &subR8, // 0x9A
    &subR8, // 0x9B
    &subR8, // 0x9C
    &subR8, // 0x9D
    &subR8, // 0x9E
    &subR8, // 0x9F
    &andR8, // 0xA0
    &andR8, // 0xA1
    &andR8, // 0xA2
    &andR8, // 0xA3
    &andR8, // 0xA4
    &andR8, // 0xA5
    &andR8, // 0xA6
    &andR8, // 0xA7
    &andR8, // 0xA8
    &andR8, // 0xA9
    &andR8, // 0xAA
    &andR8, // 0xAB
    &andR8, // 0xAC
    &andR8, // 0xAD
    &andR8, // 0xAE
    &andR8, // 0xAF
    &orR8, // 0xB0
    &orR8, // 0xB1
    &orR8, // 0xB2
    &orR8, // 0xB3
    &orR8, // 0xB4
    &orR8, // 0xB5
    &orR8, // 0xB6
    &orR8, // 0xB7
    &orR8, // 0xB8
    &orR8, // 0xB9
    &orR8, // 0xBA
    &orR8, // 0xBB
    &orR8, // 0xBC
    &orR8, // 0xBD
    &orR8, // 0xBE
    &orR8, // 0xBF
    &retCond, // 0xC0
    &pop, // 0xC1
    &jumpCond, // 0xC2
    &jump, // 0xC3
    &callCond, // 0xC4
    &push, // 0xC5
    &addImm8, // 0xC6
    &rst, // 0xC7
    &retCond, // 0xC8
    &ret, // 0xC9
    &jumpCond, // 0xCA
    &prefix, // 0xCB
    &callCond, // 0xCC
    &call, // 0xCD
    &addImm8, // 0xCE
    &rst, // 0xCF
    &retCond, // 0xD0
    &pop, // 0xD1
    &jumpCond, // 0xD2
    &hardLock, // 0xD3
    &callCond, // 0xD4
    &push, // 0xD5
    &addImm8, // 0xD6
    &rst, // 0xD7
    &retCond, // 0xD8
    &ret, // 0xD9
    &jumpCond, // 0xDA
    &hardLock, // 0xDB
    &callCond, // 0xDC
    &hardLock, // 0xDD
    &subImm8, // 0xDE
    &rst, // 0xDF
    &loadHighAddr8, // 0xE0
    &pop, // 0xE1
    &loadHighA, // 0xE2
    &hardLock, // 0xE3
    &hardLock, // 0xE4
    &push, // 0xE5
    &andImm8, // 0xE6
    &rst, // 0xE7
    &addSP, // 0xE8
    &jumpHL, // 0xE9
    &loadAddr16, // 0xEA
    &hardLock, // 0xEB
    &hardLock, // 0xEC
    &hardLock, // 0xED
    &andImm8, // 0xEE
    &rst, // 0xEF
    &loadHighAddr8, // 0xF0
    &pop, // 0xF1
    &loadHighA, // 0xF2
    &setInterrupts, // 0xF3
    &hardLock, // 0xF4
    &push, // 0xF5
    &orImm8, // 0xF6
    &rst, // 0xF7
    &loadSPHL, // 0xF8
    &loadSPHL, // 0xF9
    &loadAddr16, // 0xFA
    &setInterrupts, // 0xFB
    &hardLock, // 0xFC
    &hardLock, // 0xFD
    &orImm8, // 0xFE
    &rst, // 0xFF
};

fn hardLock(_: *State, _: u8) void {
    unreachable;
}

fn nop(_: *State, _: u8) void {
    std.debug.print("NOP", .{});
}

fn stop(state: *State, _: u8) void {
    _ = readU8(state);
    std.debug.print("STOP", .{});
}

fn halt(_: *State, _: u8) void {
    std.debug.print("HALT", .{});
}

fn incR16(_: *State, opcode: u8) void {
    const dest: R16 = @enumFromInt((opcode & 0b00110000) >> 4);
    std.debug.print("INC {s}", .{@tagName(dest)});
}

fn decR16(_: *State, opcode: u8) void {
    const dest: R16 = @enumFromInt((opcode & 0b00110000) >> 4);
    std.debug.print("DEC {s}", .{@tagName(dest)});
}

fn incR8(_: *State, opcode: u8) void {
    const dest: R8 = @enumFromInt((opcode & 0b111000) >> 3);
    std.debug.print("INC {s}", .{@tagName(dest)});
}

fn decR8(_: *State, opcode: u8) void {
    const dest: R8 = @enumFromInt((opcode & 0b111000) >> 3);
    std.debug.print("DEC {s}", .{@tagName(dest)});
}

fn loadRegIntoReg(_: *State, opcode: u8) void {
    const source: R8 = @enumFromInt(opcode & 0b111);
    const dest: R8 = @enumFromInt((opcode & 0b111000) >> 3);
    const source_name = if (source == .HL) "[HL]" else @tagName(source);
    const dest_name = if (dest == .HL) "[HL]" else @tagName(dest);
    std.debug.print("LD {s}, {s}", .{ dest_name, source_name });
}

fn loadImm8IntoR8(state: *State, opcode: u8) void {
    const dest: R8 = @enumFromInt((opcode & 0b111000) >> 3);
    const source = readU8(state);
    std.debug.print("LD {s}, ${X:0>2}", .{ @tagName(dest), source });
}

fn loadImm16IntoR16(state: *State, opcode: u8) void {
    const dest: R16 = @enumFromInt((opcode & 0b00110000) >> 4);
    const source = readU16(state);
    std.debug.print("LD {s}, ${X:0>4}", .{ @tagName(dest), source });
}

fn loadAIntoR16Mem(_: *State, opcode: u8) void {
    const dest: R16Mem = @enumFromInt((opcode & 0b00110000) >> 4);
    std.debug.print("LD [{s}], A", .{@tagName(dest)});
}

fn loadR16MemIntoA(_: *State, opcode: u8) void {
    const source: R16Mem = @enumFromInt((opcode & 0b00110000) >> 4);
    std.debug.print("LD A, [{s}]", .{@tagName(source)});
}

fn loadSPIntoAddr(state: *State, _: u8) void {
    const addr = readU16(state);
    std.debug.print("LD ${X:0>4}, SP", .{addr});
}

fn loadHighAddr8(state: *State, opcode: u8) void {
    const offset = readU8(state);
    if (opcode & 16 == 16) {
        std.debug.print("LD A, [$FF00+${X:0>2}]", .{offset});
    } else {
        std.debug.print("LD [$FF00+${X:0>2}], A", .{offset});
    }
}

fn loadAddr16(state: *State, opcode: u8) void {
    const addr = readU16(state);
    if (opcode & 16 == 16) {
        std.debug.print("LD A, [${X:0>4}]", .{addr});
    } else {
        std.debug.print("LD [${X:0>4}], A", .{addr});
    }
}

fn loadHighA(_: *State, opcode: u8) void {
    if (opcode & 16 == 16) {
        std.debug.print("LD A, [$FF00+C]", .{});
    } else {
        std.debug.print("LD [$FF00+C], A", .{});
    }
}

fn loadSPHL(state: *State, opcode: u8) void {
    if (opcode & 1 == 1) {
        std.debug.print("LD SP, HL", .{});
    } else {
        const offset = readI8(state);
        std.debug.print("LD HL, SP + ${X:0>2}", .{offset});
    }
}

fn addR8(_: *State, opcode: u8) void {
    const carry: bool = (opcode & 8) == 8;
    const source: R8 = @enumFromInt(opcode & 0b111);
    const name = if (source == .HL) "[HL]" else @tagName(source);
    const inst = if (carry) "ADC" else "ADD";
    std.debug.print("{s} A, {s}", .{ inst, name });
}

fn addImm8(state: *State, opcode: u8) void {
    const carry: bool = (opcode & 8) == 8;
    const inst = if (carry) "ADC" else "ADD";
    const source = readU8(state);
    std.debug.print("{s} A, ${X:0>2}", .{ inst, source });
}

fn addSP(state: *State, _: u8) void {
    const source = readU8(state);
    std.debug.print("ADD SP, ${X:0>2}", .{source});
}

fn subR8(_: *State, opcode: u8) void {
    const carry: bool = (opcode & 8) == 8;
    const source: R8 = @enumFromInt(opcode & 0b111);
    const name = if (source == .HL) "[HL]" else @tagName(source);
    const inst = if (carry) "SBC" else "SUB";
    std.debug.print("{s} A, {s}", .{ inst, name });
}

fn subImm8(state: *State, opcode: u8) void {
    const carry: bool = (opcode & 8) == 8;
    const inst = if (carry) "SBC" else "SUB";
    const source = readU8(state);
    std.debug.print("{s} A, ${X:0>2}", .{ inst, source });
}

fn andR8(_: *State, opcode: u8) void {
    const carry: bool = (opcode & 8) == 8;
    const source: R8 = @enumFromInt(opcode & 0b111);
    const name = if (source == .HL) "[HL]" else @tagName(source);
    const inst = if (carry) "XOR" else "AND";
    std.debug.print("{s} A, {s}", .{ inst, name });
}

fn andImm8(state: *State, opcode: u8) void {
    const carry: bool = (opcode & 8) == 8;
    const inst = if (carry) "XOR" else "AND";
    const source = readU8(state);
    std.debug.print("{s} A, ${X:0>2}", .{ inst, source });
}

fn orR8(_: *State, opcode: u8) void {
    const carry: bool = (opcode & 8) == 8;
    const source: R8 = @enumFromInt(opcode & 0b111);
    const name = if (source == .HL) "[HL]" else @tagName(source);
    const inst = if (carry) "CP" else "OR";
    std.debug.print("{s} A, {s}", .{ inst, name });
}

fn orImm8(state: *State, opcode: u8) void {
    const carry: bool = (opcode & 8) == 8;
    const inst = if (carry) "CP" else "OR";
    const source = readU8(state);
    std.debug.print("{s} A, ${X:0>2}", .{ inst, source });
}

fn addR16(_: *State, opcode: u8) void {
    const source: R16 = @enumFromInt((opcode & 0b00110000) >> 4);
    std.debug.print("ADD HL, {s}", .{@tagName(source)});
}

fn ret(_: *State, opcode: u8) void {
    if (opcode & 16 == 16) {
        std.debug.print("RETI", .{});
    } else {
        std.debug.print("RET", .{});
    }
}

fn retCond(_: *State, opcode: u8) void {
    const cond: Cond = @enumFromInt((opcode & 0b00011000) >> 3);
    std.debug.print("RET {s}", .{@tagName(cond)});
}

fn pop(_: *State, opcode: u8) void {
    const dest: R16Stk = @enumFromInt((opcode & 0b00110000) >> 4);
    std.debug.print("POP {s}", .{@tagName(dest)});
}

fn push(_: *State, opcode: u8) void {
    const dest: R16Stk = @enumFromInt((opcode & 0b00110000) >> 4);
    std.debug.print("PUSH {s}", .{@tagName(dest)});
}

fn rlca(_: *State, _: u8) void {
    std.debug.print("RLCA", .{});
}

fn rrca(_: *State, _: u8) void {
    std.debug.print("RRCA", .{});
}

fn rla(_: *State, _: u8) void {
    std.debug.print("RLA", .{});
}

fn rra(_: *State, _: u8) void {
    std.debug.print("RRA", .{});
}

fn daa(_: *State, _: u8) void {
    std.debug.print("DAA", .{});
}

fn scf(_: *State, _: u8) void {
    std.debug.print("SCF", .{});
}

fn cpl(_: *State, _: u8) void {
    std.debug.print("CPL", .{});
}

fn ccf(_: *State, _: u8) void {
    std.debug.print("CCF", .{});
}

fn jumpRelative(state: *State, _: u8) void {
    const addr = readI8(state);
    std.debug.print("JR ${X:0>2}", .{addr});
}

fn jumpRelativeCond(state: *State, opcode: u8) void {
    const cond: Cond = @enumFromInt((opcode & 0b00011000) >> 3);
    const addr = readI8(state);
    std.debug.print("JR {s}, ${X:0>2}", .{ @tagName(cond), addr });
}

fn jump(state: *State, _: u8) void {
    const addr = readU16(state);
    std.debug.print("JP ${X:0>4}", .{addr});
}

fn jumpCond(state: *State, opcode: u8) void {
    const cond: Cond = @enumFromInt((opcode & 0b00011000) >> 3);
    const addr = readU16(state);
    std.debug.print("JP {s}, ${X:0>4}", .{ @tagName(cond), addr });
}

fn jumpHL(_: *State, _: u8) void {
    std.debug.print("JP HL", .{});
}

fn call(state: *State, _: u8) void {
    const addr = readU16(state);
    std.debug.print("CALL ${X:0>4}", .{addr});
}

fn callCond(state: *State, opcode: u8) void {
    const cond: Cond = @enumFromInt((opcode & 0b00011000) >> 3);
    const addr = readU16(state);
    std.debug.print("CALL {s}, ${X:0>4}", .{ @tagName(cond), addr });
}

fn rst(_: *State, opcode: u8) void {
    const target = ((opcode & 0b00111000) >> 3) * 8;
    std.debug.print("RST ${X:0>2}", .{target});
}

fn setInterrupts(_: *State, opcode: u8) void {
    if (opcode & 8 == 8) {
        std.debug.print("EI", .{});
    } else {
        std.debug.print("DI", .{});
    }
}

fn prefix(state: *State, _: u8) void {
    // This is simpler than a FLUT
    const opcode = readU8(state);
    const reg: R8 = @enumFromInt(opcode & 0b111);
    if ((opcode & 0b11000000) == 0) {
        const inst = switch ((opcode & 0b111000) >> 3) {
            0 => "RLC",
            1 => "RRC",
            2 => "RL",
            3 => "RR",
            4 => "SLA",
            5 => "SRA",
            6 => "SWAP",
            7 => "SRL",
            else => unreachable,
        };
        std.debug.print("{s} {s}", .{ inst, @tagName(reg) });
    } else {
        const index = (opcode & 0b111000) >> 3;
        const inst = switch ((opcode & 0b11000000) >> 6) {
            1 => "BIT",
            2 => "RES",
            3 => "SET",
            else => unreachable,
        };
        std.debug.print("{s} {d}, {s}", .{ inst, index, @tagName(reg) });
    }
}

inline fn readU8(state: *State) u8 {
    const value = state.memory[state.registers.PC];
    state.registers.PC += 1;
    return value;
}

inline fn readI8(state: *State) i8 {
    const value: i8 = @bitCast(state.memory[state.registers.PC]);
    state.registers.PC += 1;
    return value;
}

inline fn readU16(state: *State) u16 {
    const value = std.mem.readVarInt(u16, state.memory[state.registers.PC .. state.registers.PC + 2], std.builtin.Endian.little);
    state.registers.PC += 2;
    return value;
}

pub fn execute(state: *State) void {
    // HACK: Just dumping the ROM like a linear disassembler initially
    while (state.registers.PC < state.memory.len) {
        std.debug.print("0x{X:0>4}: ", .{state.registers.PC});
        const opcode = state.memory[state.registers.PC];
        state.registers.PC += 1;
        FLUT[opcode](state, opcode);
        std.debug.print("\n", .{});
    }
}
