import 'package:flutter/material.dart';

import '../api.dart';

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
        body: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator()),
      );
    }
    final counts = s['counts'] as Map;
    final rows = (s['attendance'] as List).cast<Map>();
    final review = rows.where((a) => a['verdict'] == 'review').toList();
    final finalized = s['finalized_at'] != null;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} · summary')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _Stat('${counts['present']}', 'present', Colors.green.shade700),
              _Stat('${counts['review']}', 'need review', Colors.orange.shade800),
              _Stat('${counts['absent']}', 'absent', Theme.of(context).colorScheme.error),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (review.isEmpty)
            Text(
              finalized ? 'Finalised ✓' : 'Every case was clear — nothing to review.',
              textAlign: TextAlign.center,
              style: t.titleMedium,
            )
          else ...[
            Text('Check these', style: t.titleMedium),
            for (final a in review)
              Card(
                child: ListTile(
                  title: Text('${a['name']}'),
                  subtitle: Text('${a['reason']}'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(onPressed: _busy ? null : () => _mark(a, 'absent'), child: const Text('Absent')),
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _mark(a, 'present'),
                        child: const Text('Present'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _do(() async => Api.instance.post('/sessions/${widget.sessionId}/approve-all')),
              icon: const Icon(Icons.done_all),
              label: Text('Approve all (${review.length})'),
            ),
          ],
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? 'Hide full list' : 'Show all ${rows.length} students'),
          ),
          if (_showAll)
            for (final a in rows)
              ListTile(
                dense: true,
                title: Text('${a['name']}'),
                subtitle: Text('${a['reason']}'),
                trailing: Text(switch (a['verdict']) {
                  'present' => 'Present',
                  'review' => 'Review',
                  _ => 'Absent',
                }),
              ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color)),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
