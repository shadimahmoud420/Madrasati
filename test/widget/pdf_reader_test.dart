import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasati/app.dart';
import 'package:madrasati/core/router.dart';
import 'package:madrasati/features/books/library.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/harness.dart';

class _Paths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final _dir = Directory.systemTemp.createTempSync('pdfrx').path;
  @override
  Future<String?> getTemporaryPath() async => _dir;
  @override
  Future<String?> getApplicationSupportPath() async => _dir;
  @override
  Future<String?> getApplicationCachePath() async => _dir;
}

/// Rendering needs the native PDFium library, which `flutter test` only has
/// when it was placed next to the engine (see docs/RELEASE_GUIDE.md).
final _pdfium = File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/engine/linux-x64/lib/libpdfium.so');

void main() {
  PathProviderPlatform.instance = _Paths();

  testWidgets('a PDF added from the device opens from its subject page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = await openTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(
      overrides: await testOverrides(prefs: await testPrefs({'profile.grade': 'g5', 'profile.name': 'سلمى'}), db: db),
    );
    addTearDown(c.dispose);
    final book = (await tester.runAsync(
      () => c
          .read(bookLibraryProvider.notifier)
          .importFile(
            writeTo: (d) async => File('test/fixtures/sample.pdf').copySync(d),
            subjectId: 'g5_arabic',
            title: 'لغتنا الجميلة',
            semester: 1,
          ),
    ))!;

    Future<void> settle(int rounds) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MadrasatiApp()));
    await settle(5);
    c.read(routerProvider).push('/subject/g5_arabic');
    await settle(5);
    await tester.tap(find.byKey(Key('book_${book.id}')));
    await settle(40);

    expect(tester.takeException(), isNull);
    expect(find.text('صفحة 1 من 3'), findsOneWidget);
  }, skip: !_pdfium.existsSync());
}
