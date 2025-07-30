const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Register = enum { B, C, D, E, H, L, F, A, AF, BC, DE, HL, SP, PC };

const Flags = enum { Z, N, H, C };

const Condition = enum { C, NC, Z, NZ };

const InstructionMnemonic = enum {
    ADC,
    ADD,
    AND,
    BIT,
    CALL,
    CCF,
    CP,
    CPL,
    DAA,
    DEC,
    DI,
    EI,
    HALT,
    ILLEGAL,
    INC,
    JP,
    JR,
    LD,
    LDD,
    LDI,
    LD_IO,
    LD_SP,
    NOP,
    OR,
    POP,
    PREFIX,
    PUSH,
    RES,
    RET,
    RETI,
    RL,
    RLA,
    RLC,
    RLCA,
    RR,
    RRA,
    RRC,
    RRCA,
    RST,
    SBC,
    SCF,
    SET,
    SLA,
    SRA,
    SRL,
    STOP,
    SUB,
    SWAP,
    XOR,
};

const Operand = struct {
    value: union(enum) {
        prefixed,
        byte: u8,
        sbyte: i8,
        word: u16,
        register: Register,
        condition: Condition,
    },
    immediate: bool,
};

const Instruction = struct {
    address: usize,
    mnemonic: InstructionMnemonic,
    op1: ?Operand,
    op2: ?Operand,
    bytes: []u8,
};

const DataBlock = struct {
    address: usize,
    bytes: []u8,
};

const Lookup = union(enum) {
    instruction: usize,
    instruction_part: usize,
    data_block: usize,
    data_block_part: usize,
};

const Disassembly = struct {
    rom: []u8,
    base_addr: usize,
    addressbook: std.AutoHashMap(usize, Lookup),
    instructions: std.ArrayList(Instruction),
    data_blocks: std.ArrayList(DataBlock),

    pub fn init(
        rom: []u8,
        base_addr: usize,
        addressbook: std.AutoHashMap(usize, Lookup),
        instructions: std.ArrayList(Instruction),
        data_blocks: std.ArrayList(DataBlock),
    ) Disassembly {
        return Disassembly{
            .rom = rom,
            .base_addr = base_addr,
            .addressbook = addressbook,
            .instructions = instructions,
            .data_blocks = data_blocks,
        };
    }

    pub fn deinit(self: *Disassembly) void {
        self.addressbook.deinit();
        self.instructions.deinit();
        self.data_blocks.deinit();
    }
};

pub fn hexdump(writer: anytype, bytes: []const u8, base: usize) !void {
    var ascii: [16]u8 = undefined;
    for (bytes, 0..) |byte, i| {
        if (std.ascii.isPrint(byte)) {
            ascii[i % 16] = byte;
        } else {
            ascii[i % 16] = '.';
        }

        if (i % 16 == 0) {
            try writer.print("{X:0>8}: ", .{i + base});
        }

        try writer.print("{X:0>2}", .{byte});

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
            try writer.print("{s: >2}", .{""});
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
    try hexdump(result.writer(), &bytes, 0);

    try testing.expectEqualSlices(
        u8,
        "00000000: DEAD BEEF CAFE BABE                      ........\n",
        result.getWritten(),
    );
}

test "hexdump output multiline format" {
    const bytes = [_]u8{ 0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe, 'H', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', '!' };
    var buffer: [1024]u8 = undefined;
    var result = std.io.fixedBufferStream(&buffer);
    try hexdump(result.writer(), &bytes, 0);

    try testing.expectEqualSlices(u8,
        \\00000000: DEAD BEEF CAFE BABE 4865 6C6C 6F20 776F  ........Hello wo
        \\00000010: 726C 6421                                rld!
        \\
    , result.getWritten());
}

test "hexdump padding with an odd number of bytes" {
    const bytes = [_]u8{ 0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe, 0x41 };
    var buffer: [1024]u8 = undefined;
    var result = std.io.fixedBufferStream(&buffer);
    try hexdump(result.writer(), &bytes, 0);

    try testing.expectEqualSlices(
        u8,
        "00000000: DEAD BEEF CAFE BABE 41                   ........A\n",
        result.getWritten(),
    );
}

// TODO: Unit tests
// TODO: Reduce duplication
pub fn disassemble(allocator: Allocator, rom: []u8, base_addr: u16) !Disassembly {
    var addressbook = std.AutoHashMap(usize, Lookup).init(allocator);
    var instructions = std.ArrayList(Instruction).init(allocator);
    var data_blocks = std.ArrayList(DataBlock).init(allocator);

    var queue = std.ArrayList(u16).init(allocator);
    defer queue.deinit();
    try queue.append(0);

    while (queue.items.len > 0) {
        var ip: u16 = queue.pop() orelse unreachable;
        if (addressbook.contains(ip + base_addr)) {
            continue;
        }

        while (ip < rom.len and ip < std.math.maxInt(u16)) {
            const real_addr = ip + base_addr;
            const entry = try addressbook.getOrPut(real_addr);
            if (entry.found_existing) {
                break;
            } else {
                entry.value_ptr.* = Lookup{ .instruction = instructions.items.len };
            }

            const opcode = rom[ip];
            switch (opcode) {
                0x00 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.NOP,
                }),
                0x01 => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .register = Register.BC }, .immediate = true },
                        .op2 = .{ .value = .{ .word = word }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 2;
                },
                0x02 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.BC }, .immediate = false },
                    .op2 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .mnemonic = InstructionMnemonic.LD,
                }),
                0x03 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.BC }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x04 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.B }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x05 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.B }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x06 => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.B }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 1;
                },
                0x07 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.RLCA,
                }),
                0x08 => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .word = word }, .immediate = true },
                        .op2 = .{ .value = .{ .register = Register.SP }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 2;
                },
                0x09 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.BC }, .immediate = true },
                    .mnemonic = InstructionMnemonic.ADD,
                }),
                0x0A => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.BC }, .immediate = false },
                    .mnemonic = InstructionMnemonic.LD,
                }),
                0x0B => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.BC }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x0C => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.C }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x0D => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.C }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x0E => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.C }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 1;
                },
                0x0F => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.RRCA,
                }),
                0x10 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.STOP,
                }),
                0x11 => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .register = Register.DE }, .immediate = true },
                        .op2 = .{ .value = .{ .word = word }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 2;
                },
                0x12 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.DE }, .immediate = false },
                    .op2 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .mnemonic = InstructionMnemonic.LD,
                }),
                0x13 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.DE }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x14 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.D }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x15 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.D }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x16 => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.D }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 1;
                },
                0x17 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.RLA,
                }),
                0x18 => {
                    const addr_offset: i8 = @bitCast(rom[ip + 1]);
                    const addr_signed: i16 = @truncate(@as(i32, ip + 2) + addr_offset);
                    const addr: u16 = @bitCast(addr_signed);
                    try queue.append(addr);
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .word = addr }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.JR,
                    });
                    ip += 1;
                    break;
                },
                0x19 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.DE }, .immediate = true },
                    .mnemonic = InstructionMnemonic.ADD,
                }),
                0x1A => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.DE }, .immediate = false },
                    .mnemonic = InstructionMnemonic.LD,
                }),
                0x1B => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.DE }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x1C => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.E }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x1D => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.E }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x1E => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.E }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 1;
                },
                0x1F => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.RRA,
                }),
                0x20 => {
                    const addr_offset: i8 = @bitCast(rom[ip + 1]);
                    const addr_signed: i16 = @truncate(@as(i32, ip + 2) + addr_offset);
                    const addr: u16 = @bitCast(addr_signed);
                    try queue.append(addr);
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .condition = Condition.NZ }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.JR,
                    });
                    ip += 1;
                },
                0x21 => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                        .op2 = .{ .value = .{ .word = word }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 2;
                },
                0x22 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .op2 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .mnemonic = InstructionMnemonic.LDI,
                }),
                0x23 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x24 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.H }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x25 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.H }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x26 => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.H }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 1;
                },
                0x27 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DAA,
                }),
                0x28 => {
                    const addr_offset: i8 = @bitCast(rom[ip + 1]);
                    const addr_signed: i16 = @truncate(@as(i32, ip + 2) + addr_offset);
                    const addr: u16 = @bitCast(addr_signed);
                    try queue.append(addr);
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .condition = Condition.Z }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.JR,
                    });
                    ip += 1;
                },
                0x29 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                    .mnemonic = InstructionMnemonic.ADD,
                }),
                0x2A => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .mnemonic = InstructionMnemonic.LDI,
                }),
                0x2B => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x2C => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.L }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x2D => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.L }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x2E => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.L }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 1;
                },
                0x2F => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.CPL,
                }),
                0x30 => {
                    const addr_offset: i8 = @bitCast(rom[ip + 1]);
                    const addr_signed: i16 = @truncate(@as(i32, ip + 2) + addr_offset);
                    const addr: u16 = @bitCast(addr_signed);
                    try queue.append(addr);
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .condition = Condition.NC }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.JR,
                    });
                    ip += 1;
                },
                0x31 => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .register = Register.SP }, .immediate = true },
                        .op2 = .{ .value = .{ .word = word }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 2;
                },
                0x32 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .op2 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .mnemonic = InstructionMnemonic.LDD,
                }),
                0x33 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.SP }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x34 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x35 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x36 => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 1;
                },
                0x37 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.SCF,
                }),
                0x38 => {
                    const addr_offset: i8 = @bitCast(rom[ip + 1]);
                    const addr_signed: i16 = @truncate(@as(i32, ip + 2) + addr_offset);
                    const addr: u16 = @bitCast(addr_signed);
                    try queue.append(addr);
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .condition = Condition.C }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.JR,
                    });
                    ip += 1;
                },
                0x39 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.SP }, .immediate = true },
                    .mnemonic = InstructionMnemonic.ADD,
                }),
                0x3A => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .mnemonic = InstructionMnemonic.LDD,
                }),
                0x3B => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.SP }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x3C => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.INC,
                }),
                0x3D => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DEC,
                }),
                0x3E => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 1;
                },
                0x3F => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.CCF,
                }),
                0x40...0x45, 0x47...0x4D, 0x4F...0x55, 0x57...0x5D, 0x5F...0x65, 0x67...0x6D, 0x6F, 0x78...0x7D, 0x7F => {
                    const dst: Register = @enumFromInt((opcode >> 3) & 7);
                    const src: Register = @enumFromInt(opcode & 7);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = dst }, .immediate = true },
                        .op2 = .{ .value = .{ .register = src }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                },
                0x46, 0x4E, 0x56, 0x5E, 0x66, 0x6E, 0x7E => {
                    const dst: Register = @enumFromInt((opcode >> 3) & 7);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = dst }, .immediate = true },
                        .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                },
                0x70...0x75, 0x77 => {
                    const src: Register = @enumFromInt(opcode & 7);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                        .op2 = .{ .value = .{ .register = src }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                },
                0x76 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.HALT,
                }),
                0x80...0x85, 0x87...0x8D, 0x8F => {
                    const carry: bool = (opcode & 8) == 8;
                    const src: Register = @enumFromInt(opcode & 7);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .register = src }, .immediate = true },
                        .mnemonic = if (carry) InstructionMnemonic.ADC else InstructionMnemonic.ADD,
                    });
                },
                0x86 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .mnemonic = InstructionMnemonic.ADD,
                }),
                0x8E => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .mnemonic = InstructionMnemonic.ADC,
                }),
                0x90...0x95, 0x97...0x9D, 0x9F => {
                    const carry: bool = (opcode & 8) == 8;
                    const src: Register = @enumFromInt(opcode & 7);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .register = src }, .immediate = true },
                        .mnemonic = if (carry) InstructionMnemonic.SBC else InstructionMnemonic.SUB,
                    });
                },
                0x96 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .mnemonic = InstructionMnemonic.SUB,
                }),
                0x9E => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .mnemonic = InstructionMnemonic.SBC,
                }),
                0xA0...0xA5, 0xA7...0xAD, 0xAF => {
                    const carry: bool = (opcode & 8) == 8;
                    const src: Register = @enumFromInt(opcode & 7);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .register = src }, .immediate = true },
                        .mnemonic = if (carry) InstructionMnemonic.AND else InstructionMnemonic.XOR,
                    });
                },
                0xA6 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .mnemonic = InstructionMnemonic.AND,
                }),
                0xAE => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .mnemonic = InstructionMnemonic.XOR,
                }),
                0xB0...0xB5, 0xB7...0xBD, 0xBF => {
                    const carry: bool = (opcode & 8) == 8;
                    const src: Register = @enumFromInt(opcode & 7);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .register = src }, .immediate = true },
                        .mnemonic = if (carry) InstructionMnemonic.CP else InstructionMnemonic.OR,
                    });
                },
                0xB6 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .mnemonic = InstructionMnemonic.OR,
                }),
                0xBE => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                    .mnemonic = InstructionMnemonic.CP,
                }),
                0xC0 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .condition = Condition.NZ }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.RET,
                }),
                0xC1 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.BC }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.POP,
                }),
                0xC2 => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try queue.append(addr - base_addr);
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .condition = Condition.NZ }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.JP,
                    });
                    ip += 2;
                },
                0xC3 => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try queue.append(addr - base_addr);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .word = addr }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.JP,
                    });
                    ip += 2;
                    break;
                },
                0xC4 => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try queue.append(addr - base_addr);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .condition = Condition.NZ }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.CALL,
                    });
                    ip += 2;
                },
                0xC5 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.BC }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.PUSH,
                }),
                0xC6 => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.ADD,
                    });
                    ip += 1;
                },
                0xC7 => {
                    try queue.append(0x0);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .byte = 0x00 }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.RST,
                    });
                },
                0xC8 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .condition = Condition.Z }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.RET,
                }),
                0xC9 => {
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = null,
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.RET,
                    });
                    break;
                },
                0xCA => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try queue.append(addr - base_addr);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .condition = Condition.Z }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.JP,
                    });
                    ip += 2;
                },
                0xCC => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try queue.append(addr - base_addr);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .condition = Condition.Z }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.CALL,
                    });
                    ip += 2;
                },
                0xCB => {
                    const opcode_prefixed = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    switch (opcode_prefixed) {
                        0x00...0x05, 0x07 => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .prefixed, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.RLC,
                            });
                        },
                        0x06 => try instructions.append(.{
                            .address = real_addr,
                            .bytes = rom[ip .. ip + 2],
                            .op1 = .{ .value = .prefixed, .immediate = true },
                            .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                            .mnemonic = InstructionMnemonic.RLC,
                        }),
                        0x08...0x0D, 0x0F => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .prefixed, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.RRC,
                            });
                        },
                        0x0E => try instructions.append(.{
                            .address = real_addr,
                            .bytes = rom[ip .. ip + 2],
                            .op1 = .{ .value = .prefixed, .immediate = true },
                            .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                            .mnemonic = InstructionMnemonic.RRC,
                        }),
                        0x10...0x15, 0x17 => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .prefixed, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.RL,
                            });
                        },
                        0x16 => try instructions.append(.{
                            .address = real_addr,
                            .bytes = rom[ip .. ip + 2],
                            .op1 = .{ .value = .prefixed, .immediate = true },
                            .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                            .mnemonic = InstructionMnemonic.RL,
                        }),
                        0x18...0x1D, 0x1F => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .prefixed, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.RR,
                            });
                        },
                        0x1E => try instructions.append(.{
                            .address = real_addr,
                            .bytes = rom[ip .. ip + 2],
                            .op1 = .{ .value = .prefixed, .immediate = true },
                            .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                            .mnemonic = InstructionMnemonic.RR,
                        }),
                        0x20...0x25, 0x27 => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .prefixed, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.SLA,
                            });
                        },
                        0x26 => try instructions.append(.{
                            .address = real_addr,
                            .bytes = rom[ip .. ip + 2],
                            .op1 = .{ .value = .prefixed, .immediate = true },
                            .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                            .mnemonic = InstructionMnemonic.SLA,
                        }),
                        0x28...0x2D, 0x2F => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .prefixed, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.SRA,
                            });
                        },
                        0x2E => try instructions.append(.{
                            .address = real_addr,
                            .bytes = rom[ip .. ip + 2],
                            .op1 = .{ .value = .prefixed, .immediate = true },
                            .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                            .mnemonic = InstructionMnemonic.SRA,
                        }),
                        0x30...0x35, 0x37 => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .prefixed, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.SWAP,
                            });
                        },
                        0x36 => try instructions.append(.{
                            .address = real_addr,
                            .bytes = rom[ip .. ip + 2],
                            .op1 = .{ .value = .prefixed, .immediate = true },
                            .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                            .mnemonic = InstructionMnemonic.SWAP,
                        }),
                        0x38...0x3D, 0x3F => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .prefixed, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.SRL,
                            });
                        },
                        0x3E => try instructions.append(.{
                            .address = real_addr,
                            .bytes = rom[ip .. ip + 2],
                            .op1 = .{ .value = .prefixed, .immediate = true },
                            .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                            .mnemonic = InstructionMnemonic.SRL,
                        }),
                        0x40...0x45,
                        0x47...0x4D,
                        0x4F,
                        0x50...0x55,
                        0x57...0x5D,
                        0x5F,
                        0x60...0x65,
                        0x67...0x6D,
                        0x6F,
                        0x70...0x75,
                        0x77...0x7D,
                        0x7F,
                        => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .{ .byte = (opcode_prefixed & 0o70) >> 3 }, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.BIT,
                            });
                        },
                        0x46,
                        0x4E,
                        0x56,
                        0x5E,
                        0x66,
                        0x6E,
                        0x76,
                        0x7E,
                        => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .{ .byte = (opcode_prefixed & 0o70) >> 3 }, .immediate = true },
                                .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                                .mnemonic = InstructionMnemonic.BIT,
                            });
                        },
                        0x80...0x85,
                        0x87...0x8D,
                        0x8F,
                        0x90...0x95,
                        0x97...0x9D,
                        0x9F,
                        0xA0...0xA5,
                        0xA7...0xAD,
                        0xAF,
                        0xB0...0xB5,
                        0xB7...0xBD,
                        0xBF,
                        => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .{ .byte = (opcode_prefixed & 0o70) >> 3 }, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.RES,
                            });
                        },
                        0x86,
                        0x8E,
                        0x96,
                        0x9E,
                        0xA6,
                        0xAE,
                        0xB6,
                        0xBE,
                        => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .{ .byte = (opcode_prefixed & 0o70) >> 3 }, .immediate = true },
                                .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                                .mnemonic = InstructionMnemonic.RES,
                            });
                        },
                        0xC0...0xC5,
                        0xC7...0xCD,
                        0xCF,
                        0xD0...0xD5,
                        0xD7...0xDD,
                        0xDF,
                        0xE0...0xE5,
                        0xE7...0xED,
                        0xEF,
                        0xF0...0xF5,
                        0xF7...0xFD,
                        0xFF,
                        => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .{ .byte = (opcode_prefixed & 0o70) >> 3 }, .immediate = true },
                                .op2 = .{ .value = .{ .register = @enumFromInt(opcode_prefixed & 7) }, .immediate = true },
                                .mnemonic = InstructionMnemonic.SET,
                            });
                        },
                        0xC6,
                        0xCE,
                        0xD6,
                        0xDE,
                        0xE6,
                        0xEE,
                        0xF6,
                        0xFE,
                        => {
                            try instructions.append(.{
                                .address = real_addr,
                                .bytes = rom[ip .. ip + 2],
                                .op1 = .{ .value = .{ .byte = (opcode_prefixed & 0o70) >> 3 }, .immediate = true },
                                .op2 = .{ .value = .{ .register = Register.HL }, .immediate = false },
                                .mnemonic = InstructionMnemonic.SET,
                            });
                        },
                    }
                    ip += 1;
                },
                0xCD => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try queue.append(addr - base_addr);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .word = addr }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.CALL,
                    });
                    ip += 2;
                },
                0xCE => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.ADC,
                    });
                    ip += 1;
                },
                0xCF => {
                    try queue.append(0x8);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .byte = 0x08 }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.RST,
                    });
                },
                0xD0 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .condition = Condition.NC }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.RET,
                }),
                0xD1 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.DE }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.POP,
                }),
                0xD2 => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try queue.append(addr - base_addr);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .condition = Condition.NC }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.JP,
                    });
                    ip += 2;
                },
                0xD4 => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try queue.append(addr - base_addr);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .condition = Condition.NC }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.CALL,
                    });
                    ip += 2;
                },
                0xD5 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.DE }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.PUSH,
                }),
                0xD6 => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.SUB,
                    });
                    ip += 1;
                },
                0xD7 => {
                    try queue.append(0x10);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .byte = 0x10 }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.RST,
                    });
                },
                0xD8 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .condition = Condition.C }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.RET,
                }),
                0xD9 => {
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = null,
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.RETI,
                    });
                    break;
                },
                0xDA => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try queue.append(addr - base_addr);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .condition = Condition.C }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.JP,
                    });
                    ip += 2;
                },
                0xDC => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try queue.append(addr - base_addr);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .condition = Condition.C }, .immediate = true },
                        .op2 = .{ .value = .{ .word = addr }, .immediate = true },
                        .mnemonic = InstructionMnemonic.CALL,
                    });
                    ip += 2;
                },
                0xDE => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.SBC,
                    });
                    ip += 1;
                },
                0xDF => {
                    try queue.append(0x18);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .byte = 0x18 }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.RST,
                    });
                },
                0xE0 => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .byte = byte }, .immediate = false },
                        .op2 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD_IO,
                    });
                    ip += 1;
                },
                0xE1 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.POP,
                }),
                0xE2 => {
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = Register.C }, .immediate = false },
                        .op2 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD_IO,
                    });
                },
                0xE5 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.PUSH,
                }),
                0xE6 => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.AND,
                    });
                    ip += 1;
                },
                0xE7 => {
                    try queue.append(0x20);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .byte = 0x20 }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.RST,
                    });
                },
                0xE8 => {
                    const byte: i8 = @bitCast(rom[ip + 1]);
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.SP }, .immediate = true },
                        .op2 = .{ .value = .{ .sbyte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.AND,
                    });
                    ip += 1;
                },
                0xE9 => {
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.JP,
                    });
                    break;
                },
                0xEA => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .word = word }, .immediate = false },
                        .op2 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 2;
                },
                0xEE => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.XOR,
                    });
                    ip += 1;
                },
                0xEF => {
                    try queue.append(0x28);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .byte = 0x28 }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.RST,
                    });
                },
                0xF0 => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = false },
                        .mnemonic = InstructionMnemonic.LD_IO,
                    });
                    ip += 1;
                },
                0xF1 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.AF }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.POP,
                }),
                0xF2 => {
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .register = Register.C }, .immediate = false },
                        .mnemonic = InstructionMnemonic.LD_IO,
                    });
                },
                0xF3 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.DI,
                }),
                0xF5 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.AF }, .immediate = true },
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.PUSH,
                }),
                0xF6 => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.OR,
                    });
                    ip += 1;
                },
                0xF7 => {
                    try queue.append(0x30);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .byte = 0x30 }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.RST,
                    });
                },
                0xF8 => {
                    const byte: i8 = @bitCast(rom[ip + 1]);
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                        .op2 = .{ .value = .{ .sbyte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.LD_SP,
                    });
                    ip += 1;
                },
                0xF9 => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = .{ .value = .{ .register = Register.SP }, .immediate = true },
                    .op2 = .{ .value = .{ .register = Register.HL }, .immediate = true },
                    .mnemonic = InstructionMnemonic.LD,
                }),
                0xFA => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try addressbook.put(real_addr + 2, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 3],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .word = word }, .immediate = false },
                        .mnemonic = InstructionMnemonic.LD,
                    });
                    ip += 2;
                },
                0xFB => try instructions.append(.{
                    .address = real_addr,
                    .bytes = rom[ip .. ip + 1],
                    .op1 = null,
                    .op2 = null,
                    .mnemonic = InstructionMnemonic.EI,
                }),
                0xFE => {
                    const byte = rom[ip + 1];
                    try addressbook.put(real_addr + 1, Lookup{ .instruction_part = instructions.items.len });
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 2],
                        .op1 = .{ .value = .{ .register = Register.A }, .immediate = true },
                        .op2 = .{ .value = .{ .byte = byte }, .immediate = true },
                        .mnemonic = InstructionMnemonic.CP,
                    });
                    ip += 1;
                },
                0xFF => {
                    try queue.append(0x38);
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = .{ .value = .{ .byte = 0x38 }, .immediate = true },
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.RST,
                    });
                },
                0xD3,
                0xDB,
                0xDD,
                0xE3,
                0xE4,
                0xEB,
                0xEC,
                0xED,
                0xF4,
                0xFC,
                0xFD,
                => {
                    try instructions.append(.{
                        .address = real_addr,
                        .bytes = rom[ip .. ip + 1],
                        .op1 = null,
                        .op2 = null,
                        .mnemonic = InstructionMnemonic.ILLEGAL,
                    });
                    break;
                },
            }
            ip += 1;
        }
    }

    var read_data = false;
    var data_start: usize = 0;
    for (0..rom.len) |i| {
        if (addressbook.contains(@truncate(i))) {
            if (read_data) {
                try data_blocks.append(DataBlock{ .address = data_start, .bytes = rom[data_start..i] });
                read_data = false;
            }
            continue;
        }

        if (read_data) {
            try addressbook.put(i, Lookup{ .data_block_part = data_blocks.items.len });
            continue;
        }

        read_data = true;
        data_start = i;
        try addressbook.put(i, Lookup{ .data_block = data_blocks.items.len });
    }

    if (read_data) {
        try addressbook.put(rom.len - 1, Lookup{ .data_block = data_blocks.items.len });
        try data_blocks.append(DataBlock{ .address = data_start, .bytes = rom[data_start..] });
    }

    return Disassembly.init(rom, base_addr, addressbook, instructions, data_blocks);
}

pub inline fn print_operand(op: Operand) void {
    if (!op.immediate) std.debug.print("(", .{});
    switch (op.value) {
        .prefixed => return,
        .byte => |byte| std.debug.print("${X:0>2}", .{byte}),
        .sbyte => |sbyte| std.debug.print("${X:0>2}", .{sbyte}),
        .word => |word| std.debug.print("${X:0>4}", .{word}),
        .register => |reg| std.debug.print("{s}", .{@tagName(reg)}),
        .condition => |cond| std.debug.print("{s}", .{@tagName(cond)}),
    }
    if (!op.immediate) std.debug.print(")", .{});
}

pub inline fn print_instruction(instruction: Instruction) void {
    if (instruction.mnemonic == InstructionMnemonic.LD_IO) {
        std.debug.print("LD ", .{});
        const op1 = instruction.op1.?;
        const op2 = instruction.op2.?;
        if (op1.immediate) {
            std.debug.print("A, ", .{});
            switch (op2.value) {
                .register => std.debug.print("(FF00+C)", .{}),
                .byte => |byte| std.debug.print("(FF00+${X})", .{byte}),
                else => @panic("illegal value"),
            }
        } else {
            switch (op1.value) {
                .register => std.debug.print("(FF00+C)", .{}),
                .byte => |byte| std.debug.print("(FF00+${X})", .{byte}),
                else => @panic("illegal value"),
            }
            std.debug.print(", A", .{});
        }
    } else if (instruction.mnemonic == InstructionMnemonic.LD_SP) {
        std.debug.print("LD HL, SP+${X:0>2}", .{
            instruction.op2.?.value.byte,
        });
    } else {
        std.debug.print("{s}", .{@tagName(instruction.mnemonic)});
        if (instruction.op1 != null and instruction.op1.?.value == .prefixed) {
            std.debug.print(" ", .{});
            print_operand(instruction.op2.?);
        } else {
            if (instruction.op1) |op| {
                std.debug.print(" ", .{});
                print_operand(op);
            }
            if (instruction.op2) |op| {
                std.debug.print(", ", .{});
                print_operand(op);
            }
        }
    }
}

pub fn print_disassembly(disassembly: *const Disassembly) !void {
    const stdout_writer = std.io.getStdOut().writer();
    for (0..disassembly.rom.len) |ip| {
        const lookup = disassembly.addressbook.get(ip);
        if (lookup) |lu| {
            switch (lu) {
                .instruction => |index| {
                    const instruction = disassembly.instructions.items[index];
                    std.debug.print("{X:0>4}:   ", .{instruction.address});

                    for (instruction.bytes) |byte| {
                        std.debug.print("{X:0>2} ", .{byte});
                    }

                    // Each byte takes 3 chars of space, so for 3 bytes max,
                    // we need 3 * 3 chars of padding, minus whatever was printed
                    for (0..9 - instruction.bytes.len * 3) |_| {
                        std.debug.print(" ", .{});
                    }

                    std.debug.print("  ", .{});
                    print_instruction(instruction);
                    std.debug.print("\n", .{});
                },
                .data_block => |index| {
                    const data_block = disassembly.data_blocks.items[index];
                    std.debug.print("\n", .{});
                    try hexdump(stdout_writer, data_block.bytes, data_block.address);
                    std.debug.print("\n", .{});
                },
                // else => std.debug.print("{X:0>4} - {s} - 0x{X:0>2}\n", .{ ip, @tagName(lu), disassembly.rom[ip] }),
                else => continue,
            }
        }
    }
}
