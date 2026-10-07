import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import '../search/search_screen.dart';

class _Message {
  const _Message({required this.fromStudent, required this.text, this.sources = const [], this.notice = false});

  final bool fromStudent;
  final String text;

  /// Curriculum lessons the answer was grounded on.
  final List<Lesson> sources;

  /// System notices (offline, not configured) aren't sent back as history.
  final bool notice;
}

/// AI teacher grounded on the app's curriculum: relevant lessons are found
/// on the device and sent with the question, and the server-side prompt
/// tells the model to answer from them at the student's grade level.
class TutorScreen extends ConsumerStatefulWidget {
  const TutorScreen({super.key, this.lessonId});

  final String? lessonId;

  @override
  ConsumerState<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends ConsumerState<TutorScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];
  bool _waiting = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _waiting) return;
    _input.clear();
    final engine = ref.read(searchEngineProvider);
    final sources = engine.retrieve(question, focusLessonId: widget.lessonId);
    final history = [
      for (final m in _messages.where((m) => !m.notice).toList().reversed.take(8).toList().reversed)
        TutorMessage(fromStudent: m.fromStudent, text: m.text),
    ];
    setState(() {
      _messages.add(_Message(fromStudent: true, text: question));
      _waiting = true;
    });
    _scrollDown();

    final backend = ref.read(backendProvider);
    final grade = ref.read(currentGradeProvider);
    final profile = ref.read(profileProvider);
    _Message reply;
    if (!backend.enabled) {
      reply = _Message(
        fromStudent: false,
        notice: true,
        sources: sources,
        text: sources.isEmpty
            ? 'المعلم الذكي لم يُفعَّل في هذه النسخة بعد. جرّب البحث في دروسك.'
            : 'المعلم الذكي لم يُفعَّل في هذه النسخة بعد، لكن وجدت في منهجك دروسًا تجيب عن سؤالك:',
      );
    } else {
      try {
        final subject = sources.isEmpty
            ? null
            : grade?.subjects.where((s) => s.id == sources.first.subjectId).firstOrNull?.name;
        final answer = await backend.askTutor(
          TutorRequest(
            gradeName: grade?.fullName ?? '',
            studentName: profile?.name ?? '',
            subjectName: subject,
            history: history,
            question: question,
            context: [for (final l in sources) (title: l.title, text: l.fullText)],
          ),
        );
        reply = _Message(fromStudent: false, text: answer, sources: sources);
      } on BackendException catch (e) {
        reply = _Message(
          fromStudent: false,
          notice: true,
          sources: sources,
          text: e.offline
              ? 'المعلم الذكي يحتاج إلى اتصال بالإنترنت. إلى أن يعود الاتصال، هذه دروس من منهجك قد تساعدك:'
              : 'تعذّر الحصول على إجابة الآن (${e.message}). حاول مرة أخرى بعد قليل.',
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _messages.add(reply);
      _waiting = false;
    });
    _scrollDown();
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lessonId == null ? null : ref.watch(packProvider).value?.lesson(widget.lessonId!);
    final suggestions = lesson == null
        ? const ['اشرح لي درس الكسور بطريقة سهلة', 'لم أفهم قانون نيوتن الثاني', 'اختبرني بسؤال في الرياضيات']
        : ['اشرح لي هذا الدرس بطريقة سهلة', 'أعطني مثالًا آخر', 'لخّص الدرس في نقاط', 'اختبرني بسؤال عن الدرس'];
    return Scaffold(
      appBar: AppBar(title: Text(lesson == null ? 'المعلم الذكي' : 'المعلم الذكي: ${lesson.title}')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: OnlineOnlyNote('يحتاج إلى إنترنت. يجيب اعتمادًا على دروس منهجك داخل التطبيق.'),
          ),
          Expanded(
            child: _messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('اسألني عن أي درس، وسأشرحه لك خطوة بخطوة بما يناسب صفك.'),
                      const SizedBox(height: 16),
                      for (final s in suggestions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ActionChip(label: Text(s), onPressed: () => _send(s)),
                        ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_waiting ? 1 : 0),
                    itemBuilder: (context, i) => i == _messages.length
                        ? const Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
                          )
                        : _Bubble(message: _messages[i]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('tutor_input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: const InputDecoration(hintText: 'اكتب سؤالك…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('tutor_send'),
                    onPressed: _waiting ? null : () => _send(_input.text),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.fromStudent;
    return Align(
      alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(message.text, style: const TextStyle(height: 1.6)),
            if (message.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final l in message.sources)
                    ActionChip(
                      avatar: const Icon(Icons.school, size: 16),
                      label: Text(l.title),
                      onPressed: () => context.push('/lesson/${l.id}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
