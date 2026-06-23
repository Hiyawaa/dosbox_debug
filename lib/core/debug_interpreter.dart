// lib/core/debug_interpreter.dart
//
// Public API for the DEBUG.EXE emulator layer.
// debug_state.dart depends only on this file.

import '../debug_exe/dbg_commands.dart';
import '../debug_exe/dbg_cpu.dart';

// ---------------------------------------------------------------------------
// DebugMode
// ---------------------------------------------------------------------------
enum DebugMode {
  /// Normal "-" prompt: user types commands (D, U, T, G, R, …)
  command,

  /// After "A [addr]": each line is assembled as one instruction
  assembling,

  /// After "R <regname>": next line is the new hex register value
  register,

  /// After "R F": next line is space-separated flag-mnemonic toggles
  flags,
}

// ---------------------------------------------------------------------------
// DebugInterpreter
// ---------------------------------------------------------------------------
class DebugInterpreter {
  final DbgSession session;

  DebugMode _mode = DebugMode.command;
  int _assembleAddr = 0;
  String _pendingReg = '';

  /// [context] accepted but ignored — lets callers do DebugInterpreter(this).
  DebugInterpreter([dynamic context]) : session = DbgSession();

  // ---- Mode ----------------------------------------------------------------

  DebugMode get mode => _mode;

  // ---- CPU read-only accessors ---------------------------------------------

  DbgCpu get cpu => session.cpu;

  int get ax => session.cpu.ax;
  int get bx => session.cpu.bx;
  int get cx => session.cpu.cx;
  int get dx => session.cpu.dx;
  int get si => session.cpu.si;
  int get di => session.cpu.di;
  int get sp => session.cpu.sp;
  int get bp => session.cpu.bp;
  int get ip => session.cpu.ip;
  int get cs => session.cpu.cs;
  int get ds => session.cpu.ds;
  int get ss => session.cpu.ss;
  int get es => session.cpu.es;

  bool get cf => session.cpu.cf;
  bool get zf => session.cpu.zf;
  bool get sf => session.cpu.sf;
  bool get of => session.cpu.of;
  bool get pf => session.cpu.pf;
  bool get af => session.cpu.af;
  bool get df => session.cpu.df;
  bool get tf => session.cpu.tf;

  bool get halted => session.cpu.halted;

  // ---- Primary input handler -----------------------------------------------
  //
  // Returns List<String> — callers do:
  //   for (final line in interpreter.handleLine(input)) { ... }

  List<String> handleLine(String input) {
    switch (_mode) {
      case DebugMode.assembling:
        return _handleAssembleLine(input);
      case DebugMode.register:
        return _handleRegisterValue(input);
      case DebugMode.flags:
        return setFlagsValue(input); // returns List<String>
      case DebugMode.command:
        return _handleCommand(input);
    }
  }

  // ---- Command mode --------------------------------------------------------

  List<String> _handleCommand(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return [];

    final cmd = line[0].toUpperCase();

    // Q — quit (caller checks mode or output for sentinel)
    if (cmd == 'Q') {
      return ['__QUIT__']; // sentinel: debug_state.dart can check for this
    }

    // A — enter assembling mode
    if (cmd == 'A') {
      final result = session.run(line);
      if (result.lines.isNotEmpty) {
        _assembleAddr = _parseAddrFromPrompt(result.lines.first);
      }
      _mode = DebugMode.assembling;
      return result.lines;
    }

    // R — register sub-commands
    if (cmd == 'R') {
      final rest =
          line.length > 1 ? line.substring(1).trim().toUpperCase() : '';
      if (rest.isEmpty) {
        return session.run('R').lines;
      }
      if (rest == 'F') {
        _mode = DebugMode.flags;
        return [session.cpu.flagsDisplay()];
      }
      // R <regname> — show value then enter register-edit mode
      try {
        final val = session.cpu.getReg16(rest);
        _pendingReg = rest;
        _mode = DebugMode.register;
        final h4 = val.toRadixString(16).toUpperCase().padLeft(4, '0');
        return ['$rest  $h4'];
      } catch (_) {
        return ['Error: unknown register $rest'];
      }
    }

    // All other commands
    final result = session.run(line);
    _mode = DebugMode.command;
    return result.lines;
  }

  // ---- Assembling mode -----------------------------------------------------

  List<String> _handleAssembleLine(String line) {
    if (line.trim().isEmpty) {
      _mode = DebugMode.command;
      return [];
    }
    final result = session.assembleAt(_assembleAddr, line.trim());
    if (result.error != null) {
      return ['^ ${result.error}', _asmPrompt(_assembleAddr)];
    }
    _assembleAddr = result.next!;
    return [];
  }

  // ---- Register-value mode -------------------------------------------------

  List<String> _handleRegisterValue(String raw) {
    _mode = DebugMode.command;
    final input = raw.trim();
    if (input.isEmpty) return [];
    final value = int.tryParse(input, radix: 16);
    if (value == null) return ['Error: invalid hex value'];
    try {
      _applyRegister(_pendingReg, value);
      return [];
    } catch (e) {
      return ['Error: $e'];
    }
  }

  void _applyRegister(String name, int value) {
    const regs8 = ['AL', 'AH', 'BL', 'BH', 'CL', 'CH', 'DL', 'DH'];
    if (regs8.contains(name)) {
      session.cpu.setReg8(name, value & 0xFF);
    } else {
      session.cpu.setReg16(name, value & 0xFFFF);
    }
  }

  // ---- Register set (called directly by debug_state.dart) -----------------
  //
  // setRegisterValue(String name, String hexValue) -> List<String>
  // debug_state.dart iterates the result:
  //   for (final line in interpreter.setRegisterValue(name, hexStr)) { … }

  List<String> setRegisterValue(String name, String hexValue) {
    final n = name.trim().toUpperCase();
    final value = int.tryParse(hexValue.trim(), radix: 16);
    if (value == null) {
      return ['Error: invalid hex value "${hexValue.trim()}"'];
    }
    try {
      _applyRegister(n, value);
      return [];
    } catch (e) {
      return ['Error: $e'];
    }
  }

  /// Convenience overload when the caller already has an int.
  void setRegister(String name, int value) => _applyRegister(
        name.trim().toUpperCase(),
        value,
      );

  void setRegister8(String name, int value) =>
      session.cpu.setReg8(name.trim().toUpperCase(), value & 0xFF);

  int getRegister(String name) =>
      session.cpu.getReg16(name.trim().toUpperCase());

  // ---- Flags set -----------------------------------------------------------
  //
  // setFlagsValue(String) -> List<String>
  // debug_state.dart iterates the result:
  //   for (final line in interpreter.setFlagsValue(flagStr)) { … }
  //
  // Parses DEBUG.EXE flag mnemonic pairs (space-separated).
  // Each token either sets or clears the corresponding flag:
  //   OV/NV  DN/UP  EI/DI  NG/PL  ZR/NZ  AC/NA  PE/PO  CY/NC

  List<String> setFlagsValue(String flagString) {
    _mode = DebugMode.command;
    final tokens = flagString.trim().toUpperCase().split(RegExp(r'\s+'));
    for (final tok in tokens) {
      switch (tok) {
        case 'OV':
          session.cpu.of = true;
          break;
        case 'NV':
          session.cpu.of = false;
          break;
        case 'DN':
          session.cpu.df = true;
          break;
        case 'UP':
          session.cpu.df = false;
          break;
        case 'EI':
          session.cpu.ifl = true;
          break;
        case 'DI':
          session.cpu.ifl = false;
          break;
        case 'NG':
          session.cpu.sf = true;
          break;
        case 'PL':
          session.cpu.sf = false;
          break;
        case 'ZR':
          session.cpu.zf = true;
          break;
        case 'NZ':
          session.cpu.zf = false;
          break;
        case 'AC':
          session.cpu.af = true;
          break;
        case 'NA':
          session.cpu.af = false;
          break;
        case 'PE':
          session.cpu.pf = true;
          break;
        case 'PO':
          session.cpu.pf = false;
          break;
        case 'CY':
          session.cpu.cf = true;
          break;
        case 'NC':
          session.cpu.cf = false;
          break;
      }
    }
    return []; // no output lines; caller iterates this safely
  }

  // ---- High-level command aliases -----------------------------------------

  List<String> runCommand(String command) => session.run(command).lines;

  bool isQuitCommand(String command) => command.trim().toUpperCase() == 'Q';

  List<String> trace([int count = 1]) =>
      session.run('T ${count.toRadixString(16).toUpperCase()}').lines;

  List<String> proceed([int count = 1]) =>
      session.run('P ${count.toRadixString(16).toUpperCase()}').lines;

  List<String> go([String? breakAt]) {
    final arg = breakAt != null ? '=$breakAt' : '';
    return session.run('G $arg'.trim()).lines;
  }

  // ---- Assemble helpers ---------------------------------------------------

  String beginAssemble([String? addressArg]) {
    final arg = addressArg ?? '';
    final lines = session.run('A $arg'.trim()).lines;
    if (lines.isNotEmpty) {
      _assembleAddr = _parseAddrFromPrompt(lines.first);
      _mode = DebugMode.assembling;
    }
    return lines.isNotEmpty ? lines.first : '';
  }

  ({int? next, String? error}) assembleInstruction(int addr, String line) =>
      session.assembleAt(addr, line);

  // ---- Memory operations --------------------------------------------------

  List<int> readMemory(int addr, int count) => List<int>.generate(
        count,
        (i) => session.cpu.readByteLin((addr + i) & 0xFFFFF),
      );

  void writeMemory(int addr, List<int> bytes) {
    for (int i = 0; i < bytes.length; i++) {
      session.cpu.writeByteLin((addr + i) & 0xFFFFF, bytes[i]);
    }
  }

  List<String> dumpMemory([String range = '']) =>
      session.run('D $range'.trim()).lines;

  List<String> unassemble([String range = '']) =>
      session.run('U $range'.trim()).lines;

  // ---- Register display ---------------------------------------------------

  String registerDump() {
    final c = session.cpu;
    String h4(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');
    final l1 = 'AX=${h4(c.ax)}  BX=${h4(c.bx)}  CX=${h4(c.cx)}  DX=${h4(c.dx)}'
        '  SP=${h4(c.sp)}  BP=${h4(c.bp)}  SI=${h4(c.si)}  DI=${h4(c.di)}';
    final l2 = 'DS=${h4(c.ds)}  ES=${h4(c.es)}  SS=${h4(c.ss)}  CS=${h4(c.cs)}'
        '  IP=${h4(c.ip)}   ${c.flagsDisplay()}';
    return '$l1\n$l2';
  }

  // ---- Reset --------------------------------------------------------------

  void reset() {
    session.cpu.reset();
    session.cpu.cs = 0x0800;
    session.cpu.ds = 0x0800;
    session.cpu.es = 0x0800;
    session.cpu.ss = 0x0800;
    session.cpu.ip = 0x0100;
    session.cpu.sp = 0xFFFE;
    _mode = DebugMode.command;
    _assembleAddr = 0;
    _pendingReg = '';
  }

  // ---- Private helpers ----------------------------------------------------

  int _parseAddrFromPrompt(String prompt) {
    final m = RegExp(r'([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})').firstMatch(prompt);
    if (m == null) return session.cpu.csip();
    final seg = int.parse(m.group(1)!, radix: 16);
    final off = int.parse(m.group(2)!, radix: 16);
    return DbgCpu.linear(seg, off);
  }

  String _asmPrompt(int linearAddr) {
    String h4(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');
    final seg = linearAddr >> 4;
    final off = linearAddr & 0xFFFF;
    return '${h4(seg)}:${h4(off)}';
  }
}
