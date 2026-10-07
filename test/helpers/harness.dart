import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/misc.dart';
import 'package:madrasati/core/providers.dart';
import 'package:madrasati/data/backend.dart';
import 'package:madrasati/data/database.dart';
import 'package:madrasati/data/models.dart';
import 'package:madrasati/features/settings/reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Catalog loadCatalog() =>
    Catalog.fromJson(jsonDecode(File('assets/content/catalog.json').readAsStringSync()) as Map<String, dynamic>);

String packJson(String gradeId) => File('assets/content/packs/$gradeId.json').readAsStringSync();

GradePack loadPack(String gradeId) => GradePack.fromJson(jsonDecode(packJson(gradeId)) as Map<String, dynamic>);

/// In-memory database that runs on the calling isolate, so it also works
/// inside widget tests' fake-async zone.
Future<AppDatabase> openTestDatabase() {
  sqfliteFfiInit();
  return AppDatabase.open(inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
}

Future<SharedPreferencesWithCache> testPrefs([Map<String, Object> data = const {}]) {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(data);
  return SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
}

class FakeBackend implements Backend {
  FakeBackend({this.versions = const {}, this.packs = const {}, this.reply = 'إجابة المعلم', this.offline = false});

  final Map<String, int> versions;
  final Map<String, String> packs;
  final String reply;
  bool offline;
  final requests = <TutorRequest>[];
  final uploaded = <AttemptRecord>[];

  void _check() {
    if (offline) throw const BackendException('offline', offline: true);
  }

  @override
  bool get enabled => true;

  @override
  Future<Map<String, int>> packVersions() async {
    _check();
    return versions;
  }

  @override
  Future<String> downloadPack(String gradeId) async {
    _check();
    return packs[gradeId]!;
  }

  @override
  Future<String> askTutor(TutorRequest request) async {
    _check();
    requests.add(request);
    return reply;
  }

  @override
  Future<void> uploadAttempts(String gradeId, List<AttemptRecord> attempts) async {
    _check();
    uploaded.addAll(attempts);
  }
}

List<Override> testOverrides({
  required SharedPreferencesWithCache prefs,
  required AppDatabase db,
  Backend? backend,
  DateTime Function()? clock,
}) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  appDatabaseProvider.overrideWithValue(db),
  catalogProvider.overrideWithValue(loadCatalog()),
  reminderServiceProvider.overrideWithValue(NoopReminderService()),
  if (backend != null) backendProvider.overrideWithValue(backend),
  if (clock != null) clockProvider.overrideWithValue(clock),
];
