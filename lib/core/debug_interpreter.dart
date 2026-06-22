// lib/core/debug_interpreter.dart
// Interprets DEBUG.EXE-style commands and produces output strings.

import 'cpu8086.dart';
import 'disassembler.dart';
import 'assembler.dart';
import 'executor.dart';

enum DebugMode { normal, assembling }

class DebugInterpreter {
  final CPU8086 cpu;
  late final Disassembler _dis;
  late final MiniAssembler _asm;
  late final Executor _exec;

  DebugMode mode = DebugMode.normal;
  int _assembleAddr = 0;
  int _lastDumpAddr = 0x0100;
  int _lastDisasmAddr = 0x0100;

  // For 'E' interactive entry mode
  bool _enterMode = false;
  int _enterAddr = 0;

  DebugInterpreter(this.cpu) {
    _dis  = Disassembler(cpu);
    _asm  = MiniAssembler();
    _exec = Executor(cpu);
  }

  // ── Public entry point ────────────────────────────────────────────────────
  /// Handle one line of input. Returns list of output lines to display.
  List<String> handleLine(String line) {
    line = line.trimRight();

    // Assemble mode: keep reading instructions
    if (mode == DebugMode.assembling) {
      return _handleAssembleLine(line);
    }

    if (_enterMode) {
      return _handleEnterData(line);
    }

    if (line.isEmpty) return ['-'];

    final cmd = line[0].toUpperCase();
    final rest = line.length > 1 ? line.substring(1).trim() : '';

    switch (cmd) {
      case 'A': return _cmdAssemble(rest);
      case 'D': return _cmdDump(rest);
      case 'E': return _cmdEnter(rest);
      case 'F': return _cmdFill(rest);
      case 'G': return _cmdGo(rest);
      case 'H': return _cmdHex(rest);
      case 'I': return _cmdIn(rest);
      case 'M': return _cmdMove(rest);
      case 'N': return _cmdName(rest);
      case 'O': return _cmdOut(rest);
      case 'Q': return _cmdQuit();
      case 'R': return _cmdRegister(rest);
      case 'S': return _cmdSearch(rest);
      case 'T': return _cmdTrace(rest);
      case 'U': return _cmdUnassemble(rest);
      case 'W': return ['Writing (simulated)...', '-'];
      case 'L': return ['Loading (simulated)...', '-'];
      case '?': return _cmdHelp();
      default:
        return ['^ Error: Unrecognized command', '-'];
    }
  }

  // ── A — Assemble ──────────────────────────────────────────────────────────
  List<String> _cmdAssemble(String rest) {
    _assembleAddr = rest.isEmpty ? cpu.ip : _parseHex(rest);
    mode = DebugMode.assembling;
    return [_fmtAddr(_assembleAddr)]; // prompt for first instruction
  }

  List<String> _handleAssembleLine(String line) {
    if (line.trim().isEmpty) {
      // Empty line exits assemble mode
      mode = DebugMode.normal;
      return ['-'];
    }

    final result = _asm.assemble(line, _assembleAddr);
    if (!result.ok) {
      return ['^ Error: ${result.error}', _fmtAddr(_assembleAddr)];
    }
    if (result.bytes.isEmpty) {
      return [_fmtAddr(_assembleAddr)];
    }

    // Write bytes into memory
    for (int i = 0; i < result.bytes.length; i++) {
      cpu.writeByte((_assembleAddr + i) & 0xFFFF, result.bytes[i]);
    }
    _assembleAddr = (_assembleAddr + result.bytes.length) & 0xFFFF;
    return [_fmtAddr(_assembleAddr)]; // next prompt
  }

  // ── D — Dump memory ───────────────────────────────────────────────────────
  List<String> _cmdDump(String rest) {
    int start, end;
    final parts = rest.split(RegExp(r'[\s,L]+'));
    final nonEmpty = parts.where((s) => s.isNotEmpty).toList();

    if (nonEmpty.isEmpty) {
      start = _lastDumpAddr;
      end = (start + 0x7F) & 0xFFFF;
    } else if (nonEmpty.length == 1) {
      start = _parseHex(nonEmpty[0]);
      end = (start + 0x7F) & 0xFFFF;
    } else {
      start = _parseHex(nonEmpty[0]);
      // second arg could be end address or "L count"
      if (rest.toUpperCase().contains('L')) {
        end = (start + _parseHex(nonEmpty[1]) - 1) & 0xFFFF;
      } else {
        end = _parseHex(nonEmpty[1]);
      }
    }

    _lastDumpAddr = (end + 1) & 0xFFFF;
    final lines = <String>[];

    int addr = start & 0xFFF0; // align to 16
    // but start dump at [start]
    addr = start;

    while (addr <= end && addr <= 0xFFFF) {
      final row = <int>[];
      final rowStart = addr;
      for (int i = 0; i < 16 && addr <= end && addr <= 0xFFFF; i++) {
        row.add(cpu.readByte(addr++));
      }

      final hexPart = row
          .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
          .join(' ');

      // Pad hex if last row is short
      final padding = (16 - row.length) * 3;
      final asciiPart = row.map((b) => (b >= 0x20 && b < 0x7F) ? String.fromCharCode(b) : '.').join();

      lines.add(
        '${_h4(rowStart)}  ${hexPart.padRight(47 + padding)}  $asciiPart',
      );
    }

    lines.add('-');
    return lines;
  }

  // ── E — Enter/Edit bytes ──────────────────────────────────────────────────
  List<String> _cmdEnter(String rest) {
    final parts = rest.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) {
      return ['^ Usage: E address [bytes]', '-'];
    }

    _enterAddr = _parseHex(parts[0]);

    // If more args, treat as inline byte list
    if (parts.length > 1) {
      final values = parts.sublist(1);
      final output = <String>[];
      for (final v in values) {
        if (v.isEmpty) continue;
        if (v.startsWith('"') || v.startsWith("'")) {
          // string literal
          for (final ch in v.replaceAll('"', '').replaceAll("'", '').codeUnits) {
            cpu.writeByte(_enterAddr, ch);
            _enterAddr = (_enterAddr + 1) & 0xFFFF;
          }
        } else {
          final b = _parseHex(v) & 0xFF;
          cpu.writeByte(_enterAddr, b);
          _enterAddr = (_enterAddr + 1) & 0xFFFF;
        }
      }
      output.add('-');
      return output;
    }

    // Interactive mode — show current byte, await replacement
    _enterMode = true;
    final cur = cpu.readByte(_enterAddr);
    return ['${_h4(_enterAddr)}  ${_h2(cur)}.'];
  }

  List<String> _handleEnterData(String line) {
    line = line.trim();

    if (line == '-' || line.isEmpty) {
      // Done entering
      _enterMode = false;
      return ['-'];
    }

    // Replace current byte
    if (line != '.') {
      try {
        final b = _parseHex(line) & 0xFF;
        cpu.writeByte(_enterAddr, b);
      } catch (_) {
        return ['^ Error: invalid hex byte', '${_h4(_enterAddr)}  ${_h2(cpu.readByte(_enterAddr))}.'];
      }
    }

    _enterAddr = (_enterAddr + 1) & 0xFFFF;
    final cur = cpu.readByte(_enterAddr);
    return ['${_h4(_enterAddr)}  ${_h2(cur)}.'];
  }

  // ── F — Fill ──────────────────────────────────────────────────────────────
  List<String> _cmdFill(String rest) {
    try {
      final parts = rest.trim().split(RegExp(r'\s+'));
      final start = _parseHex(parts[0]);
      final end   = _parseHex(parts[1]);
      final fillBytes = parts.sublist(2).map((s) => _parseHex(s) & 0xFF).toList();
      if (fillBytes.isEmpty) return ['^ F: no fill value', '-'];
      int fi = 0;
      for (int a = start; a <= end; a++) {
        cpu.writeByte(a, fillBytes[fi % fillBytes.length]);
        fi++;
      }
      return ['-'];
    } catch (e) {
      return ['^ F: ${e}', '-'];
    }
  }

  // ── G — Go (run) ─────────────────────────────────────────────────────────
  List<String> _cmdGo(String rest) {
    final out = <String>[];
    cpu.halted = false;

    int? breakAt;
    if (rest.isNotEmpty) {
      final parts = rest.trim().split(RegExp(r'\s+'));
      if (parts[0].startsWith('=')) {
        cpu.ip = _parseHex(parts[0].substring(1));
        if (parts.length > 1) breakAt = _parseHex(parts[1]);
      } else {
        breakAt = _parseHex(parts[0]);
      }
    }

    final result = _exec.run(breakAt: breakAt);

    // Flush output log
    for (final s in cpu.outputLog) out.add(s);
    cpu.outputLog.clear();

    if (result.error != null) {
      out.add('Runtime error: ${result.error}');
    }

    out.addAll(_formatRegisters());
    out.add(_formatCurrentInstruction());
    out.add('-');
    return out;
  }

  // ── H — Hex arithmetic ────────────────────────────────────────────────────
  List<String> _cmdHex(String rest) {
    try {
      final parts = rest.trim().split(RegExp(r'\s+'));
      final a = _parseHex(parts[0]);
      final b = _parseHex(parts[1]);
      final sum  = (a + b) & 0xFFFF;
      final diff = (a - b) & 0xFFFF;
      return ['${_h4(sum)}  ${_h4(diff)}', '-'];
    } catch (_) {
      return ['^ H: Usage: H value1 value2', '-'];
    }
  }

  // ── I — Input port ────────────────────────────────────────────────────────
  List<String> _cmdIn(String rest) {
    return ['00', '-']; // Always return 0 (simulated)
  }

  // ── M — Move (copy) memory ────────────────────────────────────────────────
  List<String> _cmdMove(String rest) {
    try {
      final parts = rest.trim().split(RegExp(r'\s+'));
      final start = _parseHex(parts[0]);
      final end   = _parseHex(parts[1]);
      final dest  = _parseHex(parts[2]);
      for (int i = 0; i <= end - start; i++) {
        cpu.writeByte((dest + i) & 0xFFFF, cpu.readByte((start + i) & 0xFFFF));
      }
      return ['-'];
    } catch (e) {
      return ['^ M: ${e}', '-'];
    }
  }

  // ── N — Name (filename) ───────────────────────────────────────────────────
  List<String> _cmdName(String rest) {
    return ['-']; // Simulated — no filesystem
  }

  // ── O — Output port ───────────────────────────────────────────────────────
  List<String> _cmdOut(String rest) {
    return ['-']; // Simulated
  }

  // ── Q — Quit ──────────────────────────────────────────────────────────────
  List<String> _cmdQuit() {
    return ['__QUIT__'];
  }

  // ── R — Registers ────────────────────────────────────────────────────────
  List<String> _cmdRegister(String rest) {
    rest = rest.trim().toUpperCase();
    final out = <String>[];

    if (rest.isEmpty) {
      // Display all registers
      out.addAll(_formatRegisters());
      out.add(_formatCurrentInstruction());
      out.add('-');
      return out;
    }

    // Modify a single register
    try {
      final current = cpu.getReg(rest);
      final is8bit = cpu.is8BitReg(rest);
      out.add('$rest  ${is8bit ? _h2(current) : _h4(current)}');
      // Return a special token so the UI can prompt for new value
      out.add('__REGPROMPT__:$rest');
      return out;
    } catch (_) {
      if (rest == 'F') {
        // Show/modify flags
        out.add(_formatFlags());
        out.add('__FLAGPROMPT__');
        return out;
      }
      return ['^ R: Unknown register $rest', '-'];
    }
  }

  /// Called after user enters new register value
  List<String> setRegisterValue(String regName, String valueStr) {
    try {
      final v = _parseHex(valueStr.trim());
      cpu.setReg(regName, v);
      return ['-'];
    } catch (_) {
      return ['^ Invalid value', '-'];
    }
  }

  /// Called after user enters new flags string (e.g. "NV UP EI NG NZ AC PE NC")
  List<String> setFlagsValue(String flagStr) {
    final tokens = flagStr.trim().toUpperCase().split(RegExp(r'\s+'));
    for (final t in tokens) {
      switch (t) {
        case 'OV': cpu.of_ = true; break;
        case 'NV': cpu.of_ = false; break;
        case 'DN': cpu.df = true; break;
        case 'UP': cpu.df = false; break;
        case 'EI': cpu.ifl = true; break;
        case 'DI': cpu.ifl = false; break;
        case 'NG': cpu.sf = true; break;
        case 'PL': cpu.sf = false; break;
        case 'ZR': cpu.zf = true; break;
        case 'NZ': cpu.zf = false; break;
        case 'AC': cpu.af = true; break;
        case 'NA': cpu.af = false; break;
        case 'PE': cpu.pf = true; break;
        case 'PO': cpu.pf = false; break;
        case 'CY': cpu.cf = true; break;
        case 'NC': cpu.cf = false; break;
      }
    }
    return ['-'];
  }

  // ── S — Search ────────────────────────────────────────────────────────────
  List<String> _cmdSearch(String rest) {
    try {
      final parts = rest.trim().split(RegExp(r'\s+'));
      final start = _parseHex(parts[0]);
      final end   = _parseHex(parts[1]);
      final pattern = parts.sublist(2).map((s) => _parseHex(s) & 0xFF).toList();
      final found = <String>[];
      for (int a = start; a <= end - pattern.length + 1; a++) {
        bool match = true;
        for (int i = 0; i < pattern.length; i++) {
          if (cpu.readByte(a + i) != pattern[i]) { match = false; break; }
        }
        if (match) found.add(_h4(a));
      }
      if (found.isEmpty) found.add('(no match)');
      found.add('-');
      return found;
    } catch (e) {
      return ['^ S: $e', '-'];
    }
  }

  // ── T — Trace (single step) ──────────────────────────────────────────────
  List<String> _cmdTrace(String rest) {
    rest = rest.trim();
    int count = 1;
    if (rest.isNotEmpty) {
      if (rest.startsWith('=')) {
        final parts = rest.substring(1).split(RegExp(r'\s+'));
        cpu.ip = _parseHex(parts[0]);
        if (parts.length > 1) count = _parseHex(parts[1]);
      } else {
        count = _parseHex(rest);
      }
    }

    cpu.halted = false;
    final out = <String>[];

    for (int i = 0; i < count; i++) {
      final result = _exec.stepOne();
      for (final s in cpu.outputLog) out.add(s);
      cpu.outputLog.clear();
      if (result.error != null) out.add('Error: ${result.error}');
      if (result.halted) break;
    }

    out.addAll(_formatRegisters());
    out.add(_formatCurrentInstruction());
    out.add('-');
    return out;
  }

  // ── U — Unassemble ───────────────────────────────────────────────────────
  List<String> _cmdUnassemble(String rest) {
    int start, count = 20;
    final parts = rest.trim().split(RegExp(r'[\s,]+'));
    final nonEmpty = parts.where((s) => s.isNotEmpty).toList();

    if (nonEmpty.isEmpty) {
      start = _lastDisasmAddr;
    } else {
      start = _parseHex(nonEmpty[0]);
      if (nonEmpty.length > 1) {
        // could be end address or L count
        if (rest.toUpperCase().contains('L')) {
          count = _parseHex(nonEmpty[1]);
        } else {
          // end address — calculate how many instructions roughly
          final endAddr = _parseHex(nonEmpty[1]);
          count = ((endAddr - start) ~/ 2).clamp(1, 256);
        }
      }
    }

    final results = _dis.disasmN(start, count);
    final lines = results.map((r) {
      final bytes = r.hexBytes.padRight(14);
      return '${_h4(r.address)}  $bytes  ${r.mnemonic}';
    }).toList();

    if (results.isNotEmpty) {
      _lastDisasmAddr = results.last.nextAddress;
    }

    lines.add('-');
    return lines;
  }

  // ── Help ──────────────────────────────────────────────────────────────────
  List<String> _cmdHelp() {
    return [
      '',
      'DEBUG.EXE Commands:',
      '  A [addr]              Assemble instructions at address',
      '  D [start] [end/L n]   Dump memory (hex + ASCII)',
      '  E addr [bytes]        Enter/edit bytes at address',
      '  F start end byte      Fill memory range with byte',
      '  G [=addr] [break]     Go (run); optional start/breakpoint',
      '  H val1 val2           Hex arithmetic (sum and difference)',
      '  I port                Input from port (returns 0)',
      '  M start end dest      Move (copy) memory block',
      '  N filename            Name file (simulated)',
      '  O port byte           Output to port (no-op)',
      '  Q                     Quit DEBUG',
      '  R [reg]               Display/modify registers',
      '  S start end bytes     Search memory for byte pattern',
      '  T [=addr] [count]     Trace (single-step) instructions',
      '  U [addr] [end/L n]    Unassemble (disassemble) code',
      '',
      '-',
    ];
  }

  // ── Register display ─────────────────────────────────────────────────────
  List<String> _formatRegisters() {
    return [
      'AX=${_h4(cpu.ax)}  BX=${_h4(cpu.bx)}  CX=${_h4(cpu.cx)}  DX=${_h4(cpu.dx)}  '
      'SP=${_h4(cpu.sp)}  BP=${_h4(cpu.bp)}  SI=${_h4(cpu.si)}  DI=${_h4(cpu.di)}',
      'DS=${_h4(cpu.ds)}  ES=${_h4(cpu.es)}  SS=${_h4(cpu.ss)}  CS=${_h4(cpu.cs)}  '
      'IP=${_h4(cpu.ip)}   ${_formatFlags()}',
    ];
  }

  String _formatFlags() {
    return [
      cpu.of_ ? 'OV' : 'NV',
      cpu.df  ? 'DN' : 'UP',
      cpu.ifl ? 'EI' : 'DI',
      cpu.sf  ? 'NG' : 'PL',
      cpu.zf  ? 'ZR' : 'NZ',
      cpu.af  ? 'AC' : 'NA',
      cpu.pf  ? 'PE' : 'PO',
      cpu.cf  ? 'CY' : 'NC',
    ].join(' ');
  }

  String _formatCurrentInstruction() {
    final d = _dis.disasm(cpu.ip);
    final bytes = d.hexBytes.padRight(14);
    return '${_h4(cpu.cs)}:${_h4(cpu.ip)}  $bytes  ${d.mnemonic}';
  }

  // ── Formatting helpers ────────────────────────────────────────────────────
  String _h2(int v) => (v & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0');
  String _h4(int v) => (v & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
  String _fmtAddr(int addr) => '${_h4(cpu.cs)}:${_h4(addr)}';

  int _parseHex(String s) {
    s = s.trim().toUpperCase();
    if (s.endsWith('H')) s = s.substring(0, s.length - 1);
    if (s.startsWith('0X')) s = s.substring(2);
    return int.parse(s, radix: 16);
  }
}
