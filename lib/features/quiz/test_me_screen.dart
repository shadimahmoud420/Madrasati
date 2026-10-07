import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import 'quiz_launcher.dart';

/// "اختبرني": pick what to be tested on; the questions adapt to the level.
class TestMeScreen extends ConsumerStatefulWidget {
  const TestMeScreen({super.key});

  @override
  ConsumerState<TestMeScreen> createState() => _TestMeScreenState();
}

class _TestMeScreenState extends ConsumerState<TestMeScreen> {
  String? _subjectId;
  String? _lessonId;
  int _count = 8;

  @override
  Widget build(BuildContext context) {
    final grade = ref.watch(currentGradeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('اختبرني')),
      body: AsyncView(
        value: ref.watch(packProvider),
        builder: (pack) {
          if (pack == null) {
            return const EmptyState(icon: Icons.hourglass_top, title: 'لا توجد أسئلة لصفك بعد');
          }
          final subjects = grade?.subjects.where((s) => pack.subjects.containsKey(s.id)).toList() ?? [];
          final lessons = _subjectId == null ? const <Lesson>[] : pack.subjects[_subjectId]!.lessons.toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('يختار التطبيق أسئلة تناسب مستواك: أسهل إذا كنت تحتاج إلى تدريب، وأصعب كلما تحسّنت.'),
              const SectionTitle('المادة'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('كل المواد'),
                    selected: _subjectId == null,
                    onSelected: (_) => setState(() {
                      _subjectId = null;
                      _lessonId = null;
                    }),
                  ),
                  for (final s in subjects)
                    ChoiceChip(
                      key: Key('pick_${s.id}'),
                      avatar: Icon(subjectIcon(s.icon), size: 18),
                      label: Text(s.name),
                      selected: _subjectId == s.id,
                      onSelected: (_) => setState(() {
                        _subjectId = s.id;
                        _lessonId = null;
                      }),
                    ),
                ],
              ),
              if (lessons.isNotEmpty) ...[
                const SectionTitle('الدرس (اختياري)'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('كل الدروس'),
                      selected: _lessonId == null,
                      onSelected: (_) => setState(() => _lessonId = null),
                    ),
                    for (final l in lessons)
                      ChoiceChip(
                        label: Text(l.title),
                        selected: _lessonId == l.id,
                        onSelected: (_) => setState(() => _lessonId = l.id),
                      ),
                  ],
                ),
              ],
              const SectionTitle('عدد الأسئلة'),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 5, label: Text('5')),
                  ButtonSegment(value: 8, label: Text('8')),
                  ButtonSegment(value: 12, label: Text('12')),
                ],
                selected: {_count},
                onSelectionChanged: (v) => setState(() => _count = v.first),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                key: const Key('start_test'),
                onPressed: () =>
                    QuizLauncher(ref).testMe(context, subjectId: _subjectId, lessonId: _lessonId, count: _count),
                icon: const Icon(Icons.play_arrow),
                label: const Text('ابدأ الاختبار'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ExamsScreen extends ConsumerStatefulWidget {
  const ExamsScreen({super.key});

  @override
  ConsumerState<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends ConsumerState<ExamsScreen> {
  String? _subjectId;
  int _count = 10;
  int _minutes = 20;
  Difficulty? _difficulty;

  @override
  Widget build(BuildContext context) {
    final grade = ref.watch(currentGradeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الامتحانات التجريبية')),
      body: AsyncView(
        value: ref.watch(packProvider),
        builder: (pack) {
          if (pack == null) {
            return const EmptyState(icon: Icons.hourglass_top, title: 'لا توجد امتحانات لصفك بعد');
          }
          final subjects = grade?.subjects.where((s) => pack.subjects.containsKey(s.id)).toList() ?? [];
          final subjectId = _subjectId ?? subjects.firstOrNull?.id;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionTitle('نماذج جاهزة'),
              if (pack.exams.isEmpty) const Text('لا توجد نماذج بعد.'),
              for (final e in pack.exams)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.assignment),
                      title: Text(e.title),
                      subtitle: Text('${e.questionCount} أسئلة • ${e.durationMinutes} دقيقة • تصحيح تلقائي'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => QuizLauncher(ref).exam(context, e),
                    ),
                  ),
                ),
              const SectionTitle('أنشئ امتحانك'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: subjectId,
                        decoration: const InputDecoration(labelText: 'المادة'),
                        items: [for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name))],
                        onChanged: (v) => setState(() => _subjectId = v),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<Difficulty?>(
                        initialValue: _difficulty,
                        decoration: const InputDecoration(labelText: 'مستوى الصعوبة'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('متنوع')),
                          for (final d in Difficulty.values) DropdownMenuItem(value: d, child: Text(d.label)),
                        ],
                        onChanged: (v) => setState(() => _difficulty = v),
                      ),
                      const SizedBox(height: 12),
                      Text('عدد الأسئلة: $_count'),
                      Slider(
                        value: _count.toDouble(),
                        min: 5,
                        max: 30,
                        divisions: 5,
                        label: '$_count',
                        onChanged: (v) => setState(() => _count = v.round()),
                      ),
                      Text('المدة: $_minutes دقيقة'),
                      Slider(
                        value: _minutes.toDouble(),
                        min: 5,
                        max: 120,
                        divisions: 23,
                        label: '$_minutes',
                        onChanged: (v) => setState(() => _minutes = v.round()),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: subjectId == null
                            ? null
                            : () => QuizLauncher(ref).customExam(
                                context,
                                subjectId: subjectId,
                                count: _count,
                                timeLimit: Duration(minutes: _minutes),
                                difficulty: _difficulty,
                              ),
                        child: const Text('ابدأ الامتحان'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
