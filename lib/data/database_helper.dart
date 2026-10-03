import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'models.dart';

/// Single local SQLite file on the device - genbio_review.db.
/// This IS the offline storage; there is no server counterpart anywhere.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  // v2: choiceA-D became nullable - a 'pair' (matching) row has no MCQ
  // distractors at all, rather than empty-string placeholders.
  static const String _createQuestionsSqlV2 = '''
    CREATE TABLE questions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      moduleId INTEGER NOT NULL,
      questionText TEXT NOT NULL,
      correctAnswer TEXT NOT NULL,
      choiceA TEXT,
      choiceB TEXT,
      choiceC TEXT,
      choiceD TEXT,
      source TEXT DEFAULT 'manual',
      difficulty TEXT DEFAULT 'medium',
      theory TEXT DEFAULT '',
      gameMode TEXT NOT NULL,
      questionType TEXT DEFAULT 'mcq',
      FOREIGN KEY (moduleId) REFERENCES modules(id) ON DELETE CASCADE
    )
  ''';

  // v3: added `verified` - originally gated a post-import review/edit
  // step that has since been removed in favor of playing immediately
  // after import (see Question.verified). Left in place rather than
  // attempting a drop-column migration on a schema already shipped to
  // real devices; every row is DEFAULT 1 now, so the filter in
  // getQuestionsWithProgress is effectively always true.
  static const String _addVerifiedColumnSql =
      'ALTER TABLE questions ADD COLUMN verified INTEGER NOT NULL DEFAULT 1';

  // v4: added `mistakes` to attempts - wrong-match count for Matching mode
  // (see MatchingGameScreen), shown alongside score on ResultsScreen and
  // kept as research data the same way score/totalItems already are.
  // DEFAULT 0 so old rows (all pre-dating this column, all quiz/survival at
  // the time) read as "no mistakes tracked" rather than NULL.
  static const String _addMistakesColumnSql =
      'ALTER TABLE attempts ADD COLUMN mistakes INTEGER NOT NULL DEFAULT 0';

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'genbio_review.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE modules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            reviewContent TEXT NOT NULL
          )
        ''');
        await db.execute(_createQuestionsSqlV2);
        await db.execute(_addVerifiedColumnSql);
        await db.execute('''
          CREATE TABLE attempts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            studentIdentifier TEXT,
            gameMode TEXT NOT NULL,
            moduleId INTEGER NOT NULL,
            score INTEGER NOT NULL,
            totalItems INTEGER NOT NULL,
            timeTakenSeconds INTEGER,
            takenAt INTEGER NOT NULL
          )
        ''');
        await db.execute(_addMistakesColumnSql);
        await db.execute('''
          CREATE TABLE question_progress (
            questionId INTEGER PRIMARY KEY,
            box INTEGER NOT NULL DEFAULT 1,
            timesShown INTEGER NOT NULL DEFAULT 0,
            timesCorrect INTEGER NOT NULL DEFAULT 0,
            lastAnsweredAt INTEGER,
            lastCorrect INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (questionId) REFERENCES questions(id) ON DELETE CASCADE
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // SQLite can't ALTER COLUMN to drop NOT NULL, so rebuild the
          // table: rename old, create the new nullable-choices version,
          // copy rows across, drop the old one. Existing quiz/survival
          // rows are unaffected (their choices were always non-null).
          await db.execute('ALTER TABLE questions RENAME TO questions_v1');
          await db.execute(_createQuestionsSqlV2);
          await db.execute('''
            INSERT INTO questions
              (id, moduleId, questionText, correctAnswer, choiceA, choiceB,
               choiceC, choiceD, source, difficulty, theory, gameMode,
               questionType)
            SELECT
              id, moduleId, questionText, correctAnswer, choiceA, choiceB,
              choiceC, choiceD, source, difficulty, theory, gameMode,
              questionType
            FROM questions_v1
          ''');
          await db.execute('DROP TABLE questions_v1');
        }
        if (oldVersion < 3) {
          await db.execute(_addVerifiedColumnSql);
        }
        if (oldVersion < 4) {
          await db.execute(_addMistakesColumnSql);
        }
      },
    );
  }

  // ---------- Modules ----------

  Future<int> insertModule(Module module) async {
    final db = await database;
    final map = module.toMap()..remove('id');
    return db.insert('modules', map);
  }

  Future<List<Module>> getAllModules() async {
    final db = await database;
    final rows = await db.query('modules', orderBy: 'id DESC');
    return rows.map((r) => Module.fromMap(r)).toList();
  }

  Future<Module?> getModule(int id) async {
    final db = await database;
    final rows = await db.query('modules', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Module.fromMap(rows.first);
  }

  // ---------- Questions ----------

  Future<int> insertQuestion(Question q) async {
    final db = await database;
    final map = q.toMap()..remove('id');
    return db.insert('questions', map);
  }

  Future<void> insertQuestions(List<Question> questions) async {
    final db = await database;
    final batch = db.batch();
    for (final q in questions) {
      final map = q.toMap()..remove('id');
      batch.insert('questions', map);
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateQuestion(Question q) async {
    final db = await database;
    await db.update('questions', q.toMap(), where: 'id = ?', whereArgs: [q.id]);
  }

  Future<void> deleteQuestion(int id) async {
    final db = await database;
    await db.delete('questions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Question>> getQuestionsByModuleAndGameMode(
      int moduleId, String gameMode) async {
    final db = await database;
    final rows = await db.query(
      'questions',
      where: 'moduleId = ? AND gameMode = ?',
      whereArgs: [moduleId, gameMode],
    );
    return rows.map((r) => Question.fromMap(r)).toList();
  }

  Future<List<Question>> getRandomQuestions(int limit) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT * FROM questions ORDER BY RANDOM() LIMIT ?',
      [limit],
    );
    return rows.map((r) => Question.fromMap(r)).toList();
  }

  // ---------- Attempts (research data) ----------

  Future<int> insertAttempt(Attempt a) async {
    final db = await database;
    final map = a.toMap()..remove('id');
    return db.insert('attempts', map);
  }

  Future<List<Attempt>> getAllAttempts() async {
    final db = await database;
    final rows = await db.query('attempts', orderBy: 'takenAt DESC');
    return rows.map((r) => Attempt.fromMap(r)).toList();
  }

  /// Per-game-mode attempt count and average accuracy for one module -
  /// this is the aggregate view your capstone results chapter needs
  /// (raw per-attempt rows are in getAllAttempts()).
  Future<Map<String, Map<String, dynamic>>> getModuleStats(
      int moduleId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        gameMode,
        COUNT(*) AS attemptCount,
        AVG(score * 1.0 / totalItems) AS avgAccuracy
      FROM attempts
      WHERE moduleId = ?
      GROUP BY gameMode
    ''', [moduleId]);

    return {
      for (final r in rows)
        r['gameMode'] as String: {
          'attemptCount': r['attemptCount'] as int,
          'avgAccuracy': (r['avgAccuracy'] as num?)?.toDouble() ?? 0.0,
        },
    };
  }

  // ---------- Question progress (adaptive learning memory) ----------

  Future<QuestionProgress?> getQuestionProgress(int questionId) async {
    final db = await database;
    final rows = await db.query('question_progress',
        where: 'questionId = ?', whereArgs: [questionId], limit: 1);
    return rows.isEmpty ? null : QuestionProgress.fromMap(rows.first);
  }

  Future<void> saveQuestionProgress(QuestionProgress progress) async {
    final db = await database;
    await db.insert(
      'question_progress',
      progress.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Questions for a module/game mode/difficulty, each annotated with its
  /// current Leitner box (defaults to 1 - highest priority - for questions
  /// the student hasn't answered yet). This is the single query every game
  /// mode's pool ultimately draws from (via QuestionPoolService).
  ///
  /// Selection is by questionType, NOT gameMode: Quiz and Survival are
  /// both 4-choice MCQ modes that differ only in their rules (fixed
  /// length vs lives), so they draw from the SAME full 'mcq' pool.
  /// Previously each MCQ row was tagged for one mode or the other and the
  /// two modes split the pool in half, which is what starved Survival of
  /// questions.
  ///
  /// [difficulty] is Difficulty.dbValue (easy/medium/hard/veryHard) - see
  /// QuestionGenerator's difficulty tiering for how a question ends up
  /// tagged with one.
  Future<List<Map<String, dynamic>>> getQuestionsWithProgress(
      int moduleId, String gameMode, String difficulty) async {
    final db = await database;
    final questionType = gameMode == 'matching' ? 'pair' : 'mcq';
    return db.rawQuery('''
      SELECT q.*, COALESCE(p.box, 1) AS box
      FROM questions q
      LEFT JOIN question_progress p ON p.questionId = q.id
      WHERE q.moduleId = ? AND q.questionType = ? AND q.verified = 1
        AND q.difficulty = ?
    ''', [moduleId, questionType, difficulty]);
  }

  /// Questions the student is still struggling with (box <= [maxBox]) -
  /// backs a "Review Mistakes" style feature.
  Future<List<Question>> getWeakQuestions(int moduleId, {int maxBox = 2}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT q.*
      FROM questions q
      JOIN question_progress p ON p.questionId = q.id
      WHERE q.moduleId = ? AND p.box <= ?
    ''', [moduleId, maxBox]);
    return rows.map((r) => Question.fromMap(r)).toList();
  }

  // ---------- Aggregate stats (capstone Chapter 4 results) ----------

  /// Average score across every attempt for [moduleId], as a percentage
  /// of totalItems. 0.0 if the module has no attempts yet (AVG() over
  /// zero rows is NULL, not 0, in SQL).
  Future<double> getAverageScoreByModule(int moduleId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT AVG(score * 100.0 / totalItems) AS avgScore
      FROM attempts
      WHERE moduleId = ? AND totalItems > 0
    ''', [moduleId]);
    return (rows.first['avgScore'] as num?)?.toDouble() ?? 0.0;
  }

  /// Average score across every attempt for [gameMode], across all
  /// modules. 0.0 if that game mode has no attempts yet.
  Future<double> getAverageScoreByGameMode(String gameMode) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT AVG(score * 100.0 / totalItems) AS avgScore
      FROM attempts
      WHERE gameMode = ? AND totalItems > 0
    ''', [gameMode]);
    return (rows.first['avgScore'] as num?)?.toDouble() ?? 0.0;
  }

  /// Average score for [moduleId], broken down per game mode - e.g.
  /// {'quiz': 85.2, 'matching': 72.1, 'survival': 60.0}. A game mode the
  /// student hasn't attempted for this module is simply absent from the
  /// map rather than present with a 0.0.
  Future<Map<String, double>> getAverageScoreByGameModeForModule(
      int moduleId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT gameMode, AVG(score * 100.0 / totalItems) AS avgScore
      FROM attempts
      WHERE moduleId = ? AND totalItems > 0
      GROUP BY gameMode
    ''', [moduleId]);
    return {
      for (final r in rows)
        r['gameMode'] as String: (r['avgScore'] as num?)?.toDouble() ?? 0.0,
    };
  }
}
