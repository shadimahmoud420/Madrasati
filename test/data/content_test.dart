import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasati/features/books/library.dart';
import 'package:madrasati/data/models.dart';

import '../helpers/harness.dart';

/// Guards the bundled content (and any pack an editor adds) against
/// mistakes that would break a quiz on the device.
void main() {
  final catalog = loadCatalog();

  test('catalog covers grades 1–12 with both secondary streams', () {
    expect(catalog.grades.map((g) => g.number).toSet(), {for (var n = 1; n <= 12; n++) n});
    expect(catalog.gradesOf(Stage.secondary), hasLength(4));
    for (final g in catalog.grades) {
      expect(g.subjects, isNotEmpty, reason: g.id);
    }
  });

  for (final gradeId in catalog.bundledPacks.keys) {
    group('pack $gradeId', () {
      final pack = loadPack(gradeId);
      final grade = catalog.grade(gradeId);

      test('belongs to a catalog grade and its subjects', () {
        expect(grade, isNotNull);
        expect(pack.version, catalog.bundledPacks[gradeId]);
        final ids = grade!.subjects.map((s) => s.id).toSet();
        expect(ids, containsAll(pack.subjects.keys));
      });

      test('ids are unique', () {
        final all = [
          ...pack.lessons.map((l) => l.id),
          ...pack.questions.map((q) => q.id),
          ...pack.exams.map((e) => e.id),
          ...pack.books.map((b) => b.id),
        ];
        expect(all.toSet(), hasLength(all.length));
      });

      test('every question is answerable and gradable', () {
        for (final q in pack.questions) {
          final why = q.id;
          expect(q.prompt.trim(), isNotEmpty, reason: why);
          switch (q.type) {
            case QuestionType.mcq:
              expect(q.options.length, greaterThanOrEqualTo(2), reason: why);
              expect(q.answer, isA<int>(), reason: why);
              expect(q.answer as int, inInclusiveRange(0, q.options.length - 1), reason: why);
            case QuestionType.trueFalse:
              expect(q.answer, isA<bool>(), reason: why);
            case QuestionType.fill || QuestionType.short:
              expect(q.accepted, isNotEmpty, reason: why);
            case QuestionType.numeric:
              expect(q.answer, isA<num>(), reason: why);
            case QuestionType.match:
              expect(q.pairs.length, greaterThanOrEqualTo(2), reason: why);
              expect(q.pairs.map((p) => p.right).toSet(), hasLength(q.pairs.length), reason: why);
            case QuestionType.essay:
              expect(q.modelAnswer, isNotNull, reason: why);
          }
          expect(q.correctAnswerText, isNotEmpty, reason: why);
        }
      });

      test('lessons are complete and linked to the book', () {
        for (final l in pack.lessons) {
          expect(l.objectives, isNotEmpty, reason: l.id);
          expect(l.explanation, isNotEmpty, reason: l.id);
          expect(l.summary, isNotEmpty, reason: l.id);
          expect(l.questions.length, greaterThanOrEqualTo(4), reason: l.id);
          final book = pack.subjects[l.subjectId]!.books.first;
          expect(book.pages[l.bookPage! - 1].lessonId, l.id, reason: l.id);
        }
      });

      test('exams have enough questions', () {
        for (final e in pack.exams) {
          expect(pack.subjects[e.subjectId]!.questions.length, greaterThanOrEqualTo(e.questionCount), reason: e.id);
        }
      });
    });
  }

  test('books shipped with or linked from the app point to real grades and subjects', () {
    final books = parseBundledBooks(File('assets/content/bundled_books.json').readAsStringSync());
    for (final b in books) {
      final grade = catalog.grade(b.gradeId);
      expect(grade, isNotNull, reason: b.book.id);
      expect(grade!.subjects.map((s) => s.id), contains(b.book.subjectId), reason: b.book.id);
      expect(b.book.isPdf, isTrue, reason: b.book.id);
      if (b.book.pdfUrl case final url?) expect(Uri.parse(url).isScheme('https'), isTrue, reason: url);
    }
  });
}
