// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/app_state.dart';
import 'ui/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D1117),
  ));
  runApp(const App8086());
}

class App8086 extends StatelessWidget {
  const App8086({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: '8086 ASM IDE',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF58A6FF),
            secondary: Color(0xFF3FB950),
            surface: Color(0xFF161B22),
            error: Color(0xFFFF7B72),
          ),
          scaffoldBackgroundColor: const Color(0xFF0D1117),
          fontFamily: 'monospace',
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF161B22),
            foregroundColor: Color(0xFFE6EDF3),
            elevation: 0,
          ),
          dividerColor: const Color(0xFF21262D),
          useMaterial3: true,
        ),
        home: const MainScreen(),
      ),
    );
  }
}
