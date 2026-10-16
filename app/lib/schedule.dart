/// Weekly timetable helpers. A course's schedule is a list of slots:
/// {"d": 1..7 (Mon..Sun), "s": "09:00", "e": "09:50", "room": "SJT 304"} in local (IST) time.
class Slot {
  Slot({required this.code, required this.name, required this.start, required this.end, required this.room});
  final String code, name, room;
  final DateTime start, end;

  bool isLive(DateTime now) => !now.isBefore(start) && now.isBefore(end);
  bool isDone(DateTime now) => !now.isBefore(end);
}

DateTime _at(DateTime day, String hhmm) {
  final p = hhmm.split(':');
  return DateTime(day.year, day.month, day.day, int.parse(p[0]), int.parse(p[1]));
}

/// All classes on [day], sorted by start time.
List<Slot> classesOn(List courses, DateTime day) {
  final out = <Slot>[];
  for (final c in courses) {
    for (final s in (c['schedule'] as List? ?? const [])) {
      if (s['d'] != day.weekday) continue;
      out.add(
        Slot(
          code: '${c['code']}',
          name: '${c['name']}',
          start: _at(day, s['s'] as String),
          end: _at(day, s['e'] as String),
          room: '${s['room'] ?? ''}',
        ),
      );
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// The class happening now, or the next one within the coming week.
Slot? nextClass(List courses, DateTime now) {
  for (var i = 0; i < 8; i++) {
    final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
    for (final s in classesOn(courses, day)) {
      if (!s.isDone(now)) return s;
    }
  }
  return null;
}

/// "in 1 h 20 min", "in 5 min", "now".
String countdown(DateTime now, DateTime when) {
  final m = when.difference(now).inMinutes;
  if (m <= 0) return 'now';
  if (m < 60) return 'in $m min';
  if (m < 24 * 60) return 'in ${m ~/ 60} h ${m % 60} min';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[when.weekday - 1]} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
}
