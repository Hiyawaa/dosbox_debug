// lib/debug_exe/debug_screen.dart
//
// A terminal-style screen that recreates the MS-DOS DEBUG.EXE "-" prompt:
// type a command, see DEBUG-style output appended below, scroll history.
// Handles the one genuinely stateful quirk of real DEBUG.EXE: the A
// (assemble) command switches into a line-by-line assembly loop where each
// subsequent line is an instruction (not a new command) until you hit Enter
// on an empty line.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dbg_commands.dart';

class DebugExeScreen extends StatefulWidget {
  const DebugExeScreen({super.key});

  @override
  State<DebugExeScreen> createState() => _DebugExeScreenState();
}

class _DebugExeScreenState extends State<DebugExeScreen> {
  final DbgSession _session = DbgSession();
  final List<String> _history = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Interactive "A" (assemble) mode state.
  bool _inAssembleMode = false;
  int _assembleAddr = 0;

  @override
  void initState() {
    super.initState();
    _history.add('-');
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _hex4(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');

  void _submit() {
    final text = _input.text;
    _input.clear();

    setState(() {
      if (_inAssembleMode) {
        // Echo what was typed at the assemble sub-prompt.
        final promptLine =
            '${_hex4(_assembleAddr >> 4)}:${_hex4(_assembleAddr & 0xFFFF)} $text';
        if (text.trim().isEmpty) {
          _history.add(
              '${_hex4(_assembleAddr >> 4)}:${_hex4(_assembleAddr & 0xFFFF)}');
          _inAssembleMode = false;
        } else {
          final result = _session.assembleAt(_assembleAddr, text.trim());
          if (result.error != null) {
            _history.add(promptLine);
            _history.add(result.error!);
            // stay in assemble mode at same address, like real DEBUG re-prompting
          } else {
            _history.add(promptLine);
            _assembleAddr = result.next!;
          }
        }
      } else {
        _history.add('-$text');
        if (text.trim().isEmpty) {
          // blank line at the main prompt: no-op
        } else {
          final cmd = text.trim();
          final result = _session.run(cmd);
          _history.addAll(result.lines);
          if (result.quit) {
            _history.add('');
            _history.add(
                '(DEBUG session ended. Restart the screen to begin a new session.)');
          }
          if (cmd.toUpperCase().startsWith('A') &&
              (cmd.length == 1 ||
                  cmd[1] == ' ' ||
                  RegExp(r'^A[0-9A-Fa-f:]').hasMatch(cmd))) {
            // Entered assemble mode; figure out starting address from output.
            final addrLine = result.lines.isNotEmpty ? result.lines.first : '';
            final m = RegExp(r'([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})')
                .firstMatch(addrLine);
            if (m != null) {
              _assembleAddr = (int.parse(m.group(1)!, radix: 16) << 4) +
                  int.parse(m.group(2)!, radix: 16);
              _inAssembleMode = true;
            }
          }
        }
      }
    });
    _scrollToBottom();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        titleSpacing: 10,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF3FB950).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border:
                    Border.all(color: const Color(0xFF3FB950).withOpacity(0.5)),
              ),
              child: const Text(
                'DEBUG',
                style: TextStyle(
                  color: Color(0xFF3FB950),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '.EXE',
              style: TextStyle(
                color: Color(0xFFE6EDF3),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Command reference',
            icon: const Icon(Icons.help_outline, color: Color(0xFF8B949E)),
            onPressed: () => setState(() {
              _history.addAll(_session.run('?').lines);
              _history.add('-');
              _scrollToBottom();
            }),
          ),
          IconButton(
            tooltip: 'Reset session',
            icon: const Icon(Icons.refresh, color: Color(0xFF8B949E)),
            onPressed: () {
              setState(() {
                _session.cpu.reset();
                _session.cpu.cs = _session.cpu.ds =
                    _session.cpu.es = _session.cpu.ss = 0x0800;
                _session.cpu.ip = 0x0100;
                _session.cpu.sp = 0xFFFE;
                _history.clear();
                _history.add('-');
                _inAssembleMode = false;
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: Container(
            color: const Color(0xFF0D1117),
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: _history.length,
                    itemBuilder: (context, i) {
                      final line = _history[i];
                      return Text(
                        line,
                        style: const TextStyle(
                          color: Color(0xFFE6EDF3),
                          fontSize: 13,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _inAssembleMode
                          ? '${_hex4(_assembleAddr >> 4)}:${_hex4(_assembleAddr & 0xFFFF)} '
                          : '-',
                      style: const TextStyle(
                        color: Color(0xFF3FB950),
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focusNode,
                        autofocus: true,
                        style: const TextStyle(
                          color: Color(0xFFE6EDF3),
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        cursorColor: const Color(0xFF3FB950),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                        textInputAction: TextInputAction.go,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(
                              254), // DEBUG.EXE's MAXCMDLEN
                        ],
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_return,
                          color: Color(0xFF58A6FF), size: 18),
                      onPressed: _submit,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
