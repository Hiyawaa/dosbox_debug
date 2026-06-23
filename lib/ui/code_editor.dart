// lib/ui/code_editor.dart
import 'package:flutter/material.dart';

class CodeEditor extends StatefulWidget {
  final String initialCode;
  final int? highlightedLine;
  final Function(String) onChanged;

  const CodeEditor({
    super.key,
    required this.initialCode,
    required this.onChanged,
    this.highlightedLine,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late TextEditingController _controller;
  late ScrollController _scrollController;
  late ScrollController _lineScrollController;
  final FocusNode _focusNode = FocusNode();

  static const _keywords = [
    'MOV','ADD','SUB','MUL','DIV','INC','DEC',
    'PUSH','POP','CALL','RET','JMP','JE','JNE',
    'LOOP','INT','DB','DW','ORG','NOP','HLT',
    'CMP','XCHG','AND','OR','XOR','JZ','JNZ',
  ];
  static const _registers = [
    'AX','BX','CX','DX','SI','DI','SP','BP',
    'AH','AL','BH','BL','CH','CL','DH','DL',
    'CS','DS','SS','ES','IP',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCode);
    _scrollController = ScrollController();
    _lineScrollController = ScrollController();
    _scrollController.addListener(() {
      if (_lineScrollController.hasClients) {
        _lineScrollController.jumpTo(_scrollController.offset);
      }
    });
  }

  @override
  void didUpdateWidget(CodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedLine != oldWidget.highlightedLine && widget.highlightedLine != null) {
      _scrollToLine(widget.highlightedLine!);
    }
  }

  void _scrollToLine(int line) {
    const lineHeight = 18.0;
    final offset = (line - 1) * lineHeight;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _controller.text.split('\n');
    return Container(
      color: const Color(0xFF0D1117),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line numbers
          SizedBox(
            width: 36,
            child: SingleChildScrollView(
              controller: _lineScrollController,
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: List.generate(lines.length, (i) {
                    final lineNo = i + 1;
                    final isHighlighted = lineNo == widget.highlightedLine;
                    return Container(
                      height: 18,
                      width: 36,
                      color: isHighlighted ? const Color(0xFF1F3D6E) : Colors.transparent,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '$lineNo',
                        style: TextStyle(
                          color: isHighlighted
                              ? const Color(0xFF58A6FF)
                              : const Color(0xFF6E7681),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          // Divider
          Container(width: 1, color: const Color(0xFF21262D)),
          // Editor
          Expanded(
            child: Stack(
              children: [
                // Highlight current line background
                if (widget.highlightedLine != null)
                  Positioned(
                    top: 10 + (widget.highlightedLine! - 1) * 18.0,
                    left: 0,
                    right: 0,
                    height: 18,
                    child: Container(color: const Color(0xFF1F3D6E).withOpacity(0.4)),
                  ),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    color: Color(0xFFE6EDF3),
                    fontSize: 13,
                    fontFamily: 'monospace',
                    height: 1.385,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(8, 10, 8, 10),
                    isDense: true,
                  ),
                  cursorColor: const Color(0xFF58A6FF),
                  onChanged: (val) {
                    widget.onChanged(val);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _lineScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
