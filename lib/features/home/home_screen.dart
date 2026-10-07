import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/avatars.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../progress/learner_stats.dart';
import '../quiz/quiz_launcher.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final grade = ref.watch(currentGradeProvider);
    final pack = ref.watch(packProvider);
    final stats = ref.watch(statsProvider);
    final name = (profile?.name.isNotEmpty ?? false) ? profile!.name : 'بطلنا';
    return Scaffold(
      appBar: AppBar(
        title: Text('مرحبًا يا $name'),
        actions: [
          IconButton(
            tooltip: 'تبديل الطالب',
            icon: StudentAvatar(profile?.avatar ?? 0, radius: 16),
            onPressed: () async {
              await ref.read(profilesProvider.notifier).signOut();
              if (context.mounted) context.go('/profiles');
            },
          ),
          IconButton(
            key: const Key('search_button'),
            tooltip: 'البحث',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(contentSyncProvider).syncAll(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(grade?.fullName ?? '', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            AsyncView(
              value: stats,
              builder: (s) => _LevelCard(stats: s),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('test_me_button'),
                    onPressed: () => context.push('/test-me'),
                    icon: const Icon(Icons.quiz),
                    label: const Text('اختبرني'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('tutor_button'),
                    onPressed: () => context.push('/tutor'),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('المعلم الذكي'),
                  ),
                ),
              ],
            ),
            AsyncView(
              value: pack,
              builder: (p) => p == null
                  ? const Padding(padding: EdgeInsets.only(top: 16), child: _NoContentCard())
                  : AsyncView(
                      value: stats,
                      builder: (s) => _PackSections(pack: p, stats: s, grade: grade),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.stats});

  final LearnerStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primary,
                  child: Text(
                    '${stats.level}',
                    style: TextStyle(color: scheme.onPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المستوى ${stats.level}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${stats.points} نقطة'),
                    ],
                  ),
                ),
                _Pill(icon: Icons.local_fire_department, text: '${stats.streak} يوم', color: Colors.deepOrange),
              ],
            ),
            const SizedBox(height: 12),
            LabeledProgress(
              label: 'إلى المستوى التالي',
              value: stats.pointsIntoLevel / stats.pointsForNextLevel,
              trailing: '${stats.pointsIntoLevel}/${stats.pointsForNextLevel}',
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

class _NoContentCard extends ConsumerWidget {
  const _NoContentCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hourglass_top),
              SizedBox(width: 8),
              Expanded(
                child: Text('محتوى صفك قيد الإعداد', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'نعمل على إضافة دروس وكتب صفك. يمكنك الاتصال بالإنترنت للتحقق من وجود محتوى جديد، '
            'أو تجربة التطبيق باختيار الصف الرابع أو التاسع من الإعدادات.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/downloads'),
            icon: const Icon(Icons.download),
            label: const Text('التحقق من المحتوى'),
          ),
        ],
      ),
    ),
  );
}

class _PackSections extends ConsumerWidget {
  const _PackSections({required this.pack, required this.stats, required this.grade});

  final GradePack pack;
  final LearnerStats stats;
  final GradeInfo? grade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launcher = QuizLauncher(ref);
    final continueLesson = stats.lastLesson ?? stats.nextLesson;
    final subjects = grade?.subjects ?? const <SubjectInfo>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pack.demo)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('محتوى تجريبي لأغراض الاختبار، سيُستبدل بالمحتوى المعتمد.', style: TextStyle(fontSize: 12)),
          ),
        if (continueLesson != null) ...[
          const SectionTitle('متابعة الدراسة'),
          Card(
            child: ListTile(
              key: const Key('continue_lesson'),
              leading: const Icon(Icons.play_circle_fill, size: 40),
              title: Text(continueLesson.title),
              subtitle: Text(stats.lastLesson == null ? 'ابدأ أول درس' : 'آخر درس فتحته'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/lesson/${continueLesson.id}'),
            ),
          ),
        ],
        if (pack.lessons.isEmpty) ...[
          const SectionTitle('كتب صفك'),
          Card(
            child: ListTile(
              key: const Key('books_ready'),
              leading: const Icon(Icons.picture_as_pdf, size: 36),
              title: const Text('الكتب المدرسية متوفرة'),
              subtitle: const Text('حمّلها مرة واحدة واقرأها بدون إنترنت. الدروس والأسئلة قيد الإعداد.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/subjects'),
            ),
          ),
        ] else ...[
          const SectionTitle('خطة اليوم'),
          Card(
            child: Column(
              children: [
                if (stats.nextLesson != null)
                  _PlanTile(
                    icon: Icons.menu_book,
                    title: 'ادرس: ${stats.nextLesson!.title}',
                    onTap: () => context.push('/lesson/${stats.nextLesson!.id}'),
                  ),
                if (stats.recommendations.isNotEmpty)
                  _PlanTile(
                    icon: Icons.replay,
                    title: 'راجع: ${stats.recommendations.first.lesson.title}',
                    onTap: () => launcher.testMe(context, lessonId: stats.recommendations.first.lesson.id),
                  ),
                _PlanTile(
                  key: const Key('daily_challenge'),
                  icon: stats.challengeDoneToday ? Icons.check_circle : Icons.emoji_events,
                  title: stats.challengeDoneToday
                      ? 'أنجزت تحدي اليوم!'
                      : 'تحدي اليوم: ${QuizLauncher.challengeSize} أسئلة',
                  onTap: stats.challengeDoneToday ? null : () => launcher.dailyChallenge(context),
                ),
              ],
            ),
          ),
          const SectionTitle('تقدّمك'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LabeledProgress(
                label: 'أكملت ${stats.completedLessons} من ${stats.totalLessons} درسًا',
                value: stats.completion,
              ),
            ),
          ),
        ],
        SectionTitle(
          'موادي',
          trailing: TextButton(onPressed: () => context.go('/subjects'), child: const Text('الكل')),
        ),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: subjects.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final s = subjects[i];
              return SizedBox(
                width: 108,
                child: Card(
                  color: Color(s.color).withValues(alpha: 0.15),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => context.push('/subject/${s.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(subjectIcon(s.icon), color: Color(s.color), size: 32),
                          const SizedBox(height: 6),
                          Text(s.name, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (pack.exams.isNotEmpty) ...[
          SectionTitle(
            'امتحانات تجريبية',
            trailing: TextButton(onPressed: () => context.push('/exams'), child: const Text('الكل')),
          ),
          Card(
            child: Column(
              children: [
                for (final e in pack.exams.take(2))
                  ListTile(
                    leading: const Icon(Icons.assignment),
                    title: Text(e.title),
                    subtitle: Text('${e.questionCount} أسئلة • ${e.durationMinutes} دقيقة'),
                    onTap: () => launcher.exam(context, e),
                  ),
              ],
            ),
          ),
        ],
        if (stats.recommendations.isNotEmpty) ...[
          const SectionTitle('توصيات لك'),
          for (final r in stats.recommendations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(r.lesson.title),
                  subtitle: Text('مستواك ${(r.mastery.ratio * 100).round()}% – راجع الشرح ثم حل الأسئلة'),
                  onTap: () => context.push('/lesson/${r.lesson.id}'),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({super.key, required this.icon, required this.title, this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
