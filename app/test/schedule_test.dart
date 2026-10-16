import 'package:flutter_test/flutter_test.dart';
import 'package:proxyproof/schedule.dart';

void main() {
  final courses = [
    {
      'code': 'MAT2002',
      'name': 'Discrete Mathematics',
      'schedule': [
        {'d': 2, 's': '11:00', 'e': '11:50', 'room': 'MB 210'},
      ],
    },
    {
      'code': 'CSE1001',
      'name': 'Intro',
      'schedule': [
        {'d': 2, 's': '09:00', 'e': '09:50', 'room': 'SJT 304'},
        {'d': 3, 's': '09:00', 'e': '09:50', 'room': 'SJT 304'},
      ],
    },
  ];

  test('classes on a day are sorted', () {
    final tue = DateTime(2026, 10, 13); // a Tuesday
    expect(classesOn(courses, tue).map((s) => s.code), ['CSE1001', 'MAT2002']);
  });

  test('next class: live now, later today, or next day', () {
    expect(nextClass(courses, DateTime(2026, 10, 13, 9, 20))!.code, 'CSE1001'); // live
    expect(nextClass(courses, DateTime(2026, 10, 13, 10, 0))!.code, 'MAT2002');
    final wed = nextClass(courses, DateTime(2026, 10, 13, 12, 0))!;
    expect([wed.code, wed.start.weekday], ['CSE1001', 3]);
  });

  test('countdown text', () {
    final now = DateTime(2026, 10, 13, 10, 0);
    expect(countdown(now, DateTime(2026, 10, 13, 11, 20)), 'in 1 h 20 min');
    expect(countdown(now, DateTime(2026, 10, 13, 10, 5)), 'in 5 min');
  });
}
