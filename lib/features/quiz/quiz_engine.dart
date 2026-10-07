import 'dart:math';

import '../../core/arabic.dart';
import '../../data/database.dart';
import '../../data/models.dart';

/// A student's answer. One variant per question shape.
sealed class Response {
  const Response();
}

class ChoiceResponse extends Response {
  const ChoiceResponse(this.index);
  final int index;
}

class BoolResponse extends Response {
  const BoolResponse(this.value);
  final bool value;
}

class TextResponse extends Response {
  const TextResponse(this.text);
  final String text;
}

/// Matching: left index → chosen right text.
class MatchResponse extends Response {
  const MatchResponse(this.choices);
  final Map<int, String> choices;
}

/// Grades one answer. Returns 0..1, or null when the question can't be
/// graded on the device (essays) or wasn't answered as the right shape.
double? grade(Question q, Response? response) {
  if (!q.type.autoGraded) return null;
  if (response == null) return 0;
  switch (q.type) {
    case QuestionType.mcq:
      return response is ChoiceResponse && response.index == q.answer ? 1 : 0;
    case QuestionType.trueFalse:
      return response is BoolResponse && response.value == q.answer ? 1 : 0;
    case QuestionType.fill:
    case QuestionType.short:
      if (response is! TextResponse) return 0;
      final given = normalizeAnswer(response.text);
      if (given.isEmpty) return 0;
      return q.accepted.any((a) => normalizeAnswer(a) == given) ? 1 : 0;
    case QuestionType.numeric:
      if (response is! TextResponse) return 0;
      final value = parseNumber(response.text);
      final expected = (q.answer as num).toDouble();
      if (value == null) return 0;
      return (value - expected).abs() <= max(q.tolerance, expected.abs() * 1e-9) ? 1 : 0;
    case QuestionType.match:
      if (response is! MatchResponse || q.pairs.isEmpty) return 0;
      var right = 0;
      for (var i = 0; i < q.pairs.length; i++) {
        if (response.choices[i] == q.pairs[i].right) right++;
      }
      return right / q.pairs.length;
    case QuestionType.essay:
      return null;
  }
}

/// How well a student knows a lesson, from their recent answers.
class Mastery {
  const Mastery({required this.answered, required this.ratio});

  final int answered;

  /// Average score over the last [window] answers, 0..1.
  final double ratio;

  static const window = 10;

  static Map<String, Mastery> byLesson(Iterable<AnswerRecord> answers) => _group(answers, (a) => a.lessonId);

  static Map<String, Mastery> bySubject(Iterable<AnswerRecord> answers) => _group(answers, (a) => a.subjectId);

  static Map<String, Mastery> _group(Iterable<AnswerRecord> answers, String Function(AnswerRecord) key) {
    final grouped = <String, List<double>>{};
    for (final a in answers) {
      grouped.putIfAbsent(key(a), () => []).add(a.score);
    }
    return grouped.map((k, scores) {
      final recent = scores.length > window ? scores.sublist(scores.length - window) : scores;
      return MapEntry(k, Mastery(answered: scores.length, ratio: recent.reduce((a, b) => a + b) / recent.length));
    });
  }

  /// Difficulty to aim for: new or struggling students get easier questions.
  Difficulty get target {
    if (answered < 3) return Difficulty.easy;
    if (ratio < 0.5) return Difficulty.easy;
    if (ratio < 0.75) return Difficulty.medium;
    if (ratio < 0.9) return Difficulty.hard;
    return Difficulty.advanced;
  }
}

class QuizSpec {
  const QuizSpec({
    required this.kind,
    required this.title,
    required this.questions,
    this.timeLimit,
    this.subjectId,
    this.lessonId,
    this.examId,
  });

  final AttemptKind kind;
  final String title;
  final List<Question> questions;
  final Duration? timeLimit;
  final String? subjectId;
  final String? lessonId;
  final String? examId;
}

/// Picks questions suited to the student's level ("اختبرني").
///
/// Each question is ranked by how far its difficulty is from the target for
/// its lesson, with a penalty for questions the student already got right
/// recently and a little randomness so retakes differ. The final list goes
/// from easiest to hardest.
List<Question> pickQuestions({
  required Iterable<Question> pool,
  required int count,
  required Map<String, Mastery> mastery,
  Map<String, double> lastScores = const {},
  Difficulty? fixedDifficulty,
  Random? random,
}) {
  final rng = random ?? Random();
  final ranked = pool.map((q) {
    final target = fixedDifficulty ?? (mastery[q.lessonId] ?? const Mastery(answered: 0, ratio: 0)).target;
    var cost = (q.difficulty.level - target.level).abs().toDouble();
    if (lastScores[q.id] == 1) cost += 1.5;
    cost += rng.nextDouble();
    return (q: q, cost: cost);
  }).toList()..sort((a, b) => a.cost.compareTo(b.cost));
  final picked = ranked.take(count).map((e) => e.q).toList()
    ..sort((a, b) => a.difficulty.level.compareTo(b.difficulty.level));
  return picked;
}

/// Mock exam paper: the fixed list when the exam has one, otherwise a
/// balanced draw across difficulties from the subject's bank.
List<Question> examQuestions(Exam exam, GradePack pack, {Random? random}) {
  final fixed = exam.questionIds;
  if (fixed != null) return [for (final id in fixed) ?pack.question(id)];
  final pool = pack.subjects[exam.subjectId]?.questions.toList() ?? [];
  pool.shuffle(random ?? Random());
  final byLevel = <Difficulty, List<Question>>{};
  for (final q in pool) {
    byLevel.putIfAbsent(q.difficulty, () => []).add(q);
  }
  // Round-robin over difficulties so the paper isn't all easy questions.
  final picked = <Question>[];
  while (picked.length < exam.questionCount && byLevel.values.any((l) => l.isNotEmpty)) {
    for (final level in Difficulty.values) {
      final list = byLevel[level];
      if (list != null && list.isNotEmpty && picked.length < exam.questionCount) picked.add(list.removeLast());
    }
  }
  picked.sort((a, b) => a.difficulty.level.compareTo(b.difficulty.level));
  return picked;
}

class ItemResult {
  const ItemResult({required this.question, required this.response, required this.score});

  final Question question;
  final Response? response;

  /// null for questions that aren't auto-graded.
  final double? score;

  bool get correct => score == 1;
}

class QuizOutcome {
  QuizOutcome({required this.spec, required this.items, required this.startedAt, required this.duration});

  final QuizSpec spec;
  final List<ItemResult> items;
  final DateTime startedAt;
  final Duration duration;

  Iterable<ItemResult> get graded => items.where((i) => i.score != null);

  double get score => graded.fold(0, (sum, i) => sum + i.score!);

  int get maxScore => graded.length;

  double get ratio => maxScore == 0 ? 0 : score / maxScore;

  int get percent => (ratio * 100).round();

  bool get passed => ratio >= 0.5;

  int get correctCount => graded.where((i) => i.correct).length;

  List<ItemResult> get mistakes => graded.where((i) => !i.correct).toList();

  List<ItemResult> get ungraded => items.where((i) => i.score == null).toList();

  /// Lessons where the student scored under 70% in this attempt.
  List<String> get lessonsToReview {
    final byLesson = <String, List<double>>{};
    for (final i in graded) {
      byLesson.putIfAbsent(i.question.lessonId, () => []).add(i.score!);
    }
    return [
      for (final e in byLesson.entries)
        if (e.value.reduce((a, b) => a + b) / e.value.length < 0.7) e.key,
    ];
  }
}
