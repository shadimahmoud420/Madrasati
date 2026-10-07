import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/backend.dart';
import 'data/database.dart';
import 'data/models.dart';
import 'features/settings/reminder_service.dart';
import 'features/settings/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  final db = await AppDatabase.open(p.join(await getDatabasesPath(), 'madrasati.db'));
  final catalog = Catalog.fromJson(
    jsonDecode(await rootBundle.loadString('assets/content/catalog.json')) as Map<String, dynamic>,
  );
  const configured = AppConfig.supabaseUrl != '' && AppConfig.supabaseAnonKey != '';
  final profiles = await ProfilesController.bootstrap(prefs, ProfileStore(db), DateTime.now());

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      catalogProvider.overrideWithValue(catalog),
      initialProfilesProvider.overrideWithValue(profiles),
      reminderServiceProvider.overrideWithValue(LocalReminderService()),
      if (configured)
        backendProvider.overrideWith(
          (ref) => SupabaseBackend(
            url: AppConfig.supabaseUrl,
            anonKey: AppConfig.supabaseAnonKey,
            prefs: prefs,
            scope: () => ref.read(profileProvider)?.id ?? 'none',
          ),
        ),
    ],
  );

  // Content shipped with the app must be in place before the first screen.
  await container.read(contentSyncProvider).installBundled();
  // Best-effort background work.
  container.read(contentSyncProvider).syncAll();
  container.read(reminderSchedulerProvider).reschedule();

  runApp(UncontrolledProviderScope(container: container, child: const MadrasatiApp()));
}
