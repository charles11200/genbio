import 'package:flutter_test/flutter_test.dart';
import 'package:genbio/services/difficulty.dart';

void main() {
  group('Difficulty timers', () {
    test(
        'every difficulty shares the same 30s per-question timer '
        '(regression: difficulty used to also control time pressure - '
        '20/15/10/5s - which confounded content difficulty with speed '
        'pressure as two different variables)', () {
      for (final d in Difficulty.values) {
        expect(d.secondsPerQuestion, 30, reason: '${d.name} per-question timer');
      }
    });

    test('every difficulty shares the same 30s matching-round timer', () {
      for (final d in Difficulty.values) {
        expect(
          d.secondsPerMatchingRound,
          30,
          reason: '${d.name} matching-round timer',
        );
      }
    });
  });

  group('Difficulty.dbValue', () {
    test('maps each enum value to the string QuestionGenerator assigns', () {
      expect(Difficulty.easy.dbValue, 'easy');
      expect(Difficulty.medium.dbValue, 'medium');
      expect(Difficulty.hard.dbValue, 'hard');
      expect(Difficulty.veryHard.dbValue, 'veryHard');
    });

    test('every dbValue is distinct - a collision would silently merge two '
        'difficulty pools in DatabaseHelper.getQuestionsWithProgress', () {
      final values = Difficulty.values.map((d) => d.dbValue).toSet();
      expect(values.length, Difficulty.values.length);
    });
  });
}
