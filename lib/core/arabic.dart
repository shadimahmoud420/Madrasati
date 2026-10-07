/// Arabic-aware text helpers used for grading typed answers and for search.
library;

final _diacritics = RegExp('[ً-ْٰـ]');
final _punctuation = RegExp(r'''[.,،؛;:!?؟"'«»()\[\]{}\-_]''');
final _spaces = RegExp(r'\s+');

const _letterMap = {'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ة': 'ه', 'ى': 'ي', 'ؤ': 'و', 'ئ': 'ي'};

/// Converts Arabic-Indic and Persian digits to ASCII.
String asciiDigits(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + rune - 0x06F0);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// Lower-cases, removes diacritics/tatweel/punctuation, unifies alef/ya/ta
/// marbuta forms and digits, and collapses whitespace. "الفلاحُ يزرعُ" and
/// "الفلاح يزرع" normalize to the same string.
String normalizeArabic(String input) {
  var s = asciiDigits(input).toLowerCase().replaceAll(_diacritics, '');
  final out = StringBuffer();
  for (final ch in s.split('')) {
    out.write(_letterMap[ch] ?? ch);
  }
  s = out.toString().replaceAll(_punctuation, ' ').replaceAll(_spaces, ' ').trim();
  return s;
}

/// Normalization for answers like "2/5" where the slash matters.
String normalizeAnswer(String input) => normalizeArabic(input).replaceAll(RegExp(r'\s*/\s*'), '/');

const _stopWords = {
  'في',
  'من',
  'علي',
  'الي',
  'عن',
  'ما',
  'هو',
  'هي',
  'او',
  'ثم',
  'ان',
  'لا',
  'هل',
  'كيف',
  'لماذا',
  'هذا',
  'هذه',
  'ذلك',
  'التي',
  'الذي',
  'مع',
  'كل',
  'بعد',
  'قبل',
  'عند',
  'لي',
  'انا',
  'اريد',
  'اشرح',
  'the',
  'a',
  'an',
  'of',
  'to',
  'is',
  'in',
  'and',
  'what',
  'how',
};

/// Search tokens: normalized words with common prefixes ("ال", "وال", "بال")
/// stripped, without stop words.
List<String> searchTokens(String input) {
  final tokens = <String>[];
  for (var w in normalizeArabic(input).split(' ')) {
    if (_stopWords.contains(w)) continue;
    for (final prefix in const ['وال', 'بال', 'فال', 'كال', 'لل', 'ال']) {
      if (w.startsWith(prefix) && w.length - prefix.length >= 3) {
        w = w.substring(prefix.length);
        break;
      }
    }
    if (w.length >= 2 && !_stopWords.contains(w)) tokens.add(w);
  }
  return tokens;
}

final _number = RegExp(r'-?\d+(?:\.\d+)?(?:\s*/\s*\d+(?:\.\d+)?)?');

/// Parses the first number in a typed answer: "12", "١٢ سم", "3/4", "2.5",
/// "٢٫٥". Returns null if there is none.
double? parseNumber(String input) {
  final s = asciiDigits(input).replaceAll('٫', '.').replaceAll('−', '-').replaceAll(',', '.');
  final m = _number.firstMatch(s);
  if (m == null) return null;
  final text = m.group(0)!.replaceAll(' ', '');
  final slash = text.indexOf('/');
  if (slash < 0) return double.tryParse(text);
  final a = double.tryParse(text.substring(0, slash));
  final b = double.tryParse(text.substring(slash + 1));
  if (a == null || b == null || b == 0) return null;
  return a / b;
}
