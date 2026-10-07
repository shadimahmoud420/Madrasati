import '../../core/arabic.dart';
import '../../data/models.dart';

class SearchResults {
  const SearchResults({
    this.subjects = const [],
    this.units = const [],
    this.lessons = const [],
    this.pages = const [],
    this.questions = const [],
    this.exams = const [],
  });

  final List<SubjectInfo> subjects;
  final List<Unit> units;
  final List<Lesson> lessons;
  final List<({Book book, BookPage page})> pages;
  final List<Question> questions;
  final List<Exam> exams;

  bool get isEmpty =>
      subjects.isEmpty && units.isEmpty && lessons.isEmpty && pages.isEmpty && questions.isEmpty && exams.isEmpty;
}

/// Offline search over the current grade. Text is normalized (diacritics,
/// alef/ya forms, "ال" prefix) and ranked by how many query words match,
/// with title matches weighted higher.
class SearchEngine {
  SearchEngine(this.pack, this.subjects);

  final GradePack? pack;
  final List<SubjectInfo> subjects;

  final _cache = <Object, String>{};

  String _norm(Object key, String text) => _cache.putIfAbsent(key, () => normalizeArabic(text));

  static double score(List<String> tokens, String normTitle, String normBody) {
    var s = 0.0;
    for (final t in tokens) {
      if (normTitle.contains(t)) {
        s += 3;
      } else if (normBody.contains(t)) {
        s += 1;
      }
    }
    return s;
  }

  List<T> _rank<T>(
    Iterable<T> items,
    List<String> tokens,
    String Function(T) title,
    String Function(T) body, {
    int limit = 20,
    double minScore = 1,
  }) {
    final scored = <(T, double)>[];
    for (final item in items) {
      final s = score(tokens, _norm((item, 't'), title(item)), _norm((item, 'b'), body(item)));
      if (s >= minScore) scored.add((item, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored.take(limit)) e.$1];
  }

  SearchResults search(String query) {
    final tokens = searchTokens(query);
    if (tokens.isEmpty) return const SearchResults();
    // Require most words to match on multi-word queries.
    final min = tokens.length <= 2 ? 1.0 : tokens.length * 0.6;
    final p = pack;
    return SearchResults(
      subjects: _rank(subjects, tokens, (s) => s.name, (_) => '', minScore: min),
      units: p == null
          ? const []
          : _rank(p.subjects.values.expand((s) => s.units), tokens, (u) => u.title, (_) => '', minScore: min),
      lessons: p == null ? const [] : _rank(p.lessons, tokens, (l) => l.title, (l) => l.fullText, minScore: min),
      pages: p == null
          ? const []
          : _rank(
              [
                for (final b in p.books)
                  for (final pg in b.pages) (book: b, page: pg),
              ],
              tokens,
              (_) => '',
              (e) => e.page.text,
              minScore: min,
              limit: 10,
            ),
      questions: p == null
          ? const []
          : _rank(p.questions, tokens, (q) => q.prompt, (q) => q.explanation ?? '', minScore: min, limit: 10),
      exams: p == null ? const [] : _rank(p.exams, tokens, (e) => e.title, (_) => '', minScore: min),
    );
  }

  /// Passages for grounding the AI tutor (RAG): the best-matching lessons,
  /// always including [focusLessonId] when given.
  List<Lesson> retrieve(String query, {String? focusLessonId, int limit = 3}) {
    final p = pack;
    if (p == null) return const [];
    final focus = focusLessonId == null ? null : p.lesson(focusLessonId);
    final tokens = searchTokens(query);
    final ranked = tokens.isEmpty
        ? const <Lesson>[]
        : _rank(p.lessons, tokens, (l) => l.title, (l) => l.fullText, limit: limit);
    return [?focus, ...ranked.where((l) => l.id != focus?.id)].take(limit).toList();
  }
}
