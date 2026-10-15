import 'package:flutter/material.dart';

import 'history_screen.dart';
import 'student_home.dart';

/// Student app frame: "Today" (mark attendance) and "Classes" (all courses + percentages).
/// IndexedStack keeps both tabs alive, so scanning continues while browsing classes.
class StudentShell extends StatefulWidget {
  const StudentShell({super.key});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          StudentHome(onOpenClasses: () => setState(() => _tab = 1)),
          ClassesTab(visible: _tab == 1),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sensors_outlined), selectedIcon: Icon(Icons.sensors), label: 'Today'),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Classes',
          ),
        ],
      ),
    );
  }
}
