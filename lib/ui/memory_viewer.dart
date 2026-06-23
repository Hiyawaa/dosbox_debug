// lib/ui/memory_viewer.dart
import 'package:flutter/material.dart';
import '../models/cpu8086.dart';

class MemoryViewer extends StatefulWidget {
  final CPU8086 cpu;
  const MemoryViewer({super.key, required this.cpu});

  @override
  State<MemoryViewer> createState() => _MemoryViewerState();
}

class _MemoryViewerState extends State<MemoryViewer> {
  final _controller = TextEditingController(text: '0100');
  int _startAddr = 0x0100;
  static const int _bytesPerRow = 8;
  static const int _rows = 16;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'MEMORY',
                style: TextStyle(
                  color: Color(0xFF58A6FF),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 80,
                height: 28,
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 11, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    hintText: '0100h',
                    hintStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
                    filled: true,
                    fillColor: const Color(0xFF161B22),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                  ),
                  onSubmitted: (v) {
                    final addr = int.tryParse(v.replaceAll('H', '').replaceAll('h', ''), radix: 16) ??
                        int.tryParse(v) ?? 0x0100;
                    setState(() => _startAddr = addr.clamp(0, 65535));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: List.generate(_rows, (row) {
                  final rowAddr = (_startAddr + row * _bytesPerRow) & 0xFFFF;
                  return _buildRow(rowAddr);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(int addr) {
    final bytes = List.generate(_bytesPerRow, (i) => widget.cpu.memory[(addr + i) & 0xFFFF]);
    final isIpRow = addr <= widget.cpu.ip && widget.cpu.ip < addr + _bytesPerRow;

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isIpRow ? const Color(0xFF1F2937) : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          // Address
          Text(
            '${addr.toRadixString(16).toUpperCase().padLeft(4, '0')}:',
            style: TextStyle(
              color: isIpRow ? const Color(0xFF58A6FF) : const Color(0xFF6E7681),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),
          // Hex bytes
          ...bytes.asMap().entries.map((e) {
            final byteAddr = addr + e.key;
            final isIp = byteAddr == widget.cpu.ip;
            return Container(
              width: 22,
              alignment: Alignment.center,
              child: Text(
                e.value.toRadixString(16).toUpperCase().padLeft(2, '0'),
                style: TextStyle(
                  color: isIp
                      ? const Color(0xFFFFA657)
                      : e.value == 0
                          ? const Color(0xFF30363D)
                          : const Color(0xFFE6EDF3),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: isIp ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }),
          const SizedBox(width: 6),
          // ASCII
          Text(
            bytes.map((b) => (b >= 0x20 && b < 0x7F) ? String.fromCharCode(b) : '.').join(),
            style: const TextStyle(
              color: Color(0xFF3FB950),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
