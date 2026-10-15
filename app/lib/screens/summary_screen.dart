import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/owl.dart';
import '../widgets/ui.dart';

/// End of class on the teacher's phone: "X present · Y need review · Z absent".
/// Clear cases were decided by the server; the teacher only looks at the flagged ones,
/// fixes any they disagree with, then taps Approve all.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, required this.sessionId, required this.title});
  final int sessionId;
  final String title;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  Map? _s;
  String? _error;
  bool _busy = false;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await Api.instance.get('/sessions/${widget.sessionId}') as Map;
      setState(() => _s = s);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _do(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _mark(Map a, String status) => _do(
    () async =>
        Api.instance.post('/sessions/${widget.sessionId}/attendance', {'studentId': a['student_id'], 'status': status}),
  );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final t = Theme.of(context).textTheme;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Padding(
          padding: const EdgeInsets.all(18),
          child: _error != null ? Text(_error!) : const Skeleton(height: 100, count: 4),
        ),
      );
    }
    final counts = s['counts'] as Map;
    final rows = (s['attendance'] as List).cast<Map>();
    final review = rows.where((a) => a['verdict'] == 'review').toList();
    final finalized = s['finalized_at'] != null;
    final allClear = review.isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} · summary')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          HeroPanel(
            child: Column(
              children: [
                Owl(mood: allClear ? OwlMood.happy : OwlMood.idle, size: 110),
                const SizedBox(height: 6),
                Text(
                  allClear
                      ? (finalized ? 'All done — finalised' : 'Every case was clear')
                      : '${review.length} to check',
                  style: Brand.display(context, size: 24, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Stat(counts['present'] as int, 'present', const Color(0xFF7BE0A8)),
                    _Stat(counts['review'] as int, 'need review', Brand.goldSoft),
                    _Stat(counts['absent'] as int, 'absent', const Color(0xFFFF9C8F)),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.06),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Brand.absent)),
            ),
          if (!allClear) ...[
            const SectionTitle('Check these'),
            Text(
              'Clear cases were decided automatically. Fix any you disagree with, then approve the rest.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 10),
            ...[
              for (final a in review)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Brand.review.withValues(alpha: 0.15),
                                child: Text(
                                  '${a['name']}'.characters.first.toUpperCase(),
                                  style: const TextStyle(color: Brand.review, fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${a['name']}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                    Text('${a['reason']}', style: t.bodySmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                                  onPressed: _busy ? null : () => _mark(a, 'absent'),
                                  child: const Text('Absent'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                                  onPressed: _busy ? null : () => _mark(a, 'present'),
                                  child: const Text('Present'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ].staggered(),
            const SizedBox(height: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Brand.gold, foregroundColor: Brand.navy),
              onPressed: _busy
                  ? null
                  : () => _do(() async => Api.instance.post('/sessions/${widget.sessionId}/approve-all')),
              icon: const Icon(Icons.done_all_rounded),
              label: Text('Approve all (${review.length})'),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? 'Hide full list' : 'Show all ${rows.length} students'),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: !_showAll
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      for (final a in rows)
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          title: Text('${a['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${a['reason']}'),
                          trailing: Pill(
                            switch (a['verdict']) {
                              'present' => 'Present',
                              'review' => 'Review',
                              _ => 'Absent',
                            },
                            color: switch (a['verdict']) {
                              'present' => Brand.present,
                              'review' => Brand.review,
                              _ => Brand.absent,
                            },
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Text('${v.round()}', style: Brand.display(context, size: 34, color: color)),
        ),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
      ],
    ),
  );
}
