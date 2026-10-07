import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasati/core/providers.dart';
import 'package:madrasati/data/database.dart';

import '../helpers/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() => db.close());

  String bumped(String gradeId, int version) {
    final json = jsonDecode(packJson(gradeId)) as Map<String, dynamic>;
    json['version'] = version;
    (json['subjects'] as List).removeLast();
    return jsonEncode(json);
  }

  Future<ProviderContainer> container(FakeBackend backend) async {
    final c = ProviderContainer(
      overrides: testOverrides(prefs: await testPrefs({'profile.grade': 'g4'}), db: db, backend: backend),
    );
    addTearDown(c.dispose);
    await c.read(contentSyncProvider).installBundled();
    return c;
  }

  test('installs bundled packs once and pulls newer server versions', () async {
    final backend = FakeBackend(versions: {'g4': 2}, packs: {'g4': bumped('g4', 2)});
    final c = await container(backend);
    expect((await c.read(packProvider.future))!.version, 1);

    expect(await c.read(contentSyncProvider).pull('g4'), SyncResult.updated);
    final pack = await c.read(packProvider.future);
    expect(pack!.version, 2);
    expect(pack.subjects, hasLength(2));

    expect(await c.read(contentSyncProvider).pull('g4'), SyncResult.upToDate);
    // Re-installing bundled content never downgrades a newer download.
    await c.read(contentSyncProvider).installBundled();
    expect((await c.read(packProvider.future))!.version, 2);
  });

  test('offline pull keeps the local pack', () async {
    final c = await container(FakeBackend(offline: true));
    expect(await c.read(contentSyncProvider).pull('g4'), SyncResult.offline);
    expect((await c.read(packProvider.future))!.version, 1);
  });

  test('push uploads queued attempts once the connection is back', () async {
    final backend = FakeBackend(offline: true);
    final c = await container(backend);
    final repo = c.read(progressRepositoryProvider);
    await repo.saveAttempt(
      AttemptRecord(
        uid: 'u1',
        kind: AttemptKind.quiz,
        title: 't',
        startedAt: DateTime(2026),
        duration: Duration.zero,
        score: 1,
        maxScore: 2,
      ),
      const [],
    );
    await c.read(contentSyncProvider).push();
    expect(await repo.unsyncedAttempts(), hasLength(1));

    backend.offline = false;
    await c.read(contentSyncProvider).push();
    expect(backend.uploaded.single.uid, 'u1');
    expect(await repo.unsyncedAttempts(), isEmpty);
  });
}
