import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/backend.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../features/progress/learner_stats.dart';
import '../features/quiz/quiz_engine.dart';

// ---------------------------------------------------------------- injected

/// Overridden in `main()` (and tests) with ready instances.
final sharedPreferencesProvider = Provider<SharedPreferencesWithCache>((ref) => throw UnimplementedError());
final appDatabaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());
final catalogProvider = Provider<Catalog>((ref) => throw UnimplementedError());
final backendProvider = Provider<Backend>((ref) => const OfflineBackend());
final assetBundleProvider = Provider<AssetBundle>((ref) => rootBundle);

/// Injectable clock for tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final packStoreProvider = Provider<PackStore>((ref) => PackStore(ref.watch(appDatabaseProvider)));
final profileStoreProvider = Provider<ProfileStore>((ref) => ProfileStore(ref.watch(appDatabaseProvider)));

/// Students on this device, loaded before the first frame (see
/// [ProfilesController.bootstrap]).
final initialProfilesProvider = Provider<List<Profile>>((ref) => const []);

/// The signed-in student's activity only.
final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => ProgressRepository(ref.watch(appDatabaseProvider), ref.watch(profileProvider)?.id ?? ''),
);

// ---------------------------------------------------------------- profiles

class ProfilesState {
  const ProfilesState({required this.profiles, this.activeId});

  final List<Profile> profiles;

  /// The signed-in student, or null on the "who is studying?" screen.
  final String? activeId;

  Profile? get active => profiles.where((p) => p.id == activeId).firstOrNull;
}

/// Several students can share one device without passwords: each picks
/// their own card, and "sign out" returns to the picker. Each student's data
/// is kept apart (see [ProgressRepository]).
class ProfilesController extends Notifier<ProfilesState> {
  static const _kActive = 'profile.active';

  SharedPreferencesWithCache get _prefs => ref.read(sharedPreferencesProvider);
  ProfileStore get _store => ref.read(profileStoreProvider);
  DateTime get _now => ref.read(clockProvider)();

  @override
  ProfilesState build() {
    final profiles = ref.read(initialProfilesProvider);
    final active = _prefs.getString(_kActive);
    return ProfilesState(profiles: profiles, activeId: profiles.any((p) => p.id == active) ? active : null);
  }

  /// Loads the students, first converting the single-student settings of
  /// earlier versions into a profile that owns the existing progress.
  static Future<List<Profile>> bootstrap(SharedPreferencesWithCache prefs, ProfileStore store, DateTime now) async {
    var profiles = await store.all();
    final legacyGrade = prefs.getString('profile.grade');
    if (profiles.isEmpty && legacyGrade != null) {
      final name = prefs.getString('profile.name') ?? '';
      await store.save(
        Profile(
          id: AppDatabase.legacyProfileId,
          name: name.isEmpty ? 'طالب' : name,
          gradeId: legacyGrade,
          semester: prefs.getInt('profile.semester') ?? 1,
          avatar: 0,
          lastUsedAt: now,
        ),
        now,
      );
      await prefs.setString(_kActive, AppDatabase.legacyProfileId);
      for (final k in ['profile.grade', 'profile.name', 'profile.semester']) {
        await prefs.remove(k);
      }
      profiles = await store.all();
    }
    return profiles;
  }

  Future<Profile> create({required String name, required String gradeId, required int semester, int? avatar}) async {
    final profile = Profile(
      id: const Uuid().v4(),
      name: name,
      gradeId: gradeId,
      semester: semester,
      avatar: avatar ?? state.profiles.length % avatarCount,
      lastUsedAt: _now,
    );
    await _store.save(profile, _now);
    await _prefs.setString(_kActive, profile.id);
    state = ProfilesState(profiles: [profile, ...state.profiles], activeId: profile.id);
    return profile;
  }

  Future<void> update(Profile profile) async {
    await _store.save(profile, _now);
    state = ProfilesState(
      profiles: [for (final p in state.profiles) p.id == profile.id ? profile : p],
      activeId: state.activeId,
    );
  }

  Future<void> switchTo(String id) async {
    await _store.touch(id, _now);
    await _prefs.setString(_kActive, id);
    state = ProfilesState(profiles: await _store.all(), activeId: id);
  }

  Future<void> signOut() async {
    await _prefs.remove(_kActive);
    state = ProfilesState(profiles: state.profiles);
  }

  /// Deletes the student and all their progress on this device.
  Future<void> delete(String id) async {
    await _store.delete(id);
    if (state.activeId == id) await _prefs.remove(_kActive);
    state = ProfilesState(
      profiles: state.profiles.where((p) => p.id != id).toList(),
      activeId: state.activeId == id ? null : state.activeId,
    );
  }
}

/// Number of avatars [Profile.avatar] can point to.
const avatarCount = 8;

final profilesProvider = NotifierProvider<ProfilesController, ProfilesState>(ProfilesController.new);

/// The signed-in student.
final profileProvider = Provider<Profile?>((ref) => ref.watch(profilesProvider).active);

final currentGradeProvider = Provider<GradeInfo?>((ref) {
  final id = ref.watch(profileProvider)?.gradeId;
  return id == null ? null : ref.watch(catalogProvider).grade(id);
});

// ---------------------------------------------------------------- settings

class AppSettings {
  const AppSettings({this.themeMode = ThemeMode.system, this.remindersOn = false, this.reminderHour = 17});

  final ThemeMode themeMode;
  final bool remindersOn;
  final int reminderHour;

  AppSettings copyWith({ThemeMode? themeMode, bool? remindersOn, int? reminderHour}) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    remindersOn: remindersOn ?? this.remindersOn,
    reminderHour: reminderHour ?? this.reminderHour,
  );
}

class SettingsController extends Notifier<AppSettings> {
  static const _kTheme = 'settings.theme';
  static const _kReminders = 'settings.reminders';
  static const _kHour = 'settings.reminderHour';

  SharedPreferencesWithCache get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() => AppSettings(
    themeMode: ThemeMode.values.elementAtOrNull(_prefs.getInt(_kTheme) ?? 0) ?? ThemeMode.system,
    remindersOn: _prefs.getBool(_kReminders) ?? false,
    reminderHour: _prefs.getInt(_kHour) ?? 17,
  );

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setInt(_kTheme, mode.index);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setReminders({required bool on, int? hour}) async {
    await _prefs.setBool(_kReminders, on);
    if (hour != null) await _prefs.setInt(_kHour, hour);
    state = state.copyWith(remindersOn: on, reminderHour: hour);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

// ---------------------------------------------------------------- content

/// Bumped whenever a pack is (re)stored so readers reload.
class _Revision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final packRevisionProvider = NotifierProvider<_Revision, int>(_Revision.new);
final progressRevisionProvider = NotifierProvider<_Revision, int>(_Revision.new);

/// The current grade's content, from local storage. Null when there is no
/// content for the grade yet.
final packProvider = FutureProvider<GradePack?>((ref) async {
  ref.watch(packRevisionProvider);
  final gradeId = ref.watch(profileProvider.select((p) => p?.gradeId));
  if (gradeId == null) return null;
  return ref.read(packStoreProvider).load(gradeId);
});

enum SyncResult { upToDate, updated, offline, unavailable, error }

class ContentSync {
  ContentSync(this.ref);

  final Ref ref;

  /// Copies packs shipped in the app into the database when they are newer
  /// than what is stored (first launch, or after an app update).
  Future<void> installBundled() async {
    final store = ref.read(packStoreProvider);
    final stored = await store.versions();
    final bundle = ref.read(assetBundleProvider);
    for (final e in ref.read(catalogProvider).bundledPacks.entries) {
      if ((stored[e.key] ?? 0) >= e.value) continue;
      await store.save(await bundle.loadString('assets/content/packs/${e.key}.json'));
    }
    ref.read(packRevisionProvider.notifier).bump();
  }

  /// Downloads a newer pack for [gradeId] from the server if there is one.
  Future<SyncResult> pull(String gradeId) async {
    final backend = ref.read(backendProvider);
    if (!backend.enabled) return SyncResult.unavailable;
    try {
      final remote = (await backend.packVersions())[gradeId];
      if (remote == null) return SyncResult.upToDate;
      final store = ref.read(packStoreProvider);
      if ((await store.version(gradeId) ?? 0) >= remote) return SyncResult.upToDate;
      await store.save(await backend.downloadPack(gradeId));
      ref.read(packRevisionProvider.notifier).bump();
      return SyncResult.updated;
    } on BackendException catch (e) {
      return e.offline ? SyncResult.offline : SyncResult.error;
    } on FormatException {
      return SyncResult.error;
    }
  }

  /// Uploads attempts made offline. Silent: retried on the next call.
  Future<void> push() async {
    final backend = ref.read(backendProvider);
    final gradeId = ref.read(profileProvider)?.gradeId;
    if (!backend.enabled || gradeId == null) return;
    final repo = ref.read(progressRepositoryProvider);
    try {
      final pending = await repo.unsyncedAttempts();
      await backend.uploadAttempts(gradeId, pending);
      await repo.markAttemptsSynced([for (final a in pending) a.id!]);
    } on BackendException {
      // Offline or server error: keep them queued.
    }
  }

  Future<void> syncAll() async {
    final gradeId = ref.read(profileProvider)?.gradeId;
    if (gradeId != null) await pull(gradeId);
    await push();
  }
}

final contentSyncProvider = Provider<ContentSync>(ContentSync.new);

// ---------------------------------------------------------------- progress

final statsProvider = FutureProvider<LearnerStats>((ref) async {
  ref.watch(progressRevisionProvider);
  final repo = ref.watch(progressRepositoryProvider);
  final pack = await ref.watch(packProvider.future);
  return LearnerStats.compute(
    pack: pack,
    progress: await repo.lessonProgress(),
    attempts: await repo.attempts(),
    answers: await repo.answers(),
    activityDays: await repo.activityDays(),
    now: ref.read(clockProvider)(),
  );
});

/// Write side of progress: stores locally, refreshes stats, and queues a sync.
class ProgressActions {
  ProgressActions(this.ref);

  final Ref ref;

  ProgressRepository get _repo => ref.read(progressRepositoryProvider);

  DateTime get _now => ref.read(clockProvider)();

  void _changed() {
    ref.read(progressRevisionProvider.notifier).bump();
    ref.read(contentSyncProvider).push();
  }

  Future<void> openLesson(Lesson lesson) async {
    await _repo.openLesson(lesson, _now);
    _changed();
  }

  Future<void> completeLesson(Lesson lesson) async {
    await _repo.completeLesson(lesson, _now);
    _changed();
  }

  Future<void> saveOutcome(QuizOutcome outcome) async {
    final end = outcome.startedAt.add(outcome.duration);
    await _repo.saveAttempt(
      AttemptRecord(
        uid: const Uuid().v4(),
        kind: outcome.spec.kind,
        title: outcome.spec.title,
        subjectId: outcome.spec.subjectId,
        lessonId: outcome.spec.lessonId,
        examId: outcome.spec.examId,
        startedAt: outcome.startedAt,
        duration: outcome.duration,
        score: outcome.score,
        maxScore: outcome.maxScore.toDouble(),
      ),
      [
        for (final item in outcome.graded)
          AnswerRecord(
            questionId: item.question.id,
            lessonId: item.question.lessonId,
            subjectId: item.question.subjectId,
            score: item.score!,
            answeredAt: end,
          ),
      ],
    );
    _changed();
  }
}

final progressActionsProvider = Provider<ProgressActions>(ProgressActions.new);

/// Last score per question, to avoid repeating ones already mastered.
final lastScoresProvider = FutureProvider<Map<String, double>>((ref) async {
  ref.watch(progressRevisionProvider);
  final answers = await ref.watch(progressRepositoryProvider).answers();
  return {for (final a in answers) a.questionId: a.score};
});
