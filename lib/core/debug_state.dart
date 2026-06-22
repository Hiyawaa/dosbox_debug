// lib/core/debug_state.dart
// ChangeNotifier state that bridges the DebugInterpreter with the Flutter UI.

import 'package:flutter/foundation.dart';
import 'cpu8086.dart';
import 'debug_interpreter.dart';

enum InputMode {
  normal,       // Standard command input (prompt = '-')
  assembling,   // Inside 'A' command (prompt = 'XXXX:XXXX ')
  enterByte,    // Inside 'E' interactive byte editing
  regValue,     // Waiting for new register value
  flagValue,    // Waiting for new flags string
}

class TerminalLine {
  final String text;
  final bool isInput;
  final bool isError;
  final bool isHighlight; // Register dump lines
  TerminalLine(this.text, {this.isInput = false, this.isError = false, this.isHighlight = false});
}

class DebugState extends ChangeNotifier {
  final CPU8086 cpu = CPU8086();
  late final DebugInterpreter _interpreter;

  final List<TerminalLine> lines = [];
  InputMode inputMode = InputMode.normal;
  String _pendingReg = '';
  bool _quit = false;
  bool get hasQuit => _quit;

  // History
  final List<String> _history = [];
  int _historyIdx = -1;

  DebugState() {
    _interpreter = DebugInterpreter(cpu);
    _addOutput('DOS Debug Emulator — Flutter Edition');
    _addOutput('Type ? for help, Q to quit.');
    _addOutput('-');
  }

  String get prompt {
    switch (inputMode) {
      case InputMode.normal:       return '-';
      case InputMode.assembling:   return ''; // shown inline
      case InputMode.enterByte:    return '';
      case InputMode.regValue:     return ':';
      case InputMode.flagValue:    return '-';
    }
  }

  // ── Command submission ────────────────────────────────────────────────────
  void submitLine(String input) {
    input = input.trimRight();

    // Echo input to terminal
    _addInput(input);

    // History
    if (input.isNotEmpty) {
      _history.remove(input);
      _history.insert(0, input);
      if (_history.length > 100) _history.removeLast();
    }
    _historyIdx = -1;

    switch (inputMode) {
      case InputMode.normal:
        _processNormalCommand(input);
        break;
      case InputMode.assembling:
        _processAssemblyLine(input);
        break;
      case InputMode.enterByte:
        _processEnterByte(input);
        break;
      case InputMode.regValue:
        _processRegValue(input);
        break;
      case InputMode.flagValue:
        _processFlagValue(input);
        break;
    }

    notifyListeners();
  }

  void _processNormalCommand(String input) {
    final output = _interpreter.handleLine(input);
    for (final line in output) {
      _handleOutputLine(line);
    }
    // Sync mode
    if (_interpreter.mode == DebugMode.assembling) {
      inputMode = InputMode.assembling;
    }
  }

  void _processAssemblyLine(String input) {
    final output = _interpreter.handleLine(input);
    for (final line in output) {
      _handleOutputLine(line);
    }
    if (_interpreter.mode != DebugMode.assembling) {
      inputMode = InputMode.normal;
    }
  }

  void _processEnterByte(String input) {
    final output = _interpreter.handleLine(input);
    for (final line in output) {
      _handleOutputLine(line);
    }
    // Check if enter mode ended
    if (!_isEnterModeLine(lines.last.text)) {
      inputMode = InputMode.normal;
    }
  }

  void _processRegValue(String input) {
    final output = _interpreter.setRegisterValue(_pendingReg, input);
    for (final o in output) _addOutput(o);
    inputMode = InputMode.normal;
  }

  void _processFlagValue(String input) {
    final output = _interpreter.setFlagsValue(input);
    for (final o in output) _addOutput(o);
    inputMode = InputMode.normal;
  }

  void _handleOutputLine(String line) {
    if (line == '__QUIT__') {
      _quit = true;
      _addOutput('Program terminated normally.');
      return;
    }
    if (line.startsWith('__REGPROMPT__:')) {
      _pendingReg = line.substring('__REGPROMPT__:'.length);
      inputMode = InputMode.regValue;
      return;
    }
    if (line == '__FLAGPROMPT__') {
      inputMode = InputMode.flagValue;
      return;
    }

    // Detect enter-byte mode prompt (ends with '.')
    if (_isEnterModeLine(line)) {
      inputMode = InputMode.enterByte;
      _addOutput(line);
      return;
    }

    // Detect register lines (highlight them)
    final isReg = _isRegisterLine(line);
    lines.add(TerminalLine(line, isHighlight: isReg, isError: line.startsWith('^')));
  }

  bool _isEnterModeLine(String line) {
    // Pattern: "0100  41." — 4 hex digits, spaces, 2 hex digits, period
    return RegExp(r'^[0-9A-F]{4}\s+[0-9A-F]{2}\.$').hasMatch(line.trim());
  }

  bool _isRegisterLine(String line) {
    return line.contains('AX=') || line.contains('DS=') || line.contains('IP=');
  }

  void _addOutput(String text) {
    lines.add(TerminalLine(text));
  }

  void _addInput(String text) {
    // Add the prompt + input as a line
    lines.add(TerminalLine('-$text', isInput: true));
  }

  // ── History navigation ────────────────────────────────────────────────────
  String? historyUp(String current) {
    if (_history.isEmpty) return null;
    _historyIdx = (_historyIdx + 1).clamp(0, _history.length - 1);
    return _history[_historyIdx];
  }

  String? historyDown() {
    if (_historyIdx <= 0) { _historyIdx = -1; return ''; }
    _historyIdx--;
    return _history[_historyIdx];
  }

  // ── CPU state helpers for UI panels ──────────────────────────────────────
  Map<String, int> get registers => cpu.snapshot();

  Map<String, bool> get flags => {
    'CF': cpu.cf, 'PF': cpu.pf, 'AF': cpu.af, 'ZF': cpu.zf,
    'SF': cpu.sf, 'TF': cpu.tf, 'IF': cpu.ifl, 'DF': cpu.df, 'OF': cpu.of_,
  };

  List<int> memoryPage(int start, int count) {
    return List.generate(count, (i) => cpu.readByte((start + i) & 0xFFFF));
  }

  void reset() {
    cpu.reset();
    lines.clear();
    inputMode = InputMode.normal;
    _pendingReg = '';
    _quit = false;
    _addOutput('DEBUG.EXE emulator reset.');
    _addOutput('-');
    notifyListeners();
  }
}
