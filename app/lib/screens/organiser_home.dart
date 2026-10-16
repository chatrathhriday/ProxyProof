import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/owl.dart';
import '../widgets/ui.dart';
import 'broadcast_screen.dart';
import 'course_stats_screen.dart';

/// Lists the organiser's courses; one tap starts a session and opens the broadcast screen.
class OrganiserHome extends StatefulWidget {
  const OrganiserHome({super.key});

  @override
  State<OrganiserHome> createState() => _OrganiserHomeState();
}

class _OrganiserHomeState extends State<OrganiserHome> {
  late Future<(List, List)> _data = _load();
  // "Advanced" session settings; the defaults suit a normal classroom.
  int _presencePct = 80;
  int _rssiThreshold = -75;
  int _expectedMinutes = 50;

  Future<void> _advanced() => showModalBottomSheet(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        void update(VoidCallback f) {
          set(f);
          setState(() {});
        }

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Advanced session settings', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('Present if in range for ≥ $_presencePct% of the class'),
              Slider(
                value: _presencePct.toDouble(),
                min: 50,
                max: 100,
                divisions: 10,
                onChanged: (v) => update(() => _presencePct = v.round()),
              ),
              Text('Signal threshold: $_rssiThreshold dBm (higher = stricter radius)'),
              Slider(
                value: _rssiThreshold.toDouble(),
                min: -90,
                max: -55,
                divisions: 7,
                onChanged: (v) => update(() => _rssiThreshold = v.round()),
              ),
              Text('Class length: $_expectedMinutes min (times the random spot check)'),
              Slider(
                value: _expectedMinutes.toDouble(),
                min: 10,
                max: 120,
                divisions: 11,
                onChanged: (v) => update(() => _expectedMinutes = v.round()),
              ),
            ],
          ),
        );
      },
    ),
  );

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
      final s = await Api.instance.post('/sessions', {
        'courseId': course['id'],
        'presencePct': _presencePct,
        'rssiThreshold': _rssiThreshold,
        'expectedMinutes': _expectedMinutes,
      });
      await _open(s['id'] as int, course['code'] as String);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = '${Api.instance.user?['name'] ?? ''}';
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder(
          future: _data,
          builder: (context, snap) {
            final ready = snap.hasData;
            final (courses, active) = snap.data ?? (const [], const []);
            return RefreshIndicator(
              onRefresh: () async => setState(() => _data = _load()),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Faculty',
                              style: t.bodyMedium?.copyWith(color: Brand.gold, fontWeight: FontWeight.w700),
                            ),
                            Text(name, style: Brand.display(context, size: 28)),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.tune_rounded),
                        tooltip: 'Advanced',
                        onPressed: _advanced,
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.logout_rounded),
                        tooltip: 'Log out',
                        onPressed: () => logout(context),
                      ),
                    ],
                  ).animate().fadeIn(),
                  const SizedBox(height: 16),
                  HeroPanel(
                    child: Row(
                      children: [
                        const Owl(mood: OwlMood.idle, size: 92),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                active.isEmpty ? 'Ready when you are' : '${active.length} class live',
                                style: Brand.display(context, size: 22, color: Colors.white),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap Start on a course. Your phone becomes the class beacon — students mark themselves.',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06),
                  if (snap.hasError) Padding(padding: const EdgeInsets.all(12), child: Text('${snap.error}')),
                  if (!ready && !snap.hasError) ...[const SizedBox(height: 18), const Skeleton(height: 84, count: 3)],
                  if (active.isNotEmpty) ...[
                    const SectionTitle('Live now'),
                    ...[
                      for (final s in active)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _open(s['id'] as int, s['course_code'] as String),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    const Radar(size: 52, child: Icon(Icons.sensors, color: Brand.gold)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${s['course_code']}',
                                            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                          ),
                                          Text(
                                            '${s['present']} marked · tap to resume broadcasting',
                                            style: t.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Pill('LIVE', color: Brand.absent, pulse: true),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ].staggered(),
                  ],
                  if (ready) ...[
                    SectionTitle(
                      'Your courses',
                      trailing: Text('${courses.length}', style: const TextStyle(color: Brand.gold)),
                    ),
                    if (courses.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No courses yet. Create one on the web dashboard and add your students.'),
                        ),
                      ),
                    ...[
                      for (final c in courses)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      gradient: Brand.heroGradient,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      '${c['code']}'.replaceAll(RegExp(r'[^A-Za-z]'), '').padRight(2).substring(0, 2),
                                      style: const TextStyle(color: Brand.goldSoft, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${c['code']}',
                                          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                        ),
                                        Text(
                                          '${c['name']} · ${c['students'] ?? 0} students',
                                          style: t.bodySmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Attendance & defaulters',
                                    icon: const Icon(Icons.insights_rounded, color: Brand.gold),
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            CourseStatsScreen(courseId: c['id'] as int, title: '${c['code']}'),
                                      ),
                                    ),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
                                    onPressed: () => _start(c as Map),
                                    child: const Text('Start'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ].staggered(startMs: 80),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
