import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import 'broadcast_screen.dart';

/// Lists the organiser's courses; one tap starts a session and opens the broadcast screen.
class OrganiserHome extends StatefulWidget {
  const OrganiserHome({super.key});

  @override
  State<OrganiserHome> createState() => _OrganiserHomeState();
}

class _OrganiserHomeState extends State<OrganiserHome> {
  late Future<(List, List)> _data = _load();

  Future<(List, List)> _load() async {
    final courses = await Api.instance.get('/courses') as List;
    final sessions = await Api.instance.get('/sessions') as List;
    return (courses, sessions.where((s) => s['status'] == 'active').toList());
  }

  Future<void> _open(int sessionId, String title) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BroadcastScreen(sessionId: sessionId, title: title),
      ),
    );
    setState(() => _data = _load());
  }

  Future<void> _start(Map course) async {
    try {
      final s = await Api.instance.post('/sessions', {'courseId': course['id']});
      await _open(s['id'] as int, course['code'] as String);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${Api.instance.user?['name'] ?? ''}'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => logout(context))],
      ),
      body: FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (courses, active) = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _data = _load()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (active.isNotEmpty) ...[
                  Text('Live now', style: Theme.of(context).textTheme.titleMedium),
                  for (final s in active)
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.sensors),
                        title: Text('${s['course_code']} · ${s['present']} present'),
                        subtitle: const Text('Tap to resume broadcasting'),
                        onTap: () => _open(s['id'] as int, s['course_code'] as String),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                Text('Your courses', style: Theme.of(context).textTheme.titleMedium),
                if (courses.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No courses yet.')),
                for (final c in courses)
                  Card(
                    child: ListTile(
                      title: Text('${c['code']}'),
                      subtitle: Text('${c['name']}'),
                      trailing: FilledButton(onPressed: () => _start(c as Map), child: const Text('Start')),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
