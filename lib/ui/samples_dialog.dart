// lib/ui/samples_dialog.dart
import 'package:flutter/material.dart';
import '../core/sample_programs.dart';

class SamplesDialog extends StatelessWidget {
  final Function(SampleProgram) onSelect;
  const SamplesDialog({super.key, required this.onSelect});

  static Future<void> show(BuildContext context, Function(SampleProgram) onSelect) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SamplesDialog(onSelect: onSelect),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF30363D),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Icon(Icons.folder_open, color: Color(0xFF58A6FF), size: 18),
              SizedBox(width: 8),
              Text(
                'EXAMPLE PROGRAMS',
                style: TextStyle(
                  color: Color(0xFF58A6FF),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF21262D), height: 1),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: samplePrograms.length,
            separatorBuilder: (_, __) => const Divider(color: Color(0xFF21262D), height: 1),
            itemBuilder: (ctx, i) {
              final s = samplePrograms[i];
              return ListTile(
                onTap: () {
                  Navigator.pop(ctx);
                  onSelect(s);
                },
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F6FEB).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF1F6FEB).withOpacity(0.3)),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Color(0xFF58A6FF),
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  s.name,
                  style: const TextStyle(
                    color: Color(0xFFE6EDF3),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  s.description,
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF6E7681), size: 18),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
