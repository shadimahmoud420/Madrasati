import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:madrasati/app.dart';
import 'package:madrasati/core/providers.dart';
import 'package:madrasati/core/router.dart';
import 'package:madrasati/data/database.dart';
import 'package:madrasati/features/books/library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/harness.dart';

final _pdf = utf8.encode('%PDF-1.7\n% fake but well-formed header\n${'x' * 5000}');

/// g9 pack with an official PDF book added to maths (semester 1).
String _packWithPdf() {
  final json = jsonDecode(packJson('g9')) as Map<String, dynamic>;
  json['version'] = 5;
  final math = (json['subjects'] as List).cast<Map<String, dynamic>>().firstWhere((s) => s['id'] == 'g9_math');
  (math['books'] as List).add({
    'id': 'g9_math_s1',
    'title': 'الرياضيات – الصف التاسع – الجزء الأول',
    'pdfUrl': 'https://cdn.example/g9_math_s1.pdf',
    'semester': 1,
    'sizeBytes': _pdf.length,
  });
  return jsonEncode(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() => db.close());

  Future<ProviderContainer> container(http.Client client, {SharedPreferencesWithCache? prefs}) async {
    final c = ProviderContainer(
      overrides: [
        ...await testOverrides(
          prefs: prefs ?? await testPrefs({'profile.grade': 'g9', 'profile.name': 'محمود'}),
          db: db,
        ),
        httpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(c.dispose);
    await c.read(packStoreProvider).save(_packWithPdf());
    return c;
  }

  test('grade books include official PDFs, text books and imported files', () async {
    final c = await container(MockClient((_) async => http.Response('', 404)));
    final books = await c.read(gradeBooksProvider.future);
    final pdf = books.firstWhere((b) => b.id == 'g9_math_s1');
    expect(pdf.isPdf, isTrue);
    expect(pdf.semester, 1);
    expect(books.firstWhere((b) => b.id == 'g9_math_book').isPdf, isFalse);
  });

  test('download stores the PDF for offline reading and reports progress', () async {
    final c = await container(
      MockClient.streaming(
        (req, _) async => http.StreamedResponse(
          Stream.fromIterable([_pdf.sublist(0, 1000), _pdf.sublist(1000)]),
          200,
          contentLength: _pdf.length,
        ),
      ),
    );
    final progress = <double>[];
    c.listen(bookLibraryProvider, (_, next) {
      final p = next['g9_math_s1'];
      if (p != null) progress.add(p);
    });
    final book = (await c.read(gradeBooksProvider.future)).firstWhere((b) => b.id == 'g9_math_s1');
    await c.read(bookLibraryProvider.notifier).download(book);

    expect(progress.last, 1.0);
    expect(c.read(bookLibraryProvider), isEmpty);
    expect(await c.read(downloadedBooksProvider.future), {'g9_math_s1': _pdf.length});
    expect(c.read(bookLibraryProvider.notifier).fileFor(book).readAsBytesSync(), _pdf);

    await c.read(bookLibraryProvider.notifier).delete(book);
    expect(await c.read(downloadedBooksProvider.future), isEmpty);
    // Official books stay listed so they can be downloaded again.
    expect((await c.read(gradeBooksProvider.future)).map((b) => b.id), contains('g9_math_s1'));
  });

  test('failed or invalid downloads leave nothing behind', () async {
    final prefs = await testPrefs({'profile.grade': 'g9', 'profile.name': 'محمود'});
    for (final response in [http.Response('not found', 404), http.Response('<html>login</html>', 200)]) {
      final c = await container(MockClient((_) async => response), prefs: prefs);
      final book = (await c.read(gradeBooksProvider.future)).firstWhere((b) => b.id == 'g9_math_s1');
      await expectLater(c.read(bookLibraryProvider.notifier).download(book), throwsA(isA<DownloadException>()));
      expect(await c.read(downloadedBooksProvider.future), isEmpty);
      expect(c.read(booksDirProvider).listSync(), isEmpty);
      expect(c.read(bookLibraryProvider), isEmpty);
    }
  });

  test('import adds a PDF from the device; non-PDF files are refused', () async {
    final c = await container(MockClient((_) async => http.Response('', 404)));
    final library = c.read(bookLibraryProvider.notifier);
    final book = await library.importFile(
      writeTo: (dest) async => File(dest).writeAsBytesSync(_pdf),
      subjectId: 'g9_science',
      title: 'ملخص العلوم',
      semester: 2,
    );
    final books = await c.read(gradeBooksProvider.future);
    expect(books.where((b) => b.id == book.id).single.localOnly, isTrue);
    expect((await c.read(downloadedBooksProvider.future))[book.id], _pdf.length);

    await expectLater(
      library.importFile(
        writeTo: (dest) async => File(dest).writeAsStringSync('hello'),
        subjectId: 'g9_science',
        title: 'x',
      ),
      throwsA(isA<DownloadException>()),
    );
    expect((await c.read(gradeBooksProvider.future)).where((b) => b.localOnly), hasLength(1));

    await library.delete(book);
    expect((await c.read(gradeBooksProvider.future)).where((b) => b.localOnly), isEmpty);
  });

  testWidgets('subject page lists its books; an undownloaded book offers the download', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = ProviderContainer(
      overrides: [
        ...await testOverrides(prefs: await testPrefs({'profile.grade': 'g9', 'profile.name': 'محمود'}), db: db),
        httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('', 503))),
      ],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      await c.read(contentSyncProvider).installBundled();
      await c.read(packStoreProvider).save(_packWithPdf());
      c.read(packRevisionProvider.notifier).bump();
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MadrasatiApp()));
    await tester.pumpAndSettle();

    c.read(routerProvider).push('/subject/g9_math');
    await tester.pumpAndSettle();
    expect(find.text('الكتب'), findsOneWidget);
    expect(find.byKey(const Key('book_g9_math_s1')), findsOneWidget);
    expect(find.byKey(const Key('import_book')), findsOneWidget);

    await tester.tap(find.byKey(const Key('book_g9_math_s1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('download_book')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('download_book')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذّر تحميل الكتاب'), findsOneWidget);
  });
}
