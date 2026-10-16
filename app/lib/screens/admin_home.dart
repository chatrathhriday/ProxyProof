import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/owl.dart';
import '../widgets/ui.dart';

/// Admin in the app: Overview (whole college), Approvals (faculty + phone changes), People.
/// Audit log and college policy live on the web dashboard (bigger screen, same account).
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _tab, children: const [_Overview(), _Approvals(), _People()]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.verified_user_outlined), label: 'Approvals'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'People'),
        ],
      ),
    );
  }
}

Widget _header(BuildContext context, String title) => Row(
  children: [
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Admin',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.w700),
          ),
          Text(title, style: Brand.display(context, size: 28)),
        ],
      ),
    ),
    IconButton.filledTonal(
      icon: const Icon(Icons.logout_rounded),
      tooltip: 'Log out',
      onPressed: () => logout(context),
    ),
  ],
);

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

// ---------------------------------------------------------------- Overview

class _Overview extends StatefulWidget {
  const _Overview();
  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  Map? _o;

  @override
  void initState() {
    super.initState();
    _o = Api.instance.cached('/admin/overview') as Map?;
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await Api.instance.get('/admin/overview') as Map;
      if (mounted) setState(() => _o = o);
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final t = Theme.of(context).textTheme;
    final totals = (o?['totals'] as Map?) ?? const {};
    final live = (o?['live'] as List?) ?? const [];
    final courses = (o?['courses'] as List?) ?? const [];
    final rule = (o?['policy']?['minAttendance'] as int?) ?? 75;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          _header(context, 'College overview'),
          const SizedBox(height: 16),
          if (o == null) const Skeleton(height: 110, count: 3),
          if (o != null) ...[
            HeroPanel(
              child: Row(
                children: [
                  Owl(mood: live.isEmpty ? OwlMood.idle : OwlMood.scanning, size: 84),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 6,
                      children: [
                        _Big('${live.length}', 'live now'),
                        _Big('${totals['students'] ?? 0}', 'students'),
                        _Big('${totals['teachers'] ?? 0}', 'teachers'),
                        _Big('${totals['courses'] ?? 0}', 'courses'),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.06),
            if ((totals['pending_faculty'] ?? 0) + (totals['pending_devices'] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Card(
                  color: Brand.gold.withValues(alpha: 0.15),
                  child: ListTile(
                    leading: const Icon(Icons.notifications_active_rounded, color: Brand.gold),
                    title: Text(
                      '${totals['pending_faculty']} faculty · ${totals['pending_devices']} phone changes waiting',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('Open the Approvals tab'),
                  ),
                ),
              ),
            if (live.isNotEmpty) ...[
              const SectionTitle('Live classes'),
              ...[
                for (final s in live)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        leading: const Radar(size: 46, child: Icon(Icons.sensors, color: Brand.gold, size: 20)),
                        title: Text(
                          '${s['code']} · ${s['teacher']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('${s['present']} of ${s['enrolled']} marked'),
                        trailing: const Pill('LIVE', color: Brand.absent, pulse: true),
                      ),
                    ),
                  ),
              ].staggered(),
            ],
            SectionTitle(
              'Courses',
              trailing: Text('min $rule%', style: const TextStyle(color: Brand.gold)),
            ),
            ...[
              for (final c in courses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: AttendanceRing(
                        value: c['avg_pct'] == null ? null : (c['avg_pct'] as int) / 100,
                        size: 46,
                        stroke: 5,
                      ),
                      title: Text('${c['code']} · ${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${c['teacher']} · ${c['students']} students · ${c['held']} classes'),
                      trailing: (c['defaulters'] as int) > 0
                          ? Pill('${c['defaulters']} < $rule%', color: Brand.absent)
                          : const Icon(Icons.check_circle_rounded, color: Brand.present),
                    ),
                  ),
                ),
            ].staggered(),
            const SizedBox(height: 8),
            Text(
              'Audit log and college policy are on the web dashboard (same login).',
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Brand.display(context, size: 26, color: Brand.goldSoft)),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ],
  );
}

// ---------------------------------------------------------------- Approvals

class _Approvals extends StatefulWidget {
  const _Approvals();
  @override
  State<_Approvals> createState() => _ApprovalsState();
}

class _ApprovalsState extends State<_Approvals> {
  List? _faculty, _devices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        Api.instance.get('/admin/users?role=organiser'),
        Api.instance.get('/devices/pending'),
      ]);
      if (mounted) {
        setState(() {
          _faculty = (r[0] as List).where((u) => u['status'] == 'pending').toList();
          _devices = r[1] as List;
        });
      }
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
  }

  Future<void> _act(Future<void> Function() f, String done) async {
    try {
      await f();
      HapticFeedback.mediumImpact();
      if (mounted) _toast(context, done);
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final empty = (_faculty?.isEmpty ?? false) && (_devices?.isEmpty ?? false);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          _header(context, 'Approvals'),
          if (_faculty == null) ...[const SizedBox(height: 16), const Skeleton(height: 100, count: 2)],
          if (empty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  const Owl(mood: OwlMood.happy, size: 130),
                  const SizedBox(height: 12),
                  Text('All clear', style: Brand.display(context, size: 24)),
                  Text('No faculty or phone changes waiting.', style: t.bodyMedium),
                ],
              ),
            ),
          if (_faculty?.isNotEmpty ?? false) ...[
            const SectionTitle('New faculty'),
            for (final u in _faculty!)
              _ApprovalCard(
                icon: Icons.co_present_rounded,
                title: '${u['name']}',
                lines: ['${u['email']}', 'Signed in with Google · wants teacher access'],
                onReject: () => _act(
                  () async => Api.instance.post('/admin/users/${u['id']}/status', {'status': 'disabled'}),
                  'Request declined',
                ),
                onApprove: () => _act(
                  () async => Api.instance.post('/admin/users/${u['id']}/status', {'status': 'active'}),
                  '${u['name']} is now a teacher',
                ),
              ),
          ],
          if (_devices?.isNotEmpty ?? false) ...[
            const SectionTitle('Phone changes'),
            for (final d in _devices!)
              _ApprovalCard(
                icon: Icons.phone_android_rounded,
                title: '${d['name']}',
                lines: ['${d['email']}', 'New: ${d['model']} · current: ${d['current_model'] ?? 'none'}'],
                onReject: () => _act(() async => Api.instance.post('/devices/${d['id']}/reject'), 'Request rejected'),
                onApprove: () => _act(
                  () async => Api.instance.post('/devices/${d['id']}/approve'),
                  '${d['name']}\'s new phone approved',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.icon,
    required this.title,
    required this.lines,
    required this.onApprove,
    required this.onReject,
  });
  final IconData icon;
  final String title;
  final List<String> lines;
  final VoidCallback onApprove, onReject;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Brand.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final l in lines) Text(l, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: onReject, child: const Text('Decline')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(onPressed: onApprove, child: const Text('Approve')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ).animate().fadeIn().slideY(begin: 0.08);
}

// ---------------------------------------------------------------- People

class _People extends StatefulWidget {
  const _People();
  @override
  State<_People> createState() => _PeopleState();
}

class _PeopleState extends State<_People> {
  final _q = TextEditingController();
  String? _role;
  List? _people;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    try {
      final q = Uri.encodeQueryComponent(_q.text);
      final r = await Api.instance.get('/admin/users?q=$q${_role == null ? '' : '&role=$_role'}') as List;
      if (mounted) setState(() => _people = r);
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
  }

  Future<void> _manage(Map u) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('${u['name']}', style: Brand.display(c, size: 20)),
              subtitle: Text('${u['email']}'),
            ),
            if (u['role'] == 'student')
              ListTile(
                leading: const Icon(Icons.phonelink_erase_rounded, color: Brand.gold),
                title: const Text('Reset phone'),
                subtitle: Text(
                  u['device'] == null ? 'No phone linked' : 'Unlink ${u['device']}; next phone links itself',
                ),
                onTap: () => Navigator.pop(c, 'reset'),
              ),
            if (u['status'] != 'disabled')
              ListTile(
                leading: const Icon(Icons.block_rounded, color: Brand.absent),
                title: const Text('Disable account'),
                subtitle: const Text('Signs them out everywhere immediately'),
                onTap: () => Navigator.pop(c, 'disable'),
              )
            else
              ListTile(
                leading: const Icon(Icons.check_circle_rounded, color: Brand.present),
                title: const Text('Re-enable account'),
                onTap: () => Navigator.pop(c, 'enable'),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    try {
      switch (action) {
        case 'reset':
          await Api.instance.post('/admin/users/${u['id']}/reset-device');
        case 'disable':
          await Api.instance.post('/admin/users/${u['id']}/status', {'status': 'disabled'});
        case 'enable':
          await Api.instance.post('/admin/users/${u['id']}/status', {'status': 'active'});
      }
      HapticFeedback.mediumImpact();
      if (mounted) _toast(context, 'Done');
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
    await _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    return RefreshIndicator(
      onRefresh: _search,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          _header(context, 'People'),
          const SizedBox(height: 14),
          TextField(
            controller: _q,
            onSubmitted: (_) => _search(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search name or email',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _search),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in [
                (null, 'Everyone'),
                ('student', 'Students'),
                ('organiser', 'Faculty'),
                ('admin', 'Admins'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _role == value,
                  onSelected: (_) {
                    setState(() => _role = value);
                    _search();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (people == null) const Skeleton(height: 64, count: 4),
          ...[
            for (final u in people ?? const [])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    onTap: u['role'] == 'admin' ? null : () => _manage(u as Map),
                    leading: CircleAvatar(
                      backgroundColor: switch (u['role']) {
                        'organiser' => Brand.gold,
                        'admin' => Brand.absent,
                        _ => Brand.navy,
                      },
                      child: Icon(
                        switch (u['role']) {
                          'organiser' => Icons.co_present_rounded,
                          'admin' => Icons.shield_rounded,
                          _ => Icons.school_rounded,
                        },
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text('${u['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${u['email']}\n${u['role'] == 'student' ? '${u['enrolled']} courses · ${u['device'] ?? 'no phone linked'}' : '${u['teaching']} courses'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: u['status'] == 'active'
                        ? null
                        : Pill('${u['status']}', color: u['status'] == 'pending' ? Brand.review : Brand.absent),
                  ),
                ),
              ),
          ].staggered(),
        ],
      ),
    );
  }
}
