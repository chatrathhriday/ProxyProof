import 'package:flutter_test/flutter_test.dart';
import 'package:proxyproof/screens/history_screen.dart';

void main() {
  test('can skip: largest k with A/(T+k) >= 75%', () {
    expect(canSkip(30, 40), 0); // exactly 75%: one more skip drops below
    expect(canSkip(9, 10), 2); // 9/12 = 75%, 9/13 < 75%
    expect(canSkip(0, 0), 0);
    expect(canSkip(5, 10), 0);
  });

  test('must attend: smallest m with (A+m)/(T+m) >= 75%', () {
    expect(mustAttend(5, 10), 10); // 15/20 = 75%
    expect(mustAttend(30, 40), 0);
    expect(mustAttend(7, 10), 2); // 9/12 = 75%
    expect(mustAttend(0, 1), 3); // 3/4 = 75%
  });
}
