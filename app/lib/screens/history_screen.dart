import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/owl.dart';
import '../widgets/ui.dart';

/// The college rule: attendance must stay at or above this share of classes held.
const _rule = 0.75;

/// Classes you can still skip and stay >= 75%: largest k with A / (T + k) >= 0.75.
int canSkip(int attended, int held) => ((attended / _rule) - held + 1e-9).floor().clamp(0, 1 << 30);

/// Classes in a row you must attend to reach 75%: smallest m with (A + m) / (T + m) >= 0.75.
int mustAttend(int attended, int held) => ((_rule * held - attended) / (1 - _rule) - 1e-9).ceil().clamp(0, 1 << 30);

/// All of the student's classes: overall %, each course's %, live badges, bunk advice.
class ClassesTab extends StatefulWidget {
  const ClassesTab({super.key, this.visible = true});
  final bool visible;

  @override
  State<ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<ClassesTab> {
  List? _courses;
  String? _error;

  @override
  void initState() {
    super.initState();
    _courses = Api.instance.cached('/me/attendance') as List?; // instant first paint
    _load();
  }

  @override
  void didUpdateWidget(ClassesTab old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) _load(); // refresh whenever the tab is opened
  }

  Future<void> _load() async {
    try {
      final data = await Api.instance.get('/me/attendance') as List;
      if (mounted) {
        setState(() {
          _courses = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final courses = _courses;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            children: [
              Text('My classes', style: Brand.display(context, size: 30)).animate().fadeIn(),
              const SizedBox(height: 14),
              if (courses == null && _error == null) const Skeleton(height: 120, count: 4),
              if (_error != null && courses == null) Text(_error!),
              if (courses != null) ...[
                _Overall(courses),
                SectionTitle(
                  'Courses',
                  trailing: Text('${courses.length}', style: const TextStyle(color: Brand.gold)),
                ),
                if (courses.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('You are not enrolled in any class yet. Your teacher adds you with your VIT email.'),
                    ),
                  ),
                ...[for (final c in courses) _CourseCard(c as Map)].staggered(startMs: 100),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Overall extends StatelessWidget {
  const _Overall(this.courses);
  final List courses;

  @override
  Widget build(BuildContext context) {
    var held = 0, present = 0;
    for (final c in courses) {
      held += c['held'] as int;
      present += c['present'] as int;
    }
    final pct = held == 0 ? null : present / held;
    final ok = pct == null || pct >= _rule;
    return HeroPanel(
      child: Row(
        children: [
          AttendanceRing(value: pct, size: 104, stroke: 9, label: 'overall', dark: true),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pct == null ? 'No classes yet' : (ok ? 'You\'re on track' : 'Below 75%'),
                  style: Brand.display(context, size: 22, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  '$present of $held classes across ${courses.length} course${courses.length == 1 ? '' : 's'}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          Owl(mood: ok ? OwlMood.happy : OwlMood.worried, size: 64),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06);
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
    final color = AttendanceRing.colorFor(pct);
    final t = Theme.of(context).textTheme;
    final live = c['liveSince'] != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CourseDetail(c))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Hero(
                  tag: 'ring-${c['courseId']}',
                  child: AttendanceRing(value: pct, size: 70),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text('${c['code']}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          if (live) ...[const SizedBox(width: 8), const Pill('LIVE', color: Brand.absent, pulse: true)],
                        ],
                      ),
                      Text('${c['name']}', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Text(
                        held == 0
                            ? 'No classes held yet'
                            : ok
                            ? 'Can skip ${canSkip(present, held)} · $present/$held attended'
                            : 'Attend next ${mustAttend(present, held)} · $present/$held attended',
                        style: t.bodyMedium?.copyWith(color: held == 0 ? null : color, fontWeight: FontWeight.w600),
                      ),
                      if (review > 0)
                        Text('$review waiting for review', style: t.bodySmall?.copyWith(color: Brand.review)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
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
    final pct = held == 0 ? null : present / held;

    return Scaffold(
      appBar: AppBar(title: Text('${c['code']}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          Text('${c['name']}', style: t.titleMedium?.copyWith(color: t.bodySmall?.color)),
          const SizedBox(height: 14),
          HeroPanel(
            child: Row(
              children: [
                Hero(
                  tag: 'ring-${c['courseId']}',
                  child: AttendanceRing(value: pct, size: 96, stroke: 9, dark: true),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$present / $held', style: Brand.display(context, size: 30, color: Colors.white)),
                      Text('classes attended', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                      const SizedBox(height: 6),
                      if (held > 0)
                        Text(
                          pct! >= _rule
                              ? 'Safe to skip ${canSkip(present, held)}'
                              : 'Attend next ${mustAttend(present, held)} in a row',
                          style: const TextStyle(color: Brand.goldSoft, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (held > 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Owl(mood: ok ? OwlMood.happy : OwlMood.worried, size: 54),
                        const SizedBox(width: 10),
                        Text('Can I bunk?', style: Brand.display(context, size: 22)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('If I skip the next $skip class${skip == 1 ? '' : 'es'}…'),
                    Slider(
                      value: _skip,
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '$skip',
                      onChanged: (v) => setState(() => _skip = v),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: after * 100),
                      duration: const Duration(milliseconds: 300),
                      builder: (_, v, _) => Text(
                        '${v.toStringAsFixed(1)}%  ${ok ? '· still safe' : '· below 75%'}',
                        style: Brand.display(context, size: 26, color: ok ? Brand.present : Brand.absent),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Reviews pending with your teacher aren\'t counted until they decide.', style: t.bodySmall),
                  ],
                ),
              ),
            ),
          SectionTitle('History'),
          if (sessions.isEmpty) const Text('No classes held yet.'),
          ...[
            for (final s in sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(
                      switch (s['status']) {
                        'present' => Icons.check_circle_rounded,
                        'review' => Icons.hourglass_top_rounded,
                        _ => Icons.cancel_rounded,
                      },
                      color: switch (s['status']) {
                        'present' => Brand.present,
                        'review' => Brand.review,
                        _ => Brand.absent,
                      },
                    ),
                    title: Text(_date(s['date'] as String)),
                    trailing: Text(switch (s['status']) {
                      'present' => 'Present',
                      'review' => 'Under review',
                      _ => 'Absent',
                    }, style: const TextStyle(fontWeight: FontWeight.w600)),
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
    return '${w[d.weekday - 1]}, ${d.day} ${m[d.month - 1]} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
