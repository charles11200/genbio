/// Shared difficulty setting for all three game modes - picked once by the
/// student before a round starts (see ModuleSelectScreen) and used to size
/// every timer in the game screens. One enum, one place per-difficulty
/// timing lives, so Quiz/Matching/Survival can't silently drift apart.
enum Difficulty { easy, medium, hard }

extension DifficultyTiming on Difficulty {
  String get label => switch (this) {
    Difficulty.easy => 'Easy',
    Difficulty.medium => 'Medium',
    Difficulty.hard => 'Hard',
  };

  /// Seconds allotted per question in Timed Quiz and Survival mode.
  int get secondsPerQuestion => switch (this) {
    Difficulty.easy => 20,
    Difficulty.medium => 15,
    Difficulty.hard => 10,
  };

  /// Seconds allotted per 5-pair round in Matching mode - one shared clock
  /// for the whole round rather than per-item, since matching is a
  /// find-the-pair task, not a per-question quiz.
  int get secondsPerMatchingRound => switch (this) {
    Difficulty.easy => 75,
    Difficulty.medium => 60,
    Difficulty.hard => 45,
  };
}