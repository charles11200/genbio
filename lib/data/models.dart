/// Data models for the offline Biology review app.
/// These map 1:1 to SQLite table rows via sqflite - see database_helper.dart.

class Topic {
  final int? id;
  final String name; // e.g. "Cell Structure", "Genetics", "Ecology"

  Topic({this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory Topic.fromMap(Map<String, dynamic> map) =>
      Topic(id: map['id'] as int?, name: map['name'] as String);
}

class Question {
  final int? id;
  final int topicId;
  final String questionText;
  final String correctAnswer;
  final String choiceA;
  final String choiceB;
  final String choiceC;
  final String choiceD;
  final String source; // 'manual' or 'auto_generated'
  final String difficulty; // easy / medium / hard

  Question({
    this.id,
    required this.topicId,
    required this.questionText,
    required this.correctAnswer,
    required this.choiceA,
    required this.choiceB,
    required this.choiceC,
    required this.choiceD,
    this.source = 'manual',
    this.difficulty = 'medium',
  });

  List<String> get choices => [choiceA, choiceB, choiceC, choiceD];

  Map<String, dynamic> toMap() => {
    'id': id,
    'topicId': topicId,
    'questionText': questionText,
    'correctAnswer': correctAnswer,
    'choiceA': choiceA,
    'choiceB': choiceB,
    'choiceC': choiceC,
    'choiceD': choiceD,
    'source': source,
    'difficulty': difficulty,
  };

  factory Question.fromMap(Map<String, dynamic> map) => Question(
    id: map['id'] as int?,
    topicId: map['topicId'] as int,
    questionText: map['questionText'] as String,
    correctAnswer: map['correctAnswer'] as String,
    choiceA: map['choiceA'] as String,
    choiceB: map['choiceB'] as String,
    choiceC: map['choiceC'] as String,
    choiceD: map['choiceD'] as String,
    source: map['source'] as String? ?? 'manual',
    difficulty: map['difficulty'] as String? ?? 'medium',
  );
}

/// Every quiz/game attempt - this is the actual research data your capstone
/// needs: formative assessment scores, per game mode / topic / student.
class Attempt {
  final int? id;
  final String? studentIdentifier; // use a code per your ethics protocol, not real name
  final String gameMode; // 'quiz' | 'matching' | 'survival'
  final int topicId;
  final int score;
  final int totalItems;
  final int? timeTakenSeconds;
  final int takenAt; // epoch millis

  Attempt({
    this.id,
    this.studentIdentifier,
    required this.gameMode,
    required this.topicId,
    required this.score,
    required this.totalItems,
    this.timeTakenSeconds,
    int? takenAt,
  }) : takenAt = takenAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
    'id': id,
    'studentIdentifier': studentIdentifier,
    'gameMode': gameMode,
    'topicId': topicId,
    'score': score,
    'totalItems': totalItems,
    'timeTakenSeconds': timeTakenSeconds,
    'takenAt': takenAt,
  };

  factory Attempt.fromMap(Map<String, dynamic> map) => Attempt(
    id: map['id'] as int?,
    studentIdentifier: map['studentIdentifier'] as String?,
    gameMode: map['gameMode'] as String,
    topicId: map['topicId'] as int,
    score: map['score'] as int,
    totalItems: map['totalItems'] as int,
    timeTakenSeconds: map['timeTakenSeconds'] as int?,
    takenAt: map['takenAt'] as int,
  );
}