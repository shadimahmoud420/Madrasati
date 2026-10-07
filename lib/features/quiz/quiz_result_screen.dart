import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import 'quiz_engine.dart';

class QuizResultScreen extends ConsumerWidget {
  const QuizResultScreen({super.key, required this.outcome});

  final QuizOutcome outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = ref.watch(packProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final passed = outcome.passed;
    final color = passed ? Colors.green : Colors.orange;
    final review = [for (final id in outcome.lessonsToReview) ?pack?.lesson(id)];
    return Scaffold(
      appBar: AppBar(title: const Text('النتيجة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: color.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(passed ? Icons.emoji_events : Icons.trending_up, size: 56, color: color),
                  const SizedBox(height: 8),
                  Text(
                    '${outcome.percent}%',
                    key: const Key('result_percent'),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(passed ? 'ناجح – أحسنت!' : 'تحتاج إلى مراجعة، لا بأس، حاول مجددًا'),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 20,
                    runSpacing: 8,
                    children: [
                      _Metric('الدرجة', '${_fmt(outcome.score)}/${outcome.maxScore}'),
                      _Metric('صحيحة', '${outcome.correctCount}'),
                      _Metric('أخطاء', '${outcome.mistakes.length}'),
                      _Metric('الوقت', formatDuration(outcome.duration)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (review.isNotEmpty) ...[
            const SectionTitle('دروس تحتاج إلى مراجعة'),
            Card(
              child: Column(
                children: [
                  for (final lesson in review)
                    ListTile(
                      leading: const Icon(Icons.replay),
                      title: Text(lesson.title),
                      subtitle: const Text('راجع الشرح ← حل الأسئلة ← أعد الاختبار'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/lesson/${lesson.id}'),
                    ),
                ],
              ),
            ),
          ],
          if (outcome.mistakes.isNotEmpty) ...[
            const SectionTitle('الأخطاء والإجابات الصحيحة'),
            for (final item in outcome.mistakes) _ReviewCard(item: item, color: scheme.error),
          ],
          if (outcome.ungraded.isNotEmpty) ...[
            const SectionTitle('أسئلة مقالية (قارن إجابتك بالنموذجية)'),
            for (final item in outcome.ungraded) _ReviewCard(item: item, color: scheme.primary),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const Key('result_done'),
            onPressed: () => context.pop(),
            icon: const Icon(Icons.check),
            label: const Text('تم'),
          ),
        ),
      ),
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item, required this.color});

  final ItemResult item;
  final Color color;

  String _given() => switch (item.response) {
    null => 'لم تُجب',
    ChoiceResponse(:final index) => item.question.options[index],
    BoolResponse(:final value) => value ? 'صح' : 'خطأ',
    TextResponse(:final text) => text.trim().isEmpty ? 'لم تُجب' : text,
    MatchResponse(:final choices) => [
      for (final (i, p) in item.question.pairs.indexed) '${p.left} ← ${choices[i] ?? '؟'}',
    ].join('، '),
  };

  @override
  Widget build(BuildContext context) {
    final q = item.question;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q.prompt, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('إجابتك: ${_given()}'),
              const SizedBox(height: 4),
              Text(
                q.type == QuestionType.essay
                    ? 'الإجابة النموذجية: ${q.correctAnswerText}'
                    : 'الصحيح: ${q.correctAnswerText}',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              if (q.explanation != null) ...[const SizedBox(height: 4), Text(q.explanation!)],
            ],
          ),
        ),
      ),
    );
  }
}
