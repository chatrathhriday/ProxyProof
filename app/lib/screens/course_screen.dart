import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'summary_screen.dart';

/// Teacher's home for one course: Overview (average + defaulters), Classes (history + trend),
/// Students (add/remove), Timetable (edit), Notices (announcements).
class CourseScreen extends StatelessWidget {
  const CourseScreen({super.key, required this.courseId, required this.title});
  final int courseId;
  final String title;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Brand.gold,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Classes'),
              Tab(text: 'Students'),
              Tab(text: 'Timetable'),
              Tab(text: 'Notices'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Overview(courseId),
            _History(courseId, title),
            _Students(courseId),
            _Timetable(courseId),
            _Notices(courseId),
          ],
        ),
      ),
    );
  }
}

int _mustAttend(int present, int counted, int rule) {
  final r = rule / 100;
  return ((r * counted - present) / (1 - r) - 1e-9).ceil().clamp(0, 1 << 30);
}

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

// ---------------------------------------------------------------- Overview

class _Overview extends StatefulWidget {
  const _Overview(this.courseId);
  final int courseId;
  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  Map? _d;
  bool _onlyDefaulters = true;

  @override
  void initState() {
    super.initState();
    _d = Api.instance.cached('/courses/${widget.courseId}/students') as Map?;
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.get('/courses/${widget.courseId}/students') as Map;
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Padding(padding: EdgeInsets.all(18), child: Skeleton(count: 4));
    final held = d['held'] as int;
    final rule = (d['rule'] as int?) ?? 75;
    final students = (d['students'] as List).cast<Map>().map((s) {
      final p = s['present'] as int, e = (s['excused'] as int?) ?? 0;
      final counted = held - e;
      return (s: s, present: p, counted: counted, pct: counted > 0 ? p / counted : null);
    }).toList()..sort((a, b) => (a.pct ?? 1).compareTo(b.pct ?? 1));
    final defaulters = students.where((x) => x.pct != null && x.pct! * 100 < rule).toList();
    final withPct = students.where((x) => x.pct != null).toList();
    final avg = withPct.isEmpty ? null : withPct.map((x) => x.pct!).reduce((a, b) => a + b) / withPct.length;
    final list = _onlyDefaulters ? defaulters : students;
    final t = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
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
                      _HeroStat('$held', 'classes held'),
                      _HeroStat('${students.length}', 'students'),
                      _HeroStat('${defaulters.length}', 'below $rule%', color: const Color(0xFFFF9C8F)),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_onlyDefaulters ? 'Nobody is below $rule% — great class! 🎉' : 'No students yet.'),
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
                          ? 'No classes counted yet'
                          : x.pct! * 100 < rule
                          ? '${x.present}/${x.counted} · must attend next ${_mustAttend(x.present, x.counted, rule)}'
                          : '${x.present}/${x.counted} attended',
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
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(this.value, this.label, {this.color = Brand.goldSoft});
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

// ---------------------------------------------------------------- Classes (history + trend)

class _History extends StatefulWidget {
  const _History(this.courseId, this.title);
  final int courseId;
  final String title;
  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  List? _rows;

  @override
  void initState() {
    super.initState();
    _rows = Api.instance.cached('/courses/${widget.courseId}/sessions') as List?;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.instance.get('/courses/${widget.courseId}/sessions') as List;
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
  }

  static double _pct(Map s) {
    final counted = (s['enrolled'] as int) - (s['excused'] as int);
    return counted <= 0 ? 0 : (s['present'] as int) / counted;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) return const Padding(padding: EdgeInsets.all(18), child: Skeleton(count: 4));
    final recent = rows.reversed.toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          if (rows.length >= 2) ...[
            const SectionTitle('Attendance trend'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
                child: SizedBox(height: 150, child: _TrendChart([for (final s in rows) _pct(s as Map)])),
              ),
            ).animate().fadeIn(),
          ],
          SectionTitle(
            'Past classes',
            trailing: Text('${rows.length}', style: const TextStyle(color: Brand.gold)),
          ),
          if (rows.isEmpty)
            const Card(
              child: Padding(padding: EdgeInsets.all(20), child: Text('No finished classes yet.')),
            ),
          ...[
            for (final s in recent.take(40))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: AttendanceRing(value: _pct(s as Map), size: 44, stroke: 5),
                    title: Text(_date(s['started_at'] as String), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${s['present']} present · ${s['absent']} absent'
                      '${(s['excused'] as int) > 0 ? ' · ${s['excused']} excused' : ''}'
                      '${(s['review'] as int) > 0 ? ' · ${s['review']} to review' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SummaryScreen(sessionId: s['id'] as int, title: widget.title),
                        ),
                      );
                      _load();
                    },
                  ),
                ),
              ),
          ].staggered(),
        ],
      ),
    );
  }

  static String _date(String iso) {
    final d = DateTime.parse(iso).toLocal();
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${w[d.weekday - 1]} ${d.day} ${m[d.month - 1]} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// Smooth line of attendance % per class with a gold 75% guide, drawn in on first show.
class _TrendChart extends StatelessWidget {
  const _TrendChart(this.values);
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final grid = Theme.of(context).brightness == Brightness.dark ? Colors.white12 : const Color(0xFFE9E3D3);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (_, p, _) => CustomPaint(painter: _TrendPainter(values, p, grid), size: Size.infinite),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.v, this.progress, this.grid);
  final List<double> v;
  final double progress;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0;
    final w = size.width - left, h = size.height - 6;
    Offset pt(int i) => Offset(left + (v.length == 1 ? w / 2 : w * i / (v.length - 1)), 3 + h * (1 - v[i]));
    final label = TextStyle(color: Colors.grey.shade600, fontSize: 10);
    for (final y in [0.0, 0.5, 0.75, 1.0]) {
      final yy = 3 + h * (1 - y);
      canvas.drawLine(
        Offset(left, yy),
        Offset(size.width, yy),
        Paint()
          ..color = y == 0.75 ? Brand.gold.withValues(alpha: 0.7) : grid
          ..strokeWidth = y == 0.75 ? 1.6 : 1,
      );
      final tp = TextPainter(
        text: TextSpan(text: '${(y * 100).round()}', style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, yy - 6));
    }
    if (v.isEmpty) return;
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < v.length; i++) {
      final a = pt(i - 1), b = pt(i);
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, left + w * progress, size.height));
    final fill = Path.from(path)
      ..lineTo(pt(v.length - 1).dx, size.height)
      ..lineTo(pt(0).dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Brand.navy3.withValues(alpha: 0.25), Brand.navy3.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Brand.navy3
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < v.length; i++) {
      canvas.drawCircle(pt(i), 3.2, Paint()..color = v[i] >= 0.75 ? Brand.present : Brand.absent);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.progress != progress || old.v != v;
}

// ---------------------------------------------------------------- Students

class _Students extends StatefulWidget {
  const _Students(this.courseId);
  final int courseId;
  @override
  State<_Students> createState() => _StudentsState();
}

class _StudentsState extends State<_Students> {
  final _emails = TextEditingController();
  Map? _d;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.get('/courses/${widget.courseId}/students') as Map;
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
  }

  Future<void> _add() async {
    final list = _emails.text.split(RegExp(r'[\s,;]+')).where((e) => e.isNotEmpty).toList();
    if (list.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await Api.instance.post('/courses/${widget.courseId}/enroll', {'emails': list});
      _emails.clear();
      if (mounted) {
        _toast(
          context,
          'Added ${(r['enrolled'] as List).length}, invited ${(r['invited'] as List).length}'
          '${(r['notFound'] as List).isNotEmpty ? ', ${(r['notFound'] as List).length} invalid' : ''}',
        );
      }
      HapticFeedback.mediumImpact();
      // Probable typos of an existing student's email: offer the real address.
      for (final s in (r['suggestions'] as List? ?? const [])) {
        if (!mounted) break;
        final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Did you mean…'),
            content: Text('"${s['typed']}" isn\'t registered.\n\nAdd ${s['existing']} instead?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
            ],
          ),
        );
        if (yes == true) {
          await Api.instance.post('/courses/${widget.courseId}/enroll', {
            'emails': [s['existing']],
          });
        }
      }
      await _load();
    } catch (e) {
      if (mounted) _toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map body) async {
    await Api.instance.post('/courses/${widget.courseId}/unenroll', body);
    await _load();
  }

  @override
  void dispose() {
    _emails.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final students = (d?['students'] as List? ?? const []).cast<Map>();
    final invites = (d?['invites'] as List? ?? const []).cast<String>();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _emails,
                    minLines: 2,
                    maxLines: 5,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Add students by email',
                      hintText: 'name.surname2026@vitstudent.ac.in, …',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Add'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Students who haven\'t signed in yet are invited and join automatically on first sign-in.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          SectionTitle(
            'Enrolled',
            trailing: Text('${students.length}', style: const TextStyle(color: Brand.gold)),
          ),
          if (d == null) const Skeleton(height: 60, count: 3),
          for (final s in students)
            Dismissible(
              key: ValueKey('s${s['id']}'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async =>
                  await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text('Remove ${s['name']}?'),
                      content: const Text('Their past attendance stays in the records.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
                      ],
                    ),
                  ) ??
                  false,
              onDismissed: (_) => _remove({'studentId': s['id']}),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(color: Brand.absent, borderRadius: BorderRadius.circular(22)),
                child: const Icon(Icons.person_remove_rounded, color: Colors.white),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Brand.navy,
                      child: Text(
                        '${s['name']}'.characters.first.toUpperCase(),
                        style: const TextStyle(color: Brand.goldSoft, fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${s['email']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ),
          if (invites.isNotEmpty) ...[
            SectionTitle(
              'Invited',
              trailing: Text('${invites.length}', style: const TextStyle(color: Brand.gold)),
            ),
            for (final e in invites)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.mark_email_unread_outlined, color: Brand.gold),
                  title: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Joins on first sign-in'),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => _remove({'email': e})),
                ),
              ),
          ],
          const SizedBox(height: 6),
          Text('Swipe a student left to remove them.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Timetable

class _Timetable extends StatefulWidget {
  const _Timetable(this.courseId);
  final int courseId;
  @override
  State<_Timetable> createState() => _TimetableState();
}

class _TimetableState extends State<_Timetable> {
  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  List<Map> _slots = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final courses = await Api.instance.get('/courses') as List;
    final c = courses.firstWhere((c) => c['id'] == widget.courseId, orElse: () => null);
    if (mounted) {
      setState(() {
        _slots = ((c?['schedule'] as List?) ?? const []).cast<Map>().map((s) => Map.of(s)).toList();
        _loaded = true;
      });
    }
  }

  Future<void> _save() async {
    try {
      final r = await Api.instance.put('/courses/${widget.courseId}/schedule', {'schedule': _slots});
      setState(() => _slots = (r['schedule'] as List).cast<Map>().map((s) => Map.of(s)).toList());
      if (mounted) _toast(context, 'Timetable saved');
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
  }

  static String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _addSlot() async {
    var day = 1;
    final room = TextEditingController();
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'CLASS STARTS AT',
    );
    if (start == null || !mounted) return;
    final endDefault = TimeOfDay(
      hour: (start.hour * 60 + start.minute + 50) ~/ 60 % 24,
      minute: (start.minute + 50) % 60,
    );
    final end = await showTimePicker(context: context, initialTime: endDefault, helpText: 'CLASS ENDS AT');
    if (end == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('${_fmt(start)} – ${_fmt(end)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: day,
                decoration: const InputDecoration(labelText: 'Day'),
                items: [for (var i = 1; i <= 7; i++) DropdownMenuItem(value: i, child: Text(_days[i - 1]))],
                onChanged: (v) => set(() => day = v ?? 1),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: room,
                decoration: const InputDecoration(labelText: 'Room (e.g. SJT 304)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _slots.add({'d': day, 's': _fmt(start), 'e': _fmt(end), 'room': room.text.trim()}));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Padding(padding: EdgeInsets.all(18), child: Skeleton(height: 60, count: 3));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Brand.gold,
        foregroundColor: Brand.navy,
        onPressed: _addSlot,
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('Add class time'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
        children: [
          if (_slots.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No weekly timetable yet. Students see the next class on their Today screen once you add one.',
                ),
              ),
            ),
          ...[
            for (final (i, s) in _slots.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(14)),
                      child: Text(
                        _days[(s['d'] as int) - 1].substring(0, 3),
                        style: const TextStyle(color: Brand.goldSoft, fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text('${s['s']} – ${s['e']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${s['room']}'.isEmpty ? 'No room set' : '${s['room']}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        setState(() => _slots.removeAt(i));
                        await _save();
                      },
                    ),
                  ),
                ),
              ),
          ].staggered(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Notices

class _Notices extends StatefulWidget {
  const _Notices(this.courseId);
  final int courseId;
  @override
  State<_Notices> createState() => _NoticesState();
}

class _NoticesState extends State<_Notices> {
  final _text = TextEditingController();
  List? _items;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.instance.get('/courses/${widget.courseId}/announcements') as List;
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) _toast(context, '$e');
    }
  }

  Future<void> _post() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await Api.instance.post('/courses/${widget.courseId}/announcements', {'body': _text.text.trim()});
      _text.clear();
      HapticFeedback.mediumImpact();
      await _load();
    } catch (e) {
      if (mounted) _toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _text,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Announcement',
                      hintText: 'e.g. Today\'s class is in SJT 512',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _post,
                    icon: const Icon(Icons.campaign_rounded),
                    label: const Text('Post to students'),
                  ),
                ],
              ),
            ),
          ),
          SectionTitle(
            'Posted',
            trailing: Text('${items?.length ?? 0}', style: const TextStyle(color: Brand.gold)),
          ),
          if (items == null) const Skeleton(height: 70, count: 2),
          if (items != null && items.isEmpty)
            const Card(
              child: Padding(padding: EdgeInsets.all(20), child: Text('Nothing posted yet.')),
            ),
          ...[
            for (final a in items ?? const [])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.campaign_outlined, color: Brand.gold),
                    title: Text('${a['body']}'),
                    subtitle: Text('${a['author']} · ${_ago(a['created_at'] as String)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        await Api.instance.post('/courses/${widget.courseId}/announcements/${a['id']}/delete');
                        await _load();
                      },
                    ),
                  ),
                ),
              ),
          ].staggered(),
        ],
      ),
    );
  }
}

String _ago(String iso) {
  final m = DateTime.now().difference(DateTime.parse(iso).toLocal()).inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  if (m < 24 * 60) return '${m ~/ 60} h ago';
  return '${m ~/ (24 * 60)} d ago';
}
