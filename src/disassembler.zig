const std = @import("std");
const Allocator = std.mem.Allocator;
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

        try writer.print("{x:0>2}", .{byte});

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

// TODO: Unit tests
pub fn disassemble(allocator: Allocator, rom: []u8) !void {
    const base_addr = 0x000;
    const regs = [_]u8{ 'B', 'C', 'D', 'E', 'H', 'L', 'F', 'A' };

    var processed = std.AutoHashMap(u16, void).init(allocator);
    defer processed.deinit();
    var queue = std.ArrayList(u16).init(allocator);
    defer queue.deinit();

    try queue.append(0);
    while (queue.items.len > 0) {
        var ip: u16 = queue.pop();
        if (!processed.contains(ip)) {
            std.debug.print("========== BLOCK @ {X:0>4} ==========\n", .{ip});
        } else {
            continue;
        }

        while (ip < rom.len and ip < std.math.maxInt(u16)) {
            if ((try processed.getOrPut(ip)).found_existing) {
                break;
            }

            const opcode = rom[ip];
            const real_addr = ip + base_addr;

            switch (opcode) {
                0x00 => std.debug.print("{X:0>4} - NOP - 0x{X}\n", .{ real_addr, opcode }),
                0x01 => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    std.debug.print("{X:0>4} - LD BC, ${X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, word, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0x02 => std.debug.print("{X:0>4} - LD (BC), A - 0x{X}\n", .{ real_addr, opcode }),
                0x03 => std.debug.print("{X:0>4} - INC BC - 0x{X}\n", .{ real_addr, opcode }),
                0x04 => std.debug.print("{X:0>4} - INC B - 0x{X}\n", .{ real_addr, opcode }),
                0x05 => std.debug.print("{X:0>4} - DEC B - 0x{X}\n", .{ real_addr, opcode }),
                0x06 => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD B, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0x07 => std.debug.print("{X:0>4} - RLCA - 0x{X}\n", .{ real_addr, opcode }),
                0x08 => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    std.debug.print("{X:0>4} - LD ${X:0>4}, SP - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, word, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0x09 => std.debug.print("{X:0>4} - ADD HL, BC - 0x{X}\n", .{ real_addr, opcode }),
                0x0A => std.debug.print("{X:0>4} - LD A, (BC) - 0x{X}\n", .{ real_addr, opcode }),
                0x0B => std.debug.print("{X:0>4} - DEC BC - 0x{X}\n", .{ real_addr, opcode }),
                0x0C => std.debug.print("{X:0>4} - INC C - 0x{X}\n", .{ real_addr, opcode }),
                0x0D => std.debug.print("{X:0>4} - DEC C - 0x{X}\n", .{ real_addr, opcode }),
                0x0E => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD C, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0x0F => std.debug.print("{X:0>4} - RRCA - 0x{X}\n", .{ real_addr, opcode }),
                0x10 => std.debug.print("{X:0>4} - STOP - 0x{X}\n", .{ real_addr, opcode }),
                0x11 => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    std.debug.print("{X:0>4} - LD DE, ${X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, word, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0x12 => std.debug.print("{X:0>4} - LD (DE), A - 0x{X}\n", .{ real_addr, opcode }),
                0x13 => std.debug.print("{X:0>4} - INC DE - 0x{X}\n", .{ real_addr, opcode }),
                0x14 => std.debug.print("{X:0>4} - INC D - 0x{X}\n", .{ real_addr, opcode }),
                0x15 => std.debug.print("{X:0>4} - DEC D - 0x{X}\n", .{ real_addr, opcode }),
                0x16 => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD D, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0x17 => std.debug.print("{X:0>4} - RLA - 0x{X}\n", .{ real_addr, opcode }),
                0x18 => {
                    ip += 1;
                    const addr_offset: i8 = @bitCast(rom[ip]);
                    const addr_signed: i16 = @truncate(@as(i32, ip + 1) + addr_offset);
                    const addr: u16 = @bitCast(addr_signed);
                    try queue.append(addr);
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - JR ADDR_{X:0>4} - 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip] });
                    break;
                },
                0x19 => std.debug.print("{X:0>4} - ADD HL, DE - 0x{X}\n", .{ real_addr, opcode }),
                0x1A => std.debug.print("{X:0>4} - LD A, (DE) - 0x{X}\n", .{ real_addr, opcode }),
                0x1B => std.debug.print("{X:0>4} - DEC DE - 0x{X}\n", .{ real_addr, opcode }),
                0x1C => std.debug.print("{X:0>4} - INC E - 0x{X}\n", .{ real_addr, opcode }),
                0x1D => std.debug.print("{X:0>4} - DEC E - 0x{X}\n", .{ real_addr, opcode }),
                0x1E => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD E, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0x1F => std.debug.print("{X:0>4} - RRA - 0x{X}\n", .{ real_addr, opcode }),
                0x20 => {
                    ip += 1;
                    const addr_offset: i8 = @bitCast(rom[ip]);
                    const addr_signed: i16 = @truncate(@as(i32, ip + 1) + addr_offset);
                    const addr: u16 = @bitCast(addr_signed);
                    try queue.append(addr);
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - JR NZ, ADDR_{X:0>4} - 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip] });
                },
                0x21 => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    std.debug.print("{X:0>4} - LD HL, ${X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, word, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0x22 => std.debug.print("{X:0>4} - LD (HL+), A - 0x{X}\n", .{ real_addr, opcode }),
                0x23 => std.debug.print("{X:0>4} - INC HL - 0x{X}\n", .{ real_addr, opcode }),
                0x24 => std.debug.print("{X:0>4} - INC H - 0x{X}\n", .{ real_addr, opcode }),
                0x25 => std.debug.print("{X:0>4} - DEC H - 0x{X}\n", .{ real_addr, opcode }),
                0x26 => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD H, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0x27 => std.debug.print("{X:0>4} - DAA - 0x{X}\n", .{ real_addr, opcode }),
                0x28 => {
                    ip += 1;
                    const addr_offset: i8 = @bitCast(rom[ip]);
                    const addr_signed: i16 = @truncate(@as(i32, ip + 1) + addr_offset);
                    const addr: u16 = @bitCast(addr_signed);
                    try queue.append(addr);
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - JR Z, ADDR_{X:0>4} - 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip] });
                },
                0x29 => std.debug.print("{X:0>4} - ADD HL, HL - 0x{X}\n", .{ real_addr, opcode }),
                0x2A => std.debug.print("{X:0>4} - LD A, (HL+) - 0x{X}\n", .{ real_addr, opcode }),
                0x2B => std.debug.print("{X:0>4} - DEC HL - 0x{X}\n", .{ real_addr, opcode }),
                0x2C => std.debug.print("{X:0>4} - INC L - 0x{X}\n", .{ real_addr, opcode }),
                0x2D => std.debug.print("{X:0>4} - DEC L - 0x{X}\n", .{ real_addr, opcode }),
                0x2E => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD L, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0x2F => std.debug.print("{X:0>4} - CPL - 0x{X}\n", .{ real_addr, opcode }),
                0x30 => {
                    ip += 1;
                    const addr_offset: i8 = @bitCast(rom[ip]);
                    const addr_signed: i16 = @truncate(@as(i32, ip + 1) + addr_offset);
                    const addr: u16 = @bitCast(addr_signed);
                    try queue.append(addr);
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - JR NC, ADDR_{X:0>4} - 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip] });
                },
                0x31 => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    std.debug.print("{X:0>4} - LD SP, ${X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, word, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0x32 => std.debug.print("{X:0>4} - LD (HL-), A - 0x{X}\n", .{ real_addr, opcode }),
                0x33 => std.debug.print("{X:0>4} - INC SP - 0x{X}\n", .{ real_addr, opcode }),
                0x34 => std.debug.print("{X:0>4} - INC (HL) - 0x{X}\n", .{ real_addr, opcode }),
                0x35 => std.debug.print("{X:0>4} - DEC (HL) - 0x{X}\n", .{ real_addr, opcode }),
                0x36 => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD (HL), ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0x37 => std.debug.print("{X:0>4} - SCF - 0x{X}\n", .{ real_addr, opcode }),
                0x38 => {
                    ip += 1;
                    const addr_offset: i8 = @bitCast(rom[ip]);
                    const addr_signed: i16 = @truncate(@as(i32, ip + 1) + addr_offset);
                    const addr: u16 = @bitCast(addr_signed);
                    try queue.append(addr);
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - JR C, ADDR_{X:0>4} - 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip] });
                },
                0x39 => std.debug.print("{X:0>4} - ADD HL, SP - 0x{X}\n", .{ real_addr, opcode }),
                0x3A => std.debug.print("{X:0>4} - LD A, (HL-) - 0x{X}\n", .{ real_addr, opcode }),
                0x3B => std.debug.print("{X:0>4} - DEC SP - 0x{X}\n", .{ real_addr, opcode }),
                0x3C => std.debug.print("{X:0>4} - INC A - 0x{X}\n", .{ real_addr, opcode }),
                0x3D => std.debug.print("{X:0>4} - DEC A - 0x{X}\n", .{ real_addr, opcode }),
                0x3E => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD A, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0x3F => std.debug.print("{X:0>4} - CCF - 0x{X}\n", .{ real_addr, opcode }),
                0x40...0x45, 0x47...0x4D, 0x4F...0x55, 0x57...0x5D, 0x5F...0x65, 0x67...0x6D, 0x6F, 0x78...0x7D, 0x7F => {
                    const dst: u8 = regs[opcode >> 3 & 7];
                    const src: u8 = regs[opcode & 7];
                    std.debug.print("{X:0>4} - LD {c}, {c} - 0x{X}\n", .{ real_addr, dst, src, opcode });
                },
                0x46, 0x4E, 0x56, 0x5E, 0x66, 0x6E, 0x70...0x75, 0x77, 0x7E => {
                    std.debug.print("{X:0>4} - LD (HL) - 0x{X}\n", .{ real_addr, opcode });
                },
                0x76 => std.debug.print("{X:0>4} - HALT - 0x{X}\n", .{ real_addr, opcode }),
                0x80...0x85, 0x87...0x8D, 0x8F => {
                    const carry: bool = (opcode & 8) == 1; // && get_carry();
                    const src: u8 = regs[opcode & 7];
                    const op = if (carry) "ADC" else "ADD";
                    std.debug.print("{X:0>4} - {s} A, {c} - 0x{X}\n", .{ real_addr, op, src, opcode });
                    // adc(regs['A'], regs[opcode & 7], carry);
                },
                0x86 => std.debug.print("{X:0>4} - ADD A, (HL) - 0x{X}\n", .{ real_addr, opcode }),
                0x8E => std.debug.print("{X:0>4} - ADC A, (HL) - 0x{X}\n", .{ real_addr, opcode }),
                0x90...0x95, 0x97...0x9D, 0x9F => {
                    const carry: bool = (opcode & 8) == 1; // && get_carry();
                    const src: u8 = regs[opcode & 7];
                    const op = if (carry) "SBC" else "SUB";
                    std.debug.print("{X:0>4} - {s} A, {c} - 0x{X}\n", .{ real_addr, op, src, opcode });
                    // sbc(regs['A'], regs[opcode & 7], carry);
                },
                0x96 => std.debug.print("{X:0>4} - SUB A, (HL) - 0x{X}\n", .{ real_addr, opcode }),
                0x9E => std.debug.print("{X:0>4} - SBC A, (HL) - 0x{X}\n", .{ real_addr, opcode }),
                0xA0...0xA5, 0xA7...0xAD, 0xAF => {
                    const carry: bool = (opcode & 8) == 1; // && get_carry();
                    const src: u8 = regs[opcode & 7];
                    const op = if (carry) "XOR" else "AND";
                    std.debug.print("{X:0>4} - {s} A, {c} - 0x{X}\n", .{ real_addr, op, src, opcode });
                },
                0xA6 => std.debug.print("{X:0>4} - AND A, (HL) - 0x{X}\n", .{ real_addr, opcode }),
                0xAE => std.debug.print("{X:0>4} - XOR A, (HL) - 0x{X}\n", .{ real_addr, opcode }),
                0xB0...0xB5, 0xB7...0xBD, 0xBF => {
                    const carry: bool = (opcode & 8) == 1; // && get_carry();
                    const src: u8 = regs[opcode & 7];
                    const op = if (carry) "CP" else "OR";
                    std.debug.print("{X:0>4} - {s} A, {c} - 0x{X}\n", .{ real_addr, op, src, opcode });
                },
                0xB6 => std.debug.print("{X:0>4} - OR A, (HL) - 0x{X}\n", .{ real_addr, opcode }),
                0xBE => std.debug.print("{X:0>4} - CP A, (HL) - 0x{X}\n", .{ real_addr, opcode }),
                0xC0 => std.debug.print("{X:0>4} - RET NZ - 0x{X}\n", .{ real_addr, opcode }),
                0xC1 => std.debug.print("{X:0>4} - POP BC - 0x{X}\n", .{ real_addr, opcode }),
                0xC2 => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try queue.append(addr - base_addr);
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    std.debug.print("{X:0>4} - JP NZ, ADDR_{X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xC3 => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    try queue.append(addr - base_addr);
                    std.debug.print("{X:0>4} - JP ADDR_{X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                    break;
                },
                0xC4 => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    try queue.append(addr - base_addr);
                    std.debug.print("{X:0>4} - CALL NZ, SUB_{X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xC5 => std.debug.print("{X:0>4} - PUSH BC - 0x{X}\n", .{ real_addr, opcode }),
                0xC6 => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - ADD A, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xC7 => {
                    try queue.append(0x0);
                    std.debug.print("{X:0>4} - RST 00h - 0x{X}\n", .{ real_addr, opcode });
                },
                0xC8 => std.debug.print("{X:0>4} - RET Z - 0x{X}\n", .{ real_addr, opcode }),
                0xC9 => {
                    std.debug.print("{X:0>4} - RET - 0x{X}\n", .{ real_addr, opcode });
                    break;
                },
                0xCA => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    try queue.append(addr - base_addr);
                    std.debug.print("{X:0>4} - JP Z, ADDR_{X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xCC => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    try queue.append(addr - base_addr);
                    std.debug.print("{X:0>4} - CALL Z, SUB_{X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xCB => {
                    ip += 1;
                    const opcode_prefixed = rom[ip];
                    try processed.put(ip, {});
                    switch (opcode_prefixed) {
                        0x00...0x05, 0x07 => {
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - RLC {c} - 0x{X} 0x{X}\n", .{ real_addr, reg, opcode, opcode_prefixed });
                        },
                        0x06 => std.debug.print("{X:0>4} - RLC (HL) - 0x{X} 0x{X}\n", .{ real_addr, opcode, opcode_prefixed }),
                        0x08...0x0D, 0x0F => {
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - RRC {c} - 0x{X} 0x{X}\n", .{ real_addr, reg, opcode, opcode_prefixed });
                        },
                        0x0E => std.debug.print("{X:0>4} - RRC (HL) - 0x{X} 0x{X}\n", .{ real_addr, opcode, opcode_prefixed }),
                        0x10...0x15, 0x17 => {
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - RL {c} - 0x{X} 0x{X}\n", .{ real_addr, reg, opcode, opcode_prefixed });
                        },
                        0x16 => std.debug.print("{X:0>4} - RL (HL) - 0x{X} 0x{X}\n", .{ real_addr, opcode, opcode_prefixed }),
                        0x18...0x1D, 0x1F => {
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - RL {c} - 0x{X} 0x{X}\n", .{ real_addr, reg, opcode, opcode_prefixed });
                        },
                        0x1E => std.debug.print("{X:0>4} - RR (HL) - 0x{X} 0x{X}\n", .{ real_addr, opcode, opcode_prefixed }),
                        0x20...0x25, 0x27 => {
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - SLA {c} - 0x{X} 0x{X}\n", .{ real_addr, reg, opcode, opcode_prefixed });
                        },
                        0x26 => std.debug.print("{X:0>4} - SLA (HL) - 0x{X} 0x{X}\n", .{ real_addr, opcode, opcode_prefixed }),
                        0x28...0x2D, 0x2F => {
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - SRA {c} - 0x{X} 0x{X}\n", .{ real_addr, reg, opcode, opcode_prefixed });
                        },
                        0x2E => std.debug.print("{X:0>4} - SRA (HL) - 0x{X} 0x{X}\n", .{ real_addr, opcode, opcode_prefixed }),
                        0x30...0x35, 0x37 => {
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - SWAP {c} - 0x{X} 0x{X}\n", .{ real_addr, reg, opcode, opcode_prefixed });
                        },
                        0x36 => std.debug.print("{X:0>4} - SWAP (HL) - 0x{X} 0x{X}\n", .{ real_addr, opcode, opcode_prefixed }),
                        0x38...0x3D, 0x3F => {
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - SRL {c} - 0x{X} 0x{X}\n", .{ real_addr, reg, opcode, opcode_prefixed });
                        },
                        0x3E => std.debug.print("{X:0>4} - SRL (HL) - 0x{X} 0x{X}\n", .{ real_addr, opcode, opcode_prefixed }),
                        0x40...0x45,
                        0x47...0x4C,
                        0x4F,
                        0x50...0x55,
                        0x57...0x5C,
                        0x5F,
                        0x60...0x65,
                        0x67...0x6C,
                        0x6F,
                        0x70...0x75,
                        0x77...0x7C,
                        0x7F,
                        => {
                            const num: u8 = (opcode_prefixed & 0o70) >> 3;
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - BIT {d}, {c} - 0x{X} 0x{X}\n", .{ real_addr, num, reg, opcode, opcode_prefixed });
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
                            const num: u8 = (opcode_prefixed & 0o70) >> 3;
                            std.debug.print("{X:0>4} - BIT {d}, (HL) - 0x{X} 0x{X}\n", .{ real_addr, num, opcode, opcode_prefixed });
                        },
                        0x80...0x85,
                        0x87...0x8C,
                        0x8F,
                        0x90...0x95,
                        0x97...0x9C,
                        0x9F,
                        0xA0...0xA5,
                        0xA7...0xAC,
                        0xAF,
                        0xB0...0xB5,
                        0xB7...0xBC,
                        0xBF,
                        => {
                            const num: u8 = (opcode_prefixed & 0o70) >> 3;
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - RES {d}, {c} - 0x{X} 0x{X}\n", .{ real_addr, num, reg, opcode, opcode_prefixed });
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
                            const num: u8 = (opcode_prefixed & 0o70) >> 3;
                            std.debug.print("{X:0>4} - RES {d}, (HL) - 0x{X} 0x{X}\n", .{ real_addr, num, opcode, opcode_prefixed });
                        },
                        else => std.debug.print("{X:0>4} - OPCODE_PREFIXED - 0x{X} 0x{X}\n", .{ real_addr, opcode, opcode_prefixed }),
                        0xC0...0xC5,
                        0xC7...0xCC,
                        0xCF,
                        0xD0...0xD5,
                        0xD7...0xDC,
                        0xDF,
                        0xE0...0xE5,
                        0xE7...0xEC,
                        0xEF,
                        0xF0...0xF5,
                        0xF7...0xFC,
                        0xFF,
                        => {
                            const num: u8 = (opcode_prefixed & 0o70) >> 3;
                            const reg: u8 = regs[opcode_prefixed & 7];
                            std.debug.print("{X:0>4} - SET {d}, {c} - 0x{X} 0x{X}\n", .{ real_addr, num, reg, opcode, opcode_prefixed });
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
                            const num: u8 = (opcode_prefixed & 0o70) >> 3;
                            std.debug.print("{X:0>4} - SET {d}, (HL) - 0x{X} 0x{X}\n", .{ real_addr, num, opcode, opcode_prefixed });
                        },
                    }
                },
                0xCD => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    try queue.append(addr - base_addr);
                    std.debug.print("{X:0>4} - CALL SUB_{X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xCE => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - ADC A, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xCF => {
                    try queue.append(0x8);
                    std.debug.print("{X:0>4} - RST 08h - 0x{X}\n", .{ real_addr, opcode });
                },
                0xD0 => std.debug.print("{X:0>4} - RET NC - 0x{X}\n", .{ real_addr, opcode }),
                0xD1 => std.debug.print("{X:0>4} - POP DE - 0x{X}\n", .{ real_addr, opcode }),
                0xD2 => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    try queue.append(addr - base_addr);
                    std.debug.print("{X:0>4} - JP NC, ADDR_{X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xD4 => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    try queue.append(addr - base_addr);
                    std.debug.print("{X:0>4} - CALL NC, SUB_{X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xD5 => std.debug.print("{X:0>4} - PUSH DE - 0x{X}\n", .{ real_addr, opcode }),
                0xD6 => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - SUB A, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xD7 => {
                    try queue.append(0x10);
                    std.debug.print("{X:0>4} - RST 10h - 0x{X}\n", .{ real_addr, opcode });
                },
                0xD8 => std.debug.print("{X:0>4} - RET C - 0x{X}\n", .{ real_addr, opcode }),
                0xD9 => {
                    std.debug.print("{X:0>4} - RETI - 0x{X}\n", .{ real_addr, opcode });
                    break;
                },
                0xDA => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    try queue.append(addr - base_addr);
                    std.debug.print("{X:0>4} - JP C, ADDR_{X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xDC => {
                    const addr: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    try queue.append(addr - base_addr);
                    std.debug.print("{X:0>4} - CALL C, SUB_{X:0>4} - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, addr, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xDE => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - SBC A, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xDF => {
                    try queue.append(0x18);
                    std.debug.print("{X:0>4} - RST 18h - 0x{X}\n", .{ real_addr, opcode });
                },
                0xE0 => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD ($FF00+${X:0>2}), A - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xE1 => std.debug.print("{X:0>4} - POP HL - 0x{X}\n", .{ real_addr, opcode }),
                0xE2 => std.debug.print("{X:0>4} - LD ($FF00+C), A - 0x{X}\n", .{ real_addr, opcode }),
                0xE5 => std.debug.print("{X:0>4} - PUSH HL - 0x{X}\n", .{ real_addr, opcode }),
                0xE6 => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - AND A, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xE7 => {
                    try queue.append(0x20);
                    std.debug.print("{X:0>4} - RST 20h - 0x{X}\n", .{ real_addr, opcode });
                },
                0xE8 => {
                    ip += 1;
                    const byte: i8 = @bitCast(rom[ip]);
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - AND SP, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xE9 => {
                    std.debug.print("{X:0>4} - JP HL - 0x{X}\n", .{ real_addr, opcode });
                    break;
                },
                0xEA => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    std.debug.print("{X:0>4} - LD (${X:0>4}), A - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, word, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xEE => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - XOR A, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xEF => {
                    try queue.append(0x28);
                    std.debug.print("{X:0>4} - RST 28h - 0x{X}\n", .{ real_addr, opcode });
                },
                0xF0 => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD A, ($FF00+${X:0>2}) - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xF1 => std.debug.print("{X:0>4} - POP AF - 0x{X}\n", .{ real_addr, opcode }),
                0xF2 => std.debug.print("{X:0>4} - LD A, (FF00+C) - 0x{X}\n", .{ real_addr, opcode }),
                0xF3 => std.debug.print("{X:0>4} - DI - 0x{X}\n", .{ real_addr, opcode }),
                0xF5 => std.debug.print("{X:0>4} - PUSH AF - 0x{X}\n", .{ real_addr, opcode }),
                0xF6 => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - OR A, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xF7 => {
                    try queue.append(0x30);
                    std.debug.print("{X:0>4} - RST 30h - 0x{X}\n", .{ real_addr, opcode });
                },
                0xF8 => {
                    ip += 1;
                    const byte: i8 = @bitCast(rom[ip]);
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - LD HL, SP+${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xF9 => std.debug.print("{X:0>4} - LD SP, HL - 0x{X}\n", .{ real_addr, opcode }),
                0xFA => {
                    const word: u16 = (@as(u16, rom[ip + 2]) << 8) | rom[ip + 1];
                    try processed.put(ip + 1, {});
                    try processed.put(ip + 2, {});
                    std.debug.print("{X:0>4} - LD A, (${X:0>4}) - 0x{X} 0x{X} 0x{X}\n", .{ real_addr, word, opcode, rom[ip + 1], rom[ip + 2] });
                    ip += 2;
                },
                0xFB => std.debug.print("{X:0>4} - EI - 0x{X}\n", .{ real_addr, opcode }),
                0xFE => {
                    ip += 1;
                    const byte = rom[ip];
                    try processed.put(ip, {});
                    std.debug.print("{X:0>4} - CP A, ${X:0>2} - 0x{X} 0x{X}\n", .{ real_addr, byte, opcode, rom[ip] });
                },
                0xFF => {
                    try queue.append(0x38);
                    std.debug.print("{X:0>4} - RST 38h - 0x{X}\n", .{ real_addr, opcode });
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
                    // TODO: Handle invalid instruction
                    std.debug.print("{X:0>4} - ILLEGAL - 0x{X}\n", .{ real_addr, opcode });
                    break;
                },
            }
            ip += 1;
        }
        std.debug.print("\n", .{});
    }

    for (queue.items) |value| {
        std.debug.print("{X:0>4}\n", .{value});
    }
}
