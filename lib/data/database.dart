import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// One SQLite file holds the downloaded content packs and everything the
/// student does, so the whole app works offline. Rows with `synced = 0` are
/// pushed to the server when a connection is available.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _version = 1;

  static Future<AppDatabase> open(String path, {DatabaseFactory? factory}) async {
    final options = OpenDatabaseOptions(version: _version, onCreate: (db, _) => _create(db));
    final db = factory == null
        ? await openDatabase(path, version: options.version, onCreate: options.onCreate)
        : await factory.openDatabase(path, options: options);
    return AppDatabase._(db);
  }

  static Future<void> _create(Database db) async {
    final batch = db.batch()
      ..execute('CREATE TABLE packs (grade_id TEXT PRIMARY KEY, version INTEGER NOT NULL, json TEXT NOT NULL)')
      ..execute('''CREATE TABLE lesson_progress (
          lesson_id TEXT PRIMARY KEY, subject_id TEXT NOT NULL,
          opened_at INTEGER NOT NULL, completed_at INTEGER, synced INTEGER NOT NULL DEFAULT 0)''')
      ..execute('''CREATE TABLE attempts (
          id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, title TEXT NOT NULL,
          subject_id TEXT, lesson_id TEXT, exam_id TEXT, started_at INTEGER NOT NULL, duration_sec INTEGER NOT NULL,
          score REAL NOT NULL, max_score REAL NOT NULL, synced INTEGER NOT NULL DEFAULT 0)''')
      ..execute('''CREATE TABLE answers (
          attempt_id INTEGER NOT NULL, question_id TEXT NOT NULL, lesson_id TEXT NOT NULL, subject_id TEXT NOT NULL,
          score REAL NOT NULL, answered_at INTEGER NOT NULL)''')
      ..execute('CREATE INDEX answers_lesson ON answers (lesson_id)')
      ..execute(
        'CREATE TABLE bookmarks (book_id TEXT NOT NULL, page INTEGER NOT NULL, created_at INTEGER NOT NULL, '
        'PRIMARY KEY (book_id, page))',
      )
      ..execute('CREATE TABLE activity_days (day TEXT PRIMARY KEY)');
    await batch.commit(noResult: true);
  }

  Future<void> close() => db.close();
}

/// Stores grade packs (raw JSON) and tracks their versions.
class PackStore {
  PackStore(this._db);

  final AppDatabase _db;

  Future<int?> version(String gradeId) async {
    final rows = await _db.db.query('packs', columns: ['version'], where: 'grade_id = ?', whereArgs: [gradeId]);
    return rows.isEmpty ? null : rows.first['version'] as int;
  }

  Future<Map<String, int>> versions() async {
    final rows = await _db.db.query('packs', columns: ['grade_id', 'version']);
    return {for (final r in rows) r['grade_id'] as String: r['version'] as int};
  }

  /// Validates by parsing before writing, so a bad download never replaces a
  /// working pack.
  Future<GradePack> save(String json) async {
    final pack = GradePack.fromJson(jsonDecode(json) as Map<String, dynamic>);
    await _db.db.insert('packs', {
      'grade_id': pack.gradeId,
      'version': pack.version,
      'json': json,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return pack;
  }

  Future<GradePack?> load(String gradeId) async {
    final rows = await _db.db.query('packs', columns: ['json'], where: 'grade_id = ?', whereArgs: [gradeId]);
    if (rows.isEmpty) return null;
    return GradePack.fromJson(jsonDecode(rows.first['json'] as String) as Map<String, dynamic>);
  }
}

enum AttemptKind {
  practice('تدريب'),
  quiz('اختبرني'),
  exam('امتحان تجريبي'),
  challenge('تحدي اليوم');

  const AttemptKind(this.label);

  final String label;

  static AttemptKind parse(String v) => AttemptKind.values.firstWhere((k) => k.name == v, orElse: () => quiz);
}

class AttemptRecord {
  const AttemptRecord({
    required this.uid,
    required this.kind,
    required this.title,
    required this.startedAt,
    required this.duration,
    required this.score,
    required this.maxScore,
    this.id,
    this.subjectId,
    this.lessonId,
    this.examId,
  });

  factory AttemptRecord.fromRow(Map<String, Object?> r) => AttemptRecord(
    id: r['id'] as int,
    uid: r['uid'] as String,
    kind: AttemptKind.parse(r['kind'] as String),
    title: r['title'] as String,
    subjectId: r['subject_id'] as String?,
    lessonId: r['lesson_id'] as String?,
    examId: r['exam_id'] as String?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
    duration: Duration(seconds: r['duration_sec'] as int),
    score: (r['score'] as num).toDouble(),
    maxScore: (r['max_score'] as num).toDouble(),
  );

  final int? id;
  final String uid;
  final AttemptKind kind;
  final String title;
  final String? subjectId;
  final String? lessonId;
  final String? examId;
  final DateTime startedAt;
  final Duration duration;
  final double score;
  final double maxScore;

  double get ratio => maxScore == 0 ? 0 : score / maxScore;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'kind': kind.name,
    'title': title,
    'subject_id': subjectId,
    'lesson_id': lessonId,
    'exam_id': examId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'duration_sec': duration.inSeconds,
    'score': score,
    'max_score': maxScore,
  };
}

class AnswerRecord {
  const AnswerRecord({
    required this.questionId,
    required this.lessonId,
    required this.subjectId,
    required this.score,
    required this.answeredAt,
  });

  final String questionId;
  final String lessonId;
  final String subjectId;

  /// 0..1 (partial credit for matching).
  final double score;
  final DateTime answeredAt;
}

class LessonProgressRow {
  const LessonProgressRow({required this.lessonId, required this.subjectId, required this.openedAt, this.completedAt});

  final String lessonId;
  final String subjectId;
  final DateTime openedAt;
  final DateTime? completedAt;

  bool get completed => completedAt != null;
}

/// Everything the student does, stored locally.
class ProgressRepository {
  ProgressRepository(this._db);

  final AppDatabase _db;

  Database get _sql => _db.db;

  static String dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  Future<void> recordActivity(DateTime now) =>
      _sql.insert('activity_days', {'day': dayKey(now)}, conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<Set<String>> activityDays() async => {for (final r in await _sql.query('activity_days')) r['day'] as String};

  Future<void> openLesson(Lesson lesson, DateTime now) async {
    await _sql.rawInsert(
      'INSERT INTO lesson_progress (lesson_id, subject_id, opened_at) VALUES (?, ?, ?) '
      'ON CONFLICT(lesson_id) DO UPDATE SET opened_at = excluded.opened_at',
      [lesson.id, lesson.subjectId, now.millisecondsSinceEpoch],
    );
    await recordActivity(now);
  }

  Future<void> completeLesson(Lesson lesson, DateTime now) async {
    await openLesson(lesson, now);
    await _sql.update(
      'lesson_progress',
      {'completed_at': now.millisecondsSinceEpoch, 'synced': 0},
      where: 'lesson_id = ? AND completed_at IS NULL',
      whereArgs: [lesson.id],
    );
  }

  Future<Map<String, LessonProgressRow>> lessonProgress() async {
    final rows = await _sql.query('lesson_progress');
    return {
      for (final r in rows)
        r['lesson_id'] as String: LessonProgressRow(
          lessonId: r['lesson_id'] as String,
          subjectId: r['subject_id'] as String,
          openedAt: DateTime.fromMillisecondsSinceEpoch(r['opened_at'] as int),
          completedAt: r['completed_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['completed_at'] as int),
        ),
    };
  }

  Future<int> saveAttempt(AttemptRecord attempt, List<AnswerRecord> answers) async {
    return _sql.transaction((txn) async {
      final id = await txn.insert('attempts', {
        'uid': attempt.uid,
        'kind': attempt.kind.name,
        'title': attempt.title,
        'subject_id': attempt.subjectId,
        'lesson_id': attempt.lessonId,
        'exam_id': attempt.examId,
        'started_at': attempt.startedAt.millisecondsSinceEpoch,
        'duration_sec': attempt.duration.inSeconds,
        'score': attempt.score,
        'max_score': attempt.maxScore,
      });
      final batch = txn.batch();
      for (final a in answers) {
        batch.insert('answers', {
          'attempt_id': id,
          'question_id': a.questionId,
          'lesson_id': a.lessonId,
          'subject_id': a.subjectId,
          'score': a.score,
          'answered_at': a.answeredAt.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
      await txn.insert('activity_days', {
        'day': dayKey(attempt.startedAt.add(attempt.duration)),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return id;
    });
  }

  Future<List<AttemptRecord>> attempts({int? limit}) async {
    final rows = await _sql.query('attempts', orderBy: 'started_at DESC', limit: limit);
    return rows.map(AttemptRecord.fromRow).toList();
  }

  Future<List<AnswerRecord>> answers() async {
    final rows = await _sql.query('answers', orderBy: 'answered_at');
    return [
      for (final r in rows)
        AnswerRecord(
          questionId: r['question_id'] as String,
          lessonId: r['lesson_id'] as String,
          subjectId: r['subject_id'] as String,
          score: (r['score'] as num).toDouble(),
          answeredAt: DateTime.fromMillisecondsSinceEpoch(r['answered_at'] as int),
        ),
    ];
  }

  Future<List<int>> bookmarks(String bookId) async {
    final rows = await _sql.query('bookmarks', where: 'book_id = ?', whereArgs: [bookId], orderBy: 'page');
    return [for (final r in rows) r['page'] as int];
  }

  /// Returns true when the page is bookmarked after the call.
  Future<bool> toggleBookmark(String bookId, int page, DateTime now) async {
    final removed = await _sql.delete('bookmarks', where: 'book_id = ? AND page = ?', whereArgs: [bookId, page]);
    if (removed > 0) return false;
    await _sql.insert('bookmarks', {'book_id': bookId, 'page': page, 'created_at': now.millisecondsSinceEpoch});
    return true;
  }

  Future<List<AttemptRecord>> unsyncedAttempts() async {
    final rows = await _sql.query('attempts', where: 'synced = 0', orderBy: 'id', limit: 100);
    return rows.map(AttemptRecord.fromRow).toList();
  }

  Future<void> markAttemptsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    await _sql.update(
      'attempts',
      {'synced': 1},
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  /// Deletes the student's activity (content packs are kept).
  Future<void> clear() async {
    final batch = _sql.batch();
    for (final t in ['lesson_progress', 'attempts', 'answers', 'bookmarks', 'activity_days']) {
      batch.delete(t);
    }
    await batch.commit(noResult: true);
  }
}
