// lib/ui/register_panel.dart
import 'package:flutter/material.dart';
import '../models/cpu8086.dart';

class RegisterPanel extends StatelessWidget {
  final CPU8086 cpu;
  const RegisterPanel({super.key, required this.cpu});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('REGISTERS'),
          const SizedBox(height: 6),
          _regGrid(),
          const SizedBox(height: 10),
          _sectionLabel('FLAGS'),
          const SizedBox(height: 6),
          _flagsRow(),
          const SizedBox(height: 10),
          _sectionLabel('POINTERS'),
          const SizedBox(height: 6),
          _ptrGrid(),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF58A6FF),
      fontSize: 10,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.5,
      fontFamily: 'monospace',
    ),
  );

  Widget _regGrid() {
    final regs = [
      ('AX', cpu.ax), ('BX', cpu.bx),
      ('CX', cpu.cx), ('DX', cpu.dx),
      ('SI', cpu.si), ('DI', cpu.di),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3.5,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: regs.length,
      itemBuilder: (_, i) => _regTile(regs[i].$1, regs[i].$2),
    );
  }

  Widget _ptrGrid() {
    final ptrs = [
      ('SP', cpu.sp), ('BP', cpu.bp),
      ('IP', cpu.ip), ('CS', cpu.cs),
      ('DS', cpu.ds), ('SS', cpu.ss),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3.5,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: ptrs.length,
      itemBuilder: (_, i) => _regTile(ptrs[i].$1, ptrs[i].$2, color: const Color(0xFF3FB950)),
    );
  }

  Widget _regTile(String name, int value, {Color? color}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            name,
            style: TextStyle(
              color: color ?? const Color(0xFFFF7B72),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _hex4(value),
                style: const TextStyle(
                  color: Color(0xFFE6EDF3),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                value.toString().padLeft(5),
                style: const TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _flagsRow() {
    final flags = [
      ('ZF', cpu.zf),
      ('SF', cpu.sf),
      ('CF', cpu.cf),
      ('OF', cpu.of),
      ('PF', cpu.pf),
    ];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: flags.map((f) => _flagChip(f.$1, f.$2)).toList(),
    );
  }

  Widget _flagChip(String name, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF1F6FEB) : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: active ? const Color(0xFF58A6FF) : const Color(0xFF30363D),
        ),
      ),
      child: Text(
        '$name=${active ? '1' : '0'}',
        style: TextStyle(
          color: active ? Colors.white : const Color(0xFF8B949E),
          fontSize: 10,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _hex4(int v) => '${(v & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0')}h';
}
