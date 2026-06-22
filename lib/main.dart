// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/debug_state.dart';
import 'ui/debug_screen.dart';

void main() {
  runApp(const DebugApp());
}

class DebugApp extends StatelessWidget {
  const DebugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DebugState(),
      child: MaterialApp(
        title: 'DEBUG.EXE',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0A0F0A),
          colorScheme: ColorScheme.dark(
            primary: const Color(0xFF33FF33),
            surface: const Color(0xFF0A0F0A),
          ),
          textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'monospace',
          ),
        ),
        home: const DebugScreen(),
      ),
    );
  }
}
