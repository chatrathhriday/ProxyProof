import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'history_screen.dart' show mustAttend;

/// Teacher's view of one course: class average, defaulters (< 75%) with how many classes
/// each must attend in a row to recover, and everyone else sorted by attendance.
class CourseStatsScreen extends StatefulWidget {
  const CourseStatsScreen({super.key, required this.courseId, required this.title});
  final int courseId;
  final String title;

  @override
  State<CourseStatsScreen> createState() => _CourseStatsScreenState();
}

class _CourseStatsScreenState extends State<CourseStatsScreen> {
  Map? _data;
  String? _error;
  bool _onlyDefaulters = true;

  @override
  void initState() {
    super.initState();
    _data = Api.instance.cached('/courses/${widget.courseId}/students') as Map?;
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.get('/courses/${widget.courseId}/students') as Map;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: d == null
          ? Padding(padding: const EdgeInsets.all(18), child: _error != null ? Text(_error!) : const Skeleton(count: 4))
          : Builder(
              builder: (context) {
                final held = d['held'] as int;
                final students = (d['students'] as List).cast<Map>().map((s) {
                  final p = s['present'] as int;
                  return (s: s, pct: held == 0 ? null : p / held, present: p);
                }).toList()..sort((a, b) => (a.pct ?? 1).compareTo(b.pct ?? 1));
                final defaulters = students.where((x) => x.pct != null && x.pct! < 0.75).toList();
                final avg = held == 0 || students.isEmpty
                    ? null
                    : students.map((x) => x.pct!).reduce((a, b) => a + b) / students.length;
                final list = _onlyDefaulters ? defaulters : students;
                return RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                    children: [
                      Text('${d['course']['name']}', style: t.titleMedium?.copyWith(color: t.bodySmall?.color)),
                      const SizedBox(height: 12),
                      HeroPanel(
                        child: Row(
                          children: [
                            AttendanceRing(value: avg, size: 96, stroke: 9, label: 'class avg', dark: true),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Stat('$held', 'classes held'),
                                  _Stat('${students.length}', 'students'),
                                  _Stat('${defaulters.length}', 'below 75%', color: const Color(0xFFFF9C8F)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn().slideY(begin: 0.06),
                      const SizedBox(height: 16),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(value: true, label: Text('Defaulters (${defaulters.length})')),
                          ButtonSegment(value: false, label: Text('All (${students.length})')),
                        ],
                        selected: {_onlyDefaulters},
                        onSelectionChanged: (v) => setState(() => _onlyDefaulters = v.first),
                      ),
                      const SizedBox(height: 12),
                      if (list.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Nobody is below 75% — great class! 🎉'),
                          ),
                        ),
                      ...[
                        for (final x in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Card(
                              child: ListTile(
                                leading: AttendanceRing(value: x.pct, size: 46, stroke: 5),
                                title: Text('${x.s['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  x.pct == null
                                      ? 'No classes yet'
                                      : x.pct! < 0.75
                                      ? '${x.present}/$held · must attend next ${mustAttend(x.present, held)}'
                                      : '${x.present}/$held attended',
                                ),
                                trailing: x.s['has_device'] == true
                                    ? null
                                    : const Tooltip(
                                        message: 'Phone not linked yet',
                                        child: Icon(Icons.phonelink_off, color: Colors.grey),
                                      ),
                              ),
                            ),
                          ),
                      ].staggered(),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {this.color = Brand.goldSoft});
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(value, style: Brand.display(context, size: 22, color: color)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    ),
  );
}
