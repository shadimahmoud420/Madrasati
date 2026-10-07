import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/books/book_screen.dart';
import '../features/home/home_screen.dart';
import '../features/lessons/lesson_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profiles/profiles_screen.dart';
import '../features/progress/progress_screen.dart';
import '../features/quiz/quiz_engine.dart';
import '../features/quiz/quiz_result_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/quiz/test_me_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/downloads_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/subjects/subjects_screen.dart';
import '../features/tutor/tutor_screen.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Read once: the start location only matters at launch.
  final profiles = ref.read(profilesProvider);
  final router = GoRouter(
    initialLocation: profiles.active != null
        ? '/home'
        : profiles.profiles.isNotEmpty
        ? '/profiles'
        : '/onboarding',
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/profiles', builder: (_, _) => const ProfilesScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/subjects', builder: (_, _) => const SubjectsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
                routes: [GoRoute(path: 'grade', builder: (_, _) => const OnboardingScreen(editing: true))],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/subject/:id',
        builder: (_, s) => SubjectScreen(subjectId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/lesson/:id',
        builder: (_, s) => LessonScreen(lessonId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/book/:id',
        builder: (_, s) => BookRouteScreen(
          bookId: s.pathParameters['id']!,
          initialPage: int.tryParse(s.uri.queryParameters['page'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/quiz',
        builder: (_, s) => QuizScreen(spec: s.extra! as QuizSpec),
      ),
      GoRoute(
        path: '/quiz/result',
        builder: (_, s) => QuizResultScreen(outcome: s.extra! as QuizOutcome),
      ),
      GoRoute(path: '/test-me', builder: (_, _) => const TestMeScreen()),
      GoRoute(path: '/exams', builder: (_, _) => const ExamsScreen()),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
      GoRoute(
        path: '/tutor',
        builder: (_, s) => TutorScreen(lessonId: s.uri.queryParameters['lesson']),
      ),
      GoRoute(path: '/downloads', builder: (_, _) => const DownloadsScreen()),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _HomeShell extends StatelessWidget {
  const _HomeShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
        NavigationDestination(
          icon: Icon(Icons.auto_stories_outlined),
          selectedIcon: Icon(Icons.auto_stories),
          label: 'المواد',
        ),
        NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'تقدّمي'),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'الإعدادات',
        ),
      ],
    ),
  );
}
