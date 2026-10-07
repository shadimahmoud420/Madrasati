import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../quiz/quiz_launcher.dart';

class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.lessonId});

  final String lessonId;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  bool _recorded = false;

  void _recordOpen(Lesson lesson) {
    if (_recorded) return;
    _recorded = true;
    // After the first frame: writing bumps providers this screen watches.
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(progressActionsProvider).openLesson(lesson));
  }

  @override
  Widget build(BuildContext context) {
    final pack = ref.watch(packProvider);
    return AsyncView(
      value: pack,
      builder: (pack) {
        final lesson = pack?.lesson(widget.lessonId);
        if (lesson == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off, title: 'الدرس غير متوفر'),
          );
        }
        _recordOpen(lesson);
        final book = pack!.subjects[lesson.subjectId]?.books.firstOrNull;
        final unit = pack.unit(lesson.unitId);
        return Scaffold(
          appBar: AppBar(
            title: Text(lesson.title),
            actions: [
              if (book != null && lesson.bookPage != null)
                IconButton(
                  tooltip: 'في الكتاب',
                  icon: const Icon(Icons.chrome_reader_mode),
                  onPressed: () => context.push('/book/${book.id}?page=${lesson.bookPage}'),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (unit != null) Text(unit.title, style: Theme.of(context).textTheme.labelLarge),
              _Section(icon: Icons.flag, title: 'أهداف الدرس', child: _Bullets(lesson.objectives)),
              _Section(
                icon: Icons.lightbulb,
                title: 'الشرح',
                child: Text(lesson.explanation, style: _body(context)),
              ),
              if (lesson.examples.isNotEmpty)
                _Section(icon: Icons.edit_note, title: 'أمثلة', child: _Bullets(lesson.examples)),
              if (lesson.videoUrl != null)
                _Section(
                  icon: Icons.ondemand_video,
                  title: 'فيديو تعليمي',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const OnlineOnlyNote('مشاهدة الفيديو تحتاج إلى إنترنت.'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(lesson.videoUrl!), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('مشاهدة'),
                      ),
                    ],
                  ),
                ),
              _Section(icon: Icons.star, title: 'أهم النقاط', child: _Bullets(lesson.keyPoints)),
              _Section(
                icon: Icons.summarize,
                title: 'ملخص الدرس',
                child: Text(lesson.summary, style: _body(context)),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('practice_button'),
                onPressed: () async {
                  await ref.read(progressActionsProvider).completeLesson(lesson);
                  if (context.mounted) await QuizLauncher(ref).practice(context, lesson);
                },
                icon: const Icon(Icons.fitness_center),
                label: Text('أسئلة تدريبية (${lesson.questions.length})'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(progressActionsProvider).completeLesson(lesson);
                  if (context.mounted) await QuizLauncher(ref).testMe(context, lessonId: lesson.id, count: 5);
                },
                icon: const Icon(Icons.timer),
                label: const Text('اختبار سريع'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => context.push('/tutor?lesson=${lesson.id}'),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('اسأل المعلم الذكي عن هذا الدرس'),
              ),
            ],
          ),
        );
      },
    );
  }

  TextStyle? _body(BuildContext context) => Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7);
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    ),
  );
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  '),
              Expanded(child: Text(item, style: const TextStyle(height: 1.6))),
            ],
          ),
        ),
    ],
  );
}
