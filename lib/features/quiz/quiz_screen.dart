import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import 'quiz_engine.dart';

class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key, required this.spec});

  final QuizSpec spec;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  late final DateTime _startedAt = ref.read(clockProvider)();
  final _stopwatch = Stopwatch()..start();
  final _responses = <int, Response>{};
  final _text = <int, TextEditingController>{};
  final _matchOptions = <int, List<String>>{};
  final _checked = <int>{};
  Timer? _ticker;
  int _index = 0;
  bool _finishing = false;

  List<Question> get _questions => widget.spec.questions;

  bool get _practice => widget.spec.kind == AttemptKind.practice;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final limit = widget.spec.timeLimit;
      if (limit != null && _stopwatch.elapsed >= limit) {
        _finish(timeUp: true);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(int i) => _text.putIfAbsent(i, () {
    final c = TextEditingController();
    c.addListener(() => _responses[i] = TextResponse(c.text));
    return c;
  });

  Future<void> _finish({bool timeUp = false}) async {
    if (_finishing) return;
    _finishing = true;
    _ticker?.cancel();
    _stopwatch.stop();
    final outcome = QuizOutcome(
      spec: widget.spec,
      startedAt: _startedAt,
      duration: _stopwatch.elapsed,
      items: [
        for (final (i, q) in _questions.indexed)
          ItemResult(question: q, response: _responses[i], score: grade(q, _responses[i])),
      ],
    );
    await ref.read(progressActionsProvider).saveOutcome(outcome);
    if (!mounted) return;
    if (timeUp) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتهى الوقت! تم تسليم إجاباتك.')));
    }
    context.pushReplacement('/quiz/result', extra: outcome);
  }

  Future<bool> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الخروج من الاختبار؟'),
        content: const Text('لن تُحفظ إجاباتك إذا خرجت الآن.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('متابعة')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('خروج')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final q = _questions[_index];
    final limit = widget.spec.timeLimit;
    final clock = limit == null ? _stopwatch.elapsed : limit - _stopwatch.elapsed;
    final last = _index == _questions.length - 1;
    final showFeedback = _practice && _checked.contains(_index);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit() && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.spec.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Center(
                child: Row(
                  children: [
                    Icon(limit == null ? Icons.timer_outlined : Icons.hourglass_bottom, size: 18),
                    const SizedBox(width: 4),
                    Text(formatDuration(clock.isNegative ? Duration.zero : clock)),
                  ],
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(6),
            child: LinearProgressIndicator(value: (_index + 1) / _questions.length),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('السؤال ${_index + 1} من ${_questions.length}', style: Theme.of(context).textTheme.labelLarge),
                Chip(label: Text(q.type.label), visualDensity: VisualDensity.compact),
                Chip(label: Text(q.difficulty.label), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 8),
            Text(q.prompt, style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.5)),
            if (q.image != null) ...[const SizedBox(height: 12), ContentImage(q.image!)],
            const SizedBox(height: 16),
            _answerInput(q),
            if (showFeedback) _Feedback(question: q, score: grade(q, _responses[_index])),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                if (_index > 0)
                  IconButton.outlined(
                    tooltip: 'السابق',
                    onPressed: () => setState(() => _index--),
                    icon: const Icon(Icons.arrow_back),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: _practice && !showFeedback && q.type.autoGraded
                      ? FilledButton(
                          key: const Key('check_button'),
                          onPressed: () => setState(() => _checked.add(_index)),
                          child: const Text('تحقق'),
                        )
                      : FilledButton(
                          key: Key(last ? 'finish_button' : 'next_button'),
                          onPressed: last ? _finish : () => setState(() => _index++),
                          child: Text(last ? 'إنهاء وعرض النتيجة' : 'التالي'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _answerInput(Question q) {
    final i = _index;
    final locked = _practice && _checked.contains(i);
    switch (q.type) {
      case QuestionType.mcq:
        final selected = (_responses[i] as ChoiceResponse?)?.index;
        return Column(
          children: [
            for (final (o, option) in q.options.indexed)
              _OptionCard(
                key: Key('option_$o'),
                text: option,
                selected: selected == o,
                onTap: locked ? null : () => setState(() => _responses[i] = ChoiceResponse(o)),
              ),
          ],
        );
      case QuestionType.trueFalse:
        final value = (_responses[i] as BoolResponse?)?.value;
        return Row(
          children: [
            for (final (v, label) in const [(true, 'صح'), (false, 'خطأ')]) ...[
              Expanded(
                child: _OptionCard(
                  key: Key('tf_$v'),
                  text: label,
                  icon: v ? Icons.check : Icons.close,
                  selected: value == v,
                  onTap: locked ? null : () => setState(() => _responses[i] = BoolResponse(v)),
                ),
              ),
              if (v) const SizedBox(width: 12),
            ],
          ],
        );
      case QuestionType.fill:
      case QuestionType.short:
      case QuestionType.numeric:
      case QuestionType.essay:
        final numeric = q.type == QuestionType.numeric;
        return TextField(
          key: const Key('answer_field'),
          controller: _controllerFor(i),
          readOnly: locked,
          minLines: q.type == QuestionType.essay ? 4 : 1,
          maxLines: q.type == QuestionType.essay ? 8 : 2,
          keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
          decoration: InputDecoration(
            hintText: switch (q.type) {
              QuestionType.numeric => 'اكتب الناتج${q.unit == null ? '' : ' (${q.unit})'}',
              QuestionType.essay => 'اكتب إجابتك. ستظهر لك الإجابة النموذجية في النهاية.',
              _ => 'اكتب إجابتك هنا',
            },
          ),
        );
      case QuestionType.match:
        final options = _matchOptions.putIfAbsent(
          i,
          () => [for (final p in q.pairs) p.right]..shuffle(Random(q.id.length + i)),
        );
        final choices = (_responses[i] as MatchResponse?)?.choices ?? const <int, String>{};
        return Column(
          children: [
            for (final (p, pair) in q.pairs.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(pair.left, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    const Icon(Icons.arrow_forward, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: Key('match_$p'),
                        initialValue: choices[p],
                        hint: const Text('اختر'),
                        isExpanded: true,
                        items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
                        onChanged: locked
                            ? null
                            : (v) => setState(() => _responses[i] = MatchResponse({...choices, p: v!})),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
    }
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({super.key, required this.text, required this.selected, this.onTap, this.icon});

  final String text;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              mainAxisAlignment: icon == null ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
                Flexible(child: Text(text, style: const TextStyle(fontSize: 17))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.question, required this.score});

  final Question question;
  final double? score;

  @override
  Widget build(BuildContext context) {
    final correct = score == 1;
    final color = correct ? Colors.green : Colors.red;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            correct ? 'إجابة صحيحة! أحسنت' : 'الإجابة الصحيحة: ${question.correctAnswerText}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color.shade700),
          ),
          if (question.explanation != null) ...[const SizedBox(height: 6), Text(question.explanation!)],
        ],
      ),
    );
  }
}
