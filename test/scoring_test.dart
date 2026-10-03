import 'package:flutter_test/flutter_test.dart';
import 'package:genbio/services/scoring.dart';

void main() {
  group('isPassingScore', () {
    test('exactly 75% passes (the DepEd general passing grade)', () {
      expect(isPassingScore(3, 4), isTrue);
      expect(isPassingScore(75, 100), isTrue);
    });

    test('just under 75% fails', () {
      expect(isPassingScore(74, 100), isFalse);
      expect(isPassingScore(2, 3), isFalse); // 66.7%
    });

    test('a perfect score passes', () {
      expect(isPassingScore(10, 10), isTrue);
    });

    test('a zero score fails', () {
      expect(isPassingScore(0, 10), isFalse);
    });

    test('zero total items never passes (regression: score/totalItems is a '
        'division by zero for an empty round, which must not read as a '
        'win)', () {
      expect(isPassingScore(0, 0), isFalse);
    });
  });
}
