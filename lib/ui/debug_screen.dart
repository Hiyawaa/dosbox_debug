// lib/ui/debug_screen.dart
// DEBUG.EXE UI — works on Android, iOS, Web, and Desktop.
// Portrait: terminal stacked above input. Landscape: terminal + side panel.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/debug_state.dart';
import '../core/disassembler.dart';

const _green  = Color(0xFF33FF33);
const _amber  = Color(0xFFFFAA00);
const _dim    = Color(0xFF1A8B1A);
const _bg     = Color(0xFF0A0F0A);
const _panel  = Color(0xFF0D140D);
const _border = Color(0xFF1F3F1F);

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});
  @override State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();
  bool _showPanel   = false; // toggle side panel on mobile

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _submit(DebugState state) {
    final text = _inputCtrl.text;
    _inputCtrl.clear();
    state.submitLine(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollBottom());
  }

  void _scrollBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DebugState>(builder: (context, state, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollBottom());
      final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
      final isWide = MediaQuery.of(context).size.width > 700;

      return Scaffold(
        backgroundColor: _bg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(children: [
            _buildTitleBar(state, isWide),
            Expanded(
              child: isWide || (isLandscape && _showPanel)
                  ? Row(children: [
                      Expanded(flex: 3, child: _buildTerminal(state)),
                      SizedBox(width: 220, child: _buildSidePanel(state)),
                    ])
                  : _buildTerminal(state),
            ),
            _buildInputBar(state),
          ]),
        ),
      );
    });
  }

  // ── Title bar ──────────────────────────────────────────────────────────────
  Widget _buildTitleBar(DebugState state, bool isWide) {
    return Container(
      color: _panel,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(children: [
        const Icon(Icons.terminal, color: _green, size: 15),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'DEBUG.EXE  8086 Emulator',
            style: TextStyle(color: _green, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          'IP:${state.cpu.ip.toRadixString(16).toUpperCase().padLeft(4,'0')}',
          style: const TextStyle(color: _amber, fontFamily: 'monospace', fontSize: 11),
        ),
        const SizedBox(width: 8),
        if (!isWide) ...[
          _iconBtn(Icons.memory, 'Panel', () => setState(() => _showPanel = !_showPanel)),
          const SizedBox(width: 4),
        ],
        _iconBtn(Icons.refresh, 'Reset', () => state.reset()),
        _iconBtn(Icons.help_outline, 'Help', () => state.submitLine('?')),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: _dim, size: 18),
        ),
      ),
    );
  }

  // ── Terminal output ────────────────────────────────────────────────────────
  Widget _buildTerminal(DebugState state) {
    return GestureDetector(
      onTap: () => _inputFocus.requestFocus(),
      child: Container(
        color: _bg,
        child: ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          itemCount: state.lines.length,
          itemBuilder: (context, i) {
            final line = state.lines[i];
            Color color;
            if (line.isInput)      color = const Color(0xFF88FF88);
            else if (line.isError) color = const Color(0xFFFF5555);
            else if (line.isHighlight) color = _amber;
            else                   color = _green;

            return SelectableText(
              line.text.isEmpty ? ' ' : line.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
                color: color,
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────────
  Widget _buildInputBar(DebugState state) {
    final promptChar = state.inputMode == InputMode.regValue ? ':' : '-';

    // Quick-access command buttons for mobile
    final quickCmds = ['R', 'U', 'D', 'T', 'G', '?'];

    return Container(
      color: _panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick command row (handy on mobile)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: quickCmds.map((cmd) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () {
                    state.submitLine(cmd);
                    _inputFocus.requestFocus();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(3),
                      color: const Color(0xFF0F1F0F),
                    ),
                    child: Text(cmd, style: const TextStyle(color: _amber, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              )).toList(),
            ),
          ),
          // Input field
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: _border))),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Text(
                '$promptChar ',
                style: const TextStyle(color: _green, fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  focusNode: _inputFocus,
                  autofocus: true,
                  style: const TextStyle(color: _green, fontFamily: 'monospace', fontSize: 13),
                  cursorColor: _green,
                  cursorWidth: 8,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Enter command...',
                    hintStyle: TextStyle(color: Color(0xFF1A4A1A), fontFamily: 'monospace', fontSize: 13),
                  ),
                  onSubmitted: (_) {
                    _submit(state);
                    _inputFocus.requestFocus();
                  },
                  textInputAction: TextInputAction.send,
                  keyboardType: TextInputType.visiblePassword, // disables autocorrect on mobile
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
              InkWell(
                onTap: () {
                  _submit(state);
                  _inputFocus.requestFocus();
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2F0F),
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('↵', style: TextStyle(color: _green, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Side panel ────────────────────────────────────────────────────────────
  Widget _buildSidePanel(DebugState state) {
    return Container(
      color: _panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('REGISTERS'),
          _buildRegisterGrid(state),
          const Divider(color: _border, height: 1),
          _sectionHeader('FLAGS'),
          _buildFlagRow(state),
          const Divider(color: _border, height: 1),
          _sectionHeader('DISASM @ IP'),
          Expanded(child: _buildDisasmPanel(state)),
          const Divider(color: _border, height: 1),
          _sectionHeader('MEMORY @ 0100'),
          SizedBox(height: 90, child: _buildMemPanel(state)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: const Color(0xFF0F1F0F),
      child: Text(title, style: const TextStyle(color: _dim, fontFamily: 'monospace', fontSize: 9, letterSpacing: 1)),
    );
  }

  Widget _buildRegisterGrid(DebugState state) {
    final regs = [
      ['AX', state.cpu.ax], ['BX', state.cpu.bx],
      ['CX', state.cpu.cx], ['DX', state.cpu.dx],
      ['SI', state.cpu.si], ['DI', state.cpu.di],
      ['SP', state.cpu.sp], ['BP', state.cpu.bp],
      ['CS', state.cpu.cs], ['DS', state.cpu.ds],
      ['SS', state.cpu.ss], ['ES', state.cpu.es],
      ['IP', state.cpu.ip], ['', 0],
    ];
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Wrap(
        spacing: 8,
        runSpacing: 3,
        children: regs.map((r) {
          final name = r[0] as String;
          final val  = r[1] as int;
          if (name.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            width: 88,
            child: Row(children: [
              Text('$name=', style: const TextStyle(color: _dim, fontFamily: 'monospace', fontSize: 11)),
              Text(
                val.toRadixString(16).toUpperCase().padLeft(4, '0'),
                style: const TextStyle(color: _amber, fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFlagRow(DebugState state) {
    final flags = [
      ['CF', state.cpu.cf], ['ZF', state.cpu.zf],
      ['SF', state.cpu.sf], ['OF', state.cpu.of_],
      ['PF', state.cpu.pf], ['AF', state.cpu.af],
      ['DF', state.cpu.df], ['IF', state.cpu.ifl],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Wrap(
        spacing: 4, runSpacing: 3,
        children: flags.map((f) {
          final set = f[1] as bool;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: set ? _green.withAlpha(25) : Colors.transparent,
              border: Border.all(color: set ? _green : _border),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(f[0] as String,
              style: TextStyle(color: set ? _green : _dim, fontFamily: 'monospace', fontSize: 9, fontWeight: set ? FontWeight.bold : FontWeight.normal),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDisasmPanel(DebugState state) {
    final dis = Disassembler(state.cpu);
    final results = dis.disasmN(state.cpu.ip, 10);
    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: results.length,
      itemBuilder: (ctx, i) {
        final r = results[i];
        final isCurrent = i == 0;
        return Container(
          color: isCurrent ? _green.withAlpha(15) : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
          child: Row(children: [
            Text(
              isCurrent ? '▶' : ' ',
              style: const TextStyle(color: _green, fontFamily: 'monospace', fontSize: 10),
            ),
            const SizedBox(width: 3),
            Text(r.addrHex,
              style: TextStyle(color: isCurrent ? _amber : _dim, fontFamily: 'monospace', fontSize: 10),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(r.mnemonic,
                style: TextStyle(color: isCurrent ? _green : const Color(0xFF22AA22), fontFamily: 'monospace', fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildMemPanel(DebugState state) {
    const startAddr = 0x0100;
    final bytes = state.memoryPage(startAddr, 48);
    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: 3,
      itemBuilder: (ctx, row) {
        final offset = row * 16;
        final addr = startAddr + offset;
        final rowBytes = bytes.skip(offset).take(16).toList();
        final hex = rowBytes.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
        return Text(
          '${addr.toRadixString(16).toUpperCase().padLeft(4,'0')}: $hex',
          style: const TextStyle(color: _dim, fontFamily: 'monospace', fontSize: 9),
        );
      },
    );
  }
}
