// lib/core/assembler.dart
// TASM-compatible 8086 Assembler: tokenizes, resolves labels, encodes instructions

import '../models/cpu8086.dart';

class AssemblyError {
  final int line;
  final String message;
  AssemblyError(this.line, this.message);
  @override
  String toString() => 'Line $line: $message';
}

class AssembledProgram {
  final List<AssemblyError> errors;
  final Map<String, int> labels; // label -> address
  final Map<int, int> lineToAddress; // source line -> memory address
  final Map<int, int> addressToLine; // memory address -> source line
  final List<Instruction> instructions;
  final int startAddress;

  AssembledProgram({
    required this.errors,
    required this.labels,
    required this.lineToAddress,
    required this.addressToLine,
    required this.instructions,
    required this.startAddress,
  });

  bool get hasErrors => errors.isNotEmpty;
}

class Instruction {
  final int address;
  final int sourceLine;
  final String mnemonic;
  final List<String> operands;
  final String raw;

  Instruction({
    required this.address,
    required this.sourceLine,
    required this.mnemonic,
    required this.operands,
    required this.raw,
  });
}

class Assembler {
  static const int defaultOrg = 0x0100;

  AssembledProgram assemble(String source) {
    final lines = source.split('\n');
    final errors = <AssemblyError>[];
    final labels = <String, int>{};
    final lineToAddress = <int, int>{};
    final addressToLine = <int, int>{};
    final instructions = <Instruction>[];
    final dataDirectives = <_DataDirective>[];

    int org = defaultOrg;
    int address = org;

    // --- PASS 1: collect labels, calculate addresses ---
    final parsedLines = <_ParsedLine>[];

    for (int i = 0; i < lines.length; i++) {
      final lineNo = i + 1;
      String line = lines[i];

      // Remove comments
      final semiIdx = line.indexOf(';');
      if (semiIdx >= 0) line = line.substring(0, semiIdx);
      line = line.trim();
      if (line.isEmpty) continue;

      // ORG directive
      if (line.toUpperCase().startsWith('ORG')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          org = _parseImm(parts[1]) ?? defaultOrg;
          address = org;
        }
        continue;
      }

      // Label detection
      String? label;
      if (line.contains(':')) {
        final colonIdx = line.indexOf(':');
        label = line.substring(0, colonIdx).trim().toUpperCase();
        line = line.substring(colonIdx + 1).trim();
        labels[label] = address;
        if (line.isEmpty) continue;
      }

      // Check for data directives DB/DW
      final upper = line.toUpperCase();
      if (upper.contains(' DB ') || upper.endsWith(' DB') ||
          _startsWithToken(upper, 'DB')) {
        final dd = _parseDataDirective(line, lineNo, address, 1);
        if (dd != null) {
          dataDirectives.add(dd);
          // also store label pointing here if any
          address += dd.size;
          parsedLines.add(_ParsedLine(lineNo, address - dd.size, null, [], line, isData: true));
          continue;
        }
      }
      if (upper.contains(' DW ') || upper.endsWith(' DW') ||
          _startsWithToken(upper, 'DW')) {
        final dd = _parseDataDirective(line, lineNo, address, 2);
        if (dd != null) {
          dataDirectives.add(dd);
          address += dd.size;
          parsedLines.add(_ParsedLine(lineNo, address - dd.size, null, [], line, isData: true));
          continue;
        }
      }

      final tokens = _tokenize(line);
      if (tokens.isEmpty) continue;

      final mnemonic = tokens[0].toUpperCase();
      final operands = tokens.length > 1
          ? tokens.sublist(1).join('').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
          : <String>[];

      lineToAddress[lineNo] = address;
      addressToLine[address] = lineNo;

      parsedLines.add(_ParsedLine(lineNo, address, mnemonic, operands, line));
      address += 1; // simplified: each instruction = 1 "unit" for stepping
    }

    // Write data directives into memory model (returned as instructions)
    for (final dd in dataDirectives) {
      instructions.add(Instruction(
        address: dd.address,
        sourceLine: dd.line,
        mnemonic: dd.wordSize == 1 ? 'DB' : 'DW',
        operands: dd.values.map((v) => v.toString()).toList(),
        raw: dd.raw,
      ));
    }

    // --- PASS 2: resolve labels, build instruction list ---
    for (final pl in parsedLines) {
      if (pl.isData) continue;
      if (pl.mnemonic == null) continue;

      // Resolve label references in operands
      final resolved = pl.operands.map((op) {
        final upper = op.toUpperCase();
        if (labels.containsKey(upper)) {
          return labels[upper].toString();
        }
        return op;
      }).toList();

      instructions.add(Instruction(
        address: pl.address,
        sourceLine: pl.lineNo,
        mnemonic: pl.mnemonic!,
        operands: resolved,
        raw: pl.raw,
      ));
      lineToAddress[pl.lineNo] = pl.address;
      addressToLine[pl.address] = pl.lineNo;
    }

    return AssembledProgram(
      errors: errors,
      labels: labels,
      lineToAddress: lineToAddress,
      addressToLine: addressToLine,
      instructions: instructions,
      startAddress: org,
    );
  }

  List<String> _tokenize(String line) {
    final result = <String>[];
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return result;
    result.add(parts[0]); // mnemonic
    if (parts.length > 1) {
      result.add(parts.sublist(1).join(' '));
    }
    return result;
  }

  _DataDirective? _parseDataDirective(String line, int lineNo, int address, int wordSize) {
    final upper = line.toUpperCase();
    final keyword = wordSize == 1 ? 'DB' : 'DW';
    int kIdx = upper.indexOf(keyword);
    if (kIdx < 0) return null;
    final rest = line.substring(kIdx + 2).trim();
    final parts = rest.split(',').map((s) => s.trim()).toList();
    final values = <int>[];
    for (final p in parts) {
      // String literal support
      if (p.startsWith("'") && p.endsWith("'")) {
        for (final c in p.substring(1, p.length - 1).codeUnits) {
          values.add(c);
        }
      } else {
        values.add(_parseImm(p) ?? 0);
      }
    }
    return _DataDirective(lineNo, address, wordSize, values, line);
  }

  bool _startsWithToken(String s, String token) {
    return s == token || s.startsWith('$token ') || s.startsWith('$token\t');
  }

  static int? _parseImm(String s) {
    s = s.trim().toUpperCase();
    if (s.endsWith('H')) {
      return int.tryParse(s.substring(0, s.length - 1), radix: 16);
    }
    if (s.startsWith('0X')) {
      return int.tryParse(s.substring(2), radix: 16);
    }
    return int.tryParse(s);
  }
}

class _ParsedLine {
  final int lineNo;
  final int address;
  final String? mnemonic;
  final List<String> operands;
  final String raw;
  final bool isData;

  _ParsedLine(this.lineNo, this.address, this.mnemonic, this.operands, this.raw,
      {this.isData = false});
}

class _DataDirective {
  final int line;
  final int address;
  final int wordSize;
  final List<int> values;
  final String raw;

  _DataDirective(this.line, this.address, this.wordSize, this.values, this.raw);

  int get size => values.length * wordSize;
}
