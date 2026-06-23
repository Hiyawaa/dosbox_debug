// lib/debug_exe/dbg_isa.dart
//
// A real 8086 instruction encoder + decoder covering the common subset of
// the instruction set that MS-DOS DEBUG.EXE users actually exercise:
// data movement, arithmetic, logic, stack, control flow, and INT.
// This is deliberately scoped (not the full 8086 ISA with every addressing
// mode) but every instruction it supports round-trips correctly through
// assemble (A) -> bytes in memory -> unassemble (U) -> execute (T/G/P),
// exactly like real DEBUG.EXE.

class Reg {
  static const List<String> r8 = [
    'AL',
    'CL',
    'DL',
    'BL',
    'AH',
    'CH',
    'DH',
    'BH'
  ];
  static const List<String> r16 = [
    'AX',
    'CX',
    'DX',
    'BX',
    'SP',
    'BP',
    'SI',
    'DI'
  ];
  static const List<String> sreg = ['ES', 'CS', 'SS', 'DS'];
  // Effective address templates for mod=00/01/10, r/m 0-6 (7 is direct/BP+disp)
  static const List<String> ea = [
    'BX+SI',
    'BX+DI',
    'BP+SI',
    'BP+DI',
    'SI',
    'DI',
    'BP',
    'BX'
  ];
}

/// Result of decoding one instruction starting at a linear address.
class Decoded {
  final int length; // bytes consumed
  final String mnemonic;
  final String operands; // already comma-joined, DEBUG.EXE style
  final List<int> bytes;

  Decoded(this.length, this.mnemonic, this.operands, this.bytes);

  String get text =>
      operands.isEmpty ? mnemonic : '$mnemonic'.padRight(7) + operands;
}

class AssembleResult {
  final List<int> bytes;
  final String? error;
  AssembleResult(this.bytes, {this.error});
  bool get ok => error == null;
}

class DbgIsa {
  // ============================== DECODER ==============================

  /// Decode one instruction from `mem` (a 1MB List<int>) at linear address
  /// `addr`, with current CS used only for display purposes by the caller.
  static Decoded decode(List<int> mem, int addr) {
    final start = addr;
    int b0 = mem[addr & 0xFFFFF];
    addr++;

    int u8() {
      final v = mem[addr & 0xFFFFF];
      addr++;
      return v;
    }

    int s8() {
      final v = u8();
      return v >= 0x80 ? v - 0x100 : v;
    }

    int u16() {
      final lo = u8();
      final hi = u8();
      return lo | (hi << 8);
    }

    String hex8(int v) =>
        '${v.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    String hex16(int v) =>
        '${v.toRadixString(16).toUpperCase().padLeft(4, '0')}';
    String immStr8(int v) => v < 0 ? '-${hex8(-v)}' : hex8(v);

    // Decode a ModRM byte into (mod, reg, rm) plus the textual r/m operand,
    // consuming any displacement bytes it implies.
    Map<String, dynamic> modrm({required bool wide}) {
      final m = u8();
      final mod = (m >> 6) & 0x3;
      final reg = (m >> 3) & 0x7;
      final rm = m & 0x7;
      String rmText;
      if (mod == 3) {
        rmText = wide ? Reg.r16[rm] : Reg.r8[rm];
      } else if (mod == 0 && rm == 6) {
        final disp = u16();
        rmText = '[${hex16(disp)}]';
      } else {
        String base = Reg.ea[rm];
        if (mod == 1) {
          final d = s8();
          if (d != 0)
            base += (d < 0
                ? '-${(-d).toRadixString(16).toUpperCase()}'
                : '+${d.toRadixString(16).toUpperCase()}');
        } else if (mod == 2) {
          final d = u16();
          if (d != 0) base += '+${hex16(d)}';
        }
        rmText = '[$base]';
      }
      return {'mod': mod, 'reg': reg, 'rm': rm, 'text': rmText};
    }

    String regName(int idx, bool wide) => wide ? Reg.r16[idx] : Reg.r8[idx];

    Decoded done(String mn, String ops) {
      final len = addr - start;
      final bytes = List<int>.generate(len, (i) => mem[(start + i) & 0xFFFFF]);
      return Decoded(len, mn, ops, bytes);
    }

    // ---- ADD/SUB/CMP/AND/OR/XOR/ADC/SBB family: 00-3D, with /r and AL/AX,imm forms
    const aluMnemonics = [
      'ADD',
      'OR',
      'ADC',
      'SBB',
      'AND',
      'SUB',
      'XOR',
      'CMP'
    ];
    if (b0 < 0x40 && (b0 & 0xC0) == 0x00 && (b0 & 0x07) <= 5) {
      final group = (b0 >> 3) & 0x7;
      final mn = aluMnemonics[group];
      final low = b0 & 0x07;
      switch (low) {
        case 0:
          {
            final m = modrm(wide: false);
            return done(mn, '${m['text']},${regName(m['reg'], false)}');
          }
        case 1:
          {
            final m = modrm(wide: true);
            return done(mn, '${m['text']},${regName(m['reg'], true)}');
          }
        case 2:
          {
            final m = modrm(wide: false);
            return done(mn, '${regName(m['reg'], false)},${m['text']}');
          }
        case 3:
          {
            final m = modrm(wide: true);
            return done(mn, '${regName(m['reg'], true)},${m['text']}');
          }
        case 4:
          {
            final imm = u8();
            return done(mn, 'AL,${immStr8(imm)}');
          }
        case 5:
          {
            final imm = u16();
            return done(mn, 'AX,${hex16(imm)}');
          }
      }
    }

    // ---- MOV reg/mem, reg (88-8B)
    if (b0 == 0x88) {
      final m = modrm(wide: false);
      return done('MOV', '${m['text']},${regName(m['reg'], false)}');
    }
    if (b0 == 0x89) {
      final m = modrm(wide: true);
      return done('MOV', '${m['text']},${regName(m['reg'], true)}');
    }
    if (b0 == 0x8A) {
      final m = modrm(wide: false);
      return done('MOV', '${regName(m['reg'], false)},${m['text']}');
    }
    if (b0 == 0x8B) {
      final m = modrm(wide: true);
      return done('MOV', '${regName(m['reg'], true)},${m['text']}');
    }

    // ---- MOV sreg (8C/8E)
    if (b0 == 0x8E) {
      final m = modrm(wide: true);
      return done('MOV', '${Reg.sreg[m['reg']]},${m['text']}');
    }
    if (b0 == 0x8C) {
      final m = modrm(wide: true);
      return done('MOV', '${m['text']},${Reg.sreg[m['reg']]}');
    }

    // ---- MOV reg, imm (B0-BF)
    if (b0 >= 0xB0 && b0 <= 0xB7) {
      final r = b0 - 0xB0;
      final imm = u8();
      return done('MOV', '${Reg.r8[r]},${hex8(imm)}');
    }
    if (b0 >= 0xB8 && b0 <= 0xBF) {
      final r = b0 - 0xB8;
      final imm = u16();
      return done('MOV', '${Reg.r16[r]},${hex16(imm)}');
    }

    // ---- MOV mem/acc, imm (C6/C7)
    if (b0 == 0xC6) {
      final m = modrm(wide: false);
      final imm = u8();
      return done('MOV', '${m['text']},${hex8(imm)}');
    }
    if (b0 == 0xC7) {
      final m = modrm(wide: true);
      final imm = u16();
      return done('MOV', '${m['text']},${hex16(imm)}');
    }

    // ---- MOV AL/AX, [addr] and reverse (A0-A3)
    if (b0 == 0xA0) {
      final a = u16();
      return done('MOV', 'AL,[${hex16(a)}]');
    }
    if (b0 == 0xA1) {
      final a = u16();
      return done('MOV', 'AX,[${hex16(a)}]');
    }
    if (b0 == 0xA2) {
      final a = u16();
      return done('MOV', '[${hex16(a)}],AL');
    }
    if (b0 == 0xA3) {
      final a = u16();
      return done('MOV', '[${hex16(a)}],AX');
    }

    // ---- PUSH/POP reg (50-5F)
    if (b0 >= 0x50 && b0 <= 0x57) return done('PUSH', Reg.r16[b0 - 0x50]);
    if (b0 >= 0x58 && b0 <= 0x5F) return done('POP', Reg.r16[b0 - 0x58]);
    if (b0 == 0x06) return done('PUSH', 'ES');
    if (b0 == 0x07) return done('POP', 'ES');
    if (b0 == 0x0E) return done('PUSH', 'CS');
    if (b0 == 0x16) return done('PUSH', 'SS');
    if (b0 == 0x17) return done('POP', 'SS');
    if (b0 == 0x1E) return done('PUSH', 'DS');
    if (b0 == 0x1F) return done('POP', 'DS');

    // ---- INC/DEC reg16 (40-4F)
    if (b0 >= 0x40 && b0 <= 0x47) return done('INC', Reg.r16[b0 - 0x40]);
    if (b0 >= 0x48 && b0 <= 0x4F) return done('DEC', Reg.r16[b0 - 0x48]);

    // ---- XCHG AX,reg (91-97), and reg/mem,reg (86/87)
    if (b0 >= 0x91 && b0 <= 0x97)
      return done('XCHG', 'AX,${Reg.r16[b0 - 0x90]}');
    if (b0 == 0x86) {
      final m = modrm(wide: false);
      return done('XCHG', '${regName(m['reg'], false)},${m['text']}');
    }
    if (b0 == 0x87) {
      final m = modrm(wide: true);
      return done('XCHG', '${regName(m['reg'], true)},${m['text']}');
    }

    // ---- INC/DEC mem (FE/FF group)
    if (b0 == 0xFE) {
      final m = modrm(wide: false);
      final op = m['reg'] as int;
      return done(op == 0 ? 'INC' : 'DEC', m['text']);
    }
    if (b0 == 0xFF) {
      final m = modrm(wide: true);
      final op = m['reg'] as int;
      const names = ['INC', 'DEC', 'CALL', 'CALL', 'JMP', 'JMP', 'PUSH', '???'];
      final mn = names[op];
      if (op == 2 || op == 4) return done(mn, m['text']); // near indirect
      if (op == 3 || op == 5) return done(mn, 'FAR ${m['text']}');
      return done(mn, m['text']);
    }

    // ---- Group 1 (80/81/83): ALU with imm, mod/reg selects op
    if (b0 == 0x80) {
      final m = modrm(wide: false);
      final mn = aluMnemonics[m['reg']];
      final imm = u8();
      return done(mn, '${m['text']},${immStr8(imm)}');
    }
    if (b0 == 0x81) {
      final m = modrm(wide: true);
      final mn = aluMnemonics[m['reg']];
      final imm = u16();
      return done(mn, '${m['text']},${hex16(imm)}');
    }
    if (b0 == 0x83) {
      final m = modrm(wide: true);
      final mn = aluMnemonics[m['reg']];
      final imm = s8();
      return done(mn, '${m['text']},${immStr8(imm)}');
    }

    // ---- TEST
    if (b0 == 0x84) {
      final m = modrm(wide: false);
      return done('TEST', '${m['text']},${regName(m['reg'], false)}');
    }
    if (b0 == 0x85) {
      final m = modrm(wide: true);
      return done('TEST', '${m['text']},${regName(m['reg'], true)}');
    }
    if (b0 == 0xA8) {
      final imm = u8();
      return done('TEST', 'AL,${hex8(imm)}');
    }
    if (b0 == 0xA9) {
      final imm = u16();
      return done('TEST', 'AX,${hex16(imm)}');
    }

    // ---- NOT/NEG/MUL/IMUL/DIV/IDIV (F6/F7 group)
    if (b0 == 0xF6 || b0 == 0xF7) {
      final wide = b0 == 0xF7;
      final m = modrm(wide: wide);
      const names = [
        'TEST',
        'TEST',
        'NOT',
        'NEG',
        'MUL',
        'IMUL',
        'DIV',
        'IDIV'
      ];
      final op = m['reg'] as int;
      if (op == 0 || op == 1) {
        final imm = wide ? u16() : u8();
        return done('TEST', '${m['text']},${wide ? hex16(imm) : hex8(imm)}');
      }
      return done(names[op], m['text']);
    }

    // ---- Shift/rotate group (D0-D3)
    if (b0 >= 0xD0 && b0 <= 0xD3) {
      final wide = (b0 & 1) == 1;
      final byCl = (b0 & 2) == 2;
      final m = modrm(wide: wide);
      const names = ['ROL', 'ROR', 'RCL', 'RCR', 'SHL', 'SHR', 'SAL', 'SAR'];
      final mn = names[m['reg']];
      return done(mn, '${m['text']},${byCl ? 'CL' : '1'}');
    }

    // ---- INT
    if (b0 == 0xCD) {
      final n = u8();
      return done('INT', hex8(n));
    }
    if (b0 == 0xCC) return done('INT', '3');
    if (b0 == 0xCE) return done('INTO', '');
    if (b0 == 0xCF) return done('IRET', '');

    // ---- HLT / NOP / WAIT / CLI / STI / CLC / STC / CMC / CLD / STD
    if (b0 == 0xF4) return done('HLT', '');
    if (b0 == 0x90) return done('NOP', '');
    if (b0 == 0xF8) return done('CLC', '');
    if (b0 == 0xF9) return done('STC', '');
    if (b0 == 0xF5) return done('CMC', '');
    if (b0 == 0xFA) return done('CLI', '');
    if (b0 == 0xFB) return done('STI', '');
    if (b0 == 0xFC) return done('CLD', '');
    if (b0 == 0xFD) return done('STD', '');

    // ---- Jcc rel8 (70-7F)
    const jccNames = [
      'JO',
      'JNO',
      'JB',
      'JNB',
      'JZ',
      'JNZ',
      'JBE',
      'JA',
      'JS',
      'JNS',
      'JP',
      'JNP',
      'JL',
      'JGE',
      'JLE',
      'JG'
    ];
    if (b0 >= 0x70 && b0 <= 0x7F) {
      final rel = s8();
      final target = (start + 2 + rel) & 0xFFFF;
      return done(jccNames[b0 - 0x70], hex16(target));
    }
    // LOOP/LOOPZ/LOOPNZ/JCXZ (E0-E3)
    if (b0 == 0xE0) {
      final rel = s8();
      return done('LOOPNZ', hex16((start + 2 + rel) & 0xFFFF));
    }
    if (b0 == 0xE1) {
      final rel = s8();
      return done('LOOPZ', hex16((start + 2 + rel) & 0xFFFF));
    }
    if (b0 == 0xE2) {
      final rel = s8();
      return done('LOOP', hex16((start + 2 + rel) & 0xFFFF));
    }
    if (b0 == 0xE3) {
      final rel = s8();
      return done('JCXZ', hex16((start + 2 + rel) & 0xFFFF));
    }

    // ---- CALL/JMP near rel16 (E8/E9), JMP short rel8 (EB)
    if (b0 == 0xE8) {
      final rel = u16();
      final r = rel >= 0x8000 ? rel - 0x10000 : rel;
      return done('CALL', hex16((start + 3 + r) & 0xFFFF));
    }
    if (b0 == 0xE9) {
      final rel = u16();
      final r = rel >= 0x8000 ? rel - 0x10000 : rel;
      return done('JMP', hex16((start + 3 + r) & 0xFFFF));
    }
    if (b0 == 0xEB) {
      final rel = s8();
      return done('JMP', hex16((start + 2 + rel) & 0xFFFF));
    }

    // ---- CALL/JMP far direct (9A/EA)
    if (b0 == 0x9A) {
      final off = u16();
      final seg = u16();
      return done('CALL', '${hex16(seg)}:${hex16(off)}');
    }
    if (b0 == 0xEA) {
      final off = u16();
      final seg = u16();
      return done('JMP', '${hex16(seg)}:${hex16(off)}');
    }

    // ---- RET / RETF
    if (b0 == 0xC3) return done('RET', '');
    if (b0 == 0xC2) {
      final n = u16();
      return done('RET', hex16(n));
    }
    if (b0 == 0xCB) return done('RETF', '');
    if (b0 == 0xCA) {
      final n = u16();
      return done('RETF', hex16(n));
    }

    // ---- LEA / LDS / LES
    if (b0 == 0x8D) {
      final m = modrm(wide: true);
      return done('LEA', '${regName(m['reg'], true)},${m['text']}');
    }
    if (b0 == 0xC5) {
      final m = modrm(wide: true);
      return done('LDS', '${regName(m['reg'], true)},${m['text']}');
    }
    if (b0 == 0xC4) {
      final m = modrm(wide: true);
      return done('LES', '${regName(m['reg'], true)},${m['text']}');
    }

    // ---- String ops
    if (b0 == 0xA4) return done('MOVSB', '');
    if (b0 == 0xA5) return done('MOVSW', '');
    if (b0 == 0xA6) return done('CMPSB', '');
    if (b0 == 0xA7) return done('CMPSW', '');
    if (b0 == 0xAA) return done('STOSB', '');
    if (b0 == 0xAB) return done('STOSW', '');
    if (b0 == 0xAC) return done('LODSB', '');
    if (b0 == 0xAD) return done('LODSW', '');
    if (b0 == 0xAE) return done('SCASB', '');
    if (b0 == 0xAF) return done('SCASW', '');
    if (b0 == 0xF2) {
      final next = decode(mem, addr);
      return Decoded(1 + next.length, 'REPNZ ${next.mnemonic}', next.operands,
          [b0, ...next.bytes]);
    }
    if (b0 == 0xF3) {
      final next = decode(mem, addr);
      return Decoded(1 + next.length, 'REPZ ${next.mnemonic}', next.operands,
          [b0, ...next.bytes]);
    }

    // ---- IN/OUT
    if (b0 == 0xE4) {
      final p = u8();
      return done('IN', 'AL,${hex8(p)}');
    }
    if (b0 == 0xE5) {
      final p = u8();
      return done('IN', 'AX,${hex8(p)}');
    }
    if (b0 == 0xEC) return done('IN', 'AL,DX');
    if (b0 == 0xED) return done('IN', 'AX,DX');
    if (b0 == 0xE6) {
      final p = u8();
      return done('OUT', '${hex8(p)},AL');
    }
    if (b0 == 0xE7) {
      final p = u8();
      return done('OUT', '${hex8(p)},AX');
    }
    if (b0 == 0xEE) return done('OUT', 'DX,AL');
    if (b0 == 0xEF) return done('OUT', 'DX,AX');

    // ---- PUSHF/POPF/SAHF/LAHF
    if (b0 == 0x9C) return done('PUSHF', '');
    if (b0 == 0x9D) return done('POPF', '');
    if (b0 == 0x9E) return done('SAHF', '');
    if (b0 == 0x9F) return done('LAHF', '');
    if (b0 == 0x98) return done('CBW', '');
    if (b0 == 0x99) return done('CWD', '');

    // ---- Segment override prefixes
    const segNames = {0x26: 'ES', 0x2E: 'CS', 0x36: 'SS', 0x3E: 'DS'};
    if (segNames.containsKey(b0)) {
      final next = decode(mem, addr);
      return Decoded(1 + next.length, next.mnemonic,
          '${segNames[b0]}:${next.operands}', [b0, ...next.bytes]);
    }

    // Unknown opcode: DEBUG.EXE prints "(db    XX)"
    return done('DB', hex8(b0));
  }

  // ============================== ENCODER ==============================
  // Used by the A (assemble) command. Supports the same instruction subset
  // as the decoder, in DEBUG.EXE's "MNEMONIC operand,operand" syntax.

  static int? parseImm(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final neg = s.startsWith('-');
    if (neg) s = s.substring(1);
    final up = s.toUpperCase();
    int? v;
    if (up.endsWith('H')) {
      v = int.tryParse(up.substring(0, up.length - 1), radix: 16);
    } else {
      v = int.tryParse(up, radix: 16) ?? int.tryParse(up);
    }
    if (v == null) return null;
    return neg ? -v : v;
  }

  /// Parse a memory operand like [1234], [BX+SI], [BX+4], [SI] into modrm bits.
  /// Returns null if `s` isn't a bracketed memory operand.
  static Map<String, dynamic>? parseMem(String s) {
    s = s.trim();
    if (!s.startsWith('[') || !s.endsWith(']')) return null;
    final inner = s.substring(1, s.length - 1).trim().toUpperCase();
    // try each ea pattern first (so BX/SI etc. aren't mistaken for hex literals)
    for (int i = 0; i < Reg.ea.length; i++) {
      final base = Reg.ea[i];
      if (inner == base) {
        return {'mod': 0, 'rm': i, 'disp': 0, 'dispSize': 0};
      }
      if (inner.startsWith('$base+') || inner.startsWith('$base-')) {
        final rest = inner.substring(base.length);
        final d = parseImm(rest);
        if (d == null) continue;
        if (d >= -128 && d <= 127) {
          return {'mod': 1, 'rm': i, 'disp': d & 0xFF, 'dispSize': 1};
        }
        return {'mod': 2, 'rm': i, 'disp': d & 0xFFFF, 'dispSize': 2};
      }
    }
    // direct address [1234]
    final direct = parseImm(inner);
    if (direct != null) {
      return {'mod': 0, 'rm': 6, 'disp': direct & 0xFFFF, 'dispSize': 2};
    }
    return null;
  }

  static List<int> _modrmBytes(int regField, Map<String, dynamic> ea) {
    final mod = ea['mod'] as int;
    final rm = ea['rm'] as int;
    final out = <int>[(mod << 6) | ((regField & 7) << 3) | rm];
    if (ea['dispSize'] == 1) out.add(ea['disp'] & 0xFF);
    if (ea['dispSize'] == 2) {
      out.add(ea['disp'] & 0xFF);
      out.add((ea['disp'] >> 8) & 0xFF);
    }
    return out;
  }

  /// Assemble one DEBUG.EXE-style instruction line, e.g. "MOV AX,1234".
  /// `addr` is the linear address the instruction will be placed at (needed
  /// to compute relative jump displacements).
  static AssembleResult assembleLine(String line, int addr) {
    line = line.trim();
    if (line.isEmpty) return AssembleResult([], error: 'Empty instruction');

    final spaceIdx = line.indexOf(RegExp(r'\s'));
    final mnemonic =
        (spaceIdx == -1 ? line : line.substring(0, spaceIdx)).toUpperCase();
    final rest = spaceIdx == -1 ? '' : line.substring(spaceIdx + 1).trim();
    final operands = rest.isEmpty
        ? <String>[]
        : rest.split(',').map((s) => s.trim()).toList();

    int? r16(String s) => Reg.r16.contains(s.toUpperCase())
        ? Reg.r16.indexOf(s.toUpperCase())
        : null;
    int? r8(String s) => Reg.r8.contains(s.toUpperCase())
        ? Reg.r8.indexOf(s.toUpperCase())
        : null;
    int? sr(String s) => Reg.sreg.contains(s.toUpperCase())
        ? Reg.sreg.indexOf(s.toUpperCase())
        : null;

    try {
      switch (mnemonic) {
        case 'MOV':
          {
            if (operands.length != 2)
              return AssembleResult([], error: 'MOV needs 2 operands');
            final dst = operands[0], src = operands[1];
            final dr16 = r16(dst), sr16 = r16(src);
            final dr8 = r8(dst), sr8 = r8(src);
            final dsr = sr(dst), ssr = sr(src);
            final dmem = parseMem(dst), smem = parseMem(src);

            if (dr16 != null && sr16 != null)
              return AssembleResult([0x89, (3 << 6) | (sr16 << 3) | dr16]);
            if (dr8 != null && sr8 != null)
              return AssembleResult([0x88, (3 << 6) | (sr8 << 3) | dr8]);
            if (dr16 != null && ssr != null)
              return AssembleResult([0x8C, (3 << 6) | (ssr << 3) | dr16]);
            if (dsr != null && sr16 != null)
              return AssembleResult([0x8E, (3 << 6) | (dsr << 3) | sr16]);
            if (dr16 != null && smem != null)
              return AssembleResult([0x8B, ..._modrmBytes(dr16, smem)]);
            if (dmem != null && sr16 != null)
              return AssembleResult([0x89, ..._modrmBytes(sr16, dmem)]);
            if (dr8 != null && smem != null)
              return AssembleResult([0x8A, ..._modrmBytes(dr8, smem)]);
            if (dmem != null && sr8 != null)
              return AssembleResult([0x88, ..._modrmBytes(sr8, dmem)]);
            if (dr16 != null) {
              final imm = parseImm(src);
              if (imm == null)
                return AssembleResult([], error: 'Bad immediate: $src');
              return AssembleResult(
                  [0xB8 + dr16, imm & 0xFF, (imm >> 8) & 0xFF]);
            }
            if (dr8 != null) {
              final imm = parseImm(src);
              if (imm == null)
                return AssembleResult([], error: 'Bad immediate: $src');
              return AssembleResult([0xB0 + dr8, imm & 0xFF]);
            }
            if (dmem != null) {
              final imm = parseImm(src);
              if (imm == null)
                return AssembleResult([], error: 'Bad immediate: $src');
              return AssembleResult([
                0xC7,
                ..._modrmBytes(0, dmem),
                imm & 0xFF,
                (imm >> 8) & 0xFF
              ]);
            }
            return AssembleResult([], error: 'Cannot encode MOV $dst,$src');
          }

        case 'ADD':
        case 'OR':
        case 'ADC':
        case 'SBB':
        case 'AND':
        case 'SUB':
        case 'XOR':
        case 'CMP':
          {
            const names = [
              'ADD',
              'OR',
              'ADC',
              'SBB',
              'AND',
              'SUB',
              'XOR',
              'CMP'
            ];
            final group = names.indexOf(mnemonic);
            if (operands.length != 2)
              return AssembleResult([], error: '$mnemonic needs 2 operands');
            final dst = operands[0], src = operands[1];
            final dr16 = r16(dst), sr16 = r16(src);
            final dr8 = r8(dst), sr8 = r8(src);
            final dmem = parseMem(dst);

            if (dr16 != null && sr16 != null)
              return AssembleResult(
                  [(group << 3) | 0x01, (3 << 6) | (sr16 << 3) | dr16]);
            if (dr8 != null && sr8 != null)
              return AssembleResult(
                  [(group << 3) | 0x00, (3 << 6) | (sr8 << 3) | dr8]);
            if (dst.toUpperCase() == 'AX') {
              final imm = parseImm(src);
              if (imm != null)
                return AssembleResult(
                    [(group << 3) | 0x05, imm & 0xFF, (imm >> 8) & 0xFF]);
            }
            if (dr8 != null) {
              final imm = parseImm(src);
              if (imm == null)
                return AssembleResult([], error: 'Bad immediate: $src');
              if (dst.toUpperCase() == 'AL')
                return AssembleResult([(group << 3) | 0x04, imm & 0xFF]);
              return AssembleResult(
                  [0x80, (3 << 6) | (group << 3) | dr8, imm & 0xFF]);
            }
            if (dr16 != null) {
              final imm = parseImm(src);
              if (imm == null)
                return AssembleResult([], error: 'Bad immediate: $src');
              if (imm >= -128 && imm <= 127) {
                return AssembleResult(
                    [0x83, (3 << 6) | (group << 3) | dr16, imm & 0xFF]);
              }
              return AssembleResult([
                0x81,
                (3 << 6) | (group << 3) | dr16,
                imm & 0xFF,
                (imm >> 8) & 0xFF
              ]);
            }
            if (dmem != null && sr16 != null)
              return AssembleResult(
                  [(group << 3) | 0x01, ..._modrmBytes(sr16, dmem)]);
            if (dmem != null && sr8 != null)
              return AssembleResult(
                  [(group << 3) | 0x00, ..._modrmBytes(sr8, dmem)]);
            if (dmem != null) {
              final imm = parseImm(src);
              if (imm == null)
                return AssembleResult([], error: 'Bad immediate: $src');
              if (imm >= -128 && imm <= 127) {
                return AssembleResult(
                    [0x83, ..._modrmBytes(group, dmem), imm & 0xFF]);
              }
              return AssembleResult([
                0x81,
                ..._modrmBytes(group, dmem),
                imm & 0xFF,
                (imm >> 8) & 0xFF
              ]);
            }
            return AssembleResult([],
                error: 'Cannot encode $mnemonic $dst,$src');
          }

        case 'INC':
        case 'DEC':
          {
            if (operands.length != 1)
              return AssembleResult([], error: '$mnemonic needs 1 operand');
            final op = operands[0];
            final ri16 = r16(op);
            if (ri16 != null)
              return AssembleResult([(mnemonic == 'INC' ? 0x40 : 0x48) + ri16]);
            final ri8 = r8(op);
            if (ri8 != null)
              return AssembleResult(
                  [0xFE, (3 << 6) | ((mnemonic == 'INC' ? 0 : 1) << 3) | ri8]);
            final mem = parseMem(op);
            if (mem != null)
              return AssembleResult(
                  [0xFF, ..._modrmBytes(mnemonic == 'INC' ? 0 : 1, mem)]);
            return AssembleResult([], error: 'Cannot encode $mnemonic $op');
          }

        case 'PUSH':
        case 'POP':
          {
            if (operands.length != 1)
              return AssembleResult([], error: '$mnemonic needs 1 operand');
            final op = operands[0];
            final ri16 = r16(op);
            if (ri16 != null)
              return AssembleResult(
                  [(mnemonic == 'PUSH' ? 0x50 : 0x58) + ri16]);
            final si = sr(op);
            if (si != null) {
              const pushOp = [0x06, 0x0E, 0x16, 0x1E];
              const popOp = [0x07, -1, 0x17, 0x1F];
              final code = mnemonic == 'PUSH' ? pushOp[si] : popOp[si];
              if (code < 0)
                return AssembleResult([], error: 'POP CS not valid');
              return AssembleResult([code]);
            }
            return AssembleResult([], error: 'Cannot encode $mnemonic $op');
          }

        case 'JMP':
        case 'CALL':
          {
            if (operands.length != 1)
              return AssembleResult([], error: '$mnemonic needs 1 operand');
            final target = parseImm(operands[0]);
            if (target == null)
              return AssembleResult([], error: 'Bad target: ${operands[0]}');
            if (mnemonic == 'CALL') {
              final rel = (target - (addr + 3)) & 0xFFFF;
              return AssembleResult([0xE8, rel & 0xFF, (rel >> 8) & 0xFF]);
            } else {
              final rel = target - (addr + 2);
              if (rel >= -128 && rel <= 127) {
                return AssembleResult([0xEB, rel & 0xFF]);
              }
              final rel16 = (target - (addr + 3)) & 0xFFFF;
              return AssembleResult([0xE9, rel16 & 0xFF, (rel16 >> 8) & 0xFF]);
            }
          }

        case 'JO':
        case 'JNO':
        case 'JB':
        case 'JC':
        case 'JNB':
        case 'JNC':
        case 'JZ':
        case 'JE':
        case 'JNZ':
        case 'JNE':
        case 'JBE':
        case 'JNA':
        case 'JA':
        case 'JNBE':
        case 'JS':
        case 'JNS':
        case 'JP':
        case 'JPE':
        case 'JNP':
        case 'JPO':
        case 'JL':
        case 'JNGE':
        case 'JGE':
        case 'JNL':
        case 'JLE':
        case 'JNG':
        case 'JG':
        case 'JNLE':
          {
            const map = {
              'JO': 0x70,
              'JNO': 0x71,
              'JB': 0x72,
              'JC': 0x72,
              'JNB': 0x73,
              'JNC': 0x73,
              'JZ': 0x74,
              'JE': 0x74,
              'JNZ': 0x75,
              'JNE': 0x75,
              'JBE': 0x76,
              'JNA': 0x76,
              'JA': 0x77,
              'JNBE': 0x77,
              'JS': 0x78,
              'JNS': 0x79,
              'JP': 0x7A,
              'JPE': 0x7A,
              'JNP': 0x7B,
              'JPO': 0x7B,
              'JL': 0x7C,
              'JNGE': 0x7C,
              'JGE': 0x7D,
              'JNL': 0x7D,
              'JLE': 0x7E,
              'JNG': 0x7E,
              'JG': 0x7F,
              'JNLE': 0x7F,
            };
            if (operands.length != 1)
              return AssembleResult([], error: '$mnemonic needs 1 operand');
            final target = parseImm(operands[0]);
            if (target == null)
              return AssembleResult([], error: 'Bad target: ${operands[0]}');
            final rel = target - (addr + 2);
            if (rel < -128 || rel > 127)
              return AssembleResult([], error: 'Jump out of short range');
            return AssembleResult([map[mnemonic]!, rel & 0xFF]);
          }

        case 'LOOP':
        case 'LOOPZ':
        case 'LOOPE':
        case 'LOOPNZ':
        case 'LOOPNE':
        case 'JCXZ':
          {
            const map = {
              'LOOP': 0xE2,
              'LOOPZ': 0xE1,
              'LOOPE': 0xE1,
              'LOOPNZ': 0xE0,
              'LOOPNE': 0xE0,
              'JCXZ': 0xE3
            };
            if (operands.length != 1)
              return AssembleResult([], error: '$mnemonic needs 1 operand');
            final target = parseImm(operands[0]);
            if (target == null)
              return AssembleResult([], error: 'Bad target: ${operands[0]}');
            final rel = target - (addr + 2);
            if (rel < -128 || rel > 127)
              return AssembleResult([], error: 'Jump out of short range');
            return AssembleResult([map[mnemonic]!, rel & 0xFF]);
          }

        case 'RET':
          {
            if (operands.isEmpty) return AssembleResult([0xC3]);
            final n = parseImm(operands[0]);
            if (n == null) return AssembleResult([], error: 'Bad RET operand');
            return AssembleResult([0xC2, n & 0xFF, (n >> 8) & 0xFF]);
          }
        case 'RETF':
          {
            if (operands.isEmpty) return AssembleResult([0xCB]);
            final n = parseImm(operands[0]);
            if (n == null) return AssembleResult([], error: 'Bad RETF operand');
            return AssembleResult([0xCA, n & 0xFF, (n >> 8) & 0xFF]);
          }

        case 'INT':
          {
            if (operands.length != 1)
              return AssembleResult([], error: 'INT needs 1 operand');
            final n = parseImm(operands[0]);
            if (n == null) return AssembleResult([], error: 'Bad INT operand');
            return AssembleResult([0xCD, n & 0xFF]);
          }
        case 'INT3':
          return AssembleResult([0xCC]);

        case 'NOP':
          return AssembleResult([0x90]);
        case 'HLT':
          return AssembleResult([0xF4]);
        case 'CLC':
          return AssembleResult([0xF8]);
        case 'STC':
          return AssembleResult([0xF9]);
        case 'CMC':
          return AssembleResult([0xF5]);
        case 'CLI':
          return AssembleResult([0xFA]);
        case 'STI':
          return AssembleResult([0xFB]);
        case 'CLD':
          return AssembleResult([0xFC]);
        case 'STD':
          return AssembleResult([0xFD]);
        case 'CBW':
          return AssembleResult([0x98]);
        case 'CWD':
          return AssembleResult([0x99]);
        case 'PUSHF':
          return AssembleResult([0x9C]);
        case 'POPF':
          return AssembleResult([0x9D]);
        case 'SAHF':
          return AssembleResult([0x9E]);
        case 'LAHF':
          return AssembleResult([0x9F]);
        case 'MOVSB':
          return AssembleResult([0xA4]);
        case 'MOVSW':
          return AssembleResult([0xA5]);
        case 'CMPSB':
          return AssembleResult([0xA6]);
        case 'CMPSW':
          return AssembleResult([0xA7]);
        case 'STOSB':
          return AssembleResult([0xAA]);
        case 'STOSW':
          return AssembleResult([0xAB]);
        case 'LODSB':
          return AssembleResult([0xAC]);
        case 'LODSW':
          return AssembleResult([0xAD]);
        case 'SCASB':
          return AssembleResult([0xAE]);
        case 'SCASW':
          return AssembleResult([0xAF]);
        case 'IRET':
          return AssembleResult([0xCF]);

        case 'MUL':
        case 'IMUL':
        case 'DIV':
        case 'IDIV':
        case 'NEG':
        case 'NOT':
          {
            if (operands.length != 1)
              return AssembleResult([], error: '$mnemonic needs 1 operand');
            final op = operands[0];
            const grpMap = {
              'MUL': 4,
              'IMUL': 5,
              'DIV': 6,
              'IDIV': 7,
              'NOT': 2,
              'NEG': 3
            };
            final grp = grpMap[mnemonic]!;
            final ri8 = r8(op), ri16 = r16(op);
            final memOp = parseMem(op);
            if (ri8 != null)
              return AssembleResult([0xF6, (3 << 6) | (grp << 3) | ri8]);
            if (ri16 != null)
              return AssembleResult([0xF7, (3 << 6) | (grp << 3) | ri16]);
            if (memOp != null)
              return AssembleResult([0xF7, ..._modrmBytes(grp, memOp)]);
            return AssembleResult([], error: 'Cannot encode $mnemonic $op');
          }

        case 'XCHG':
          {
            if (operands.length != 2)
              return AssembleResult([], error: 'XCHG needs 2 operands');
            final a = operands[0], b = operands[1];
            final ar16 = r16(a), br16 = r16(b);
            if (a.toUpperCase() == 'AX' && br16 != null)
              return AssembleResult([0x90 + br16]);
            if (b.toUpperCase() == 'AX' && ar16 != null)
              return AssembleResult([0x90 + ar16]);
            if (ar16 != null && br16 != null)
              return AssembleResult([0x87, (3 << 6) | (ar16 << 3) | br16]);
            return AssembleResult([], error: 'Cannot encode XCHG $a,$b');
          }

        case 'LEA':
          {
            if (operands.length != 2)
              return AssembleResult([], error: 'LEA needs 2 operands');
            final dr16 = r16(operands[0]);
            final mem = parseMem(operands[1]);
            if (dr16 == null || mem == null)
              return AssembleResult([], error: 'Cannot encode LEA');
            return AssembleResult([0x8D, ..._modrmBytes(dr16, mem)]);
          }

        default:
          return AssembleResult([],
              error: 'Unknown or unsupported instruction: $mnemonic');
      }
    } catch (e) {
      return AssembleResult([], error: e.toString());
    }
  }
}
