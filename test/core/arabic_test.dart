import 'package:flutter_test/flutter_test.dart';
import 'package:madrasati/core/arabic.dart';

void main() {
  test('normalizeArabic removes diacritics and unifies letter forms', () {
    expect(normalizeArabic('الفلاحُ يزرعُ الزيتونَ.'), 'الفلاح يزرع الزيتون');
    expect(normalizeArabic('إلى  مدرسةٍ'), normalizeArabic('الي مدرسه'));
    expect(normalizeArabic('He HAS'), 'he has');
  });

  test('normalizeAnswer keeps fractions', () {
    expect(normalizeAnswer(' ٢ / ٥ '), '2/5');
  });

  test('parseNumber reads Arabic digits, units, decimals and fractions', () {
    expect(parseNumber('١٢ سم'), 12);
    expect(parseNumber('2.5'), 2.5);
    expect(parseNumber('٢٫٥'), 2.5);
    expect(parseNumber('3/4'), 0.75);
    expect(parseNumber('−4'), -4);
    expect(parseNumber('لا أعرف'), isNull);
  });

  test('searchTokens strips the definite article and stop words', () {
    expect(searchTokens('قانون نيوتن الثاني'), ['قانون', 'نيوتن', 'ثاني']);
    expect(searchTokens('اشرح لي الكسور'), ['كسور']);
  });
}
