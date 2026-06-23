// lib/debug_exe/dbg_commands.dart
//
// Parses and executes classic MS-DOS DEBUG.EXE commands against a DbgCpu.
// Output strings are formatted to match real DEBUG.EXE as closely as is
// reasonable in a terminal-emulator widget.

import 'dbg_cpu.dart';
import 'dbg_exec.dart';
import 'dbg_isa.dart';

class CmdResult {
  final List<String> lines;
  final bool quit;
  CmdResult(this.lines, {this.quit = false});
}

class DbgSession {
  final DbgCpu cpu = DbgCpu();
  late final DbgExec exec;
  int dumpPtr = 0x0100; // address D continues from when called with no range
  int unasmPtr = 0x0100; // address U continues from
  String? fileName;
  int fileSize = 0;
  final List<int> breakpoints = [];

  DbgSession() {
    cpu.reset();
    cpu.cs = cpu.ds = cpu.es = cpu.ss =
        0x0800; // arbitrary PSP-like segment, like real DEBUG's default
    cpu.ip = 0x0100;
    cpu.sp = 0xFFFE;
    exec = DbgExec(cpu);
  }

  String hex2(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');
  String hex4(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');

  /// Top-level entry point: run one line typed at the "-" prompt.
  CmdResult run(String line) {
    line = line.trim();
    if (line.isEmpty) return CmdResult([]);
    final cmdChar = line[0].toUpperCase();
    final rest = line.substring(1).trim();

    switch (cmdChar) {
      case 'Q':
        return CmdResult([], quit: true);
      case '?':
        return CmdResult(_help());
      case 'R':
        return _cmdRegisters(rest);
      case 'D':
        return _cmdDump(rest);
      case 'E':
        return _cmdEnter(rest);
      case 'F':
        return _cmdFill(rest);
      case 'U':
        return _cmdUnassemble(rest);
      case 'A':
        return _cmdAssemble(rest);
      case 'G':
        return _cmdGo(rest);
      case 'T':
        return _cmdTrace(rest);
      case 'P':
        return _cmdProceed(rest);
      case 'C':
        return _cmdCompare(rest);
      case 'M':
        return _cmdMove(rest);
      case 'S':
        return _cmdSearch(rest);
      case 'N':
        return _cmdName(rest);
      case 'L':
        return _cmdLoad(rest);
      case 'H':
        return _cmdHex(rest);
      case 'I':
        return CmdResult([readPort(rest)]);
      case 'O':
        return _cmdOutput(rest);
      default:
        return CmdResult(['^']);
    }
  }

  // ----------------------------------------------------------- helpers ---

  /// Parse an address token: bare offset (uses DS), seg:off, or a register
  /// name is NOT valid here (DEBUG ranges only take literal addresses).
  int? _parseAddr(String s, {int? defaultSeg}) {
    s = s.trim();
    if (s.isEmpty) return null;
    if (s.contains(':')) {
      final parts = s.split(':');
      final seg = int.tryParse(parts[0], radix: 16);
      final off = int.tryParse(parts[1], radix: 16);
      if (seg == null || off == null) return null;
      return DbgCpu.linear(seg, off);
    }
    final off = int.tryParse(s, radix: 16);
    if (off == null) return null;
    return DbgCpu.linear(defaultSeg ?? cpu.ds, off);
  }

  /// Parse a DEBUG range: "addr", "addr addr2" (start,end), or "addr L len".
  (int start, int end)? _parseRange(String s, {int defaultLen = 0x80}) {
    s = s.trim();
    if (s.isEmpty) return null;
    final parts = s.split(RegExp(r'\s+'));
    final start = _parseAddr(parts[0]);
    if (start == null) return null;
    if (parts.length == 1) {
      return (start, (start + defaultLen - 1) & 0xFFFFF);
    }
    if (parts[1].toUpperCase() == 'L' && parts.length >= 3) {
      final len = int.tryParse(parts[2], radix: 16) ?? defaultLen;
      return (start, (start + len - 1) & 0xFFFFF);
    }
    if (parts[1].toUpperCase().startsWith('L')) {
      final lenStr = parts[1].substring(1);
      final len = int.tryParse(lenStr, radix: 16) ?? defaultLen;
      return (start, (start + len - 1) & 0xFFFFF);
    }
    final end = _parseAddr(parts[1]);
    if (end == null) return (start, (start + defaultLen - 1) & 0xFFFFF);
    return (start, end);
  }

  // -------------------------------------------------------------- R -----

  CmdResult _cmdRegisters(String rest) {
    if (rest.isEmpty) {
      return CmdResult(_registerDump());
    }
    if (rest.toUpperCase() == 'F') {
      return CmdResult(['${cpu.flagsDisplay()}', '-'], quit: false);
    }
    // R regname -> show then allow next line to set it; here we just show
    // and accept "R AX" followed by a value on the SAME invocation isn't
    // how real DEBUG works (it prompts on a second line), so we support
    // the common shorthand "R AX 1234" too for convenience.
    final parts = rest.split(RegExp(r'\s+'));
    final regName = parts[0].toUpperCase();
    if (parts.length >= 2) {
      final value = int.tryParse(parts[1], radix: 16);
      if (value == null) return CmdResult(['Error']);
      try {
        if (['AL', 'AH', 'BL', 'BH', 'CL', 'CH', 'DL', 'DH']
            .contains(regName)) {
          cpu.setReg8(regName, value);
        } else {
          cpu.setReg16(regName, value);
        }
      } catch (_) {
        return CmdResult(['Error']);
      }
      return CmdResult(_registerDump());
    }
    try {
      final v = cpu.getReg16(regName);
      return CmdResult(['$regName ${hex4(v)}', ':']);
    } catch (_) {
      return CmdResult(['Error']);
    }
  }

  List<String> _registerDump() {
    final c = cpu;
    final line1 =
        'AX=${hex4(c.ax)}  BX=${hex4(c.bx)}  CX=${hex4(c.cx)}  DX=${hex4(c.dx)}  '
        'SP=${hex4(c.sp)}  BP=${hex4(c.bp)}  SI=${hex4(c.si)}  DI=${hex4(c.di)}';
    final line2 =
        'DS=${hex4(c.ds)}  ES=${hex4(c.es)}  SS=${hex4(c.ss)}  CS=${hex4(c.cs)}  '
        'IP=${hex4(c.ip)}   ${c.flagsDisplay()}';
    final d = DbgIsa.decode(c.memory, c.csip());
    final line3 =
        '${hex4(c.cs)}:${hex4(c.ip)} ${_bytesHex(d.bytes).padRight(20)}${d.text}';
    return [line1, line2, line3];
  }

  String _bytesHex(List<int> bytes) => bytes.map((b) => hex2(b)).join('');

  // -------------------------------------------------------------- D -----

  CmdResult _cmdDump(String rest) {
    int start;
    int end;
    if (rest.isEmpty) {
      start = dumpPtr;
      end = (start + 0x7F) & 0xFFFFF;
    } else {
      final r = _parseRange(rest);
      if (r == null) return CmdResult(['Error']);
      start = r.$1;
      end = r.$2;
    }
    final lines = <String>[];
    int addr = start & 0xFFFF0; // align to 16-byte row like real DEBUG
    final segDisplay = start >> 4;
    while (addr <= end) {
      final rowBytes = <int>[];
      for (int i = 0; i < 16; i++) {
        rowBytes.add(cpu.readByteLin(addr + i));
      }
      final hexPart = List.generate(16, (i) {
        final s = hex2(rowBytes[i]);
        return i == 7 ? '$s-' : '$s ';
      }).join();
      final asciiPart = rowBytes
          .map((b) => (b >= 0x20 && b < 0x7F) ? String.fromCharCode(b) : '.')
          .join();
      final segOff = addr & 0xFFFF0;
      lines.add(
          '${hex4(segDisplay)}:${hex4(segOff & 0xFFFF)}  $hexPart $asciiPart');
      addr += 16;
    }
    dumpPtr = (end + 1) & 0xFFFFF;
    return CmdResult(lines);
  }

  // -------------------------------------------------------------- E -----

  CmdResult _cmdEnter(String rest) {
    final parts = rest.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return CmdResult(['Error']);
    final addr = _parseAddr(parts[0]);
    if (addr == null) return CmdResult(['Error']);
    if (parts.length == 1) {
      // Real DEBUG enters interactive byte-by-byte edit mode; we apply the
      // single-shot form here since this is a non-interactive command line.
      return CmdResult([
        '${hex4(addr >> 4)}:${hex4(addr & 0xF)}  ${hex2(cpu.readByteLin(addr))}.'
      ]);
    }
    int a = addr;
    for (int i = 1; i < parts.length; i++) {
      final tok = parts[i];
      if (tok.startsWith("'") && tok.endsWith("'") && tok.length >= 2) {
        for (final c in tok.substring(1, tok.length - 1).codeUnits) {
          cpu.writeByteLin(a, c);
          a++;
        }
        continue;
      }
      final v = int.tryParse(tok, radix: 16);
      if (v == null) return CmdResult(['Error']);
      cpu.writeByteLin(a, v & 0xFF);
      a++;
    }
    return CmdResult([]);
  }

  // -------------------------------------------------------------- F -----

  CmdResult _cmdFill(String rest) {
    final m = RegExp(r'^(\S+(?:\s+\S+)?)\s+(.+)$').firstMatch(rest);
    if (m == null) return CmdResult(['Error']);
    final r = _parseRange(m.group(1)!);
    if (r == null) return CmdResult(['Error']);
    final listStr = m.group(2)!;
    final values = <int>[];
    for (final tok in listStr.split(RegExp(r'\s+'))) {
      if (tok.startsWith("'") && tok.endsWith("'") && tok.length >= 2) {
        values.addAll(tok.substring(1, tok.length - 1).codeUnits);
      } else {
        final v = int.tryParse(tok, radix: 16);
        if (v != null) values.add(v & 0xFF);
      }
    }
    if (values.isEmpty) return CmdResult(['Error']);
    int a = r.$1;
    int i = 0;
    while (a <= r.$2) {
      cpu.writeByteLin(a, values[i % values.length]);
      a++;
      i++;
    }
    return CmdResult([]);
  }

  // -------------------------------------------------------------- U -----

  CmdResult _cmdUnassemble(String rest) {
    int start;
    int end;
    if (rest.isEmpty) {
      start = unasmPtr;
      end = (start + 31) & 0xFFFFF; // roughly enough for ~10-20 lines
    } else {
      final r = _parseRange(rest, defaultLen: 32);
      if (r == null) return CmdResult(['Error']);
      start = r.$1;
      end = r.$2;
    }
    final lines = <String>[];
    int addr = start;
    final seg = start >> 4;
    while (addr <= end) {
      final d = DbgIsa.decode(cpu.memory, addr);
      final off = addr & 0xFFFFF;
      final segShown = off >> 4 == seg ? seg : off >> 4;
      lines.add(
          '${hex4(segShown)}:${hex4(off & 0xFFFF)} ${_bytesHex(d.bytes).padRight(20)}${d.text}');
      addr += d.length;
    }
    unasmPtr = addr & 0xFFFFF;
    return CmdResult(lines);
  }

  // -------------------------------------------------------------- A -----

  CmdResult _cmdAssemble(String rest) {
    int addr = rest.isEmpty ? cpu.csip() : (_parseAddr(rest) ?? cpu.csip());
    // Non-interactive single-shot form: if the caller passed "A addr" with
    // nothing else, we report the address and expect subsequent lines fed
    // back through assembleAt(). The terminal UI handles the multi-line
    // interactive loop; this just primes the starting address.
    return CmdResult(['${hex4(addr >> 4)}:${hex4(addr & 0xFFFF)}']);
  }

  /// Assemble one instruction line at `addr`, writing bytes into memory.
  /// Returns the next address to assemble at, or null on error.
  ({int? next, String? error}) assembleAt(int addr, String instrLine) {
    final r = DbgIsa.assembleLine(instrLine, addr);
    if (!r.ok) return (next: null, error: r.error);
    for (int i = 0; i < r.bytes.length; i++) {
      cpu.writeByteLin(addr + i, r.bytes[i]);
    }
    return (next: (addr + r.bytes.length) & 0xFFFFF, error: null);
  }

  // -------------------------------------------------------------- G -----

  CmdResult _cmdGo(String rest) {
    int? breakAt;
    rest = rest.trim();
    if (rest.startsWith('=')) {
      final sp = rest.indexOf(' ');
      final addrTok = sp == -1 ? rest.substring(1) : rest.substring(1, sp);
      final a = _parseAddr(addrTok, defaultSeg: cpu.cs);
      if (a != null) cpu.ip = a & 0xFFFF;
      rest = sp == -1 ? '' : rest.substring(sp + 1).trim();
    }
    if (rest.isNotEmpty) {
      final a = _parseAddr(rest, defaultSeg: cpu.cs);
      if (a != null) breakAt = a & 0xFFFFF;
    }
    int guard = 0;
    while (!cpu.halted && guard++ < 2000000) {
      final lin = cpu.csip();
      if (breakAt != null && lin == breakAt) {
        return CmdResult(['', ..._registerDump()]);
      }
      final outcome = exec.step();
      if (outcome.error != null) {
        return CmdResult(['', 'Runtime error: ${outcome.error}']);
      }
    }
    if (guard >= 2000000) {
      return CmdResult([
        '',
        'Program appears to be in an infinite loop (stopped).',
        '',
        ..._registerDump()
      ]);
    }
    return CmdResult(['', 'Program terminated normally.']);
  }

  // -------------------------------------------------------------- T -----

  CmdResult _cmdTrace(String rest) {
    rest = rest.trim();
    int count = 1;
    if (rest.startsWith('=')) {
      final sp = rest.indexOf(' ');
      final addrTok = sp == -1 ? rest.substring(1) : rest.substring(1, sp);
      final a = _parseAddr(addrTok, defaultSeg: cpu.cs);
      if (a != null) cpu.ip = a & 0xFFFF;
      rest = sp == -1 ? '' : rest.substring(sp + 1).trim();
    }
    if (rest.isNotEmpty) {
      count = int.tryParse(rest, radix: 16) ?? 1;
    }
    final lines = <String>[];
    for (int i = 0; i < count && !cpu.halted; i++) {
      final outcome = exec.step();
      lines.addAll(_registerDump());
      if (i < count - 1) lines.add('');
      if (outcome.error != null) {
        lines.add('Runtime error: ${outcome.error}');
        break;
      }
    }
    return CmdResult(lines);
  }

  // -------------------------------------------------------------- P -----

  CmdResult _cmdProceed(String rest) {
    rest = rest.trim();
    int count = 1;
    if (rest.startsWith('=')) {
      final sp = rest.indexOf(' ');
      final addrTok = sp == -1 ? rest.substring(1) : rest.substring(1, sp);
      final a = _parseAddr(addrTok, defaultSeg: cpu.cs);
      if (a != null) cpu.ip = a & 0xFFFF;
      rest = sp == -1 ? '' : rest.substring(sp + 1).trim();
    }
    if (rest.isNotEmpty) {
      count = int.tryParse(rest, radix: 16) ?? 1;
    }
    final lines = <String>[];
    for (int i = 0; i < count && !cpu.halted; i++) {
      if (exec.currentIsCallLikeForProceed()) {
        final after = exec.addressAfterCurrent();
        int guard = 0;
        final targetCs = cpu.cs;
        while (!cpu.halted && guard++ < 2000000) {
          exec.step();
          if (cpu.ip == after && cpu.cs == targetCs) break;
        }
      } else {
        exec.step();
      }
      lines.addAll(_registerDump());
      if (i < count - 1) lines.add('');
    }
    return CmdResult(lines);
  }

  // -------------------------------------------------------------- C -----

  CmdResult _cmdCompare(String rest) {
    final m = RegExp(r'^(\S+(?:\s+\S+)?)\s+(\S+)$').firstMatch(rest);
    if (m == null) return CmdResult(['Error']);
    final r = _parseRange(m.group(1)!);
    if (r == null) return CmdResult(['Error']);
    final target = _parseAddr(m.group(2)!);
    if (target == null) return CmdResult(['Error']);
    final lines = <String>[];
    int a = r.$1;
    int b = target;
    while (a <= r.$2) {
      final av = cpu.readByteLin(a);
      final bv = cpu.readByteLin(b);
      if (av != bv) {
        lines.add(
            '${hex4(a >> 4)}:${hex4(a & 0xF)}  ${hex2(av)}   ${hex2(bv)}   ${hex4(b >> 4)}:${hex4(b & 0xF)}');
      }
      a++;
      b++;
    }
    return CmdResult(lines);
  }

  // -------------------------------------------------------------- M -----

  CmdResult _cmdMove(String rest) {
    final m = RegExp(r'^(\S+(?:\s+\S+)?)\s+(\S+)$').firstMatch(rest);
    if (m == null) return CmdResult(['Error']);
    final r = _parseRange(m.group(1)!);
    if (r == null) return CmdResult(['Error']);
    final dest = _parseAddr(m.group(2)!);
    if (dest == null) return CmdResult(['Error']);
    final len = r.$2 - r.$1 + 1;
    final data = List<int>.generate(len, (i) => cpu.readByteLin(r.$1 + i));
    for (int i = 0; i < len; i++) {
      cpu.writeByteLin(dest + i, data[i]);
    }
    return CmdResult([]);
  }

  // -------------------------------------------------------------- S -----

  CmdResult _cmdSearch(String rest) {
    final m = RegExp(r'^(\S+(?:\s+\S+)?)\s+(.+)$').firstMatch(rest);
    if (m == null) return CmdResult(['Error']);
    final r = _parseRange(m.group(1)!);
    if (r == null) return CmdResult(['Error']);
    final listStr = m.group(2)!;
    final pattern = <int>[];
    for (final tok in listStr.split(RegExp(r'\s+'))) {
      if (tok.startsWith("'") && tok.endsWith("'") && tok.length >= 2) {
        pattern.addAll(tok.substring(1, tok.length - 1).codeUnits);
      } else {
        final v = int.tryParse(tok, radix: 16);
        if (v != null) pattern.add(v & 0xFF);
      }
    }
    if (pattern.isEmpty) return CmdResult(['Error']);
    final lines = <String>[];
    final seg = r.$1 >> 4;
    for (int a = r.$1; a <= r.$2 - pattern.length + 1; a++) {
      bool match = true;
      for (int i = 0; i < pattern.length; i++) {
        if (cpu.readByteLin(a + i) != pattern[i]) {
          match = false;
          break;
        }
      }
      if (match) {
        lines.add('${hex4(seg)}:${hex4((a - (seg << 4)) & 0xFFFF)}');
      }
    }
    if (lines.isEmpty) lines.add('Pattern not found');
    return CmdResult(lines);
  }

  // -------------------------------------------------------------- N -----

  CmdResult _cmdName(String rest) {
    fileName = rest.trim();
    return CmdResult([]);
  }

  CmdResult _cmdLoad(String rest) {
    return CmdResult([
      'Load: no file system in this recreation — use A/E to enter code/data directly.'
    ]);
  }

  CmdResult _cmdHex(String rest) {
    final parts = rest.split(RegExp(r'\s+'));
    if (parts.length < 2) return CmdResult(['Error']);
    final a = int.tryParse(parts[0], radix: 16);
    final b = int.tryParse(parts[1], radix: 16);
    if (a == null || b == null) return CmdResult(['Error']);
    final sum = (a + b) & 0xFFFF;
    final diff = (a - b) & 0xFFFF;
    return CmdResult(['${hex4(sum)}  ${hex4(diff)}']);
  }

  String readPort(String rest) {
    final p = int.tryParse(rest.trim(), radix: 16);
    if (p == null) return 'Error';
    return hex2(0xFF); // no real hardware behind this recreation
  }

  CmdResult _cmdOutput(String rest) {
    return CmdResult([]); // accepted, no-op: no real I/O ports to write to
  }

  List<String> _help() => const [
        'A [address]              Assemble',
        'C range address          Compare',
        'D [range]                Dump',
        'E address [list]         Enter',
        'F range list              Fill',
        'G [=address] [address]   Go',
        'H value1 value2          Hexadecimal',
        'I port                   Input',
        'L [address]               Load',
        'M range address           Move',
        'N [pathname]               Name',
        'O port byte               Output',
        'P [=address] [number]      Proceed',
        'Q                          Quit',
        'R [register]               Register',
        'S range list                Search',
        'T [=address] [value]        Trace',
        'U [range]                   Unassemble',
        '? Help',
      ];
}
