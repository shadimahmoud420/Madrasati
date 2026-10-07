import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/arabic.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';

final _bookmarksProvider = FutureProvider.family<List<int>, String>((ref, bookId) async {
  ref.watch(progressRevisionProvider);
  return ref.watch(progressRepositoryProvider).bookmarks(bookId);
});

/// Offline book reader: swipe pages, search inside the book, jump to a page,
/// and bookmark pages.
class BookScreen extends ConsumerStatefulWidget {
  const BookScreen({super.key, required this.bookId, this.initialPage});

  final String bookId;
  final int? initialPage;

  @override
  ConsumerState<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends ConsumerState<BookScreen> {
  late final PageController _controller = PageController(initialPage: (widget.initialPage ?? 1) - 1);
  late int _page = widget.initialPage ?? 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jump(int page, Book book) {
    final p = page.clamp(1, book.pages.length);
    _controller.jumpToPage(p - 1);
    setState(() => _page = p);
  }

  Future<void> _goTo(Book book) async {
    final controller = TextEditingController();
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الانتقال إلى صفحة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: 'من 1 إلى ${book.pages.length}'),
          onSubmitted: (v) => Navigator.pop(context, parseNumber(v)?.toInt()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, parseNumber(controller.text)?.toInt()),
            child: const Text('انتقال'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (page != null) _jump(page, book);
  }

  Future<void> _search(Book book) async {
    final page = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BookSearchSheet(book: book),
    );
    if (page != null) _jump(page, book);
  }

  Future<void> _bookmarks(Book book, List<int> pages) async {
    final page = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => pages.isEmpty
          ? const SizedBox(
              height: 160,
              child: EmptyState(icon: Icons.bookmark_border, title: 'لا توجد علامات مرجعية بعد'),
            )
          : ListView(
              shrinkWrap: true,
              children: [
                for (final p in pages)
                  ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text('صفحة $p'),
                    subtitle: Text(
                      book.pages[p - 1].text.split('\n').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(context, p),
                  ),
              ],
            ),
    );
    if (page != null) _jump(page, book);
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(packProvider).value?.book(widget.bookId);
    if (book == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.menu_book, title: 'الكتاب غير متوفر'),
      );
    }
    final bookmarks = ref.watch(_bookmarksProvider(book.id)).value ?? const <int>[];
    final marked = bookmarks.contains(_page);
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const Key('book_search'),
            tooltip: 'بحث في الكتاب',
            icon: const Icon(Icons.search),
            onPressed: () => _search(book),
          ),
          IconButton(
            key: const Key('book_bookmark'),
            tooltip: marked ? 'إزالة العلامة' : 'إضافة علامة مرجعية',
            icon: Icon(marked ? Icons.bookmark : Icons.bookmark_add_outlined),
            onPressed: () async {
              await ref.read(progressRepositoryProvider).toggleBookmark(book.id, _page, ref.read(clockProvider)());
              ref.invalidate(_bookmarksProvider(book.id));
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'goto' ? _goTo(book) : _bookmarks(book, bookmarks),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'goto', child: Text('الانتقال إلى صفحة')),
              PopupMenuItem(value: 'marks', child: Text('العلامات المرجعية')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: book.pages.length,
              onPageChanged: (i) => setState(() => _page = i + 1),
              itemBuilder: (context, i) => _PageView(page: book.pages[i]),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _page > 1 ? () => _jump(_page - 1, book) : null,
                  ),
                  Expanded(
                    child: TextButton(onPressed: () => _goTo(book), child: Text('صفحة $_page من ${book.pages.length}')),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _page < book.pages.length ? () => _jump(_page + 1, book) : null,
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

class _PageView extends StatelessWidget {
  const _PageView({required this.page});

  final BookPage page;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(page.text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.8)),
            if (page.lessonId != null) ...[
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => context.push('/lesson/${page.lessonId}'),
                  icon: const Icon(Icons.school),
                  label: const Text('شرح هذا الدرس'),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _BookSearchSheet extends StatefulWidget {
  const _BookSearchSheet({required this.book});

  final Book book;

  @override
  State<_BookSearchSheet> createState() => _BookSearchSheetState();
}

class _BookSearchSheetState extends State<_BookSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = normalizeArabic(_query);
    final hits = q.length < 2
        ? const <BookPage>[]
        : widget.book.pages.where((p) => normalizeArabic(p.text).contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('book_search_field'),
                autofocus: true,
                decoration: const InputDecoration(hintText: 'ابحث عن كلمة داخل الكتاب', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (q.length >= 2 && hits.isEmpty) const ListTile(title: Text('لا توجد نتائج')),
                  for (final p in hits)
                    ListTile(
                      leading: CircleAvatar(child: Text('${p.number}')),
                      title: Text(_snippet(p.text, q), maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, p.number),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _snippet(String text, String q) {
    for (final line in text.split('\n')) {
      if (normalizeArabic(line).contains(q)) return line.trim();
    }
    return text.split('\n').first;
  }
}
