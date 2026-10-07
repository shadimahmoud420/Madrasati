import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasati/core/providers.dart';
import 'package:madrasati/data/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 7, 18);
  final lesson = loadPack('g4').lessons.first;

  AttemptRecord attempt(String uid) => AttemptRecord(
    uid: uid,
    kind: AttemptKind.quiz,
    title: 't',
    startedAt: now,
    duration: const Duration(minutes: 1),
    score: 1,
    maxScore: 1,
  );

  test('students on one device never see each other\'s data', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final mahmoud = ProgressRepository(db, 'mahmoud');
    final mohammed = ProgressRepository(db, 'mohammed');

    await mahmoud.completeLesson(lesson, now);
    await mahmoud.saveAttempt(attempt('a1'), [
      AnswerRecord(questionId: 'q', lessonId: lesson.id, subjectId: lesson.subjectId, score: 1, answeredAt: now),
    ]);
    await mahmoud.toggleBookmark('b', 3, now);

    expect(await mohammed.lessonProgress(), isEmpty);
    expect(await mohammed.attempts(), isEmpty);
    expect(await mohammed.answers(), isEmpty);
    expect(await mohammed.bookmarks('b'), isEmpty);
    expect(await mohammed.activityDays(), isEmpty);
    expect(await mohammed.unsyncedAttempts(), isEmpty);

    // Opening the same lesson is tracked per student.
    await mohammed.openLesson(lesson, now);
    expect((await mahmoud.lessonProgress())[lesson.id]!.completed, isTrue);
    expect((await mohammed.lessonProgress())[lesson.id]!.completed, isFalse);

    await mohammed.clear();
    expect(await mahmoud.attempts(), hasLength(1));
  });

  test('profiles: create, switch, sign out, delete with all their data', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(
      overrides: await testOverrides(prefs: await testPrefs(), db: db, clock: () => now),
    );
    addTearDown(c.dispose);
    final profiles = c.read(profilesProvider.notifier);

    final mahmoud = await profiles.create(name: 'محمود', gradeId: 'g9', semester: 1);
    expect(c.read(profileProvider)!.name, 'محمود');
    await c.read(progressRepositoryProvider).saveAttempt(attempt('m1'), const []);

    final mohammed = await profiles.create(name: 'محمد', gradeId: 'g4', semester: 2);
    expect(c.read(profileProvider)!.id, mohammed.id);
    expect(c.read(currentGradeProvider)!.id, 'g4');
    expect(await c.read(progressRepositoryProvider).attempts(), isEmpty);

    await profiles.signOut();
    expect(c.read(profileProvider), isNull);
    expect(c.read(profilesProvider).profiles, hasLength(2));

    await profiles.switchTo(mahmoud.id);
    expect(c.read(currentGradeProvider)!.id, 'g9');
    expect(await c.read(progressRepositoryProvider).attempts(), hasLength(1));

    await profiles.delete(mahmoud.id);
    expect(c.read(profileProvider), isNull);
    expect(await ProfileStore(db).all(), [isA<Profile>().having((p) => p.name, 'name', 'محمد')]);
    expect(await ProgressRepository(db, mahmoud.id).attempts(), isEmpty);
  });

  test('the active student is remembered across app restarts', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final prefs = await testPrefs();
    final first = ProviderContainer(
      overrides: await testOverrides(prefs: prefs, db: db),
    );
    final p = await first.read(profilesProvider.notifier).create(name: 'ليان', gradeId: 'g9', semester: 1);
    first.dispose();

    final second = ProviderContainer(
      overrides: await testOverrides(prefs: prefs, db: db),
    );
    addTearDown(second.dispose);
    expect(second.read(profileProvider)?.id, p.id);
  });

  test('upgrading from the single-student version keeps progress under a profile', () async {
    sqfliteFfiInit();
    final dir = Directory.systemTemp.createTempSync('madrasati_v1');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/app.db';

    // A database as created by version 1 of the app.
    final v1 = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE packs (grade_id TEXT PRIMARY KEY, version INTEGER NOT NULL, json TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE lesson_progress (lesson_id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, '
            'opened_at INTEGER NOT NULL, completed_at INTEGER, synced INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE attempts (id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, '
            'title TEXT NOT NULL, subject_id TEXT, lesson_id TEXT, exam_id TEXT, started_at INTEGER NOT NULL, '
            'duration_sec INTEGER NOT NULL, score REAL NOT NULL, max_score REAL NOT NULL, synced INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE answers (attempt_id INTEGER NOT NULL, question_id TEXT NOT NULL, lesson_id TEXT NOT NULL, '
            'subject_id TEXT NOT NULL, score REAL NOT NULL, answered_at INTEGER NOT NULL)',
          );
          await db.execute('CREATE INDEX answers_lesson ON answers (lesson_id)');
          await db.execute(
            'CREATE TABLE bookmarks (book_id TEXT NOT NULL, page INTEGER NOT NULL, created_at INTEGER NOT NULL, '
            'PRIMARY KEY (book_id, page))',
          );
          await db.execute('CREATE TABLE activity_days (day TEXT PRIMARY KEY)');
        },
      ),
    );
    await v1.insert('lesson_progress', {'lesson_id': lesson.id, 'subject_id': lesson.subjectId, 'opened_at': 1});
    await v1.insert('attempts', {
      'uid': 'old',
      'kind': 'quiz',
      'title': 't',
      'started_at': 1,
      'duration_sec': 60,
      'score': 1,
      'max_score': 2,
    });
    await v1.insert('bookmarks', {'book_id': 'b', 'page': 2, 'created_at': 1});
    await v1.insert('activity_days', {'day': '2026-10-01'});
    await v1.close();

    final db = await AppDatabase.open(path, factory: databaseFactoryFfiNoIsolate);
    addTearDown(db.close);
    final prefs = await testPrefs({'profile.grade': 'g4', 'profile.name': 'أحمد', 'profile.semester': 2});
    final profiles = await ProfilesController.bootstrap(prefs, ProfileStore(db), now);

    expect(profiles.single.name, 'أحمد');
    expect(profiles.single.semester, 2);
    expect(prefs.getString('profile.grade'), isNull);
    final repo = ProgressRepository(db, profiles.single.id);
    expect((await repo.attempts()).single.uid, 'old');
    expect(await repo.lessonProgress(), contains(lesson.id));
    expect(await repo.bookmarks('b'), [2]);
    expect(await repo.activityDays(), {'2026-10-01'});
  });
}
