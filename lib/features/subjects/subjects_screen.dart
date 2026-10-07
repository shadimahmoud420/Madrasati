import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../books/book_tile.dart';
import '../books/library.dart';
import '../progress/learner_stats.dart';
import '../quiz/quiz_launcher.dart';

class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grade = ref.watch(currentGradeProvider);
    final pack = ref.watch(packProvider).value;
    final books = ref.watch(gradeBooksProvider).value ?? const <Book>[];
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
              subtitle: content == null || content.lessons.isEmpty
                  ? Text(switch (books.where((b) => b.subjectId == s.id).length) {
                      0 => 'المحتوى قيد الإعداد',
                      1 => 'كتاب واحد',
                      final n => '$n كتب',
                    })
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
          final books = (ref.watch(gradeBooksProvider).value ?? const <Book>[])
              .where((b) => b.subjectId == widget.subjectId && (b.semester == null || b.semester == semester))
              .toList();
          final units = content?.units.where((u) => u.semester == semester).toList() ?? const <Unit>[];
          final subjectStats = stats?.subjects.where((x) => x.subjectId == widget.subjectId).firstOrNull;
          final hasQuestions = content?.questions.isNotEmpty ?? false;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (subjectStats != null && subjectStats.totalLessons > 0) ...[
                _SubjectSummary(stats: subjectStats),
                const SizedBox(height: 12),
              ],
              if (hasQuestions) ...[
                FilledButton.icon(
                  onPressed: () => QuizLauncher(ref).testMe(context, subjectId: widget.subjectId),
                  icon: const Icon(Icons.quiz),
                  label: const Text('اختبرني في هذه المادة'),
                ),
                const SizedBox(height: 16),
              ],
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('الفصل الأول')),
                  ButtonSegment(value: 2, label: Text('الفصل الثاني')),
                ],
                selected: {semester},
                onSelectionChanged: (v) => setState(() => _semester = v.first),
              ),
              const SectionTitle('الكتب'),
              Card(
                child: Column(
                  children: [
                    for (final b in books) BookTile(book: b),
                    ListTile(
                      key: const Key('import_book'),
                      leading: const Icon(Icons.upload_file),
                      title: const Text('إضافة كتاب PDF من جهازي'),
                      subtitle: const Text('مثل كتاب وصلك عبر واتساب أو تيليجرام'),
                      onTap: () => importBookFromDevice(context, ref, subjectId: widget.subjectId, semester: semester),
                    ),
                  ],
                ),
              ),
              if (content == null)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text(
                    'الدروس والأسئلة لهذه المادة قيد الإعداد، وستظهر تلقائيًا عند إضافتها.',
                    textAlign: TextAlign.center,
                  ),
                )
              else if (units.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text('لا توجد دروس لهذا الفصل بعد.', textAlign: TextAlign.center),
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
              if (content != null && content.exams.isNotEmpty) ...[
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
