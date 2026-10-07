import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../progress/learner_stats.dart';
import '../quiz/quiz_launcher.dart';

class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grade = ref.watch(currentGradeProvider);
    final pack = ref.watch(packProvider).value;
    final stats = ref.watch(statsProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text('مواد ${grade?.fullName ?? ''}')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: grade?.subjects.length ?? 0,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final s = grade!.subjects[i];
          final content = pack?.subjects[s.id];
          final st = stats?.subjects.where((x) => x.subjectId == s.id).firstOrNull;
          return Card(
            child: ListTile(
              key: Key('subject_${s.id}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: Color(s.color).withValues(alpha: 0.15),
                child: Icon(subjectIcon(s.icon), color: Color(s.color)),
              ),
              title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: content == null
                  ? const Text('المحتوى قيد الإعداد')
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(value: st?.completion ?? 0, minHeight: 6),
                    ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/subject/${s.id}'),
            ),
          );
        },
      ),
    );
  }
}

class SubjectScreen extends ConsumerStatefulWidget {
  const SubjectScreen({super.key, required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends ConsumerState<SubjectScreen> {
  int? _semester;

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(currentGradeProvider)?.subjects.where((s) => s.id == widget.subjectId).firstOrNull;
    final semester = _semester ?? ref.watch(profileProvider)?.semester ?? 1;
    final stats = ref.watch(statsProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(info?.name ?? '')),
      body: AsyncView(
        value: ref.watch(packProvider),
        builder: (pack) {
          final content = pack?.subjects[widget.subjectId];
          if (content == null) {
            return const EmptyState(
              icon: Icons.hourglass_top,
              title: 'محتوى هذه المادة قيد الإعداد',
              message: 'سيظهر هنا تلقائيًا عند إضافته من إدارة التطبيق واتصالك بالإنترنت.',
            );
          }
          final units = content.units.where((u) => u.semester == semester).toList();
          final subjectStats = stats?.subjects.where((x) => x.subjectId == widget.subjectId).firstOrNull;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (subjectStats != null) _SubjectSummary(stats: subjectStats),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => QuizLauncher(ref).testMe(context, subjectId: widget.subjectId),
                      icon: const Icon(Icons.quiz),
                      label: const Text('اختبرني'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: content.books.isEmpty ? null : () => context.push('/book/${content.books.first.id}'),
                      icon: const Icon(Icons.chrome_reader_mode),
                      label: const Text('الكتاب'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('الفصل الأول')),
                  ButtonSegment(value: 2, label: Text('الفصل الثاني')),
                ],
                selected: {semester},
                onSelectionChanged: (v) => setState(() => _semester = v.first),
              ),
              if (units.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text('لا توجد وحدات لهذا الفصل بعد.', textAlign: TextAlign.center),
                ),
              for (final unit in units) ...[
                SectionTitle(unit.title),
                Card(
                  child: Column(
                    children: [
                      for (final (i, lesson) in unit.lessons.indexed)
                        _LessonTile(index: i + 1, lesson: lesson, stats: stats),
                    ],
                  ),
                ),
              ],
              if (content.exams.isNotEmpty) ...[
                const SectionTitle('امتحانات تجريبية'),
                Card(
                  child: Column(
                    children: [
                      for (final e in content.exams)
                        ListTile(
                          leading: const Icon(Icons.assignment),
                          title: Text(e.title),
                          subtitle: Text('${e.questionCount} أسئلة • ${e.durationMinutes} دقيقة'),
                          onTap: () => QuizLauncher(ref).exam(context, e),
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
}

class _SubjectSummary extends StatelessWidget {
  const _SubjectSummary({required this.stats});

  final SubjectStats stats;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LabeledProgress(
            label: 'الدروس المكتملة ${stats.completedLessons}/${stats.totalLessons}',
            value: stats.completion,
          ),
          if (stats.mastery != null) ...[
            const SizedBox(height: 12),
            LabeledProgress(label: 'نسبة النجاح في الأسئلة', value: stats.mastery!.ratio, color: Colors.green),
          ],
        ],
      ),
    ),
  );
}

class _LessonTile extends ConsumerWidget {
  const _LessonTile({required this.index, required this.lesson, required this.stats});

  final int index;
  final Lesson lesson;
  final LearnerStats? stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mastery = stats?.lessonMastery[lesson.id];
    return ListTile(
      key: Key('lesson_${lesson.id}'),
      leading: CircleAvatar(child: Text('$index')),
      title: Text(lesson.title),
      subtitle: Text(
        mastery == null ? '${lesson.questions.length} سؤالًا' : 'مستواك ${(mastery.ratio * 100).round()}%',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/lesson/${lesson.id}'),
    );
  }
}
