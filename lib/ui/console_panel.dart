// lib/ui/console_panel.dart
import 'package:flutter/material.dart';

class ConsolePanel extends StatefulWidget {
  final List<String> output;
  final String? error;

  const ConsolePanel({super.key, required this.output, this.error});

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(ConsolePanel old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF161B22),
            child: Row(
              children: [
                const Text(
                  'CONSOLE',
                  style: TextStyle(
                    color: Color(0xFF58A6FF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                if (widget.output.isNotEmpty)
                  GestureDetector(
                    onTap: () {},
                    child: const Text(
                      'CLEAR',
                      style: TextStyle(
                        color: Color(0xFF8B949E),
                        fontSize: 10,
                        letterSpacing: 1,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Output
          Expanded(
            child: widget.output.isEmpty
                ? const Center(
                    child: Text(
                      'Run or debug your program to see output.',
                      style: TextStyle(color: Color(0xFF6E7681), fontSize: 12, fontFamily: 'monospace'),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(10),
                    itemCount: widget.output.length,
                    itemBuilder: (_, i) {
                      final line = widget.output[i];
                      Color color = const Color(0xFFE6EDF3);
                      if (line.startsWith('❌')) color = const Color(0xFFFF7B72);
                      if (line.startsWith('✅')) color = const Color(0xFF3FB950);
                      if (line.startsWith('🐛')) color = const Color(0xFFFFA657);
                      if (line.startsWith('[INT')) color = const Color(0xFF8B949E);
                      return Text(
                        line,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
