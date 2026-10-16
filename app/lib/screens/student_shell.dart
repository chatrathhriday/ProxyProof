import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'history_screen.dart';
import 'student_home.dart';

/// Student app frame: "Today" (mark attendance) and "Classes" (all courses + percentages).
/// IndexedStack keeps both tabs alive, so scanning continues while browsing classes;
/// each tab fades/rises in when selected.
class StudentShell extends StatefulWidget {
  const StudentShell({super.key});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _tab = 0;

  void _go(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = i);
  }

  Widget _animated(int i, Widget child) {
    final on = _tab == i;
    return AnimatedOpacity(
      opacity: on ? 1 : 0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: on ? Offset.zero : const Offset(0, 0.03),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          _animated(0, StudentHome(onOpenClasses: () => _go(1))),
          _animated(1, ClassesTab(visible: _tab == 1)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sensors_outlined), selectedIcon: Icon(Icons.sensors), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'Classes'),
        ],
      ),
    );
  }
}
