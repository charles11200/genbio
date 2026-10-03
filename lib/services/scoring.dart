/// Shared pass/fail threshold for Quiz and Matching mode, which - unlike
/// Survival Mode's lives-based pool-cleared-or-not - have no other
/// intrinsic win/lose state of their own. Used to pick a win or lose sound
/// effect at the end of a round (see SoundService and each game screen's
/// _finish()).
///
/// 75% mirrors the Philippine DepEd K-12 general passing grade - a
/// defensible, locally-familiar cutoff for a formative-assessment app
/// rather than an arbitrary number invented for this feature.
bool isPassingScore(int score, int totalItems) =>
    totalItems > 0 && score / totalItems >= 0.75;
