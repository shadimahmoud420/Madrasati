import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasati/data/database.dart';
import 'package:madrasati/data/models.dart';
import 'package:madrasati/features/quiz/quiz_engine.dart';

import '../helpers/harness.dart';

Question _q(
  String type, {
  Object? answer,
  List<String> accepted = const [],
  List<List<String>> pairs = const [],
  int d = 1,
}) => Question.fromJson(
  {
    'id': 'q_$type$d',
    'type': type,
    'difficulty': d,
    'prompt': 'p',
    'options': ['a', 'b', 'c'],
    'answer': answer,
    'accepted': accepted,
    'pairs': pairs,
  },
  lessonId: 'l$d',
  subjectId: 's',
);

void main() {
  group('grade', () {
    test('mcq and true/false', () {
      final mcq = _q('mcq', answer: 1);
      expect(grade(mcq, const ChoiceResponse(1)), 1);
      expect(grade(mcq, const ChoiceResponse(0)), 0);
      expect(grade(mcq, null), 0);
      final tf = _q('trueFalse', answer: false);
      expect(grade(tf, const BoolResponse(false)), 1);
      expect(grade(tf, const BoolResponse(true)), 0);
    });

    test('fill and short answers tolerate diacritics and spacing', () {
      final fill = _q('fill', accepted: ['المقام', 'مقام']);
      expect(grade(fill, const TextResponse(' المَقامُ ')), 1);
      expect(grade(fill, const TextResponse('البسط')), 0);
      expect(grade(fill, const TextResponse('')), 0);
      final short = _q('short', accepted: ['2/5']);
      expect(grade(short, const TextResponse('٢/٥')), 1);
    });

    test('numeric accepts units and Arabic digits', () {
      final q = _q('numeric', answer: 12);
      expect(grade(q, const TextResponse('١٢ سم')), 1);
      expect(grade(q, const TextResponse('12.0')), 1);
      expect(grade(q, const TextResponse('13')), 0);
      expect(grade(q, const TextResponse('؟')), 0);
    });

    test('match gives partial credit', () {
      final q = _q(
        'match',
        pairs: [
          ['1/2', 'نصف'],
          ['1/4', 'ربع'],
        ],
      );
      expect(grade(q, const MatchResponse({0: 'نصف', 1: 'ربع'})), 1);
      expect(grade(q, const MatchResponse({0: 'نصف', 1: 'نصف'})), 0.5);
    });

    test('essays are not auto-graded', () {
      expect(grade(_q('essay'), const TextResponse('...')), isNull);
    });
  });

  group('Mastery', () {
    AnswerRecord a(String lesson, double s) =>
        AnswerRecord(questionId: 'q', lessonId: lesson, subjectId: 's', score: s, answeredAt: DateTime(2026));

    test('targets easy questions for new or struggling students and harder ones as they improve', () {
      expect(const Mastery(answered: 0, ratio: 0).target, Difficulty.easy);
      final m = Mastery.byLesson([for (var i = 0; i < 5; i++) a('good', 1), a('weak', 0), a('weak', 0), a('weak', 1)]);
      expect(m['good']!.target, Difficulty.advanced);
      expect(m['weak']!.ratio, closeTo(1 / 3, 1e-9));
      expect(m['weak']!.target, Difficulty.easy);
    });

    test('uses only the most recent answers', () {
      final m = Mastery.byLesson([for (var i = 0; i < 10; i++) a('l', 0), for (var i = 0; i < 10; i++) a('l', 1)]);
      expect(m['l']!.ratio, 1);
      expect(m['l']!.answered, 20);
    });
  });

  test('pickQuestions prefers the target difficulty and orders easiest first', () {
    final pool = [
      for (var d = 1; d <= 4; d++)
        for (var i = 0; i < 3; i++) _q('mcq', answer: 0, d: d),
    ];
    final fixed = [
      for (final (i, q) in pool.indexed)
        Question(id: 'q$i', type: q.type, difficulty: q.difficulty, prompt: 'p', lessonId: 'l', subjectId: 's'),
    ];
    final easy = pickQuestions(pool: fixed, count: 3, mastery: const {}, random: Random(1));
    expect(easy.every((q) => q.difficulty == Difficulty.easy), isTrue);
    final hard = pickQuestions(
      pool: fixed,
      count: 3,
      mastery: const {'l': Mastery(answered: 10, ratio: 0.95)},
      random: Random(1),
    );
    expect(hard.every((q) => q.difficulty == Difficulty.advanced), isTrue);
    final mixed = pickQuestions(pool: fixed, count: 12, mastery: const {}, random: Random(2));
    for (var i = 1; i < mixed.length; i++) {
      expect(mixed[i].difficulty.level, greaterThanOrEqualTo(mixed[i - 1].difficulty.level));
    }
  });

  test('examQuestions draws a balanced paper of the requested size', () {
    final pack = loadPack('g9');
    final exam = pack.exam('g9_science_exam1')!;
    final paper = examQuestions(exam, pack, random: Random(3));
    expect(paper, hasLength(exam.questionCount));
    expect(paper.map((q) => q.id).toSet(), hasLength(paper.length));
    expect(paper.every((q) => q.subjectId == 'g9_science'), isTrue);
    expect(paper.map((q) => q.difficulty).toSet().length, greaterThan(2));
  });

  test('QuizOutcome scores, finds mistakes and lessons to review', () {
    final ok = _q('mcq', answer: 0, d: 1);
    final bad = _q('mcq', answer: 0, d: 2);
    final essay = _q('essay', d: 3);
    final outcome = QuizOutcome(
      spec: QuizSpec(kind: AttemptKind.quiz, title: 't', questions: [ok, bad, essay]),
      startedAt: DateTime(2026),
      duration: const Duration(seconds: 90),
      items: [
        ItemResult(question: ok, response: const ChoiceResponse(0), score: 1),
        ItemResult(question: bad, response: const ChoiceResponse(1), score: 0),
        ItemResult(question: essay, response: const TextResponse('x'), score: null),
      ],
    );
    expect(outcome.maxScore, 2);
    expect(outcome.percent, 50);
    expect(outcome.passed, isTrue);
    expect(outcome.mistakes.single.question, bad);
    expect(outcome.ungraded.single.question, essay);
    expect(outcome.lessonsToReview, ['l2']);
  });
}
