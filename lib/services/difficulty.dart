/// Shared difficulty setting for all three game modes - picked once by the
/// student before a round starts (see ModuleSelectScreen).
///
/// Difficulty now selects WHICH questions get played, not how fast you
/// have to answer them: QuestionGenerator tags every generated question
/// with a difficulty tier (see its _assignDifficulties), and each game
/// screen's question pool is filtered to the chosen tier via [dbValue].
/// Every tier shares the same flat timer (see secondsPerQuestion /
/// secondsPerMatchingRound) precisely so that time pressure isn't a second,
/// confounding variable alongside content difficulty - a student comparing
/// Easy and Hard rounds is only ever comparing question content.
enum Difficulty { easy, medium, hard, veryHard }

extension DifficultyTiming on Difficulty {
  String get label => switch (this) {
    Difficulty.easy => 'Easy',
    Difficulty.medium => 'Medium',
    Difficulty.hard => 'Hard',
    Difficulty.veryHard => 'Very Hard',
  };

  /// The value stored in Question.difficulty - see
  /// QuestionGenerator's difficulty tiering and
  /// DatabaseHelper.getQuestionsWithProgress, which filters on it.
  String get dbValue => switch (this) {
    Difficulty.easy => 'easy',
    Difficulty.medium => 'medium',
    Difficulty.hard => 'hard',
    Difficulty.veryHard => 'veryHard',
  };

  /// Seconds allotted per question in Timed Quiz and Survival mode. Flat
  /// across every difficulty - see the class doc for why.
  int get secondsPerQuestion => 30;

  /// Seconds allotted per 5-pair round in Matching mode - one shared clock
  /// for the whole round rather than per-item, since matching is a
  /// find-the-pair task, not a per-question quiz. Flat across every
  /// difficulty, same reasoning as secondsPerQuestion.
  int get secondsPerMatchingRound => 30;
}
