// lib/ui/main_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import 'code_editor.dart';
import 'register_panel.dart';
import 'memory_viewer.dart';
import 'console_panel.dart';
import 'instruction_ref.dart';
import 'samples_dialog.dart';
import '../core/sample_programs.dart';
import '../debug_exe/debug_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _bottomTab = 0; // 0=console, 1=registers, 2=memory

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0D1117),
          appBar: _buildAppBar(state),
          body: Column(
            children: [
              // Top: Editor / Reference tabs
              Expanded(
                flex: 6,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Editor
                    CodeEditor(
                      initialCode: state.sourceCode,
                      highlightedLine: state.currentLine,
                      onChanged: state.updateSource,
                    ),
                    // Instruction Reference
                    const InstructionRef(),
                  ],
                ),
              ),
              // Divider with bottom panel tabs
              Container(
                color: const Color(0xFF161B22),
                child: Row(
                  children: [
                    _bottomTabBtn(0, Icons.terminal, 'Console'),
                    _bottomTabBtn(1, Icons.memory, 'Registers'),
                    _bottomTabBtn(2, Icons.grid_view, 'Memory'),
                  ],
                ),
              ),
              // Bottom: Console / Registers / Memory
              Expanded(
                flex: 4,
                child: IndexedStack(
                  index: _bottomTab,
                  children: [
                    ConsolePanel(
                        output: state.consoleOutput, error: state.runtimeError),
                    SingleChildScrollView(
                      child: RegisterPanel(cpu: state.cpu),
                    ),
                    MemoryViewer(cpu: state.cpu),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(AppState state) {
    return AppBar(
      backgroundColor: const Color(0xFF161B22),
      elevation: 0,
      titleSpacing: 10,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1F6FEB).withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border:
                  Border.all(color: const Color(0xFF1F6FEB).withOpacity(0.5)),
            ),
            child: const Text(
              '8086',
              style: TextStyle(
                color: Color(0xFF58A6FF),
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'ASM IDE',
            style: TextStyle(
              color: Color(0xFFE6EDF3),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Tab switcher
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: const Color(0xFF58A6FF),
            indicatorWeight: 2,
            labelColor: const Color(0xFF58A6FF),
            unselectedLabelColor: const Color(0xFF8B949E),
            labelStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'EDITOR'),
              Tab(text: 'REFERENCE'),
            ],
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: _buildToolbar(state),
      ),
    );
  }

  Widget _buildToolbar(AppState state) {
    final isDebugging = state.mode == AppMode.debugging;
    final canStep = isDebugging && !state.cpu.halted;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      color: const Color(0xFF161B22),
      child: Row(
        children: [
          // Assemble
          _toolBtn(
            icon: Icons.build_rounded,
            label: 'Assemble',
            color: const Color(0xFF58A6FF),
            onTap: () => state.assemble(),
          ),
          const SizedBox(width: 6),
          // Run
          _toolBtn(
            icon: Icons.play_arrow_rounded,
            label: 'Run',
            color: const Color(0xFF3FB950),
            onTap: state.mode == AppMode.running ? null : () => state.runAll(),
          ),
          const SizedBox(width: 6),
          // Debug
          _toolBtn(
            icon: Icons.bug_report_rounded,
            label: 'Debug',
            color: const Color(0xFFFFA657),
            onTap: isDebugging
                ? null
                : () {
                    state.startDebug();
                    setState(() => _bottomTab = 1); // show registers
                  },
          ),
          const SizedBox(width: 6),
          // Step
          _toolBtn(
            icon: Icons.skip_next_rounded,
            label: 'Step',
            color: canStep ? const Color(0xFFD2A8FF) : const Color(0xFF30363D),
            onTap: canStep ? () => state.stepDebug() : null,
          ),
          const Spacer(),
          // Mode badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _modeColor(state.mode).withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border:
                  Border.all(color: _modeColor(state.mode).withOpacity(0.4)),
            ),
            child: Text(
              state.mode.name.toUpperCase(),
              style: TextStyle(
                color: _modeColor(state.mode),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Samples
          GestureDetector(
            onTap: () => SamplesDialog.show(context, (SampleProgram p) {
              state.reset();
              state.updateSource(p.code);
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: const Icon(Icons.folder_open,
                  color: Color(0xFF8B949E), size: 16),
            ),
          ),
          const SizedBox(width: 6),
          // DEBUG.EXE
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebugExeScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(5),
                border:
                    Border.all(color: const Color(0xFF3FB950).withOpacity(0.4)),
              ),
              child: const Icon(Icons.terminal,
                  color: Color(0xFF3FB950), size: 16),
            ),
          ),
          const SizedBox(width: 6),
          // Reset
          GestureDetector(
            onTap: () => state.reset(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child:
                  const Icon(Icons.refresh, color: Color(0xFF8B949E), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Color _modeColor(AppMode mode) {
    switch (mode) {
      case AppMode.editor:
        return const Color(0xFF8B949E);
      case AppMode.running:
        return const Color(0xFF3FB950);
      case AppMode.debugging:
        return const Color(0xFFFFA657);
      case AppMode.halted:
        return const Color(0xFFFF7B72);
    }
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:
              onTap != null ? color.withOpacity(0.12) : const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: onTap != null
                ? color.withOpacity(0.4)
                : const Color(0xFF21262D),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: onTap != null ? color : const Color(0xFF30363D),
                size: 15),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: onTap != null ? color : const Color(0xFF30363D),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomTabBtn(int idx, IconData icon, String label) {
    final active = _bottomTab == idx;
    return GestureDetector(
      onTap: () => setState(() => _bottomTab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? const Color(0xFF58A6FF) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color:
                    active ? const Color(0xFF58A6FF) : const Color(0xFF6E7681)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color:
                    active ? const Color(0xFF58A6FF) : const Color(0xFF6E7681),
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
