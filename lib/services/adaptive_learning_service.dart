import 'dart:math';

import '../data/database_helper.dart';
import '../data/models.dart';

/// Rule-based adaptive question selection - a Leitner-box spaced
/// repetition system, the same idea flashcard apps like Anki use. This is
/// NOT machine learning: there's no training, no model, just one fixed
/// rule applied every time a question is answered, plus a weighted random
/// draw when building a game session. Fully offline, fully deterministic
/// in its RULE (only the tie-breaking is random), and explainable in one
/// sentence: "questions you get wrong come back sooner."
///
/// How it works:
///  1. Every question has a "box" from 1 (needs review) to 5 (well
///     known), stored in QuestionProgress. A question the student hasn't
///     answered yet is treated as box 1.
///  2. Answer a question wrong -> box resets to 1.
///     Answer it right -> box goes up by 1, capped at 5.
///  3. When building a game session, each box has a fixed selection
///     weight (box 1 = 5x more likely to be picked than box 5), so weak
///     questions surface more often without ever fully disappearing from
///     rotation.
class AdaptiveLearningService {
  static const int maxBox = 5;
  static const int minBox = 1;

  static const Map<int, int> _boxWeight = {1: 5, 2: 4, 3: 3, 4: 2, 5: 1};

  /// The Leitner-box rule itself - a pure function with no I/O, so it can
  /// be unit tested directly without touching the database.
  static int nextBox(int currentBox, bool wasCorrect) {
    if (!wasCorrect) return minBox;
    return currentBox < maxBox ? currentBox + 1 : maxBox;
  }

  static int weightForBox(int box) => _boxWeight[box] ?? 1;

  /// Call this every time a student answers a question, win or lose.
  static Future<void> recordAnswer(int questionId, bool wasCorrect) async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await db.getQuestionProgress(questionId);

    final updated = QuestionProgress(
      questionId: questionId,
      box: nextBox(existing?.box ?? minBox, wasCorrect),
      timesShown: (existing?.timesShown ?? 0) + 1,
      timesCorrect: (existing?.timesCorrect ?? 0) + (wasCorrect ? 1 : 0),
      lastAnsweredAt: now,
      lastCorrect: wasCorrect,
    );

    await db.saveQuestionProgress(updated);
  }

  /// Builds a game session for [moduleId]/[gameMode]: up to [limit]
  /// questions, weighted so ones the student struggles with show up more
  /// often, without ever completely excluding well-known questions.
  static Future<List<Question>> buildSession(
      int moduleId, String gameMode, int limit) async {
    final rows = await DatabaseHelper.instance
        .getQuestionsWithProgress(moduleId, gameMode);
    if (rows.isEmpty) return [];
    final pool = [
      for (final r in rows)
        (
          question: Question.fromMap(r),
          weight: weightForBox(r['box'] as int? ?? minBox),
        ),
    ];

    return weightedSampleWithoutReplacement(pool, limit, Random());
  }

  /// Weighted random sampling without replacement - takes an injectable
  /// [random] so the selection distribution can be verified in tests
  /// without relying on true randomness.
  static List<Question> weightedSampleWithoutReplacement(
      List<({Question question, int weight})> pool,
      int limit,
      Random random) {
    final remaining = List.of(pool);
    final result = <Question>[];

    while (remaining.isNotEmpty && result.length < limit) {
      final totalWeight = remaining.fold<int>(0, (sum, e) => sum + e.weight);
      var roll = random.nextInt(totalWeight);
      var pickedIndex = remaining.length - 1;
      for (var i = 0; i < remaining.length; i++) {
        if (roll < remaining[i].weight) {
          pickedIndex = i;
          break;
        }
        roll -= remaining[i].weight;
      }
      result.add(remaining.removeAt(pickedIndex).question);
    }
    return result;
  }
}
