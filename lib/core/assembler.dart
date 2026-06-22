// lib/core/assembler.dart
// Mini 8086 Assembler — encodes Intel-syntax mnemonics into machine code bytes.
// Used by the DEBUG 'A' (assemble) command.

class AssembleError {
  final String message;
  AssembleError(this.message);
  @override String toString() => message;
}

class AssembleResult {
  final List<int> bytes;
  final AssembleError? error;
  AssembleResult({required this.bytes, this.error});
  bool get ok => error == null;
}

class MiniAssembler {
  static const List<String> _reg16 = ['AX','CX','DX','BX','SP','BP','SI','DI'];
  static const List<String> _reg8  = ['AL','CL','DL','BL','AH','CH','DH','BH'];
  static const List<String> _seg   = ['ES','CS','SS','DS'];

  AssembleResult assemble(String line, int currentAddr) {
    line = line.trim();
    // Strip inline comments
    final semi = line.indexOf(';');
    if (semi >= 0) line = line.substring(0, semi).trim();
    if (line.isEmpty) return AssembleResult(bytes: []);

    final tokens = _tokenize(line);
    if (tokens.isEmpty) return AssembleResult(bytes: []);

    final mnem = tokens[0].toUpperCase();
    final operands = tokens.length > 1
        ? tokens.sublist(1).join(' ').split(',').map((s) => s.trim().toUpperCase()).toList()
        : <String>[];

    try {
      return _encode(mnem, operands, currentAddr);
    } catch (e) {
      return AssembleResult(bytes: [], error: AssembleError('$e'));
    }
  }

  AssembleResult _encode(String mnem, List<String> ops, int addr) {
    final bytes = <int>[];
    void emit(int b) => bytes.add(b & 0xFF);
    void emit16(int w) { emit(w); emit(w >> 8); }

    int parseImm(String s) {
      s = s.trim().toUpperCase();
      if (s.endsWith('H')) return int.parse(s.substring(0, s.length - 1), radix: 16);
      if (s.startsWith('0X')) return int.parse(s.substring(2), radix: 16);
      final v = int.tryParse(s);
      if (v == null) throw Exception('Invalid immediate: $s');
      return v;
    }

    int reg16Idx(String s) {
      final i = _reg16.indexOf(s.toUpperCase());
      if (i < 0) throw Exception('Unknown register: $s');
      return i;
    }

    int reg8Idx(String s) {
      final i = _reg8.indexOf(s.toUpperCase());
      if (i < 0) throw Exception('Unknown 8-bit register: $s');
      return i;
    }

    int segIdx(String s) {
      final i = _seg.indexOf(s.toUpperCase());
      if (i < 0) throw Exception('Unknown segment: $s');
      return i;
    }

    bool isReg16(String s) => _reg16.contains(s.toUpperCase());
    bool isReg8(String s)  => _reg8.contains(s.toUpperCase());
    bool isSeg(String s)   => _seg.contains(s.toUpperCase());

    // Encode ModRM for reg/reg (both same width)
    int modrmRR(int reg, int rm) => 0xC0 | (reg << 3) | rm;

    // Memory ref decode: returns (mod, base, disp) or null if not mem
    // Parses: [BX], [BX+SI], [1234h], [BX+2], etc.
    _MemRef? parseMem(String s) {
      s = s.trim().toUpperCase();
      // Strip BYTE PTR / WORD PTR
      if (s.startsWith('BYTE PTR ')) s = s.substring(9).trim();
      if (s.startsWith('WORD PTR ')) s = s.substring(9).trim();
      if (!s.startsWith('[') || !s.endsWith(']')) return null;
      final inner = s.substring(1, s.length - 1).trim();
      return _MemRef.parse(inner);
    }

    void emitModRM(int reg, _MemRef mem) {
      // Determine rm/base from mem.base
      final rmMap = {
        'BX+SI': 0, 'BX+DI': 1, 'BP+SI': 2, 'BP+DI': 3,
        'SI': 4, 'DI': 5, 'BP': 6, 'BX': 7,
        '': 6, // direct address → mod=0, rm=6
      };
      final rm = rmMap[mem.base] ?? 7;
      final disp = mem.disp;

      if (mem.base.isEmpty) {
        // Direct address
        emit(0x00 | (reg << 3) | 6);
        emit16(disp);
      } else if (disp == 0 && !(mem.base == 'BP')) {
        emit(0x00 | (reg << 3) | rm);
      } else if (disp >= -128 && disp <= 127) {
        emit(0x40 | (reg << 3) | rm);
        emit(disp & 0xFF);
      } else {
        emit(0x80 | (reg << 3) | rm);
        emit16(disp & 0xFFFF);
      }
    }

    switch (mnem) {

      // ── NOP ───────────────────────────────────────────────────────────
      case 'NOP': emit(0x90); break;
      case 'HLT': emit(0xF4); break;
      case 'RET': emit(0xC3); break;
      case 'RETF': emit(0xCB); break;
      case 'CLC': emit(0xF8); break;
      case 'STC': emit(0xF9); break;
      case 'CLI': emit(0xFA); break;
      case 'STI': emit(0xFB); break;
      case 'CLD': emit(0xFC); break;
      case 'STD': emit(0xFD); break;
      case 'PUSHF': emit(0x9C); break;
      case 'POPF':  emit(0x9D); break;
      case 'PUSHA': emit(0x60); break;
      case 'POPA':  emit(0x61); break;
      case 'CBW':   emit(0x98); break;
      case 'CWD':   emit(0x99); break;
      case 'IRET':  emit(0xCF); break;
      case 'MOVSB': emit(0xA4); break;
      case 'MOVSW': emit(0xA5); break;
      case 'STOSB': emit(0xAA); break;
      case 'STOSW': emit(0xAB); break;
      case 'LODSB': emit(0xAC); break;
      case 'LODSW': emit(0xAD); break;
      case 'SCASB': emit(0xAE); break;
      case 'SCASW': emit(0xAF); break;
      case 'DAA':   emit(0x27); break;
      case 'DAS':   emit(0x2F); break;
      case 'AAA':   emit(0x37); break;
      case 'AAS':   emit(0x3F); break;
      case 'XLAT':  emit(0xD7); break;
      case 'LEAVE': emit(0xC9); break;
      case 'LAHF':  emit(0x9F); break;
      case 'SAHF':  emit(0x9E); break;
      case 'INT 3': emit(0xCC); break;

      // ── PUSH ───────────────────────────────────────────────────────────
      case 'PUSH': {
        final op = ops[0];
        if (op == 'ES') { emit(0x06); break; }
        if (op == 'CS') { emit(0x0E); break; }
        if (op == 'SS') { emit(0x16); break; }
        if (op == 'DS') { emit(0x1E); break; }
        if (isReg16(op)) { emit(0x50 | reg16Idx(op)); break; }
        // imm
        final v = parseImm(op);
        if (v >= -128 && v <= 127) { emit(0x6A); emit(v); }
        else { emit(0x68); emit16(v); }
        break;
      }
      case 'POP': {
        final op = ops[0];
        if (op == 'ES') { emit(0x07); break; }
        if (op == 'SS') { emit(0x17); break; }
        if (op == 'DS') { emit(0x1F); break; }
        if (isReg16(op)) { emit(0x58 | reg16Idx(op)); break; }
        throw Exception('Invalid POP operand: $op');
      }

      // ── INC / DEC ──────────────────────────────────────────────────────
      case 'INC': {
        final op = ops[0];
        if (isReg16(op)) { emit(0x40 | reg16Idx(op)); break; }
        if (isReg8(op))  { emit(0xFE); emit(modrmRR(0, reg8Idx(op))); break; }
        throw Exception('INC: invalid operand');
      }
      case 'DEC': {
        final op = ops[0];
        if (isReg16(op)) { emit(0x48 | reg16Idx(op)); break; }
        if (isReg8(op))  { emit(0xFE); emit(modrmRR(1, reg8Idx(op))); break; }
        throw Exception('DEC: invalid operand');
      }

      // ── INT ────────────────────────────────────────────────────────────
      case 'INT': {
        final n = parseImm(ops[0]);
        emit(0xCD); emit(n);
        break;
      }

      // ── MOV ────────────────────────────────────────────────────────────
      case 'MOV': {
        final dst = ops[0]; final src = ops[1];
        // seg = r16
        if (isSeg(dst) && isReg16(src)) {
          emit(0x8E); emit(modrmRR(segIdx(dst), reg16Idx(src))); break;
        }
        // r16 = seg
        if (isReg16(dst) && isSeg(src)) {
          emit(0x8C); emit(modrmRR(segIdx(src), reg16Idx(dst))); break;
        }
        // r16 = imm
        if (isReg16(dst) && !isReg16(src)) {
          final mem = parseMem(src);
          if (mem == null) {
            final v = parseImm(src);
            emit(0xB8 | reg16Idx(dst)); emit16(v); break;
          }
        }
        // r8 = imm
        if (isReg8(dst) && !isReg8(src) && parseMem(src) == null) {
          final v = parseImm(src);
          emit(0xB0 | reg8Idx(dst)); emit(v); break;
        }
        // r16, r16
        if (isReg16(dst) && isReg16(src)) {
          emit(0x8B); emit(modrmRR(reg16Idx(dst), reg16Idx(src))); break;
        }
        // r8, r8
        if (isReg8(dst) && isReg8(src)) {
          emit(0x8A); emit(modrmRR(reg8Idx(dst), reg8Idx(src))); break;
        }
        // r16, [mem]
        final srcMem = parseMem(src);
        final dstMem = parseMem(dst);
        if (isReg16(dst) && srcMem != null) {
          emit(0x8B); emitModRM(reg16Idx(dst), srcMem); break;
        }
        if (isReg8(dst) && srcMem != null) {
          emit(0x8A); emitModRM(reg8Idx(dst), srcMem); break;
        }
        if (dstMem != null && isReg16(src)) {
          emit(0x89); emitModRM(reg16Idx(src), dstMem); break;
        }
        if (dstMem != null && isReg8(src)) {
          emit(0x88); emitModRM(reg8Idx(src), dstMem); break;
        }
        throw Exception('MOV: unrecognized operand combo: $dst, $src');
      }

      // ── ADD / SUB / AND / OR / XOR / CMP ──────────────────────────────
      case 'ADD': case 'SUB': case 'AND': case 'OR': case 'XOR': case 'CMP':
      case 'ADC': case 'SBB': {
        const opcTable = {
          'ADD': [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x80, 0x81, 0],
          'OR':  [0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x80, 0x81, 1],
          'ADC': [0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x80, 0x81, 2],
          'SBB': [0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x80, 0x81, 3],
          'AND': [0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x80, 0x81, 4],
          'SUB': [0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x80, 0x81, 5],
          'XOR': [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x80, 0x81, 6],
          'CMP': [0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x80, 0x81, 7],
        };
        final tbl = opcTable[mnem]!;
        final ext = tbl[8];
        final dst = ops[0]; final src = ops[1];

        // AL/AX accum-imm short form
        if (dst == 'AL' && parseMem(src) == null && !isReg8(src)) {
          emit(tbl[4]); emit(parseImm(src)); break;
        }
        if (dst == 'AX' && parseMem(src) == null && !isReg16(src)) {
          emit(tbl[5]); emit16(parseImm(src)); break;
        }
        // r16, r16
        if (isReg16(dst) && isReg16(src)) {
          emit(tbl[3]); emit(modrmRR(reg16Idx(dst), reg16Idx(src))); break;
        }
        // r8, r8
        if (isReg8(dst) && isReg8(src)) {
          emit(tbl[2]); emit(modrmRR(reg8Idx(dst), reg8Idx(src))); break;
        }
        // r16, imm  (use 83 if fits in sign byte)
        if (isReg16(dst) && parseMem(src) == null) {
          final v = parseImm(src);
          if (v >= -128 && v <= 127 && mnem != 'MOV') {
            emit(0x83); emit(modrmRR(ext, reg16Idx(dst))); emit(v & 0xFF);
          } else {
            emit(tbl[7]); emit(modrmRR(ext, reg16Idx(dst))); emit16(v);
          }
          break;
        }
        // r8, imm
        if (isReg8(dst) && parseMem(src) == null) {
          emit(tbl[6]); emit(modrmRR(ext, reg8Idx(dst))); emit(parseImm(src)); break;
        }
        // r16, [mem]
        final srcMem = parseMem(src);
        final dstMem = parseMem(dst);
        if (isReg16(dst) && srcMem != null) {
          emit(tbl[3]); emitModRM(reg16Idx(dst), srcMem); break;
        }
        if (isReg8(dst) && srcMem != null) {
          emit(tbl[2]); emitModRM(reg8Idx(dst), srcMem); break;
        }
        if (dstMem != null && isReg16(src)) {
          emit(tbl[1]); emitModRM(reg16Idx(src), dstMem); break;
        }
        if (dstMem != null && isReg8(src)) {
          emit(tbl[0]); emitModRM(reg8Idx(src), dstMem); break;
        }
        throw Exception('$mnem: unrecognized operand combo: ${ops.join(",")}');
      }

      // ── MUL / IMUL / DIV / IDIV / NEG / NOT ───────────────────────────
      case 'MUL': case 'IMUL': case 'DIV': case 'IDIV':
      case 'NEG': case 'NOT': {
        const extMap = {'MUL':4,'IMUL':5,'DIV':6,'IDIV':7,'NOT':2,'NEG':3};
        final ext = extMap[mnem]!;
        final op = ops[0];
        if (isReg16(op)) { emit(0xF7); emit(modrmRR(ext, reg16Idx(op))); }
        else if (isReg8(op)) { emit(0xF6); emit(modrmRR(ext, reg8Idx(op))); }
        else throw Exception('$mnem: invalid operand');
        break;
      }

      // ── XCHG ──────────────────────────────────────────────────────────
      case 'XCHG': {
        final a = ops[0]; final b = ops[1];
        if (a == 'AX' && isReg16(b)) { emit(0x90 | reg16Idx(b)); break; }
        if (isReg16(a) && b == 'AX') { emit(0x90 | reg16Idx(a)); break; }
        if (isReg16(a) && isReg16(b)) { emit(0x87); emit(modrmRR(reg16Idx(a), reg16Idx(b))); break; }
        if (isReg8(a)  && isReg8(b))  { emit(0x86); emit(modrmRR(reg8Idx(a), reg8Idx(b))); break; }
        throw Exception('XCHG: invalid operands');
      }

      // ── LEA ──────────────────────────────────────────────────────────
      case 'LEA': {
        final dst = ops[0]; final src = ops[1];
        final mem = parseMem(src);
        if (mem == null) throw Exception('LEA: source must be memory ref');
        emit(0x8D); emitModRM(reg16Idx(dst), mem); break;
      }

      // ── Jumps ─────────────────────────────────────────────────────────
      case 'JMP': {
        final op = ops[0].replaceAll('SHORT','').trim();
        final target = parseImm(op);
        final rel16 = target - (addr + 3);
        final rel8  = target - (addr + 2);
        if (rel8 >= -128 && rel8 <= 127) { emit(0xEB); emit(rel8 & 0xFF); }
        else { emit(0xE9); emit16(rel16 & 0xFFFF); }
        break;
      }
      case 'CALL': {
        final target = parseImm(ops[0]);
        final rel = target - (addr + 3);
        emit(0xE8); emit16(rel & 0xFFFF); break;
      }
      case 'JO':  case 'JNO': case 'JB':  case 'JNB': case 'JE':  case 'JNE':
      case 'JBE': case 'JA':  case 'JS':  case 'JNS': case 'JPE': case 'JPO':
      case 'JL':  case 'JGE': case 'JLE': case 'JG':
      case 'JZ': case 'JNZ': case 'JC': case 'JNC': case 'JP': case 'JNP':
      case 'LOOP': case 'LOOPZ': case 'LOOPNZ': case 'JCXZ': {
        const jmap = {
          'JO':0x70,'JNO':0x71,'JB':0x72,'JNB':0x73,'JE':0x74,'JNE':0x75,
          'JBE':0x76,'JA':0x77,'JS':0x78,'JNS':0x79,'JPE':0x7A,'JPO':0x7B,
          'JL':0x7C,'JGE':0x7D,'JLE':0x7E,'JG':0x7F,
          'JZ':0x74,'JNZ':0x75,'JC':0x72,'JNC':0x73,'JP':0x7A,'JNP':0x7B,
          'LOOP':0xE2,'LOOPZ':0xE1,'LOOPNZ':0xE0,'JCXZ':0xE3,
        };
        final opc = jmap[mnem]!;
        final target = parseImm(ops[0]);
        final rel = target - (addr + 2);
        emit(opc); emit(rel & 0xFF); break;
      }

      // ── LOOP (already in jumps above) ─────────────────────────────────

      // ── IN / OUT ──────────────────────────────────────────────────────
      case 'IN': {
        final dst = ops[0]; final src = ops[1];
        if (src == 'DX') { emit(dst == 'AL' ? 0xEC : 0xED); }
        else { emit(dst == 'AL' ? 0xE4 : 0xE5); emit(parseImm(src)); }
        break;
      }
      case 'OUT': {
        final dst = ops[0]; final src = ops[1];
        if (dst == 'DX') { emit(src == 'AL' ? 0xEE : 0xEF); }
        else { emit(src == 'AL' ? 0xE6 : 0xE7); emit(parseImm(dst)); }
        break;
      }

      // ── DB (raw bytes) ────────────────────────────────────────────────
      case 'DB': {
        for (final op in ops) {
          if (op.startsWith("'") && op.endsWith("'")) {
            for (final c in op.substring(1, op.length-1).codeUnits) emit(c);
          } else {
            emit(parseImm(op));
          }
        }
        break;
      }
      case 'DW': {
        for (final op in ops) emit16(parseImm(op));
        break;
      }

      default:
        throw Exception('Unknown mnemonic: $mnem');
    }

    return AssembleResult(bytes: bytes);
  }

  List<String> _tokenize(String line) {
    // Split on first whitespace to get mnemonic, rest is operands
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return [];
    final mnem = parts[0];
    final rest = parts.sublist(1).join(' ');
    return rest.isEmpty ? [mnem] : [mnem, rest];
  }
}

class _MemRef {
  final String base; // e.g. 'BX+SI', 'BX', '' (for direct)
  final int disp;    // displacement

  _MemRef(this.base, this.disp);

  static _MemRef parse(String expr) {
    expr = expr.trim().toUpperCase();

    const bases = ['BX+SI','BX+DI','BP+SI','BP+DI','BX','BP','SI','DI'];

    // Check for known base
    for (final b in bases) {
      if (expr == b) return _MemRef(b, 0);
      if (expr.startsWith('$b+')) {
        final dispStr = expr.substring(b.length + 1);
        final disp = _parseDisp(dispStr);
        return _MemRef(b, disp);
      }
      if (expr.startsWith('$b-')) {
        final dispStr = expr.substring(b.length);
        final disp = _parseDisp(dispStr);
        return _MemRef(b, disp);
      }
    }

    // Direct address
    final v = _parseDisp(expr);
    return _MemRef('', v);
  }

  static int _parseDisp(String s) {
    s = s.trim().toUpperCase();
    if (s.startsWith('-')) {
      return -_parseDisp(s.substring(1));
    }
    if (s.startsWith('+')) s = s.substring(1).trim();
    if (s.endsWith('H')) return int.parse(s.substring(0, s.length - 1), radix: 16);
    if (s.startsWith('0X')) return int.parse(s.substring(2), radix: 16);
    return int.tryParse(s) ?? int.parse(s, radix: 16);
  }
}
