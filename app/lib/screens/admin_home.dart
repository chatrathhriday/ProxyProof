import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/owl.dart';
import '../widgets/ui.dart';

/// Admin's job in the app: approve or reject device-change requests.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  late Future<List> _pending = _load();

  Future<List> _load() async => await Api.instance.get('/devices/pending') as List;

  Future<void> _decide(Map d, bool approve) async {
    try {
      await Api.instance.post('/devices/${d['id']}/${approve ? 'approve' : 'reject'}');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(approve ? '${d['name']}\'s new phone approved' : 'Request rejected')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    setState(() => _pending = _load());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder(
          future: _pending,
          builder: (context, snap) {
            final list = snap.data ?? const [];
            return RefreshIndicator(
              onRefresh: () async => setState(() => _pending = _load()),
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
                              'Admin',
                              style: t.bodyMedium?.copyWith(color: Brand.gold, fontWeight: FontWeight.w700),
                            ),
                            Text('Device approvals', style: Brand.display(context, size: 28)),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.logout_rounded),
                        tooltip: 'Log out',
                        onPressed: () => logout(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  HeroPanel(
                    child: Row(
                      children: [
                        Owl(mood: list.isEmpty ? OwlMood.happy : OwlMood.alert, size: 84),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            snap.hasData
                                ? (list.isEmpty
                                      ? 'All clear — no phones waiting.'
                                      : '${list.length} phone change${list.length == 1 ? '' : 's'} to review')
                                : 'Loading…',
                            style: Brand.display(context, size: 20, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A student on a new phone, or whose fingerprints changed. Approving retires their old phone.',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (snap.hasError) Text('${snap.error}'),
                  if (!snap.hasData && !snap.hasError) const Skeleton(height: 120, count: 2),
                  ...[
                    for (final d in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${d['name']}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                Text('${d['email']}', style: t.bodySmall),
                                const SizedBox(height: 10),
                                _Line(Icons.phone_android, 'New phone', '${d['model']}'),
                                _Line(Icons.history, 'Current phone', '${d['current_model'] ?? 'none'}'),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _decide(d as Map, false),
                                        child: const Text('Reject'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () => _decide(d as Map, true),
                                        child: const Text('Approve'),
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
                ].animate(interval: 30.ms).fadeIn(duration: 250.ms),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Brand.gold),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
