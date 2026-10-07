import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import 'quiz_engine.dart';

/// Builds quizzes from the current pack and opens the quiz screen.
class QuizLauncher {
  QuizLauncher(this.ref);

  final WidgetRef ref;

  static const challengeSize = 5;

  Future<void> _open(BuildContext context, QuizSpec spec) async {
    if (spec.questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد أسئلة متاحة هنا بعد.')));
      return;
    }
    await context.push('/quiz', extra: spec);
  }

  Future<({GradePack pack, Map<String, Mastery> mastery, Map<String, double> last})?> _inputs() async {
    final pack = await ref.read(packProvider.future);
    if (pack == null) return null;
    final stats = await ref.read(statsProvider.future);
    final last = await ref.read(lastScoresProvider.future);
    return (pack: pack, mastery: stats.lessonMastery, last: last);
  }

  /// "اختبرني": adaptive quiz on a lesson, a subject, or the whole grade.
  Future<void> testMe(BuildContext context, {String? subjectId, String? lessonId, int count = 8}) async {
    final input = await _inputs();
    if (input == null || !context.mounted) return;
    final pack = input.pack;
    final Iterable<Question> pool;
    final String title;
    if (lessonId != null) {
      final lesson = pack.lesson(lessonId)!;
      pool = lesson.questions;
      title = 'اختبرني: ${lesson.title}';
    } else if (subjectId != null) {
      pool = pack.subjects[subjectId]?.questions ?? const [];
      title = 'اختبرني: ${_subjectName(subjectId)}';
    } else {
      pool = pack.questions;
      title = 'اختبرني: كل المواد';
    }
    final questions = pickQuestions(pool: pool, count: count, mastery: input.mastery, lastScores: input.last);
    await _open(
      context,
      QuizSpec(kind: AttemptKind.quiz, title: title, questions: questions, subjectId: subjectId, lessonId: lessonId),
    );
  }

  /// Practice right after a lesson: all its questions, easiest first.
  Future<void> practice(BuildContext context, Lesson lesson) => _open(
    context,
    QuizSpec(
      kind: AttemptKind.practice,
      title: 'تدريب: ${lesson.title}',
      questions: [...lesson.questions]..sort((a, b) => a.difficulty.level.compareTo(b.difficulty.level)),
      subjectId: lesson.subjectId,
      lessonId: lesson.id,
    ),
  );

  /// Same 5 questions for everyone on a given day.
  Future<void> dailyChallenge(BuildContext context) async {
    final pack = await ref.read(packProvider.future);
    if (pack == null || !context.mounted) return;
    final day = ProgressRepository.dayKey(ref.read(clockProvider)());
    final pool = pack.questions.where((q) => q.type.autoGraded).toList()..sort((a, b) => a.id.compareTo(b.id));
    pool.shuffle(Random(int.parse(day.replaceAll('-', ''))));
    await _open(
      context,
      QuizSpec(kind: AttemptKind.challenge, title: 'تحدي اليوم', questions: pool.take(challengeSize).toList()),
    );
  }

  Future<void> exam(BuildContext context, Exam exam) async {
    final pack = await ref.read(packProvider.future);
    if (pack == null || !context.mounted) return;
    await _open(
      context,
      QuizSpec(
        kind: AttemptKind.exam,
        title: exam.title,
        questions: examQuestions(exam, pack),
        timeLimit: Duration(minutes: exam.durationMinutes),
        subjectId: exam.subjectId,
        examId: exam.id,
      ),
    );
  }

  /// Custom mock exam: chosen subject, number of questions, difficulty, time.
  Future<void> customExam(
    BuildContext context, {
    required String subjectId,
    required int count,
    required Duration timeLimit,
    Difficulty? difficulty,
  }) async {
    final input = await _inputs();
    if (input == null || !context.mounted) return;
    final pool = input.pack.subjects[subjectId]?.questions ?? const <Question>[];
    final questions = difficulty == null
        ? examQuestions(
            Exam(id: 'custom', subjectId: subjectId, title: '', durationMinutes: 0, questionCount: count),
            input.pack,
          )
        : pickQuestions(pool: pool, count: count, mastery: input.mastery, fixedDifficulty: difficulty);
    await _open(
      context,
      QuizSpec(
        kind: AttemptKind.exam,
        title: 'امتحان مخصص: ${_subjectName(subjectId)}',
        questions: questions,
        timeLimit: timeLimit,
        subjectId: subjectId,
      ),
    );
  }

  String _subjectName(String subjectId) =>
      ref.read(currentGradeProvider)?.subjects.where((s) => s.id == subjectId).firstOrNull?.name ?? '';
}
