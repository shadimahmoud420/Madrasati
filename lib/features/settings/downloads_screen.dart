import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../books/book_tile.dart';
import '../books/library.dart';

final _pendingUploadsProvider = FutureProvider<int>((ref) async {
  ref.watch(progressRevisionProvider);
  return (await ref.watch(progressRepositoryProvider).unsyncedAttempts()).length;
});

/// Offline-first status: what is stored on the device, and manual sync.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _sync() async {
    final gradeId = ref.read(profileProvider)?.gradeId;
    if (gradeId == null) return;
    setState(() => _busy = true);
    final sync = ref.read(contentSyncProvider);
    final result = await sync.pull(gradeId);
    await sync.push();
    ref.invalidate(_pendingUploadsProvider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (result) {
        SyncResult.updated => 'تم تحميل محتوى جديد لصفك.',
        SyncResult.upToDate => 'المحتوى محدّث.',
        SyncResult.offline => 'لا يوجد اتصال بالإنترنت. سنحاول تلقائيًا عند عودته.',
        SyncResult.unavailable => 'هذه النسخة تعمل بالمحتوى المرفق بالتطبيق فقط.',
        SyncResult.error => 'تعذّر التحديث الآن، حاول لاحقًا.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final pack = ref.watch(packProvider).value;
    final grade = ref.watch(currentGradeProvider);
    final pending = ref.watch(_pendingUploadsProvider).value ?? 0;
    final lessons = pack?.lessons.length ?? 0;
    final questions = pack?.questions.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('المحتوى بدون إنترنت')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(pack == null ? Icons.cloud_off : Icons.offline_pin, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          grade?.fullName ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pack == null
                        ? 'لا يوجد محتوى محفوظ لصفك بعد.'
                        : 'محفوظ على جهازك ويعمل بدون إنترنت:\n'
                              '• ${pack.subjects.length} مواد، $lessons درسًا، $questions سؤالًا\n'
                              '• ${pack.books.length} كتب و ${pack.exams.length} امتحانات تجريبية\n'
                              '• إصدار المحتوى: ${pack.version}',
                    style: const TextStyle(height: 1.7),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('نتائج بانتظار المزامنة'),
              subtitle: Text(pending == 0 ? 'كل نتائجك متزامنة أو محفوظة محليًا' : '$pending نتيجة سترسل عند الاتصال'),
            ),
          ),
          const SizedBox(height: 16),
          const OnlineOnlyNote('التحديث يحتاج إلى إنترنت. الدراسة والاختبارات تعمل دائمًا بدونه.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('sync_button'),
            onPressed: _busy ? null : _sync,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download),
            label: const Text('تحديث المحتوى الآن'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, key: const Key('sync_message'), textAlign: TextAlign.center),
          ],
          const _GradeLibrary(),
        ],
      ),
    );
  }
}

/// The grade's PDF books with their offline status, and "download all".
class _GradeLibrary extends ConsumerWidget {
  const _GradeLibrary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = (ref.watch(gradeBooksProvider).value ?? const <Book>[]).where((b) => b.isPdf && !b.bundled).toList();
    final downloaded = ref.watch(downloadedBooksProvider).value ?? const <String, int>{};
    final missing = books.where((b) => b.pdfUrl != null && !downloaded.containsKey(b.id)).toList();
    final used = books.fold<int>(0, (sum, b) => sum + (downloaded[b.id] ?? 0));
    final busy = ref.watch(bookLibraryProvider).isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'كتب صفي (PDF)',
          trailing: used == 0 ? null : Text(formatSize(used), style: Theme.of(context).textTheme.bodySmall),
        ),
        if (books.isEmpty)
          const Text('لا توجد كتب PDF لصفك بعد. يمكنك إضافة كتاب من جهازك من صفحة المادة.')
        else
          Card(
            child: Column(children: [for (final b in books) BookTile(book: b)]),
          ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('download_all_books'),
            onPressed: busy
                ? null
                : () async {
                    for (final b in missing) {
                      try {
                        await ref.read(bookLibraryProvider.notifier).download(b);
                      } on DownloadException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                        }
                        return;
                      }
                    }
                  },
            icon: const Icon(Icons.download_for_offline),
            label: Text('تحميل كل الكتب (${missing.length})'),
          ),
        ],
      ],
    );
  }
}
