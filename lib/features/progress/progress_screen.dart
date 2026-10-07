import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../quiz/quiz_launcher.dart';
import 'learner_stats.dart';

final _recentAttemptsProvider = FutureProvider<List<AttemptRecord>>((ref) async {
  ref.watch(progressRevisionProvider);
  return ref.watch(progressRepositoryProvider).attempts(limit: 15);
});

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grade = ref.watch(currentGradeProvider);
    final attempts = ref.watch(_recentAttemptsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('تقدّمي')),
      body: AsyncView(
        value: ref.watch(statsProvider),
        builder: (stats) {
          String subjectName(String id) => grade?.subjects.where((s) => s.id == id).firstOrNull?.name ?? id;
          final improvement = stats.improvement;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Row(
                children: [
                  _StatTile(icon: Icons.menu_book, value: '${stats.completedLessons}', label: 'درس مكتمل'),
                  const SizedBox(width: 8),
                  _StatTile(icon: Icons.quiz, value: '${stats.attemptCount}', label: 'اختبار'),
                  const SizedBox(width: 8),
                  _StatTile(icon: Icons.timer, value: '${stats.studyTime.inMinutes}', label: 'دقيقة تدريب'),
                ],
              ),
              const SectionTitle('إنجاز المنهج'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      LabeledProgress(label: 'كل المواد', value: stats.completion),
                      if (improvement != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              improvement >= 0 ? Icons.trending_up : Icons.trending_down,
                              color: improvement >= 0 ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                improvement >= 0
                                    ? 'تحسّن مستواك هذا الأسبوع بنسبة $improvement%'
                                    : 'انخفض مستواك هذا الأسبوع بنسبة ${-improvement}%، راجع الدروس المقترحة',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SectionTitle('المواد'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (stats.subjects.isEmpty) const Text('لا توجد مواد بمحتوى بعد.'),
                      for (final s in stats.subjects) ...[
                        LabeledProgress(
                          label: subjectName(s.subjectId),
                          value: s.mastery?.ratio ?? 0,
                          trailing: s.mastery == null ? 'لم تختبر بعد' : null,
                          color: _colorFor(s.mastery?.ratio),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 14),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              'الدروس: ${s.completedLessons}/${s.totalLessons}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (stats.strengths.isNotEmpty) ...[
                const SectionTitle('نقاط القوة'),
                Card(
                  child: Column(
                    children: [
                      for (final l in stats.strengths)
                        ListTile(
                          leading: const Icon(Icons.verified, color: Colors.green),
                          title: Text(l.title),
                          subtitle: Text('ممتاز: ${(stats.lessonMastery[l.id]!.ratio * 100).round()}%'),
                        ),
                    ],
                  ),
                ),
              ],
              if (stats.recommendations.isNotEmpty) ...[
                const SectionTitle('يحتاج إلى تحسين – مسارك المقترح'),
                for (final r in stats.recommendations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r.lesson.title} – ${(r.mastery.ratio * 100).round()}%',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text('1. راجع شرح الدرس  2. اقرأ الملخص  3. حل الأسئلة التدريبية  4. أعد الاختبار'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () => context.push('/lesson/${r.lesson.id}'),
                                  child: const Text('الشرح'),
                                ),
                                FilledButton(
                                  onPressed: () => QuizLauncher(ref).testMe(context, lessonId: r.lesson.id),
                                  child: const Text('أعد الاختبار'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              const SectionTitle('الشارات'),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final b in stats.badges) _BadgeChip(badge: b)]),
              if (attempts.isNotEmpty) ...[
                const SectionTitle('آخر الاختبارات'),
                Card(
                  child: Column(
                    children: [
                      for (final a in attempts)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _colorFor(a.ratio).withValues(alpha: 0.2),
                            child: Text('${(a.ratio * 100).round()}', style: const TextStyle(fontSize: 13)),
                          ),
                          title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${a.kind.label} • ${formatDuration(a.duration)}'),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static Color _colorFor(double? ratio) {
    if (ratio == null) return Colors.grey;
    if (ratio >= 0.8) return Colors.green;
    if (ratio >= 0.6) return Colors.amber.shade700;
    return Colors.deepOrange;
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge});

  final AchievementBadge badge;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: badge.description,
    child: Chip(
      avatar: Icon(
        badge.earned ? Icons.military_tech : Icons.lock_outline,
        color: badge.earned ? Colors.amber.shade800 : Colors.grey,
      ),
      label: Text(badge.title),
      backgroundColor: badge.earned ? Colors.amber.withValues(alpha: 0.15) : null,
    ),
  );
}
