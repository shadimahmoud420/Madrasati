import 'package:flutter_test/flutter_test.dart';
import 'package:madrasati/data/database.dart';
import 'package:madrasati/features/progress/learner_stats.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late ProgressRepository repo;
  final pack = loadPack('g4');
  final now = DateTime(2026, 10, 7, 18);

  setUp(() async {
    db = await openTestDatabase();
    repo = ProgressRepository(db);
  });

  tearDown(() => db.close());

  test('PackStore saves, versions and reloads packs', () async {
    final store = PackStore(db);
    expect(await store.load('g4'), isNull);
    await store.save(packJson('g4'));
    expect(await store.version('g4'), pack.version);
    final loaded = await store.load('g4');
    expect(loaded!.lessons.length, pack.lessons.length);
  });

  test('PackStore rejects invalid JSON without touching the stored pack', () async {
    final store = PackStore(db);
    await store.save(packJson('g4'));
    await expectLater(store.save('{"gradeId": "g4"'), throwsFormatException);
    expect(await store.version('g4'), pack.version);
  });

  test('bookmarks toggle', () async {
    expect(await repo.toggleBookmark('b', 3, now), isTrue);
    expect(await repo.toggleBookmark('b', 5, now), isTrue);
    expect(await repo.bookmarks('b'), [3, 5]);
    expect(await repo.toggleBookmark('b', 3, now), isFalse);
    expect(await repo.bookmarks('b'), [5]);
  });

  Future<void> attempt(AttemptKind kind, DateTime at, List<(String, double)> answers, {String uid = ''}) async {
    final lesson = pack.lessons.first;
    await repo.saveAttempt(
      AttemptRecord(
        uid: uid.isEmpty ? '${at.millisecondsSinceEpoch}${kind.name}' : uid,
        kind: kind,
        title: 't',
        startedAt: at,
        duration: const Duration(minutes: 2),
        score: answers.fold(0, (s, a) => s + a.$2),
        maxScore: answers.length.toDouble(),
      ),
      [
        for (final (lessonId, score) in answers)
          AnswerRecord(
            questionId: '$lessonId-q',
            lessonId: lessonId,
            subjectId: lesson.subjectId,
            score: score,
            answeredAt: at,
          ),
      ],
    );
  }

  Future<LearnerStats> stats() async => LearnerStats.compute(
    pack: pack,
    progress: await repo.lessonProgress(),
    attempts: await repo.attempts(),
    answers: await repo.answers(),
    activityDays: await repo.activityDays(),
    now: now,
  );

  test('stats: points, level, streak, strengths, weaknesses and next lesson', () async {
    final l1 = pack.lessons.first;
    final l2 = pack.lessons.elementAt(1);
    await repo.completeLesson(l1, now.subtract(const Duration(days: 2)));
    await attempt(AttemptKind.quiz, now.subtract(const Duration(days: 1)), [
      for (var i = 0; i < 4; i++) (l1.id, 1.0),
      (l2.id, 0.0),
      (l2.id, 0.0),
    ]);
    await attempt(AttemptKind.challenge, now, [(l1.id, 1.0)]);

    final s = await stats();
    expect(s.completedLessons, 1);
    expect(s.streak, 3);
    // 5 correct answers ×10 + 1 lesson ×20 + 1 challenge ×30
    expect(s.points, 100);
    expect(s.level, 2);
    expect(s.pointsIntoLevel, 0);
    expect(s.strengths.map((l) => l.id), [l1.id]);
    expect(s.weaknesses.map((l) => l.id), [l2.id]);
    expect(s.recommendations.single.lesson.id, l2.id);
    expect(s.challengeDoneToday, isTrue);
    expect(s.lastLesson!.id, l1.id);
    expect(s.nextLesson!.id, l2.id);
    expect(s.badges.firstWhere((b) => b.id == 'streak3').earned, isTrue);
  });

  test('streak breaks after a missed day and survives until today is studied', () async {
    await repo.recordActivity(now.subtract(const Duration(days: 3)));
    await repo.recordActivity(now.subtract(const Duration(days: 1)));
    expect((await stats()).streak, 1);
  });

  test('week-over-week improvement', () async {
    final l1 = pack.lessons.first.id;
    await attempt(AttemptKind.quiz, now.subtract(const Duration(days: 10)), [(l1, 0.0), (l1, 1.0)]);
    await attempt(AttemptKind.quiz, now.subtract(const Duration(days: 2)), [(l1, 1.0), (l1, 1.0)]);
    expect((await stats()).improvement, 50);
  });

  test('unsynced attempts are queued until marked', () async {
    await attempt(AttemptKind.quiz, now, [('x', 1.0)], uid: 'a');
    await attempt(AttemptKind.exam, now, [('x', 0.0)], uid: 'b');
    final pending = await repo.unsyncedAttempts();
    expect(pending.map((a) => a.uid), ['a', 'b']);
    await repo.markAttemptsSynced([pending.first.id!]);
    expect((await repo.unsyncedAttempts()).map((a) => a.uid), ['b']);
  });

  test('clear removes activity', () async {
    await attempt(AttemptKind.quiz, now, [('x', 1.0)]);
    await repo.clear();
    expect(await repo.attempts(), isEmpty);
    expect(await repo.answers(), isEmpty);
  });
}
