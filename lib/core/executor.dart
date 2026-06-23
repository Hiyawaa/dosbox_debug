// lib/core/executor.dart
// Executes 8086 instructions: MOV ADD SUB MUL DIV INC DEC PUSH POP CALL RET JMP JE JNE LOOP INT DB DW ORG

import '../models/cpu8086.dart';
import 'assembler.dart';

class ExecutionResult {
  final bool halted;
  final String? error;
  final List<String> output;

  ExecutionResult({required this.halted, this.error, required this.output});
}

class Executor {
  final CPU8086 cpu;
  late AssembledProgram _program;
  final _callStack = <int>[];
  int _stepCount = 0;
  static const int maxSteps = 100000;

  Executor(this.cpu);

  void loadProgram(AssembledProgram program) {
    _program = program;
    cpu.reset();
    cpu.ip = program.startAddress;

    // Load DB/DW data into memory
    for (final instr in program.instructions) {
      if (instr.mnemonic == 'DB') {
        for (int i = 0; i < instr.operands.length; i++) {
          final val = int.tryParse(instr.operands[i]) ?? 0;
          cpu.memory[(instr.address + i) & 0xFFFF] = val & 0xFF;
        }
      } else if (instr.mnemonic == 'DW') {
        for (int i = 0; i < instr.operands.length; i++) {
          final val = int.tryParse(instr.operands[i]) ?? 0;
          cpu.writeWord((instr.address + i * 2) & 0xFFFF, val);
        }
      }
    }
  }

  Instruction? currentInstruction() {
    return _program.instructions.firstWhere(
      (i) => i.address == cpu.ip && i.mnemonic != 'DB' && i.mnemonic != 'DW',
      orElse: () => _program.instructions.firstWhere(
        (i) => i.address >= cpu.ip && i.mnemonic != 'DB' && i.mnemonic != 'DW',
        orElse: () => _program.instructions.isEmpty
            ? Instruction(address: 0, sourceLine: 0, mnemonic: '', operands: [], raw: '')
            : _program.instructions.last,
      ),
    );
  }

  /// Execute one instruction (step mode)
  ExecutionResult step() {
    if (cpu.halted) {
      return ExecutionResult(halted: true, output: List.from(cpu.outputLog));
    }
    if (_stepCount++ > maxSteps) {
      cpu.halted = true;
      return ExecutionResult(
        halted: true,
        error: 'Execution limit reached (infinite loop?)',
        output: List.from(cpu.outputLog),
      );
    }

    final instr = _findInstructionAt(cpu.ip);
    if (instr == null) {
      cpu.halted = true;
      return ExecutionResult(halted: true, output: List.from(cpu.outputLog));
    }

    try {
      _execute(instr);
    } catch (e) {
      cpu.halted = true;
      return ExecutionResult(
        halted: true,
        error: 'Runtime error at line ${instr.sourceLine}: $e',
        output: List.from(cpu.outputLog),
      );
    }

    return ExecutionResult(halted: cpu.halted, output: List.from(cpu.outputLog));
  }

  /// Run entire program
  ExecutionResult runAll() {
    _stepCount = 0;
    while (!cpu.halted) {
      final result = step();
      if (result.halted || result.error != null) return result;
    }
    return ExecutionResult(halted: true, output: List.from(cpu.outputLog));
  }

  Instruction? _findInstructionAt(int ip) {
    for (final i in _program.instructions) {
      if (i.address == ip && i.mnemonic != 'DB' && i.mnemonic != 'DW') return i;
    }
    return null;
  }

  void _advance() {
    // Find next executable instruction
    final sortedExec = _program.instructions
        .where((i) => i.mnemonic != 'DB' && i.mnemonic != 'DW')
        .toList()
      ..sort((a, b) => a.address.compareTo(b.address));
    final idx = sortedExec.indexWhere((i) => i.address == cpu.ip);
    if (idx >= 0 && idx < sortedExec.length - 1) {
      cpu.ip = sortedExec[idx + 1].address;
    } else {
      cpu.halted = true;
    }
  }

  void _execute(Instruction instr) {
    final m = instr.mnemonic.toUpperCase();
    final ops = instr.operands;

    switch (m) {
      case 'MOV':
        _ensureOps(m, ops, 2);
        final val = _getOperandValue(ops[1]);
        _setOperandValue(ops[0], val);
        _advance();
        break;

      case 'ADD':
        _ensureOps(m, ops, 2);
        final dst = _getOperandValue(ops[0]);
        final src = _getOperandValue(ops[1]);
        final result = dst + src;
        if (cpu.is8BitReg(ops[0])) {
          cpu.updateFlags8(result);
          _setOperandValue(ops[0], result & 0xFF);
        } else {
          cpu.updateFlags16(result);
          _setOperandValue(ops[0], result & 0xFFFF);
        }
        _advance();
        break;

      case 'SUB':
        _ensureOps(m, ops, 2);
        final dst = _getOperandValue(ops[0]);
        final src = _getOperandValue(ops[1]);
        final result = dst - src;
        if (cpu.is8BitReg(ops[0])) {
          cpu.updateFlags8(result);
          _setOperandValue(ops[0], result & 0xFF);
        } else {
          cpu.updateFlags16(result);
          _setOperandValue(ops[0], result & 0xFFFF);
        }
        _advance();
        break;

      case 'MUL':
        _ensureOps(m, ops, 1);
        final src = _getOperandValue(ops[0]);
        if (cpu.is8BitReg(ops[0])) {
          // AL * src8 -> AX
          final result = cpu.al * src;
          cpu.ax = result & 0xFFFF;
          cpu.cf = cpu.of = (result > 0xFF);
        } else {
          // AX * src16 -> DX:AX
          final result = cpu.ax * src;
          cpu.ax = result & 0xFFFF;
          cpu.dx = (result >> 16) & 0xFFFF;
          cpu.cf = cpu.of = (result > 0xFFFF);
        }
        _advance();
        break;

      case 'DIV':
        _ensureOps(m, ops, 1);
        final divisor = _getOperandValue(ops[0]);
        if (divisor == 0) throw Exception('Division by zero');
        if (cpu.is8BitReg(ops[0])) {
          // AX / src8 -> AL=quotient, AH=remainder
          final q = cpu.ax ~/ divisor;
          final r = cpu.ax % divisor;
          cpu.al = q & 0xFF;
          cpu.ah = r & 0xFF;
        } else {
          // DX:AX / src16 -> AX=quotient, DX=remainder
          final dividend = (cpu.dx << 16) | cpu.ax;
          final q = dividend ~/ divisor;
          final r = dividend % divisor;
          cpu.ax = q & 0xFFFF;
          cpu.dx = r & 0xFFFF;
        }
        _advance();
        break;

      case 'INC':
        _ensureOps(m, ops, 1);
        final val = _getOperandValue(ops[0]);
        final result = val + 1;
        if (cpu.is8BitReg(ops[0])) {
          cpu.updateFlags8(result);
          _setOperandValue(ops[0], result & 0xFF);
        } else {
          cpu.updateFlags16(result);
          _setOperandValue(ops[0], result & 0xFFFF);
        }
        _advance();
        break;

      case 'DEC':
        _ensureOps(m, ops, 1);
        final val = _getOperandValue(ops[0]);
        final result = val - 1;
        if (cpu.is8BitReg(ops[0])) {
          cpu.updateFlags8(result);
          _setOperandValue(ops[0], result & 0xFF);
        } else {
          cpu.updateFlags16(result);
          _setOperandValue(ops[0], result & 0xFFFF);
        }
        _advance();
        break;

      case 'PUSH':
        _ensureOps(m, ops, 1);
        final val = _getOperandValue(ops[0]);
        cpu.pushWord(val);
        _advance();
        break;

      case 'POP':
        _ensureOps(m, ops, 1);
        final val = cpu.popWord();
        _setOperandValue(ops[0], val);
        _advance();
        break;

      case 'CALL':
        _ensureOps(m, ops, 1);
        // Save next instruction address
        final nextInstr = _nextExecAddress();
        cpu.pushWord(nextInstr);
        _callStack.add(nextInstr);
        final target = int.tryParse(ops[0]) ?? _program.labels[ops[0].toUpperCase()] ?? 0;
        cpu.ip = target;
        break;

      case 'RET':
        if (_callStack.isNotEmpty) _callStack.removeLast();
        final retAddr = cpu.popWord();
        cpu.ip = retAddr;
        break;

      case 'JMP':
        _ensureOps(m, ops, 1);
        final target = _resolveJumpTarget(ops[0]);
        cpu.ip = target;
        break;

      case 'JE':
      case 'JZ':
        _ensureOps(m, ops, 1);
        if (cpu.zf) {
          cpu.ip = _resolveJumpTarget(ops[0]);
        } else {
          _advance();
        }
        break;

      case 'JNE':
      case 'JNZ':
        _ensureOps(m, ops, 1);
        if (!cpu.zf) {
          cpu.ip = _resolveJumpTarget(ops[0]);
        } else {
          _advance();
        }
        break;

      case 'LOOP':
        _ensureOps(m, ops, 1);
        cpu.cx = (cpu.cx - 1) & 0xFFFF;
        if (cpu.cx != 0) {
          cpu.ip = _resolveJumpTarget(ops[0]);
        } else {
          _advance();
        }
        break;

      case 'INT':
        _ensureOps(m, ops, 1);
        final intNum = _parseImmediate(ops[0]) ?? 0;
        _handleInterrupt(intNum);
        _advance();
        break;

      case 'NOP':
        _advance();
        break;

      case 'HLT':
        cpu.halted = true;
        break;

      case 'CMP':
        _ensureOps(m, ops, 2);
        final a = _getOperandValue(ops[0]);
        final b = _getOperandValue(ops[1]);
        final res = a - b;
        if (cpu.is8BitReg(ops[0])) cpu.updateFlags8(res);
        else cpu.updateFlags16(res);
        _advance();
        break;

      case 'XCHG':
        _ensureOps(m, ops, 2);
        final a = _getOperandValue(ops[0]);
        final b = _getOperandValue(ops[1]);
        _setOperandValue(ops[0], b);
        _setOperandValue(ops[1], a);
        _advance();
        break;

      case 'AND':
        _ensureOps(m, ops, 2);
        final result = _getOperandValue(ops[0]) & _getOperandValue(ops[1]);
        _setOperandValue(ops[0], result);
        cpu.updateFlags16(result); cpu.cf = false; cpu.of = false;
        _advance();
        break;

      case 'OR':
        _ensureOps(m, ops, 2);
        final result = _getOperandValue(ops[0]) | _getOperandValue(ops[1]);
        _setOperandValue(ops[0], result);
        cpu.updateFlags16(result); cpu.cf = false; cpu.of = false;
        _advance();
        break;

      case 'XOR':
        _ensureOps(m, ops, 2);
        final result = _getOperandValue(ops[0]) ^ _getOperandValue(ops[1]);
        _setOperandValue(ops[0], result);
        cpu.updateFlags16(result); cpu.cf = false; cpu.of = false;
        _advance();
        break;

      case 'DB':
      case 'DW':
        _advance(); // data, skip
        break;

      default:
        _advance(); // Unknown: skip silently
    }
  }

  void _handleInterrupt(int intNum) {
    if (intNum == 0x21) {
      // DOS INT 21h
      switch (cpu.ah) {
        case 0x02:
          // Print character in DL
          cpu.outputLog.add(String.fromCharCode(cpu.dl));
          break;
        case 0x09:
          // Print string at DS:DX until '$'
          int addr = cpu.dx;
          final sb = StringBuffer();
          while (addr < 65536) {
            final ch = cpu.memory[addr++];
            if (ch == 0x24) break; // '$'
            sb.writeCharCode(ch);
          }
          cpu.outputLog.add(sb.toString());
          break;
        case 0x4C:
          // Exit
          cpu.halted = true;
          break;
        default:
          cpu.outputLog.add('[INT 21h AH=${cpu.ah.toRadixString(16).toUpperCase()}]');
      }
    } else if (intNum == 0x10) {
      // Video BIOS - simplified
      if (cpu.ah == 0x0E) {
        cpu.outputLog.add(String.fromCharCode(cpu.al));
      }
    } else {
      cpu.outputLog.add('[INT ${intNum.toRadixString(16).toUpperCase()}h]');
    }
  }

  int _nextExecAddress() {
    final sorted = _program.instructions
        .where((i) => i.mnemonic != 'DB' && i.mnemonic != 'DW' && i.address > cpu.ip)
        .toList()
      ..sort((a, b) => a.address.compareTo(b.address));
    return sorted.isEmpty ? cpu.ip + 1 : sorted.first.address;
  }

  int _resolveJumpTarget(String op) {
    // Try direct address
    final imm = int.tryParse(op);
    if (imm != null) return imm;
    // Try label
    final label = _program.labels[op.toUpperCase()];
    if (label != null) return label;
    return cpu.ip;
  }

  int _getOperandValue(String op) {
    op = op.trim();
    // Memory reference [addr] or [reg]
    if (op.startsWith('[') && op.endsWith(']')) {
      final inner = op.substring(1, op.length - 1).trim();
      final addr = _resolveMemoryAddress(inner);
      return cpu.readWord(addr);
    }
    // Register
    try {
      return cpu.getRegister(op);
    } catch (_) {}
    // Immediate
    return _parseImmediate(op) ?? 0;
  }

  void _setOperandValue(String op, int value) {
    op = op.trim();
    if (op.startsWith('[') && op.endsWith(']')) {
      final inner = op.substring(1, op.length - 1).trim();
      final addr = _resolveMemoryAddress(inner);
      cpu.writeWord(addr, value);
      return;
    }
    try {
      cpu.setRegister(op, value);
      return;
    } catch (_) {}
  }

  int _resolveMemoryAddress(String expr) {
    // Simple: [BX], [SI], [DI], [BP], [1234H], [BX+SI], etc.
    expr = expr.toUpperCase().trim();
    // Register+offset: BX+4, SI+2, etc.
    if (expr.contains('+')) {
      final parts = expr.split('+');
      int addr = 0;
      for (final p in parts) {
        final t = p.trim();
        try { addr += cpu.getRegister(t); } catch (_) {
          addr += _parseImmediate(t) ?? 0;
        }
      }
      return addr & 0xFFFF;
    }
    if (expr.contains('-')) {
      final parts = expr.split('-');
      int addr = 0;
      bool first = true;
      for (final p in parts) {
        final t = p.trim();
        int v = 0;
        try { v = cpu.getRegister(t); } catch (_) {
          v = _parseImmediate(t) ?? 0;
        }
        if (first) { addr = v; first = false; }
        else addr -= v;
      }
      return addr & 0xFFFF;
    }
    // Pure register
    try { return cpu.getRegister(expr) & 0xFFFF; } catch (_) {}
    // Pure immediate
    return (_parseImmediate(expr) ?? 0) & 0xFFFF;
  }

  int? _parseImmediate(String s) {
    s = s.trim().toUpperCase();
    if (s.endsWith('H')) return int.tryParse(s.substring(0, s.length - 1), radix: 16);
    if (s.startsWith('0X')) return int.tryParse(s.substring(2), radix: 16);
    return int.tryParse(s);
  }

  void _ensureOps(String mnemonic, List<String> ops, int count) {
    if (ops.length < count) {
      throw Exception('$mnemonic requires $count operand(s), got ${ops.length}');
    }
  }
}
