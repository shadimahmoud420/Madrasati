import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/arabic.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import 'library.dart';

final _pdfBookmarksProvider = FutureProvider.family<List<int>, String>((ref, bookId) async {
  ref.watch(progressRevisionProvider);
  return ref.watch(progressRepositoryProvider).bookmarks(bookId);
});

/// Official book as a PDF: download once, then read offline at full quality
/// with search inside the book, go-to-page and bookmarks.
class PdfBookScreen extends ConsumerWidget {
  const PdfBookScreen({super.key, required this.book, this.initialPage});

  final Book book;
  final int? initialPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(downloadedBooksProvider).value?.containsKey(book.id) ?? false;
    if (!downloaded) return _DownloadPrompt(book: book);
    return _PdfReader(
      book: book,
      path: ref.read(bookLibraryProvider.notifier).fileFor(book).path,
      initialPage: initialPage,
    );
  }
}

class _DownloadPrompt extends ConsumerWidget {
  const _DownloadPrompt({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(bookLibraryProvider)[book.id];
    final size = formatSize(book.sizeBytes);
    return Scaffold(
      appBar: AppBar(title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.menu_book, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(book.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'حمّل الكتاب مرة واحدة لتقرأه بعد ذلك دائمًا بدون إنترنت${size.isEmpty ? '' : ' (الحجم $size)'}.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (progress != null) ...[
            LinearProgressIndicator(value: progress == 0 ? null : progress, minHeight: 10),
            const SizedBox(height: 8),
            Text('جارٍ التحميل… ${(progress * 100).round()}%', textAlign: TextAlign.center),
          ] else ...[
            const OnlineOnlyNote('التحميل يحتاج إلى إنترنت مرة واحدة فقط.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('download_book'),
              onPressed: () async {
                try {
                  await ref.read(bookLibraryProvider.notifier).download(book);
                } on DownloadException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
              icon: const Icon(Icons.download),
              label: const Text('تحميل الكتاب'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PdfReader extends ConsumerStatefulWidget {
  const _PdfReader({required this.book, this.path, this.initialPage});

  final Book book;

  /// Downloaded or imported file; null for books bundled in the app.
  final String? path;
  final int? initialPage;

  @override
  ConsumerState<_PdfReader> createState() => _PdfReaderState();
}

class _PdfReaderState extends ConsumerState<_PdfReader> {
  final _controller = PdfViewerController();

  /// Created once the document is open: the searcher needs the loaded
  /// document and crashes the screen if built earlier.
  PdfTextSearcher? _searcher;

  /// Built once: a new params object on every rebuild makes the viewer
  /// restart loading the document.
  PdfViewerParams? _params;

  PdfViewerParams _buildParams(Color background) => PdfViewerParams(
    backgroundColor: background,
    onViewerReady: (_, _) {
      _searcher ??= PdfTextSearcher(_controller)..addListener(_update);
      _update();
    },
    onPageChanged: (page) {
      if (page != null && mounted) setState(() => _page = page);
    },
    pagePaintCallbacks: [(canvas, rect, page) => _searcher?.pageTextMatchPaintCallback(canvas, rect, page)],
    errorBannerBuilder: (context, error, stackTrace, documentRef) => const EmptyState(
      icon: Icons.broken_image_outlined,
      title: 'تعذّر فتح الكتاب',
      message: 'قد يكون الملف تالفًا. احذفه من القائمة ثم حمّله من جديد.',
    ),
  );
  final _query = TextEditingController();
  late int _page = widget.initialPage ?? 1;
  bool _searching = false;

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searcher
      ?..removeListener(_update)
      ..dispose();
    _query.dispose();
    super.dispose();
  }

  int get _pageCount => _controller.isReady ? _controller.pageCount : 0;

  Future<void> _goTo(int page) async {
    if (!_controller.isReady) return;
    await _controller.goToPage(pageNumber: page.clamp(1, _pageCount));
  }

  Future<void> _askPage() async {
    final input = TextEditingController();
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الانتقال إلى صفحة'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: 'من 1 إلى $_pageCount'),
          onSubmitted: (v) => Navigator.pop(context, parseNumber(v)?.toInt()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, parseNumber(input.text)?.toInt()),
            child: const Text('انتقال'),
          ),
        ],
      ),
    );
    input.dispose();
    if (page != null) await _goTo(page);
  }

  Future<void> _showBookmarks() async {
    final pages = await ref.read(_pdfBookmarksProvider(widget.book.id).future);
    if (!mounted) return;
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
                    onTap: () => Navigator.pop(context, p),
                  ),
              ],
            ),
    );
    if (page != null) await _goTo(page);
  }

  Future<void> _deleteDownload() async {
    final local = widget.book.localOnly;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local ? 'إزالة الكتاب؟' : 'حذف النسخة المحمّلة؟'),
        content: Text(
          local ? 'سيُزال الكتاب من مكتبة هذا الجهاز.' : 'يمكنك تحميله مرة أخرى لاحقًا. حذفه يوفّر مساحة على الجهاز.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(bookLibraryProvider.notifier).delete(widget.book);
    if (mounted && local) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final searcher = _searcher;
    final matches = searcher?.matches.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'ابحث داخل الكتاب',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (v) => searcher?.startTextSearch(v.trim(), goToFirstMatch: true),
              )
            : Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _searching ? 'إغلاق البحث' : 'بحث في الكتاب',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query.clear();
                searcher?.resetTextSearch();
              }
            }),
          ),
          if (!_searching) ...[
            _BookmarkButton(bookId: book.id, page: _page),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'goto' => _askPage(),
                'marks' => _showBookmarks(),
                _ => _deleteDownload(),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'goto', child: Text('الانتقال إلى صفحة')),
                const PopupMenuItem(value: 'marks', child: Text('العلامات المرجعية')),
                if (!book.bundled)
                  PopupMenuItem(value: 'delete', child: Text(book.localOnly ? 'إزالة الكتاب' : 'حذف من الجهاز')),
              ],
            ),
          ],
        ],
      ),
      body: Directionality(
        // PDF pages keep their own layout; scroll gestures stay natural.
        textDirection: TextDirection.ltr,
        child: widget.path == null
            ? PdfViewer.asset(
                widget.book.asset!,
                controller: _controller,
                initialPageNumber: widget.initialPage ?? 1,
                params: _params ??= _buildParams(Theme.of(context).colorScheme.surfaceContainerHighest),
              )
            : PdfViewer.file(
                widget.path!,
                controller: _controller,
                initialPageNumber: widget.initialPage ?? 1,
                params: _params ??= _buildParams(Theme.of(context).colorScheme.surfaceContainerHighest),
              ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: _searching && _query.text.trim().isNotEmpty
              ? Row(
                  children: [
                    Expanded(
                      child: Text(
                        searcher?.isSearching ?? false
                            ? 'جارٍ البحث…'
                            : matches == 0
                            ? 'لا توجد نتائج'
                            : 'النتيجة ${(searcher?.currentIndex ?? 0) + 1} من $matches',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      tooltip: 'السابق',
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: matches == 0 ? null : searcher!.goToPrevMatch,
                    ),
                    IconButton(
                      tooltip: 'التالي',
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: matches == 0 ? null : searcher!.goToNextMatch,
                    ),
                  ],
                )
              : TextButton(onPressed: _askPage, child: Text(_pageCount == 0 ? '' : 'صفحة $_page من $_pageCount')),
        ),
      ),
    );
  }
}

/// Kept separate so loading bookmarks never rebuilds the PDF viewer.
class _BookmarkButton extends ConsumerWidget {
  const _BookmarkButton({required this.bookId, required this.page});

  final String bookId;
  final int page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marked = ref.watch(_pdfBookmarksProvider(bookId)).value?.contains(page) ?? false;
    return IconButton(
      tooltip: marked ? 'إزالة العلامة' : 'إضافة علامة مرجعية',
      icon: Icon(marked ? Icons.bookmark : Icons.bookmark_add_outlined),
      onPressed: () async {
        await ref.read(progressRepositoryProvider).toggleBookmark(bookId, page, ref.read(clockProvider)());
        ref.invalidate(_pdfBookmarksProvider(bookId));
      },
    );
  }
}
