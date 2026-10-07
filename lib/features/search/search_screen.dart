import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../quiz/quiz_launcher.dart';
import 'search_engine.dart';

final searchEngineProvider = Provider<SearchEngine>((ref) {
  final pack = ref.watch(packProvider).value;
  return SearchEngine(pack, ref.watch(currentGradeProvider)?.subjects ?? const []);
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchEngineProvider).search(_query);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('search_field'),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ابحث عن درس أو موضوع أو كلمة',
            border: InputBorder.none,
            filled: false,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: _query.trim().length < 2
          ? const EmptyState(
              icon: Icons.manage_search,
              title: 'ابحث في كل محتوى صفك',
              message: 'الدروس، صفحات الكتب، الأسئلة والامتحانات – يعمل بدون إنترنت.',
            )
          : results.isEmpty
          ? const EmptyState(icon: Icons.search_off, title: 'لا توجد نتائج')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (results.subjects.isNotEmpty) ...[
                  const SectionTitle('المواد'),
                  for (final s in results.subjects)
                    ListTile(
                      leading: Icon(subjectIcon(s.icon), color: Color(s.color)),
                      title: Text(s.name),
                      onTap: () => context.push('/subject/${s.id}'),
                    ),
                ],
                if (results.lessons.isNotEmpty) ...[
                  const SectionTitle('الدروس'),
                  for (final l in results.lessons)
                    ListTile(
                      key: Key('result_lesson_${l.id}'),
                      leading: const Icon(Icons.school),
                      title: Text(l.title),
                      subtitle: Text(l.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => context.push('/lesson/${l.id}'),
                    ),
                ],
                if (results.units.isNotEmpty) ...[
                  const SectionTitle('الوحدات'),
                  for (final u in results.units)
                    ListTile(
                      leading: const Icon(Icons.folder_open),
                      title: Text(u.title),
                      onTap: u.lessons.isEmpty ? null : () => context.push('/lesson/${u.lessons.first.id}'),
                    ),
                ],
                if (results.pages.isNotEmpty) ...[
                  const SectionTitle('في الكتاب'),
                  for (final r in results.pages)
                    ListTile(
                      leading: CircleAvatar(child: Text('${r.page.number}')),
                      title: Text(r.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(r.page.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => context.push('/book/${r.book.id}?page=${r.page.number}'),
                    ),
                ],
                if (results.questions.isNotEmpty) ...[
                  const SectionTitle('أسئلة متعلقة'),
                  for (final q in results.questions)
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: Text(q.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${q.type.label} • ${q.difficulty.label}'),
                      onTap: () => QuizLauncher(ref).testMe(context, lessonId: q.lessonId, count: 5),
                    ),
                ],
                if (results.exams.isNotEmpty) ...[
                  const SectionTitle('امتحانات'),
                  for (final e in results.exams)
                    ListTile(
                      leading: const Icon(Icons.assignment),
                      title: Text(e.title),
                      onTap: () => QuizLauncher(ref).exam(context, e),
                    ),
                ],
              ],
            ),
    );
  }
}
