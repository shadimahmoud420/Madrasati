import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasati/app.dart';
import 'package:madrasati/core/providers.dart';
import 'package:madrasati/core/router.dart';
import 'package:madrasati/data/backend.dart';
import 'package:madrasati/data/database.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() => db.close());

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    Backend? backend,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: await testOverrides(
        prefs: await testPrefs(prefs),
        db: db,
        backend: backend,
        clock: () => DateTime(2026, 10, 7, 18),
      ),
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(contentSyncProvider).installBundled());
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MadrasatiApp()));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('onboarding: stage → grade → home with that grade\'s content', (tester) async {
    await pumpApp(tester);
    expect(find.text('أهلًا بك في مدرستي'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('name_field')), 'سارة');
    await tester.ensureVisible(find.byKey(const Key('stage_lowerBasic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stage_lowerBasic')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('grade_g4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grade_g4')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('start_button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    expect(find.text('مرحبًا يا سارة'), findsOneWidget);
    expect(find.text('الصف الرابع'), findsOneWidget);
    expect(find.byKey(const Key('continue_lesson')), findsOneWidget);
    expect(find.text('مفهوم الكسر'), findsOneWidget);
  });

  testWidgets('switching students: each sees only their own grade and progress', (tester) async {
    final container = await pumpApp(tester, prefs: {'profile.grade': 'g9', 'profile.name': 'محمود'});
    expect(find.text('مرحبًا يا محمود'), findsOneWidget);
    await tester.runAsync(
      () => container
          .read(progressRepositoryProvider)
          .saveAttempt(
            AttemptRecord(
              uid: 'm1',
              kind: AttemptKind.quiz,
              title: 't',
              startedAt: DateTime(2026, 10, 7),
              duration: Duration.zero,
              score: 1,
              maxScore: 1,
            ),
            const [],
          ),
    );

    // Sign out from settings → picker → add a new student.
    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch_student')));
    await tester.pumpAndSettle();
    expect(find.text('من يدرس الآن؟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add_student')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name_field')), 'محمد');
    await tester.ensureVisible(find.byKey(const Key('stage_lowerBasic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stage_lowerBasic')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('grade_g4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grade_g4')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('start_button')),
      200,
      scrollable: find.ancestor(of: find.byKey(const Key('name_field')), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pumpAndSettle();

    expect(find.text('مرحبًا يا محمد'), findsOneWidget);
    expect(find.text('الصف الرابع'), findsOneWidget);
    expect((await container.read(statsProvider.future)).attemptCount, 0);

    // Back to Mahmoud: his grade and his result are still there.
    container.read(routerProvider).go('/settings');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch_student')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('محمود'));
    await tester.pumpAndSettle();
    expect(find.text('مرحبًا يا محمود'), findsOneWidget);
    expect(find.text('الصف التاسع'), findsOneWidget);
    expect((await container.read(statsProvider.future)).attemptCount, 1);
  });

  testWidgets('grade without content shows a clear placeholder', (tester) async {
    await pumpApp(tester, prefs: {'profile.grade': 'g7'});
    expect(find.text('محتوى صفك قيد الإعداد'), findsOneWidget);
  });

  testWidgets('lesson → practice with feedback → result → progress', (tester) async {
    final container = await pumpApp(tester, prefs: {'profile.grade': 'g4', 'profile.name': 'أحمد'});

    await tester.tap(find.text('المواد'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('subject_g4_math')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lesson_g4_math_l1')));
    await tester.pumpAndSettle();
    expect(find.text('أهداف الدرس'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('practice_button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('practice_button')));
    await tester.pumpAndSettle();

    // First question (easiest): "في الكسر 3/5، ما هو البسط؟" → "3".
    await tester.tap(find.byKey(const Key('option_1')));
    await tester.tap(find.byKey(const Key('check_button')));
    await tester.pump();
    expect(find.text('إجابة صحيحة! أحسنت'), findsOneWidget);

    // Skip the rest unanswered.
    for (var i = 0; i < 20 && find.byKey(const Key('finish_button')).evaluate().isEmpty; i++) {
      final check = find.byKey(const Key('check_button'));
      await tester.tap(check.evaluate().isNotEmpty ? check : find.byKey(const Key('next_button')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('finish_button')));
    await tester.pumpAndSettle();

    expect(find.text('النتيجة'), findsOneWidget);
    expect(find.text('الأخطاء والإجابات الصحيحة'), findsOneWidget);
    expect(find.text('دروس تحتاج إلى مراجعة'), findsOneWidget);
    // 1 of 8 auto-graded questions right (the essay isn't scored).
    expect(find.text('13%'), findsOneWidget);

    final stats = await container.read(statsProvider.future);
    expect(stats.attemptCount, 1);
    expect(stats.completedLessons, 1);
    expect(stats.streak, 1);
    expect(await db.db.query('answers'), hasLength(8));
  });

  testWidgets('daily challenge is offered once per day', (tester) async {
    await pumpApp(tester, prefs: {'profile.grade': 'g9'});
    await tester.scrollUntilVisible(
      find.byKey(const Key('daily_challenge')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('daily_challenge')));
    await tester.pumpAndSettle();
    expect(find.text('تحدي اليوم'), findsOneWidget);
    for (var i = 0; i < 10 && find.byKey(const Key('finish_button')).evaluate().isEmpty; i++) {
      await tester.tap(find.byKey(const Key('next_button')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('finish_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('result_done')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('أنجزت تحدي اليوم!'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('أنجزت تحدي اليوم!'), findsOneWidget);
  });

  testWidgets('search finds lessons offline', (tester) async {
    await pumpApp(tester, prefs: {'profile.grade': 'g9'});
    await tester.tap(find.byKey(const Key('search_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search_field')), 'قانون نيوتن الثاني');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('result_lesson_g9_science_l2')), findsOneWidget);
    expect(find.text('في الكتاب'), findsOneWidget);
  });

  testWidgets('book: search inside, jump to page and bookmark', (tester) async {
    final container = await pumpApp(tester, prefs: {'profile.grade': 'g4'});
    container.read(routerProvider).push('/book/g4_math_book');
    await tester.pumpAndSettle();
    expect(find.textContaining('صفحة 1 من'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book_search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('book_search_field')), 'محيط المربع');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('صفحة 1 من'), findsNothing);

    await tester.tap(find.byKey(const Key('book_bookmark')));
    await tester.pumpAndSettle();
    expect(await ProgressRepository(db, AppDatabase.legacyProfileId).bookmarks('g4_math_book'), hasLength(1));
  });

  testWidgets('AI tutor sends the question with curriculum context', (tester) async {
    final backend = FakeBackend(reply: 'الكسر جزء من كل.');
    final container = await pumpApp(tester, prefs: {'profile.grade': 'g4'}, backend: backend);
    container.read(routerProvider).push('/tutor?lesson=g4_math_l1');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tutor_input')), 'اشرح لي البسط والمقام');
    await tester.tap(find.byKey(const Key('tutor_send')));
    await tester.pumpAndSettle();

    expect(find.text('الكسر جزء من كل.'), findsOneWidget);
    final request = backend.requests.single;
    expect(request.gradeName, 'الصف الرابع');
    expect(request.context.first.title, 'مفهوم الكسر');
    expect(request.context.first.text, contains('البسط'));
  });

  testWidgets('AI tutor explains it needs internet and offers lessons when offline', (tester) async {
    final backend = FakeBackend(offline: true);
    final container = await pumpApp(tester, prefs: {'profile.grade': 'g9'}, backend: backend);
    container.read(routerProvider).push('/tutor');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tutor_input')), 'ما هو القصور الذاتي؟');
    await tester.tap(find.byKey(const Key('tutor_send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('يحتاج إلى اتصال بالإنترنت'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'قانون نيوتن الأول (القصور الذاتي)'), findsOneWidget);
  });
}
