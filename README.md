# 8086 ASM IDE — Flutter Android App

A complete 8086 assembly IDE for Android, built entirely in Dart/Flutter.
**No DOSBox. No server. 100% offline.**

## Supported Instructions

| Category    | Instructions |
|-------------|-------------|
| Data        | MOV, XCHG |
| Arithmetic  | ADD, SUB, MUL, DIV, INC, DEC, CMP |
| Stack       | PUSH, POP |
| Control     | CALL, RET, JMP, JE/JZ, JNE/JNZ, LOOP |
| Logic       | AND, OR, XOR |
| System      | INT (21h DOS, 10h Video), NOP, HLT |
| Data Def    | DB, DW |
| Directive   | ORG |

## INT 21h Support
| AH | Function |
|----|----------|
| 02h | Print character in DL |
| 09h | Print string at DS:DX (terminated by `$`) |
| 4Ch | Exit program |

## Features
- **Code Editor** — monospaced editor with line numbers and current-line highlight
- **Assemble** — parse + validate your source code
- **Run** — execute entire program to completion
- **Debug** — step-by-step execution
- **Register Panel** — live AX/BX/CX/DX/SI/DI/SP/BP/IP + ZF/SF/CF/OF/PF flags
- **Memory Viewer** — hex dump of any 64KB address range
- **Console** — output from INT 21h / INT 10h calls
- **Reference** — searchable built-in instruction reference
- **7 Example Programs** — showcasing all instructions

## Project Structure
```
lib/
  main.dart                  # App entry point
  models/
    cpu8086.dart             # CPU state: registers, flags, memory, stack
  core/
    assembler.dart           # 2-pass assembler: tokenizer, label resolver
    executor.dart            # Instruction executor (all 19 instructions)
    app_state.dart           # Provider state management
    sample_programs.dart     # Built-in example programs
  ui/
    main_screen.dart         # Main layout: toolbar, tabs, panels
    code_editor.dart         # Source code editor with line numbers
    register_panel.dart      # Register & flag display
    memory_viewer.dart       # Hex memory dump
    console_panel.dart       # Output console
    instruction_ref.dart     # Searchable instruction reference
    samples_dialog.dart      # Example programs picker
android/
  app/src/main/
    AndroidManifest.xml      # Android permissions & activity config
pubspec.yaml                 # Flutter dependencies
```

## Build & Run

### Prerequisites
- Flutter SDK ≥ 3.10.0
- Android SDK (API 21+)
- Android device or emulator

### Steps
```bash
# 1. Get dependencies
flutter pub get

# 2. Run on connected device
flutter run

# 3. Build release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## Architecture

```
User types ASM code
       ↓
  Assembler (2 passes)
  ├─ Pass 1: tokenize, detect labels, calculate addresses
  └─ Pass 2: resolve label references → List<Instruction>
       ↓
  CPU8086 (memory model)
  └─ 64KB byte array + registers + flags + stack
       ↓
  Executor
  ├─ step()  → execute one instruction, update CPU state
  └─ runAll() → loop until HLT or INT 4Ch
       ↓
  AppState (ChangeNotifier)
  └─ notifies UI → register panel, memory, console update live
```

## Adding More Instructions
Edit `lib/core/executor.dart` — add a new `case 'INSTR':` in the `_execute()` switch.
Edit `lib/ui/instruction_ref.dart` — add an `_InstrDoc` entry.
