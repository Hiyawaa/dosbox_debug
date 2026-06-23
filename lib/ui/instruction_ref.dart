// lib/ui/instruction_ref.dart
import 'package:flutter/material.dart';

class InstructionRef extends StatefulWidget {
  const InstructionRef({super.key});

  @override
  State<InstructionRef> createState() => _InstructionRefState();
}

class _InstructionRefState extends State<InstructionRef> {
  String _filter = '';

  static const _instructions = [
    _InstrDoc(
        'MOV',
        'MOV dst, src',
        'Move data from src to dst.\nMOV AX, BX  | MOV AX, 5  | MOV [BX], AX',
        'Data Transfer'),
    _InstrDoc(
        'ADD',
        'ADD dst, src',
        'Add src to dst. Updates ZF,SF,CF,OF.\nADD AX, BX  | ADD CX, 10',
        'Arithmetic'),
    _InstrDoc(
        'SUB',
        'SUB dst, src',
        'Subtract src from dst. Updates flags.\nSUB AX, BX  | SUB DX, 1',
        'Arithmetic'),
    _InstrDoc(
        'MUL',
        'MUL src',
        '8-bit: AL*src→AX\n16-bit: AX*src→DX:AX\nMUL BL  | MUL CX',
        'Arithmetic'),
    _InstrDoc(
        'DIV',
        'DIV src',
        '8-bit: AX/src→AL quot, AH rem\n16-bit: DX:AX/src→AX quot, DX rem\nDIV BL  | DIV CX',
        'Arithmetic'),
    _InstrDoc(
        'INC',
        'INC dst',
        'Increment dst by 1. Updates ZF,SF,OF.\nINC AX  | INC BL',
        'Arithmetic'),
    _InstrDoc(
        'DEC',
        'DEC dst',
        'Decrement dst by 1. Updates ZF,SF,OF.\nDEC CX  | DEC DH',
        'Arithmetic'),
    _InstrDoc('PUSH', 'PUSH src',
        'Push 16-bit word onto stack. SP-=2.\nPUSH AX  | PUSH BX', 'Stack'),
    _InstrDoc(
        'POP',
        'POP dst',
        'Pop 16-bit word from stack into dst. SP+=2.\nPOP AX  | POP DX',
        'Stack'),
    _InstrDoc('CALL', 'CALL label',
        'Push return address, jump to label.\nCALL MYFUNC', 'Control'),
    _InstrDoc('RET', 'RET', 'Pop return address from stack and jump.\nRET',
        'Control'),
    _InstrDoc('JMP', 'JMP label',
        'Unconditional jump to label or address.\nJMP LOOP_START', 'Jump'),
    _InstrDoc('JE', 'JE label',
        'Jump if ZF=1 (equal). Also: JZ.\nCMP AX,BX  then  JE EQUAL', 'Jump'),
    _InstrDoc(
        'JNE',
        'JNE label',
        'Jump if ZF=0 (not equal). Also: JNZ.\nCMP AX,0  then  JNE NOT_ZERO',
        'Jump'),
    _InstrDoc('LOOP', 'LOOP label',
        'DEC CX; jump to label if CX≠0.\nMOV CX,10  →  LOOP TOP', 'Loop'),
    _InstrDoc('INT', 'INT n',
        'Software interrupt.\nINT 21h (DOS)  | INT 10h (Video)', 'System'),
    _InstrDoc('DB', 'label DB val,...',
        'Define byte(s) at current address.\nMSG DB \'Hello\',\'\$\'', 'Data'),
    _InstrDoc('DW', 'label DW val,...',
        'Define word(s) (2 bytes) at current address.\nNUM DW 1234h', 'Data'),
    _InstrDoc(
        'ORG',
        'ORG addr',
        'Set origin (load address) for program.\nORG 100h  (standard .COM)',
        'Directive'),
  ];

  static const _categoryColors = {
    'Arithmetic': Color(0xFFFFA657),
    'Data Transfer': Color(0xFF58A6FF),
    'Stack': Color(0xFF3FB950),
    'Control': Color(0xFFFF7B72),
    'Jump': Color(0xFFD2A8FF),
    'Loop': Color(0xFFD2A8FF),
    'System': Color(0xFFF78166),
    'Data': Color(0xFF79C0FF),
    'Directive': Color(0xFF8B949E),
  };

  @override
  Widget build(BuildContext context) {
    final filtered = _filter.isEmpty
        ? _instructions
        : _instructions
            .where((i) =>
                i.name.contains(_filter.toUpperCase()) ||
                i.category.toUpperCase().contains(_filter.toUpperCase()))
            .toList();

    return Container(
      color: const Color(0xFF0D1117),
      child: Column(
        children: [
          // Search bar
          Container(
            color: const Color(0xFF161B22),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: TextField(
              style: const TextStyle(
                  color: Color(0xFFE6EDF3),
                  fontSize: 13,
                  fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Search instructions...',
                hintStyle:
                    const TextStyle(color: Color(0xFF6E7681), fontSize: 12),
                prefixIcon: const Icon(Icons.search,
                    color: Color(0xFF6E7681), size: 18),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF58A6FF)),
                ),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          // Instruction list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: Color(0xFF21262D), height: 1),
              itemBuilder: (_, i) =>
                  _InstrTile(doc: filtered[i], categoryColors: _categoryColors),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstrTile extends StatefulWidget {
  final _InstrDoc doc;
  final Map<String, Color> categoryColors;
  const _InstrTile({required this.doc, required this.categoryColors});

  @override
  State<_InstrTile> createState() => _InstrTileState();
}

class _InstrTileState extends State<_InstrTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final color =
        widget.categoryColors[widget.doc.category] ?? const Color(0xFF8B949E);
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Text(
                    widget.doc.name,
                    style: TextStyle(
                      color: color,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.doc.syntax,
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF6E7681),
                  size: 18,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        widget.doc.category,
                        style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1),
                      ),
                    ),
                    Text(
                      widget.doc.description,
                      style: const TextStyle(
                        color: Color(0xFFE6EDF3),
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InstrDoc {
  final String name;
  final String syntax;
  final String description;
  final String category;
  const _InstrDoc(this.name, this.syntax, this.description, this.category);
}
