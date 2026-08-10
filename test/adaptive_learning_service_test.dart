import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbio/data/models.dart';
import 'package:genbio/services/adaptive_learning_service.dart';

Question _q(int id) => Question(
      id: id,
      moduleId: 1,
      questionText: 'Q$id',
      correctAnswer: 'A',
      choiceA: 'A',
      choiceB: 'B',
      choiceC: 'C',
      choiceD: 'D',
      gameMode: 'quiz',
    );

void main() {
  group('AdaptiveLearningService.nextBox', () {
    test('a wrong answer always resets to box 1, regardless of current box',
        () {
      expect(AdaptiveLearningService.nextBox(1, false), 1);
      expect(AdaptiveLearningService.nextBox(3, false), 1);
      expect(AdaptiveLearningService.nextBox(5, false), 1);
    });

    test('a correct answer promotes the box by exactly 1', () {
      expect(AdaptiveLearningService.nextBox(1, true), 2);
      expect(AdaptiveLearningService.nextBox(2, true), 3);
    });

    test('a correct answer never promotes past the max box', () {
      expect(AdaptiveLearningService.nextBox(5, true),
          AdaptiveLearningService.maxBox);
    });
  });

  group('AdaptiveLearningService.weightForBox', () {
    test('lower boxes (weaker questions) get higher weight', () {
      final weights = [
        for (var box = 1; box <= 5; box++)
          AdaptiveLearningService.weightForBox(box),
      ];
      for (var i = 0; i < weights.length - 1; i++) {
        expect(weights[i], greaterThan(weights[i + 1]));
      }
    });

    test('an unknown box defaults to the lowest weight', () {
      expect(AdaptiveLearningService.weightForBox(99), 1);
    });
  });

  group('AdaptiveLearningService.weightedSampleWithoutReplacement', () {
    test('never returns duplicate questions', () {
      final pool = [
        for (var i = 1; i <= 10; i++) (question: _q(i), weight: 1),
      ];
      final result = AdaptiveLearningService.weightedSampleWithoutReplacement(
          pool, 10, Random(1));
      final ids = result.map((q) => q.id).toSet();
      expect(ids.length, 10);
    });

    test('returns at most the pool size even if limit is larger', () {
      final pool = [
        for (var i = 1; i <= 3; i++) (question: _q(i), weight: 1),
      ];
      final result = AdaptiveLearningService.weightedSampleWithoutReplacement(
          pool, 100, Random(1));
      expect(result.length, 3);
    });

    test(
        'a pool larger than the old hardcoded 15-question quiz cap is '
        'returned in full (regression: QuizGameScreen passed limit:15, so '
        'a student who chose 50 questions at import silently played only '
        '15 of them)', () {
      final pool = [
        for (var i = 1; i <= 50; i++) (question: _q(i), weight: 1),
      ];
      final result = AdaptiveLearningService.weightedSampleWithoutReplacement(
          pool, 1 << 30, Random(1));
      expect(result.length, 50);
    });

    test('heavily favors high-weight (weak/box-1) questions over many draws',
        () {
      final pool = [
        (question: _q(1), weight: AdaptiveLearningService.weightForBox(1)),
        (question: _q(5), weight: AdaptiveLearningService.weightForBox(5)),
      ];

      var box1Picks = 0;
      var box5Picks = 0;
      final random = Random(42);
      for (var trial = 0; trial < 500; trial++) {
        final picked = AdaptiveLearningService
            .weightedSampleWithoutReplacement(pool, 1, random)
            .first;
        if (picked.id == 1) box1Picks++;
        if (picked.id == 5) box5Picks++;
      }

      expect(box1Picks, greaterThan(box5Picks));
    });
  });
}
