import 'package:flutter/material.dart';

import '../api.dart';

/// The college rule: attendance must stay at or above this share of classes held.
const _rule = 0.75;

/// Classes you can still skip and stay >= 75%: largest k with A / (T + k) >= 0.75.
int canSkip(int attended, int held) => ((attended / _rule) - held + 1e-9).floor().clamp(0, 1 << 30);

/// Classes in a row you must attend to reach 75%: smallest m with (A + m) / (T + m) >= 0.75.
int mustAttend(int attended, int held) => ((_rule * held - attended) / (1 - _rule) - 1e-9).ceil().clamp(0, 1 << 30);

/// Student's attendance per course, with the "can I bunk?" calculator.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List> _data = _load();

  Future<List> _load() async => await Api.instance.get('/me/attendance') as List;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My attendance')),
      body: FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final courses = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _data = _load()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (courses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('You are not enrolled yet.')),
                  ),
                for (final c in courses) _CourseCard(c as Map),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard(this.c);
  final Map c;

  @override
  Widget build(BuildContext context) {
    final held = c['held'] as int;
    final present = c['present'] as int;
    final review = c['review'] as int;
    final pct = held == 0 ? null : present / held;
    final ok = pct == null || pct >= _rule;
    final color = ok ? Colors.green.shade700 : Theme.of(context).colorScheme.error;
    final t = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: held == 0 ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CourseDetail(c))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: pct ?? 0,
                      strokeWidth: 6,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.15),
                    ),
                    Center(child: Text(pct == null ? '—' : '${(pct * 100).round()}%', style: t.titleMedium)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c['code']}', style: t.titleMedium),
                    Text('${c['name']}', style: t.bodySmall),
                    const SizedBox(height: 6),
                    Text(held == 0 ? 'No classes held yet' : '$present of $held classes'),
                    if (review > 0) Text('$review waiting for teacher review', style: t.bodySmall),
                    if (held > 0)
                      Text(
                        ok
                            ? 'You can skip ${canSkip(present, held)} more and stay at 75%'
                            : 'Attend the next ${mustAttend(present, held)} to reach 75%',
                        style: t.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseDetail extends StatefulWidget {
  const _CourseDetail(this.c);
  final Map c;

  @override
  State<_CourseDetail> createState() => _CourseDetailState();
}

class _CourseDetailState extends State<_CourseDetail> {
  double _skip = 1;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final held = c['held'] as int;
    final present = c['present'] as int;
    final skip = _skip.round();
    final after = present / (held + skip);
    final ok = after >= _rule;
    final t = Theme.of(context).textTheme;
    final sessions = (c['sessions'] as List).cast<Map>();

    return Scaffold(
      appBar: AppBar(title: Text('${c['code']}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Can I bunk?', style: t.titleLarge),
                  const SizedBox(height: 8),
                  Text('If I skip the next $skip class${skip == 1 ? '' : 'es'}…'),
                  Slider(
                    value: _skip,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '$skip',
                    onChanged: (v) => setState(() => _skip = v),
                  ),
                  Text(
                    '${(after * 100).toStringAsFixed(1)}% — ${ok ? 'still safe ✓' : 'below 75% ✗'}',
                    style: t.headlineSmall?.copyWith(
                      color: ok ? Colors.green.shade700 : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Now: $present / $held. Safe to skip: ${canSkip(present, held)}. '
                    'Pending reviews are not counted until the teacher decides.',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Classes', style: t.titleMedium),
          for (final s in sessions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (s['status']) {
                  'present' => Icons.check_circle,
                  'review' => Icons.help,
                  _ => Icons.cancel,
                },
                color: switch (s['status']) {
                  'present' => Colors.green,
                  'review' => Colors.orange,
                  _ => Colors.red,
                },
              ),
              title: Text(_date(s['date'] as String)),
              trailing: Text(switch (s['status']) {
                'present' => 'Present',
                'review' => 'Under review',
                _ => 'Absent',
              }),
            ),
        ],
      ),
    );
  }

  static String _date(String iso) {
    final d = DateTime.parse(iso).toLocal();
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
