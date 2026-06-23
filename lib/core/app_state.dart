// lib/core/app_state.dart
import 'package:flutter/foundation.dart';
import '../models/cpu8086.dart';
import 'assembler.dart';
import 'executor.dart';

enum AppMode { editor, running, debugging, halted }

class AppState extends ChangeNotifier {
  final CPU8086 cpu = CPU8086();
  late final Assembler _assembler;
  late Executor _executor;

  AppMode mode = AppMode.editor;
  AssembledProgram? program;
  String sourceCode = _defaultSource;
  List<String> consoleOutput = [];
  List<AssemblyError> assembleErrors = [];
  int? currentLine;
  String? runtimeError;
  bool get isRunning => mode == AppMode.running || mode == AppMode.debugging;

  AppState() {
    _assembler = Assembler();
    _executor = Executor(cpu);
  }

  void updateSource(String code) {
    sourceCode = code;
    notifyListeners();
  }

  bool assemble() {
    program = _assembler.assemble(sourceCode);
    assembleErrors = program!.errors;
    if (program!.hasErrors) {
      consoleOutput = program!.errors.map((e) => '❌ $e').toList();
      mode = AppMode.editor;
      notifyListeners();
      return false;
    }
    _executor = Executor(cpu);
    _executor.loadProgram(program!);
    consoleOutput = ['✅ Assembly successful. ${program!.instructions.where((i) => i.mnemonic != "DB" && i.mnemonic != "DW").length} instructions loaded.'];
    runtimeError = null;
    currentLine = null;
    notifyListeners();
    return true;
  }

  void runAll() {
    if (program == null) {
      if (!assemble()) return;
    }
    if (program!.hasErrors) return;
    _executor = Executor(cpu);
    _executor.loadProgram(program!);
    mode = AppMode.running;
    notifyListeners();

    final result = _executor.runAll();
    _handleResult(result);
  }

  void startDebug() {
    if (!assemble()) return;
    _executor = Executor(cpu);
    _executor.loadProgram(program!);
    mode = AppMode.debugging;
    currentLine = _currentSourceLine();
    consoleOutput = ['🐛 Debug mode. Step through with ▶️'];
    notifyListeners();
  }

  void stepDebug() {
    if (mode != AppMode.debugging) return;
    final result = _executor.step();
    _handleResult(result);
    currentLine = _currentSourceLine();
    notifyListeners();
  }

  void _handleResult(ExecutionResult result) {
    // Accumulate output
    final allOutput = result.output;
    if (allOutput.isNotEmpty) {
      consoleOutput = [...consoleOutput, ...allOutput.where((l) => !consoleOutput.contains(l))];
    }
    if (result.error != null) {
      runtimeError = result.error;
      consoleOutput = [...consoleOutput, '❌ ${result.error}'];
      mode = AppMode.halted;
    } else if (result.halted) {
      if (mode != AppMode.debugging) {
        consoleOutput = [...consoleOutput, '✅ Program halted.'];
      }
      mode = AppMode.halted;
    }
    notifyListeners();
  }

  void reset() {
    cpu.reset();
    mode = AppMode.editor;
    consoleOutput = [];
    assembleErrors = [];
    currentLine = null;
    runtimeError = null;
    program = null;
    notifyListeners();
  }

  int? _currentSourceLine() {
    if (program == null) return null;
    return program!.addressToLine[cpu.ip];
  }

  List<int> memoryPage(int pageStart, int count) {
    final end = (pageStart + count).clamp(0, 65535);
    return cpu.memory.sublist(pageStart.clamp(0, 65535), end);
  }
}

const _defaultSource = '''; 8086 Assembly Example
; Demonstrates: MOV, ADD, LOOP, INT

ORG 100h

START:
    MOV AX, 0        ; AX = 0
    MOV CX, 5        ; Loop 5 times
    MOV BX, 10       ; BX = 10

SUM_LOOP:
    ADD AX, BX       ; AX = AX + BX
    LOOP SUM_LOOP    ; CX--, if CX!=0 jump

    ; AX should be 50 (10*5)
    MOV AH, 4Ch      ; DOS exit
    INT 21h
''';
