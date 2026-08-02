/// Data models for the offline Biology review app.
/// These map 1:1 to SQLite table rows via sqflite - see database_helper.dart.
library;

/// A student-imported reviewer: one PDF/PPTX/pasted-notes source becomes
/// one Module, which is then split across the three game modes.
class Module {
  final int? id;
  final String title;
  final String description;
  final String reviewContent; // full extracted/pasted source text

  Module({
    this.id,
    required this.title,
    required this.description,
    required this.reviewContent,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'reviewContent': reviewContent,
  };

  factory Module.fromMap(Map<String, dynamic> map) => Module(
    id: map['id'] as int?,
    title: map['title'] as String,
    description: map['description'] as String,
    reviewContent: map['reviewContent'] as String,
  );
}

class Question {
  final int? id;
  final int moduleId;
  final String questionText;
  final String correctAnswer;
  // Nullable: only 'mcq' rows (quiz/survival) have distractor choices. A
  // 'pair' row (matching) is just questionText=term / correctAnswer=
  // definition and has no choices at all - see questionType.
  final String? choiceA;
  final String? choiceB;
  final String? choiceC;
  final String? choiceD;
  final String source; // 'manual' or 'auto_generated'
  final String difficulty; // easy / medium / hard
  final String theory; // source sentence shown on the post-answer explanation
  final String gameMode; // 'quiz' | 'matching' | 'survival'
  final String questionType; // 'mcq' (quiz/survival) | 'pair' (matching)

  Question({
    this.id,
    required this.moduleId,
    required this.questionText,
    required this.correctAnswer,
    this.choiceA,
    this.choiceB,
    this.choiceC,
    this.choiceD,
    required this.gameMode,
    this.source = 'manual',
    this.difficulty = 'medium',
    this.theory = '',
    this.questionType = 'mcq',
  });

  /// Non-null choices only - always length 4 for a well-formed 'mcq' row,
  /// empty for a 'pair' (matching) row.
  List<String> get choices =>
      [choiceA, choiceB, choiceC, choiceD].whereType<String>().toList();

  Map<String, dynamic> toMap() => {
    'id': id,
    'moduleId': moduleId,
    'questionText': questionText,
    'correctAnswer': correctAnswer,
    'choiceA': choiceA,
    'choiceB': choiceB,
    'choiceC': choiceC,
    'choiceD': choiceD,
    'source': source,
    'difficulty': difficulty,
    'theory': theory,
    'gameMode': gameMode,
    'questionType': questionType,
  };

  factory Question.fromMap(Map<String, dynamic> map) => Question(
    id: map['id'] as int?,
    moduleId: map['moduleId'] as int,
    questionText: map['questionText'] as String,
    correctAnswer: map['correctAnswer'] as String,
    choiceA: map['choiceA'] as String?,
    choiceB: map['choiceB'] as String?,
    choiceC: map['choiceC'] as String?,
    choiceD: map['choiceD'] as String?,
    source: map['source'] as String? ?? 'manual',
    difficulty: map['difficulty'] as String? ?? 'medium',
    theory: map['theory'] as String? ?? '',
    gameMode: map['gameMode'] as String,
    questionType: map['questionType'] as String? ?? 'mcq',
  );
}

/// Per-question memory for the Leitner-box adaptive learning system - see
/// AdaptiveLearningService. One row per question the student has ever
/// answered at least once; unanswered questions simply have no row (and
/// are treated as box 1 - highest priority - by the service).
class QuestionProgress {
  final int questionId;
  final int box; // 1 (needs review) .. 5 (well known)
  final int timesShown;
  final int timesCorrect;
  final int? lastAnsweredAt; // epoch millis
  final bool lastCorrect;

  QuestionProgress({
    required this.questionId,
    this.box = 1,
    this.timesShown = 0,
    this.timesCorrect = 0,
    this.lastAnsweredAt,
    this.lastCorrect = false,
  });

  Map<String, dynamic> toMap() => {
    'questionId': questionId,
    'box': box,
    'timesShown': timesShown,
    'timesCorrect': timesCorrect,
    'lastAnsweredAt': lastAnsweredAt,
    'lastCorrect': lastCorrect ? 1 : 0,
  };

  factory QuestionProgress.fromMap(Map<String, dynamic> map) =>
      QuestionProgress(
        questionId: map['questionId'] as int,
        box: map['box'] as int? ?? 1,
        timesShown: map['timesShown'] as int? ?? 0,
        timesCorrect: map['timesCorrect'] as int? ?? 0,
        lastAnsweredAt: map['lastAnsweredAt'] as int?,
        lastCorrect: (map['lastCorrect'] as int? ?? 0) == 1,
      );
}

/// Every quiz/game attempt - this is the actual research data your capstone
/// needs: formative assessment scores, per game mode / module / student.
class Attempt {
  final int? id;
  final String? studentIdentifier; // use a code per your ethics protocol, not real name
  final String gameMode; // 'quiz' | 'matching' | 'survival'
  final int moduleId;
  final int score;
  final int totalItems;
  final int? timeTakenSeconds;
  final int takenAt; // epoch millis

  Attempt({
    this.id,
    this.studentIdentifier,
    required this.gameMode,
    required this.moduleId,
    required this.score,
    required this.totalItems,
    this.timeTakenSeconds,
    int? takenAt,
  }) : takenAt = takenAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
    'id': id,
    'studentIdentifier': studentIdentifier,
    'gameMode': gameMode,
    'moduleId': moduleId,
    'score': score,
    'totalItems': totalItems,
    'timeTakenSeconds': timeTakenSeconds,
    'takenAt': takenAt,
  };

  factory Attempt.fromMap(Map<String, dynamic> map) => Attempt(
    id: map['id'] as int?,
    studentIdentifier: map['studentIdentifier'] as String?,
    gameMode: map['gameMode'] as String,
    moduleId: map['moduleId'] as int,
    score: map['score'] as int,
    totalItems: map['totalItems'] as int,
    timeTakenSeconds: map['timeTakenSeconds'] as int?,
    takenAt: map['takenAt'] as int,
  );
}
