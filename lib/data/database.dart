import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// One SQLite file holds the downloaded content packs, the students who use
/// this device, and everything each of them does, so the whole app works
/// offline. Every activity row carries its `profile_id`, so students sharing
/// a phone never see each other's progress. Rows with `synced = 0` are pushed
/// to the server when a connection is available.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _version = 2;

  /// Profile id given to activity recorded before multi-student support.
  static const legacyProfileId = 'legacy';

  static Future<AppDatabase> open(String path, {DatabaseFactory? factory}) async {
    final options = OpenDatabaseOptions(
      version: _version,
      onCreate: (db, _) => _create(db),
      onUpgrade: (db, from, _) => _upgrade(db, from),
    );
    final db = factory == null
        ? await openDatabase(path, version: options.version, onCreate: options.onCreate, onUpgrade: options.onUpgrade)
        : await factory.openDatabase(path, options: options);
    return AppDatabase._(db);
  }

  static const _activityTables = [
    '''CREATE TABLE lesson_progress (
        profile_id TEXT NOT NULL, lesson_id TEXT NOT NULL, subject_id TEXT NOT NULL,
        opened_at INTEGER NOT NULL, completed_at INTEGER, synced INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (profile_id, lesson_id))''',
    '''CREATE TABLE attempts (
        id INTEGER PRIMARY KEY AUTOINCREMENT, profile_id TEXT NOT NULL, uid TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL, title TEXT NOT NULL, subject_id TEXT, lesson_id TEXT, exam_id TEXT,
        started_at INTEGER NOT NULL, duration_sec INTEGER NOT NULL,
        score REAL NOT NULL, max_score REAL NOT NULL, synced INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE answers (
        profile_id TEXT NOT NULL, attempt_id INTEGER NOT NULL, question_id TEXT NOT NULL,
        lesson_id TEXT NOT NULL, subject_id TEXT NOT NULL, score REAL NOT NULL, answered_at INTEGER NOT NULL)''',
    'CREATE INDEX answers_profile ON answers (profile_id, answered_at)',
    '''CREATE TABLE bookmarks (
        profile_id TEXT NOT NULL, book_id TEXT NOT NULL, page INTEGER NOT NULL, created_at INTEGER NOT NULL,
        PRIMARY KEY (profile_id, book_id, page))''',
    'CREATE TABLE activity_days (profile_id TEXT NOT NULL, day TEXT NOT NULL, PRIMARY KEY (profile_id, day))',
  ];

  static const _profilesTable = '''CREATE TABLE profiles (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, grade_id TEXT NOT NULL, semester INTEGER NOT NULL DEFAULT 1,
      avatar INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, last_used_at INTEGER NOT NULL)''';

  static Future<void> _create(Database db) async {
    final batch = db.batch()
      ..execute('CREATE TABLE packs (grade_id TEXT PRIMARY KEY, version INTEGER NOT NULL, json TEXT NOT NULL)')
      ..execute(_profilesTable);
    for (final sql in _activityTables) {
      batch.execute(sql);
    }
    await batch.commit(noResult: true);
  }

  /// v1 → v2: activity tables gain `profile_id`; existing rows belong to the
  /// [legacyProfileId] student (created from the old settings on start-up).
  static Future<void> _upgrade(Database db, int from) async {
    if (from >= 2) return;
    const columns = {
      'lesson_progress': 'lesson_id, subject_id, opened_at, completed_at, synced',
      'attempts':
          'id, uid, kind, title, subject_id, lesson_id, exam_id, started_at, duration_sec, score, max_score, synced',
      'answers': 'attempt_id, question_id, lesson_id, subject_id, score, answered_at',
      'bookmarks': 'book_id, page, created_at',
      'activity_days': 'day',
    };
    await db.transaction((txn) async {
      await txn.execute('DROP INDEX IF EXISTS answers_lesson');
      for (final t in columns.keys) {
        await txn.execute('ALTER TABLE $t RENAME TO ${t}_v1');
      }
      await txn.execute(_profilesTable);
      for (final sql in _activityTables) {
        await txn.execute(sql);
      }
      for (final e in columns.entries) {
        await txn.execute(
          "INSERT INTO ${e.key} (profile_id, ${e.value}) SELECT '$legacyProfileId', ${e.value} FROM ${e.key}_v1",
        );
        await txn.execute('DROP TABLE ${e.key}_v1');
      }
    });
  }

  Future<void> close() => db.close();
}

/// A student using this device. No password: the device is shared within a
/// family, and each student simply picks their own card.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.gradeId,
    required this.semester,
    required this.avatar,
    required this.lastUsedAt,
  });

  factory Profile.fromRow(Map<String, Object?> r) => Profile(
    id: r['id'] as String,
    name: r['name'] as String,
    gradeId: r['grade_id'] as String,
    semester: r['semester'] as int,
    avatar: r['avatar'] as int,
    lastUsedAt: DateTime.fromMillisecondsSinceEpoch(r['last_used_at'] as int),
  );

  final String id;
  final String name;
  final String gradeId;
  final int semester;

  /// Index into the avatar list shown on the student's card.
  final int avatar;
  final DateTime lastUsedAt;

  Profile copyWith({String? name, String? gradeId, int? semester, int? avatar}) => Profile(
    id: id,
    name: name ?? this.name,
    gradeId: gradeId ?? this.gradeId,
    semester: semester ?? this.semester,
    avatar: avatar ?? this.avatar,
    lastUsedAt: lastUsedAt,
  );
}

class ProfileStore {
  ProfileStore(this._db);

  final AppDatabase _db;

  Future<List<Profile>> all() async =>
      (await _db.db.query('profiles', orderBy: 'last_used_at DESC')).map(Profile.fromRow).toList();

  Future<void> save(Profile p, DateTime now) => _db.db.insert('profiles', {
    'id': p.id,
    'name': p.name,
    'grade_id': p.gradeId,
    'semester': p.semester,
    'avatar': p.avatar,
    'created_at': now.millisecondsSinceEpoch,
    'last_used_at': now.millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> touch(String id, DateTime now) =>
      _db.db.update('profiles', {'last_used_at': now.millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);

  /// Removes the student and everything they did on this device.
  Future<void> delete(String id) async {
    await _db.db.transaction((txn) async {
      await txn.delete('profiles', where: 'id = ?', whereArgs: [id]);
      for (final t in ProgressRepository.tables) {
        await txn.delete(t, where: 'profile_id = ?', whereArgs: [id]);
      }
    });
  }
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

/// Everything one student does, stored locally. Every query is scoped to
/// [profileId].
class ProgressRepository {
  ProgressRepository(this._db, this.profileId);

  final AppDatabase _db;
  final String profileId;

  static const tables = ['lesson_progress', 'attempts', 'answers', 'bookmarks', 'activity_days'];

  Database get _sql => _db.db;

  static String dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  static const _mine = 'profile_id = ?';

  List<Object?> _args([List<Object?> more = const []]) => [profileId, ...more];

  Future<void> recordActivity(DateTime now) => _sql.insert('activity_days', {
    'profile_id': profileId,
    'day': dayKey(now),
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<Set<String>> activityDays() async => {
    for (final r in await _sql.query('activity_days', where: _mine, whereArgs: _args())) r['day'] as String,
  };

  Future<void> openLesson(Lesson lesson, DateTime now) async {
    await _sql.rawInsert(
      'INSERT INTO lesson_progress (profile_id, lesson_id, subject_id, opened_at) VALUES (?, ?, ?, ?) '
      'ON CONFLICT(profile_id, lesson_id) DO UPDATE SET opened_at = excluded.opened_at',
      [profileId, lesson.id, lesson.subjectId, now.millisecondsSinceEpoch],
    );
    await recordActivity(now);
  }

  Future<void> completeLesson(Lesson lesson, DateTime now) async {
    await openLesson(lesson, now);
    await _sql.update(
      'lesson_progress',
      {'completed_at': now.millisecondsSinceEpoch, 'synced': 0},
      where: '$_mine AND lesson_id = ? AND completed_at IS NULL',
      whereArgs: _args([lesson.id]),
    );
  }

  Future<Map<String, LessonProgressRow>> lessonProgress() async {
    final rows = await _sql.query('lesson_progress', where: _mine, whereArgs: _args());
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
        'profile_id': profileId,
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
          'profile_id': profileId,
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
        'profile_id': profileId,
        'day': dayKey(attempt.startedAt.add(attempt.duration)),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return id;
    });
  }

  Future<List<AttemptRecord>> attempts({int? limit}) async {
    final rows = await _sql.query(
      'attempts',
      where: _mine,
      whereArgs: _args(),
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(AttemptRecord.fromRow).toList();
  }

  Future<List<AnswerRecord>> answers() async {
    final rows = await _sql.query('answers', where: _mine, whereArgs: _args(), orderBy: 'answered_at');
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
    final rows = await _sql.query(
      'bookmarks',
      where: '$_mine AND book_id = ?',
      whereArgs: _args([bookId]),
      orderBy: 'page',
    );
    return [for (final r in rows) r['page'] as int];
  }

  /// Returns true when the page is bookmarked after the call.
  Future<bool> toggleBookmark(String bookId, int page, DateTime now) async {
    final removed = await _sql.delete(
      'bookmarks',
      where: '$_mine AND book_id = ? AND page = ?',
      whereArgs: _args([bookId, page]),
    );
    if (removed > 0) return false;
    await _sql.insert('bookmarks', {
      'profile_id': profileId,
      'book_id': bookId,
      'page': page,
      'created_at': now.millisecondsSinceEpoch,
    });
    return true;
  }

  Future<List<AttemptRecord>> unsyncedAttempts() async {
    final rows = await _sql.query(
      'attempts',
      where: '$_mine AND synced = 0',
      whereArgs: _args(),
      orderBy: 'id',
      limit: 100,
    );
    return rows.map(AttemptRecord.fromRow).toList();
  }

  Future<void> markAttemptsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    await _sql.update(
      'attempts',
      {'synced': 1},
      where: '$_mine AND id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: _args(ids),
    );
  }

  /// Deletes this student's activity (content packs are kept).
  Future<void> clear() async {
    final batch = _sql.batch();
    for (final t in tables) {
      batch.delete(t, where: _mine, whereArgs: _args());
    }
    await batch.commit(noResult: true);
  }
}
