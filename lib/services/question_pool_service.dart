import 'dart:math';

import '../data/models.dart';
import 'adaptive_learning_service.dart';

/// Builds the question set a game screen actually plays through.
///
/// "No-repeat" here means: within one built pool, no question appears
/// twice - AdaptiveLearningService.buildSession draws via weighted
/// sampling *without replacement*, so a game session never shows the same
/// question/pair twice even though weaker (low Leitner-box) questions are
/// more likely to be picked. This is the one place all three game modes
/// go to get their questions, so that guarantee lives in a single spot.
class QuestionPoolService {
  /// The question/pair pool for [gameMode]/[difficulty] in [moduleId],
  /// no-repeat shuffled and weighted toward questions the student is still
  /// weak on. Pass [limit] to cap a rolling draw (Quiz/Survival); omit it
  /// to pull the module's entire pool for that mode (Matching, which needs
  /// every pair up front to split into rounds).
  static Future<List<Question>> buildPool(
    int moduleId,
    String gameMode, {
    required String difficulty,
    int limit = 1 << 30,
  }) {
    return AdaptiveLearningService.buildSession(
      moduleId,
      gameMode,
      difficulty,
      limit,
    );
  }

  /// Splits a full Matching-mode pool into fixed-size rounds (5 pairs by
  /// default, per the game design) - the last round may be shorter if the
  /// pool size isn't a multiple of [roundSize].
  static List<List<Question>> chunkIntoRounds(
    List<Question> pool, {
    int roundSize = 5,
  }) {
    final rounds = <List<Question>>[];
    for (var i = 0; i < pool.length; i += roundSize) {
      rounds.add(pool.sublist(i, min(i + roundSize, pool.length)));
    }
    return rounds;
  }
}