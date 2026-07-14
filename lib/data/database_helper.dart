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

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'genbio_review.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE admin (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            username TEXT NOT NULL,
            passwordHash TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE topics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE questions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            topicId INTEGER NOT NULL,
            questionText TEXT NOT NULL,
            correctAnswer TEXT NOT NULL,
            choiceA TEXT NOT NULL,
            choiceB TEXT NOT NULL,
            choiceC TEXT NOT NULL,
            choiceD TEXT NOT NULL,
            source TEXT DEFAULT 'manual',
            difficulty TEXT DEFAULT 'medium',
            FOREIGN KEY (topicId) REFERENCES topics(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE attempts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            studentIdentifier TEXT,
            gameMode TEXT NOT NULL,
            topicId INTEGER NOT NULL,
            score INTEGER NOT NULL,
            totalItems INTEGER NOT NULL,
            timeTakenSeconds INTEGER,
            takenAt INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  // ---------- Admin ----------

  Future<Map<String, dynamic>?> getAdmin() async {
    final db = await database;
    final rows = await db.query('admin', where: 'id = 1', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertAdmin(String username, String passwordHash) async {
    final db = await database;
    await db.insert(
      'admin',
      {'id': 1, 'username': username, 'passwordHash': passwordHash},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------- Topics ----------

  Future<int> insertTopic(Topic topic) async {
    final db = await database;
    return db.insert('topics', {'name': topic.name});
  }

  Future<List<Topic>> getAllTopics() async {
    final db = await database;
    final rows = await db.query('topics', orderBy: 'name ASC');
    return rows.map((r) => Topic.fromMap(r)).toList();
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

  Future<List<Question>> getQuestionsByTopic(int topicId) async {
    final db = await database;
    final rows =
    await db.query('questions', where: 'topicId = ?', whereArgs: [topicId]);
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
}