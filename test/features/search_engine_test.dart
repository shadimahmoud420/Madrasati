import 'package:flutter_test/flutter_test.dart';
import 'package:madrasati/features/search/search_engine.dart';

import '../helpers/harness.dart';

void main() {
  final pack = loadPack('g9');
  final engine = SearchEngine(pack, loadCatalog().grade('g9')!.subjects);

  test('finds the lesson, book pages and questions for a topic', () {
    final r = engine.search('قانون نيوتن الثاني');
    expect(r.lessons.first.id, 'g9_science_l2');
    expect(r.pages, isNotEmpty);
    expect(r.pages.first.page.lessonId, 'g9_science_l2');
    expect(r.questions, isNotEmpty);
  });

  test('matches without diacritics or the definite article', () {
    expect(engine.search('فيثاغورس').lessons.single.id, 'g9_math_l2');
    expect(engine.search('المعادلات').units.single.id, 'g9_math_u1');
    expect(engine.search('رياضيات').subjects.single.id, 'g9_math');
  });

  test('retrieve grounds the tutor on the focused lesson first', () {
    final docs = engine.retrieve('أعطني مثالا', focusLessonId: 'g9_math_l1');
    expect(docs.first.id, 'g9_math_l1');
    expect(engine.retrieve('ما هو القصور الذاتي').first.id, 'g9_science_l1');
  });
}
