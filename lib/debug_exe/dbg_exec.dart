// lib/debug_exe/dbg_exec.dart
//
// Executes real 8086 machine code (decoded by DbgIsa) against a DbgCpu.
// Backs the G (go), T (trace), and P (proceed) commands.

import 'dbg_cpu.dart';
import 'dbg_isa.dart';

class StepOutcome {
  final bool halted;
  final String? error;
  StepOutcome({this.halted = false, this.error});
}

class DbgExec {
  final DbgCpu cpu;
  DbgExec(this.cpu);

  /// Decode+execute exactly one instruction at CS:IP. Returns the Decoded
  /// instruction that was executed, so callers (T/P) can print it.
  Decoded? lastDecoded;

  StepOutcome step() {
    if (cpu.halted) return StepOutcome(halted: true);
    final lin = cpu.csip();
    final d = DbgIsa.decode(cpu.memory, lin);
    lastDecoded = d;
    try {
      _exec(d, lin);
    } catch (e) {
      cpu.halted = true;
      return StepOutcome(halted: true, error: e.toString());
    }
    return StepOutcome(halted: cpu.halted);
  }

  /// Returns the CS:IP linear address right after the current instruction —
  /// used by P (proceed) to set a temporary breakpoint when stepping over
  /// CALL/LOOP/INT/REP instructions instead of stepping into them.
  int addressAfterCurrent() {
    final lin = cpu.csip();
    final d = DbgIsa.decode(cpu.memory, lin);
    return (cpu.ip + d.length) & 0xFFFF;
  }

  bool currentIsCallLikeForProceed() {
    final lin = cpu.csip();
    final d = DbgIsa.decode(cpu.memory, lin);
    final mn = d.mnemonic.trim();
    return mn == 'CALL' ||
        mn == 'INT' ||
        mn == 'LOOP' ||
        mn == 'LOOPZ' ||
        mn == 'LOOPNZ' ||
        mn.startsWith('REP');
  }

  void _exec(Decoded d, int atLinear) {
    final mn = d.mnemonic.trim();
    final opsStr = d.operands;
    final nextIp = (cpu.ip + d.length) & 0xFFFF;

    int regOrMemRead(String token, {required bool wide}) {
      token = token.trim();
      if (token.contains('[')) {
        final addr = _evalEA(token);
        return wide
            ? cpu.readWord(_segFor(token), addr)
            : cpu.readByte(_segFor(token), addr);
      }
      return wide ? cpu.getReg16(token) : cpu.getReg8(token);
    }

    void regOrMemWrite(String token, int value, {required bool wide}) {
      token = token.trim();
      if (token.contains('[')) {
        final addr = _evalEA(token);
        if (wide) {
          cpu.writeWord(_segFor(token), addr, value);
        } else {
          cpu.writeByte(_segFor(token), addr, value);
        }
        return;
      }
      if (wide) {
        cpu.setReg16(token, value);
      } else {
        cpu.setReg8(token, value);
      }
    }

    bool isWideOperand(String token) {
      token = token.trim();
      final bare = token.contains(':') ? token.split(':').last : token;
      if (Reg.r16.contains(bare.toUpperCase())) return true;
      if (Reg.r8.contains(bare.toUpperCase())) return false;
      // memory operand width is ambiguous without a size prefix; default word
      return true;
    }

    List<String> ops = opsStr.isEmpty ? [] : opsStr.split(',');

    switch (mn) {
      case 'MOV':
        {
          final dst = ops[0], src = ops[1];
          final wide = isWideOperand(dst);
          final val = _isImm(src) ? _imm(src) : regOrMemRead(src, wide: wide);
          regOrMemWrite(dst, val, wide: wide);
          cpu.ip = nextIp;
          break;
        }
      case 'ADD':
      case 'SUB':
      case 'AND':
      case 'OR':
      case 'XOR':
      case 'ADC':
      case 'SBB':
        {
          final dst = ops[0], src = ops[1];
          final wide = isWideOperand(dst);
          final a = regOrMemRead(dst, wide: wide);
          final b = _isImm(src) ? _imm(src) : regOrMemRead(src, wide: wide);
          int result;
          switch (mn) {
            case 'ADD':
              result = a + b;
              if (wide)
                cpu.updateFlagsAdd16(a, b, result);
              else
                cpu.updateFlagsAdd8(a, b, result);
              break;
            case 'ADC':
              {
                final carry = cpu.cf ? 1 : 0;
                result = a + b + carry;
                if (wide)
                  cpu.updateFlagsAdd16(a, b + carry, result);
                else
                  cpu.updateFlagsAdd8(a, b + carry, result);
                break;
              }
            case 'SUB':
              result = a - b;
              if (wide)
                cpu.updateFlagsSub16(a, b, result);
              else
                cpu.updateFlagsSub8(a, b, result);
              break;
            case 'SBB':
              {
                final borrow = cpu.cf ? 1 : 0;
                result = a - b - borrow;
                if (wide)
                  cpu.updateFlagsSub16(a, b + borrow, result);
                else
                  cpu.updateFlagsSub8(a, b + borrow, result);
                break;
              }
            case 'AND':
              result = a & b;
              if (wide)
                cpu.updateFlagsLogic16(result);
              else
                cpu.updateFlagsLogic8(result);
              break;
            case 'OR':
              result = a | b;
              if (wide)
                cpu.updateFlagsLogic16(result);
              else
                cpu.updateFlagsLogic8(result);
              break;
            case 'XOR':
              result = a ^ b;
              if (wide)
                cpu.updateFlagsLogic16(result);
              else
                cpu.updateFlagsLogic8(result);
              break;
            default:
              result = a;
          }
          regOrMemWrite(dst, result, wide: wide);
          cpu.ip = nextIp;
          break;
        }
      case 'CMP':
        {
          final dst = ops[0], src = ops[1];
          final wide = isWideOperand(dst);
          final a = regOrMemRead(dst, wide: wide);
          final b = _isImm(src) ? _imm(src) : regOrMemRead(src, wide: wide);
          final result = a - b;
          if (wide)
            cpu.updateFlagsSub16(a, b, result);
          else
            cpu.updateFlagsSub8(a, b, result);
          cpu.ip = nextIp;
          break;
        }
      case 'TEST':
        {
          final dst = ops[0], src = ops[1];
          final wide = isWideOperand(dst);
          final a = regOrMemRead(dst, wide: wide);
          final b = _isImm(src) ? _imm(src) : regOrMemRead(src, wide: wide);
          final result = a & b;
          if (wide)
            cpu.updateFlagsLogic16(result);
          else
            cpu.updateFlagsLogic8(result);
          cpu.ip = nextIp;
          break;
        }
      case 'INC':
        {
          final dst = ops[0];
          final wide = isWideOperand(dst);
          final a = regOrMemRead(dst, wide: wide);
          final result = a + 1;
          final savedCf = cpu.cf;
          if (wide)
            cpu.updateFlagsAdd16(a, 1, result);
          else
            cpu.updateFlagsAdd8(a, 1, result);
          cpu.cf = savedCf; // INC doesn't affect CF
          regOrMemWrite(dst, result, wide: wide);
          cpu.ip = nextIp;
          break;
        }
      case 'DEC':
        {
          final dst = ops[0];
          final wide = isWideOperand(dst);
          final a = regOrMemRead(dst, wide: wide);
          final result = a - 1;
          final savedCf = cpu.cf;
          if (wide)
            cpu.updateFlagsSub16(a, 1, result);
          else
            cpu.updateFlagsSub8(a, 1, result);
          cpu.cf = savedCf; // DEC doesn't affect CF
          regOrMemWrite(dst, result, wide: wide);
          cpu.ip = nextIp;
          break;
        }
      case 'NEG':
        {
          final dst = ops[0];
          final wide = isWideOperand(dst);
          final a = regOrMemRead(dst, wide: wide);
          final result = -a;
          if (wide)
            cpu.updateFlagsSub16(0, a, result);
          else
            cpu.updateFlagsSub8(0, a, result);
          cpu.cf = a != 0;
          regOrMemWrite(dst, result, wide: wide);
          cpu.ip = nextIp;
          break;
        }
      case 'NOT':
        {
          final dst = ops[0];
          final wide = isWideOperand(dst);
          final a = regOrMemRead(dst, wide: wide);
          regOrMemWrite(dst, wide ? (~a & 0xFFFF) : (~a & 0xFF), wide: wide);
          cpu.ip = nextIp;
          break;
        }
      case 'MUL':
        {
          final src = ops[0];
          final wide = isWideOperand(src);
          final v = regOrMemRead(src, wide: wide);
          if (wide) {
            final result = cpu.ax * v;
            cpu.ax = result & 0xFFFF;
            cpu.dx = (result >> 16) & 0xFFFF;
            cpu.cf = cpu.of = cpu.dx != 0;
          } else {
            final result = cpu.al * v;
            cpu.ax = result & 0xFFFF;
            cpu.cf = cpu.of = cpu.ah != 0;
          }
          cpu.ip = nextIp;
          break;
        }
      case 'DIV':
        {
          final src = ops[0];
          final wide = isWideOperand(src);
          final v = regOrMemRead(src, wide: wide);
          if (v == 0) throw Exception('Divide by zero');
          if (wide) {
            final dividend = (cpu.dx << 16) | cpu.ax;
            cpu.ax = (dividend ~/ v) & 0xFFFF;
            cpu.dx = (dividend % v) & 0xFFFF;
          } else {
            final dividend = cpu.ax;
            cpu.al = (dividend ~/ v) & 0xFF;
            cpu.ah = (dividend % v) & 0xFF;
          }
          cpu.ip = nextIp;
          break;
        }
      case 'PUSH':
        {
          final val = cpu.getReg16(ops[0]);
          cpu.pushWord(val);
          cpu.ip = nextIp;
          break;
        }
      case 'POP':
        {
          final val = cpu.popWord();
          cpu.setReg16(ops[0], val);
          cpu.ip = nextIp;
          break;
        }
      case 'XCHG':
        {
          final a = ops[0], b = ops[1];
          final wide = isWideOperand(a);
          final av = regOrMemRead(a, wide: wide);
          final bv = regOrMemRead(b, wide: wide);
          regOrMemWrite(a, bv, wide: wide);
          regOrMemWrite(b, av, wide: wide);
          cpu.ip = nextIp;
          break;
        }
      case 'LEA':
        {
          final dst = ops[0], src = ops[1];
          final addr = _evalEA(src);
          cpu.setReg16(dst, addr);
          cpu.ip = nextIp;
          break;
        }
      case 'JMP':
        {
          cpu.ip = _imm(ops[0]) & 0xFFFF;
          break;
        }
      case 'CALL':
        {
          cpu.pushWord(nextIp);
          cpu.ip = _imm(ops[0]) & 0xFFFF;
          break;
        }
      case 'RET':
        {
          final extra = ops.isNotEmpty ? _imm(ops[0]) : 0;
          cpu.ip = cpu.popWord();
          cpu.sp = (cpu.sp + extra) & 0xFFFF;
          break;
        }
      case 'RETF':
        {
          final extra = ops.isNotEmpty ? _imm(ops[0]) : 0;
          cpu.ip = cpu.popWord();
          cpu.cs = cpu.popWord();
          cpu.sp = (cpu.sp + extra) & 0xFFFF;
          break;
        }
      case 'JO':
        cpu.ip = cpu.of ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JNO':
        cpu.ip = !cpu.of ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JB':
        cpu.ip = cpu.cf ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JNB':
        cpu.ip = !cpu.cf ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JZ':
        cpu.ip = cpu.zf ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JNZ':
        cpu.ip = !cpu.zf ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JBE':
        cpu.ip = (cpu.cf || cpu.zf) ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JA':
        cpu.ip = (!cpu.cf && !cpu.zf) ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JS':
        cpu.ip = cpu.sf ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JNS':
        cpu.ip = !cpu.sf ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JP':
        cpu.ip = cpu.pf ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JNP':
        cpu.ip = !cpu.pf ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JL':
        cpu.ip = (cpu.sf != cpu.of) ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JGE':
        cpu.ip = (cpu.sf == cpu.of) ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JLE':
        cpu.ip =
            (cpu.zf || (cpu.sf != cpu.of)) ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JG':
        cpu.ip =
            (!cpu.zf && (cpu.sf == cpu.of)) ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'JCXZ':
        cpu.ip = cpu.cx == 0 ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'LOOP':
        cpu.cx = (cpu.cx - 1) & 0xFFFF;
        cpu.ip = cpu.cx != 0 ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'LOOPZ':
        cpu.cx = (cpu.cx - 1) & 0xFFFF;
        cpu.ip = (cpu.cx != 0 && cpu.zf) ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'LOOPNZ':
        cpu.cx = (cpu.cx - 1) & 0xFFFF;
        cpu.ip = (cpu.cx != 0 && !cpu.zf) ? _imm(ops[0]) & 0xFFFF : nextIp;
        break;
      case 'INT':
        {
          final n = _imm(ops[0]) & 0xFF;
          cpu.ip = nextIp;
          _interrupt(n);
          break;
        }
      case 'NOP':
        cpu.ip = nextIp;
        break;
      case 'HLT':
        cpu.halted = true;
        cpu.ip = nextIp;
        break;
      case 'CLC':
        cpu.cf = false;
        cpu.ip = nextIp;
        break;
      case 'STC':
        cpu.cf = true;
        cpu.ip = nextIp;
        break;
      case 'CMC':
        cpu.cf = !cpu.cf;
        cpu.ip = nextIp;
        break;
      case 'CLI':
        cpu.ifl = false;
        cpu.ip = nextIp;
        break;
      case 'STI':
        cpu.ifl = true;
        cpu.ip = nextIp;
        break;
      case 'CLD':
        cpu.df = false;
        cpu.ip = nextIp;
        break;
      case 'STD':
        cpu.df = true;
        cpu.ip = nextIp;
        break;
      case 'CBW':
        cpu.ax = (cpu.al & 0x80) != 0 ? (0xFF00 | cpu.al) : cpu.al;
        cpu.ip = nextIp;
        break;
      case 'CWD':
        cpu.dx = (cpu.ax & 0x8000) != 0 ? 0xFFFF : 0x0000;
        cpu.ip = nextIp;
        break;
      case 'PUSHF':
        cpu.pushWord(cpu.flagsWord);
        cpu.ip = nextIp;
        break;
      case 'POPF':
        cpu.flagsWord = cpu.popWord();
        cpu.ip = nextIp;
        break;
      case 'SAHF':
        cpu.flagsWord = (cpu.flagsWord & 0xFF00) | cpu.ah;
        cpu.ip = nextIp;
        break;
      case 'LAHF':
        cpu.ah = cpu.flagsWord & 0xFF;
        cpu.ip = nextIp;
        break;
      case 'STOSB':
        cpu.writeByte(cpu.es, cpu.di, cpu.al);
        cpu.di = (cpu.di + (cpu.df ? -1 : 1)) & 0xFFFF;
        cpu.ip = nextIp;
        break;
      case 'STOSW':
        cpu.writeWord(cpu.es, cpu.di, cpu.ax);
        cpu.di = (cpu.di + (cpu.df ? -2 : 2)) & 0xFFFF;
        cpu.ip = nextIp;
        break;
      case 'LODSB':
        cpu.al = cpu.readByte(cpu.ds, cpu.si);
        cpu.si = (cpu.si + (cpu.df ? -1 : 1)) & 0xFFFF;
        cpu.ip = nextIp;
        break;
      case 'LODSW':
        cpu.ax = cpu.readWord(cpu.ds, cpu.si);
        cpu.si = (cpu.si + (cpu.df ? -2 : 2)) & 0xFFFF;
        cpu.ip = nextIp;
        break;
      case 'MOVSB':
        {
          final v = cpu.readByte(cpu.ds, cpu.si);
          cpu.writeByte(cpu.es, cpu.di, v);
          cpu.si = (cpu.si + (cpu.df ? -1 : 1)) & 0xFFFF;
          cpu.di = (cpu.di + (cpu.df ? -1 : 1)) & 0xFFFF;
          cpu.ip = nextIp;
          break;
        }
      case 'MOVSW':
        {
          final v = cpu.readWord(cpu.ds, cpu.si);
          cpu.writeWord(cpu.es, cpu.di, v);
          cpu.si = (cpu.si + (cpu.df ? -2 : 2)) & 0xFFFF;
          cpu.di = (cpu.di + (cpu.df ? -2 : 2)) & 0xFFFF;
          cpu.ip = nextIp;
          break;
        }
      case 'DB':
        // Unknown/unsupported opcode byte at this address: treat as a no-op
        // data byte (real DEBUG.EXE would also refuse to execute past it
        // meaningfully — there's nothing valid to run).
        cpu.ip = nextIp;
        break;
      default:
        cpu.ip = nextIp;
    }
  }

  int _segFor(String memToken) {
    final up = memToken.toUpperCase();
    if (up.startsWith('ES:')) return cpu.es;
    if (up.startsWith('CS:')) return cpu.cs;
    if (up.startsWith('SS:')) return cpu.ss;
    if (up.startsWith('DS:')) return cpu.ds;
    if (memToken.contains('BP')) return cpu.ss; // BP-relative defaults to SS
    return cpu.ds;
  }

  int _evalEA(String token) {
    var t = token.trim();
    final colonIdx = t.indexOf(':');
    if (colonIdx != -1) t = t.substring(colonIdx + 1);
    if (!t.startsWith('[') || !t.endsWith(']')) return 0;
    final inner = t.substring(1, t.length - 1).trim().toUpperCase();
    if (inner.contains('+')) {
      final parts = inner.split('+');
      int addr = 0;
      for (final p in parts) {
        final tok = p.trim();
        try {
          addr += cpu.getReg16(tok);
        } catch (_) {
          addr += DbgIsa.parseImm(tok) ?? 0;
        }
      }
      return addr & 0xFFFF;
    }
    if (inner.contains('-')) {
      final parts = inner.split('-');
      int addr = 0;
      bool first = true;
      for (final p in parts) {
        final tok = p.trim();
        int v;
        try {
          v = cpu.getReg16(tok);
        } catch (_) {
          v = DbgIsa.parseImm(tok) ?? 0;
        }
        if (first) {
          addr = v;
          first = false;
        } else {
          addr -= v;
        }
      }
      return addr & 0xFFFF;
    }
    try {
      return cpu.getReg16(inner) & 0xFFFF;
    } catch (_) {}
    return (DbgIsa.parseImm(inner) ?? 0) & 0xFFFF;
  }

  bool _isImm(String token) {
    token = token.trim();
    if (token.contains('[')) return false;
    final bare = token.contains(':') ? token.split(':').last : token;
    if (Reg.r16.contains(bare.toUpperCase())) return false;
    if (Reg.r8.contains(bare.toUpperCase())) return false;
    if (Reg.sreg.contains(bare.toUpperCase())) return false;
    return true;
  }

  int _imm(String token) {
    token = token.trim();
    return DbgIsa.parseImm(token) ?? 0;
  }

  /// DOS INT 21h + BIOS INT 10h, the handful of services real DOS programs
  /// (and short DEBUG.EXE scratch programs) actually invoke.
  void _interrupt(int n) {
    if (n == 0x21) {
      switch (cpu.ah) {
        case 0x01: // Read char with echo (no input source -> 0)
          cpu.al = 0;
          break;
        case 0x02: // Print char in DL
          cpu.output.add(String.fromCharCode(cpu.dl));
          break;
        case 0x09:
          {
            // Print $-terminated string at DS:DX
            int off = cpu.dx;
            final sb = StringBuffer();
            while (true) {
              final ch = cpu.readByte(cpu.ds, off);
              if (ch == 0x24) break;
              sb.writeCharCode(ch);
              off = (off + 1) & 0xFFFF;
              if (sb.length > 8192) break;
            }
            cpu.output.add(sb.toString());
            break;
          }
        case 0x4C: // Exit
          cpu.halted = true;
          break;
        default:
          cpu.output.add(
              '[INT 21,AH=${cpu.ah.toRadixString(16).toUpperCase().padLeft(2, '0')}]');
      }
    } else if (n == 0x10) {
      if (cpu.ah == 0x0E) {
        cpu.output.add(String.fromCharCode(cpu.al));
      }
    } else if (n == 0x20) {
      cpu.halted = true;
    } else {
      cpu.output
          .add('[INT ${n.toRadixString(16).toUpperCase().padLeft(2, '0')}]');
    }
  }
}
