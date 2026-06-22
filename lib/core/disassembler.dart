// lib/core/disassembler.dart
// 8086 Disassembler — decodes machine code bytes to Intel-syntax mnemonics.
// Supports the most common real-mode instructions used in DOS DEBUG sessions.

import 'cpu8086.dart';

class DisasmResult {
  final int address;
  final List<int> bytes;
  final String mnemonic;
  final int nextAddress;

  DisasmResult({
    required this.address,
    required this.bytes,
    required this.mnemonic,
    required this.nextAddress,
  });

  String get hexBytes =>
      bytes.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');

  String get addrHex =>
      address.toRadixString(16).toUpperCase().padLeft(4, '0');
}

class Disassembler {
  final CPU8086 cpu;
  Disassembler(this.cpu);

  static const List<String> _reg16 = ['AX','CX','DX','BX','SP','BP','SI','DI'];
  static const List<String> _reg8  = ['AL','CL','DL','BL','AH','CH','DH','BH'];
  static const List<String> _seg   = ['ES','CS','SS','DS'];

  // Decode one instruction starting at [addr], return DisasmResult
  DisasmResult disasm(int addr) {
    addr &= 0xFFFF;
    final start = addr;
    final bytes = <int>[];

    int nextByte() {
      final b = cpu.memory[addr & 0xFFFF];
      bytes.add(b);
      addr = (addr + 1) & 0xFFFF;
      return b;
    }

    int peekByte() => cpu.memory[addr & 0xFFFF];

    int nextWord() {
      final lo = nextByte();
      final hi = nextByte();
      return lo | (hi << 8);
    }

    String imm8Signed() {
      final b = nextByte();
      final signed = b > 127 ? b - 256 : b;
      if (signed < 0) return '-${(-signed).toRadixString(16).toUpperCase().padLeft(2,'0')}';
      return '+${signed.toRadixString(16).toUpperCase().padLeft(2,'0')}';
    }

    String imm8Hex() =>
        nextByte().toRadixString(16).toUpperCase().padLeft(2, '0') + 'h';

    String imm16Hex() =>
        nextWord().toRadixString(16).toUpperCase().padLeft(4, '0') + 'h';

    String rel8(int base) {
      final off = nextByte();
      final signed = off > 127 ? off - 256 : off;
      final target = (base + 2 + signed) & 0xFFFF;
      return target.toRadixString(16).toUpperCase().padLeft(4, '0');
    }

    // ModRM decoder
    String modRM(int modrm, bool is16) {
      final mod = (modrm >> 6) & 3;
      final rm  = modrm & 7;
      final regs = is16 ? _reg16 : _reg8;

      const bases = ['BX+SI','BX+DI','BP+SI','BP+DI','SI','DI','BP','BX'];

      if (mod == 3) return regs[rm];

      String ea;
      if (mod == 0 && rm == 6) {
        // direct address
        ea = '[${imm16Hex()}]';
      } else {
        final base = bases[rm];
        if (mod == 0) {
          ea = '[$base]';
        } else if (mod == 1) {
          ea = '[$base${imm8Signed()}]';
        } else {
          ea = '[$base+${imm16Hex()}]';
        }
      }
      return ea;
    }

    String regRM(int modrm, bool is16) {
      final reg = (modrm >> 3) & 7;
      return is16 ? _reg16[reg] : _reg8[reg];
    }

    String alu(String op, int opcode) {
      final byte2 = nextByte();
      final mod = (byte2 >> 6) & 3;
      final is16 = (opcode & 1) == 1;
      final dir  = (opcode & 2) == 2; // 1 = reg is dst
      final rm   = modRM(byte2, is16);
      final reg  = regRM(byte2, is16);
      if (dir) return '$op $reg, $rm';
      return '$op $rm, $reg';
    }

    final opcode = nextByte();

    String mnemonic;

    switch (opcode) {
      // ── MOV ──────────────────────────────────────────────────────────────
      case 0x88: case 0x89: case 0x8A: case 0x8B:
        mnemonic = alu('MOV', opcode);
        break;
      case 0x8C: { // MOV r/m16, Sreg
        final b2 = nextByte();
        final sr = _seg[(b2 >> 3) & 3];
        mnemonic = 'MOV ${modRM(b2, true)}, $sr';
        break;
      }
      case 0x8E: { // MOV Sreg, r/m16
        final b2 = nextByte();
        final sr = _seg[(b2 >> 3) & 3];
        mnemonic = 'MOV $sr, ${modRM(b2, true)}';
        break;
      }
      case 0xB0: case 0xB1: case 0xB2: case 0xB3:
      case 0xB4: case 0xB5: case 0xB6: case 0xB7:
        mnemonic = 'MOV ${_reg8[opcode & 7]}, ${imm8Hex()}';
        break;
      case 0xB8: case 0xB9: case 0xBA: case 0xBB:
      case 0xBC: case 0xBD: case 0xBE: case 0xBF:
        mnemonic = 'MOV ${_reg16[opcode & 7]}, ${imm16Hex()}';
        break;
      case 0xA0: mnemonic = 'MOV AL, [${imm16Hex()}]'; break;
      case 0xA1: mnemonic = 'MOV AX, [${imm16Hex()}]'; break;
      case 0xA2: mnemonic = 'MOV [${imm16Hex()}], AL'; break;
      case 0xA3: mnemonic = 'MOV [${imm16Hex()}], AX'; break;
      case 0xC6: { // MOV r/m8, imm8
        final b2 = nextByte();
        mnemonic = 'MOV BYTE PTR ${modRM(b2, false)}, ${imm8Hex()}';
        break;
      }
      case 0xC7: { // MOV r/m16, imm16
        final b2 = nextByte();
        mnemonic = 'MOV WORD PTR ${modRM(b2, true)}, ${imm16Hex()}';
        break;
      }

      // ── ADD ──────────────────────────────────────────────────────────────
      case 0x00: case 0x01: case 0x02: case 0x03:
        mnemonic = alu('ADD', opcode);
        break;
      case 0x04: mnemonic = 'ADD AL, ${imm8Hex()}'; break;
      case 0x05: mnemonic = 'ADD AX, ${imm16Hex()}'; break;

      // ── SUB ──────────────────────────────────────────────────────────────
      case 0x28: case 0x29: case 0x2A: case 0x2B:
        mnemonic = alu('SUB', opcode);
        break;
      case 0x2C: mnemonic = 'SUB AL, ${imm8Hex()}'; break;
      case 0x2D: mnemonic = 'SUB AX, ${imm16Hex()}'; break;

      // ── CMP ──────────────────────────────────────────────────────────────
      case 0x38: case 0x39: case 0x3A: case 0x3B:
        mnemonic = alu('CMP', opcode);
        break;
      case 0x3C: mnemonic = 'CMP AL, ${imm8Hex()}'; break;
      case 0x3D: mnemonic = 'CMP AX, ${imm16Hex()}'; break;

      // ── AND ──────────────────────────────────────────────────────────────
      case 0x20: case 0x21: case 0x22: case 0x23:
        mnemonic = alu('AND', opcode);
        break;
      case 0x24: mnemonic = 'AND AL, ${imm8Hex()}'; break;
      case 0x25: mnemonic = 'AND AX, ${imm16Hex()}'; break;

      // ── OR ───────────────────────────────────────────────────────────────
      case 0x08: case 0x09: case 0x0A: case 0x0B:
        mnemonic = alu('OR', opcode);
        break;
      case 0x0C: mnemonic = 'OR AL, ${imm8Hex()}'; break;
      case 0x0D: mnemonic = 'OR AX, ${imm16Hex()}'; break;

      // ── XOR ──────────────────────────────────────────────────────────────
      case 0x30: case 0x31: case 0x32: case 0x33:
        mnemonic = alu('XOR', opcode);
        break;
      case 0x34: mnemonic = 'XOR AL, ${imm8Hex()}'; break;
      case 0x35: mnemonic = 'XOR AX, ${imm16Hex()}'; break;

      // ── INC / DEC ────────────────────────────────────────────────────────
      case 0x40: case 0x41: case 0x42: case 0x43:
      case 0x44: case 0x45: case 0x46: case 0x47:
        mnemonic = 'INC ${_reg16[opcode & 7]}'; break;
      case 0x48: case 0x49: case 0x4A: case 0x4B:
      case 0x4C: case 0x4D: case 0x4E: case 0x4F:
        mnemonic = 'DEC ${_reg16[opcode & 7]}'; break;

      // ── PUSH / POP ───────────────────────────────────────────────────────
      case 0x50: case 0x51: case 0x52: case 0x53:
      case 0x54: case 0x55: case 0x56: case 0x57:
        mnemonic = 'PUSH ${_reg16[opcode & 7]}'; break;
      case 0x58: case 0x59: case 0x5A: case 0x5B:
      case 0x5C: case 0x5D: case 0x5E: case 0x5F:
        mnemonic = 'POP ${_reg16[opcode & 7]}'; break;
      case 0x06: mnemonic = 'PUSH ES'; break;
      case 0x0E: mnemonic = 'PUSH CS'; break;
      case 0x16: mnemonic = 'PUSH SS'; break;
      case 0x1E: mnemonic = 'PUSH DS'; break;
      case 0x07: mnemonic = 'POP ES'; break;
      case 0x17: mnemonic = 'POP SS'; break;
      case 0x1F: mnemonic = 'POP DS'; break;
      case 0x68: mnemonic = 'PUSH ${imm16Hex()}'; break;
      case 0x6A: mnemonic = 'PUSH ${imm8Hex()}'; break;
      case 0x8F: {
        final b2 = nextByte();
        mnemonic = 'POP ${modRM(b2, true)}';
        break;
      }

      // ── MUL / IMUL / DIV / IDIV ──────────────────────────────────────────
      case 0xF6: {
        final b2 = nextByte();
        final ext = (b2 >> 3) & 7;
        final rm = modRM(b2, false);
        switch (ext) {
          case 0: mnemonic = 'TEST $rm, ${imm8Hex()}'; break;
          case 2: mnemonic = 'NOT $rm'; break;
          case 3: mnemonic = 'NEG $rm'; break;
          case 4: mnemonic = 'MUL $rm'; break;
          case 5: mnemonic = 'IMUL $rm'; break;
          case 6: mnemonic = 'DIV $rm'; break;
          case 7: mnemonic = 'IDIV $rm'; break;
          default: mnemonic = 'DB ${(b2 & 0xFF).toRadixString(16).toUpperCase()}h';
        }
        break;
      }
      case 0xF7: {
        final b2 = nextByte();
        final ext = (b2 >> 3) & 7;
        final rm = modRM(b2, true);
        switch (ext) {
          case 0: mnemonic = 'TEST $rm, ${imm16Hex()}'; break;
          case 2: mnemonic = 'NOT $rm'; break;
          case 3: mnemonic = 'NEG $rm'; break;
          case 4: mnemonic = 'MUL $rm'; break;
          case 5: mnemonic = 'IMUL $rm'; break;
          case 6: mnemonic = 'DIV $rm'; break;
          case 7: mnemonic = 'IDIV $rm'; break;
          default: mnemonic = 'DB ${(b2 & 0xFF).toRadixString(16).toUpperCase()}h';
        }
        break;
      }

      // ── IMUL with immediate ───────────────────────────────────────────────
      case 0x69: {
        final b2 = nextByte();
        mnemonic = 'IMUL ${regRM(b2, true)}, ${modRM(b2, true)}, ${imm16Hex()}';
        break;
      }
      case 0x6B: {
        final b2 = nextByte();
        mnemonic = 'IMUL ${regRM(b2, true)}, ${modRM(b2, true)}, ${imm8Hex()}';
        break;
      }

      // ── GRP1: ADD/OR/ADC/SBB/AND/SUB/XOR/CMP with immediate ─────────────
      case 0x80: {
        final b2 = nextByte();
        final ops = ['ADD','OR','ADC','SBB','AND','SUB','XOR','CMP'];
        mnemonic = '${ops[(b2>>3)&7]} ${modRM(b2, false)}, ${imm8Hex()}';
        break;
      }
      case 0x81: {
        final b2 = nextByte();
        final ops = ['ADD','OR','ADC','SBB','AND','SUB','XOR','CMP'];
        mnemonic = '${ops[(b2>>3)&7]} ${modRM(b2, true)}, ${imm16Hex()}';
        break;
      }
      case 0x83: {
        final b2 = nextByte();
        final ops = ['ADD','OR','ADC','SBB','AND','SUB','XOR','CMP'];
        mnemonic = '${ops[(b2>>3)&7]} ${modRM(b2, true)}, ${imm8Hex()}';
        break;
      }

      // ── FE/FF: INC/DEC/CALL/JMP/PUSH r/m ────────────────────────────────
      case 0xFE: {
        final b2 = nextByte();
        final ext = (b2 >> 3) & 7;
        final rm = modRM(b2, false);
        mnemonic = ext == 0 ? 'INC $rm' : ext == 1 ? 'DEC $rm' : 'DB FEh';
        break;
      }
      case 0xFF: {
        final b2 = nextByte();
        final ext = (b2 >> 3) & 7;
        final rm = modRM(b2, true);
        switch (ext) {
          case 0: mnemonic = 'INC $rm'; break;
          case 1: mnemonic = 'DEC $rm'; break;
          case 2: mnemonic = 'CALL $rm'; break;
          case 4: mnemonic = 'JMP $rm'; break;
          case 6: mnemonic = 'PUSH $rm'; break;
          default: mnemonic = 'DB FFh';
        }
        break;
      }

      // ── Jumps ─────────────────────────────────────────────────────────────
      case 0x70: mnemonic = 'JO  ${rel8(start)}'; break;
      case 0x71: mnemonic = 'JNO ${rel8(start)}'; break;
      case 0x72: mnemonic = 'JB  ${rel8(start)}'; break;
      case 0x73: mnemonic = 'JNB ${rel8(start)}'; break;
      case 0x74: mnemonic = 'JE  ${rel8(start)}'; break;
      case 0x75: mnemonic = 'JNE ${rel8(start)}'; break;
      case 0x76: mnemonic = 'JBE ${rel8(start)}'; break;
      case 0x77: mnemonic = 'JA  ${rel8(start)}'; break;
      case 0x78: mnemonic = 'JS  ${rel8(start)}'; break;
      case 0x79: mnemonic = 'JNS ${rel8(start)}'; break;
      case 0x7A: mnemonic = 'JPE ${rel8(start)}'; break;
      case 0x7B: mnemonic = 'JPO ${rel8(start)}'; break;
      case 0x7C: mnemonic = 'JL  ${rel8(start)}'; break;
      case 0x7D: mnemonic = 'JGE ${rel8(start)}'; break;
      case 0x7E: mnemonic = 'JLE ${rel8(start)}'; break;
      case 0x7F: mnemonic = 'JG  ${rel8(start)}'; break;
      case 0xE0: mnemonic = 'LOOPNZ ${rel8(start)}'; break;
      case 0xE1: mnemonic = 'LOOPZ  ${rel8(start)}'; break;
      case 0xE2: mnemonic = 'LOOP   ${rel8(start)}'; break;
      case 0xE3: mnemonic = 'JCXZ   ${rel8(start)}'; break;
      case 0xEB: mnemonic = 'JMP SHORT ${rel8(start)}'; break;

      case 0xE9: {
        final off = nextWord();
        final signed = off > 32767 ? off - 65536 : off;
        final target = (start + 3 + signed) & 0xFFFF;
        mnemonic = 'JMP ${target.toRadixString(16).toUpperCase().padLeft(4,'0')}h';
        break;
      }
      case 0xEA: {
        final off  = nextWord();
        final seg  = nextWord();
        mnemonic = 'JMP FAR ${seg.toRadixString(16).toUpperCase()}:${off.toRadixString(16).toUpperCase().padLeft(4,'0')}';
        break;
      }

      // ── CALL ─────────────────────────────────────────────────────────────
      case 0xE8: {
        final off = nextWord();
        final signed = off > 32767 ? off - 65536 : off;
        final target = (start + 3 + signed) & 0xFFFF;
        mnemonic = 'CALL ${target.toRadixString(16).toUpperCase().padLeft(4,'0')}h';
        break;
      }
      case 0x9A: {
        final off  = nextWord();
        final seg  = nextWord();
        mnemonic = 'CALL FAR ${seg.toRadixString(16).toUpperCase()}:${off.toRadixString(16).toUpperCase().padLeft(4,'0')}';
        break;
      }

      // ── RET ──────────────────────────────────────────────────────────────
      case 0xC3: mnemonic = 'RET'; break;
      case 0xC2: mnemonic = 'RET ${imm16Hex()}'; break;
      case 0xCB: mnemonic = 'RETF'; break;

      // ── INT / IRET ───────────────────────────────────────────────────────
      case 0xCD: mnemonic = 'INT ${imm8Hex()}'; break;
      case 0xCC: mnemonic = 'INT 3'; break;
      case 0xCE: mnemonic = 'INTO'; break;
      case 0xCF: mnemonic = 'IRET'; break;

      // ── LEA / LDS / LES ──────────────────────────────────────────────────
      case 0x8D: {
        final b2 = nextByte();
        mnemonic = 'LEA ${regRM(b2, true)}, ${modRM(b2, true)}';
        break;
      }
      case 0xC4: {
        final b2 = nextByte();
        mnemonic = 'LES ${regRM(b2, true)}, ${modRM(b2, true)}';
        break;
      }
      case 0xC5: {
        final b2 = nextByte();
        mnemonic = 'LDS ${regRM(b2, true)}, ${modRM(b2, true)}';
        break;
      }

      // ── XCHG ─────────────────────────────────────────────────────────────
      case 0x86: {
        final b2 = nextByte();
        mnemonic = 'XCHG ${modRM(b2,false)}, ${regRM(b2,false)}';
        break;
      }
      case 0x87: {
        final b2 = nextByte();
        mnemonic = 'XCHG ${modRM(b2,true)}, ${regRM(b2,true)}';
        break;
      }
      case 0x90: mnemonic = 'NOP'; break;
      case 0x91: case 0x92: case 0x93: case 0x94:
      case 0x95: case 0x96: case 0x97:
        mnemonic = 'XCHG AX, ${_reg16[opcode & 7]}'; break;

      // ── String ops ───────────────────────────────────────────────────────
      case 0xA4: mnemonic = 'MOVSB'; break;
      case 0xA5: mnemonic = 'MOVSW'; break;
      case 0xA6: mnemonic = 'CMPSB'; break;
      case 0xA7: mnemonic = 'CMPSW'; break;
      case 0xAA: mnemonic = 'STOSB'; break;
      case 0xAB: mnemonic = 'STOSW'; break;
      case 0xAC: mnemonic = 'LODSB'; break;
      case 0xAD: mnemonic = 'LODSW'; break;
      case 0xAE: mnemonic = 'SCASB'; break;
      case 0xAF: mnemonic = 'SCASW'; break;
      case 0xA8: mnemonic = 'TEST AL, ${imm8Hex()}'; break;
      case 0xA9: mnemonic = 'TEST AX, ${imm16Hex()}'; break;

      // ── REP prefixes ─────────────────────────────────────────────────────
      case 0xF2: {
        final nx = nextByte();
        mnemonic = 'REPNZ ${_stringOp(nx)}';
        break;
      }
      case 0xF3: {
        final nx = nextByte();
        mnemonic = 'REP ${_stringOp(nx)}';
        break;
      }

      // ── IN / OUT ─────────────────────────────────────────────────────────
      case 0xE4: mnemonic = 'IN AL, ${imm8Hex()}'; break;
      case 0xE5: mnemonic = 'IN AX, ${imm8Hex()}'; break;
      case 0xE6: mnemonic = 'OUT ${imm8Hex()}, AL'; break;
      case 0xE7: mnemonic = 'OUT ${imm8Hex()}, AX'; break;
      case 0xEC: mnemonic = 'IN AL, DX'; break;
      case 0xED: mnemonic = 'IN AX, DX'; break;
      case 0xEE: mnemonic = 'OUT DX, AL'; break;
      case 0xEF: mnemonic = 'OUT DX, AX'; break;

      // ── Flag ops ─────────────────────────────────────────────────────────
      case 0xF8: mnemonic = 'CLC'; break;
      case 0xF9: mnemonic = 'STC'; break;
      case 0xFA: mnemonic = 'CLI'; break;
      case 0xFB: mnemonic = 'STI'; break;
      case 0xFC: mnemonic = 'CLD'; break;
      case 0xFD: mnemonic = 'STD'; break;
      case 0xF4: mnemonic = 'HLT'; break;
      case 0xF0: mnemonic = 'LOCK'; break;

      // ── PUSHA / POPA / PUSHF / POPF ──────────────────────────────────────
      case 0x60: mnemonic = 'PUSHA'; break;
      case 0x61: mnemonic = 'POPA'; break;
      case 0x9C: mnemonic = 'PUSHF'; break;
      case 0x9D: mnemonic = 'POPF'; break;
      case 0x9E: mnemonic = 'SAHF'; break;
      case 0x9F: mnemonic = 'LAHF'; break;

      // ── CBW / CWD ────────────────────────────────────────────────────────
      case 0x98: mnemonic = 'CBW'; break;
      case 0x99: mnemonic = 'CWD'; break;

      // ── Shift / rotate GRP2 ──────────────────────────────────────────────
      case 0xD0: {
        final b2 = nextByte();
        final ops = ['ROL','ROR','RCL','RCR','SHL','SHR','SAL','SAR'];
        mnemonic = '${ops[(b2>>3)&7]} ${modRM(b2,false)}, 1';
        break;
      }
      case 0xD1: {
        final b2 = nextByte();
        final ops = ['ROL','ROR','RCL','RCR','SHL','SHR','SAL','SAR'];
        mnemonic = '${ops[(b2>>3)&7]} ${modRM(b2,true)}, 1';
        break;
      }
      case 0xD2: {
        final b2 = nextByte();
        final ops = ['ROL','ROR','RCL','RCR','SHL','SHR','SAL','SAR'];
        mnemonic = '${ops[(b2>>3)&7]} ${modRM(b2,false)}, CL';
        break;
      }
      case 0xD3: {
        final b2 = nextByte();
        final ops = ['ROL','ROR','RCL','RCR','SHL','SHR','SAL','SAR'];
        mnemonic = '${ops[(b2>>3)&7]} ${modRM(b2,true)}, CL';
        break;
      }

      // ── ENTER / LEAVE ─────────────────────────────────────────────────────
      case 0xC8: {
        final sz = nextWord();
        final lv = nextByte();
        mnemonic = 'ENTER ${sz.toRadixString(16).toUpperCase()}h, ${lv.toRadixString(16).toUpperCase()}h';
        break;
      }
      case 0xC9: mnemonic = 'LEAVE'; break;

      // ── ADC / SBB ────────────────────────────────────────────────────────
      case 0x10: case 0x11: case 0x12: case 0x13:
        mnemonic = alu('ADC', opcode); break;
      case 0x14: mnemonic = 'ADC AL, ${imm8Hex()}'; break;
      case 0x15: mnemonic = 'ADC AX, ${imm16Hex()}'; break;
      case 0x18: case 0x19: case 0x1A: case 0x1B:
        mnemonic = alu('SBB', opcode); break;
      case 0x1C: mnemonic = 'SBB AL, ${imm8Hex()}'; break;
      case 0x1D: mnemonic = 'SBB AX, ${imm16Hex()}'; break;

      // ── TEST ─────────────────────────────────────────────────────────────
      case 0x84: {
        final b2 = nextByte();
        mnemonic = 'TEST ${modRM(b2,false)}, ${regRM(b2,false)}';
        break;
      }
      case 0x85: {
        final b2 = nextByte();
        mnemonic = 'TEST ${modRM(b2,true)}, ${regRM(b2,true)}';
        break;
      }

      // ── DAA/DAS/AAA/AAS/AAM/AAD ──────────────────────────────────────────
      case 0x27: mnemonic = 'DAA'; break;
      case 0x2F: mnemonic = 'DAS'; break;
      case 0x37: mnemonic = 'AAA'; break;
      case 0x3F: mnemonic = 'AAS'; break;
      case 0xD4: { nextByte(); mnemonic = 'AAM'; break; }
      case 0xD5: { nextByte(); mnemonic = 'AAD'; break; }

      // ── XLAT ─────────────────────────────────────────────────────────────
      case 0xD7: mnemonic = 'XLAT'; break;

      // ── Segment overrides (show with next instr) ──────────────────────────
      case 0x26: case 0x2E: case 0x36: case 0x3E: {
        final segs = {0x26:'ES:',0x2E:'CS:',0x36:'SS:',0x3E:'DS:'};
        mnemonic = '${segs[opcode]}${_peekMnemonicByte(peekByte())}';
        nextByte(); // consume next opcode (simplified)
        break;
      }

      default:
        mnemonic = 'DB ${opcode.toRadixString(16).toUpperCase().padLeft(2,'0')}h';
    }

    return DisasmResult(
      address: start,
      bytes: bytes,
      mnemonic: mnemonic.trimRight(),
      nextAddress: addr,
    );
  }

  String _stringOp(int op) {
    const map = {
      0xA4:'MOVSB', 0xA5:'MOVSW',
      0xA6:'CMPSB', 0xA7:'CMPSW',
      0xAA:'STOSB', 0xAB:'STOSW',
      0xAC:'LODSB', 0xAD:'LODSW',
      0xAE:'SCASB', 0xAF:'SCASW',
    };
    return map[op] ?? op.toRadixString(16).toUpperCase().padLeft(2,'0') + 'h';
  }

  String _peekMnemonicByte(int op) {
    const simple = {
      0xA4:'MOVSB', 0xA5:'MOVSW', 0xAA:'STOSB', 0xAB:'STOSW',
      0xAC:'LODSB', 0xAD:'LODSW', 0xAE:'SCASB', 0xAF:'SCASW',
    };
    return simple[op] ?? '...';
  }

  // Disassemble [count] instructions starting at [addr]
  List<DisasmResult> disasmN(int addr, int count) {
    final result = <DisasmResult>[];
    int cur = addr & 0xFFFF;
    for (int i = 0; i < count; i++) {
      final d = disasm(cur);
      result.add(d);
      cur = d.nextAddress;
      if (cur == 0) break; // wrapped
    }
    return result;
  }
}
