import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import 'library.dart';

/// A book row with its offline status: downloaded, downloading, or not yet.
class BookTile extends ConsumerWidget {
  const BookTile({super.key, required this.book, this.showDownloadButton = true});

  final Book book;
  final bool showDownloadButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(downloadedBooksProvider).value?[book.id];
    final progress = ref.watch(bookLibraryProvider)[book.id];
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (book.semester != null) 'الفصل ${book.semester == 1 ? 'الأول' : 'الثاني'}',
      if (!book.isPdf) 'نسخة نصية من الدروس',
      if (book.localOnly) 'من جهازك',
      if (downloaded != null) 'متوفر بدون إنترنت • ${formatSize(downloaded)}',
      if (downloaded == null && book.pdfUrl != null)
        'غير محمّل${book.sizeBytes == null ? '' : ' • ${formatSize(book.sizeBytes)}'}',
    ].join(' • ');
    Widget? trailing;
    if (progress != null) {
      trailing = SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(value: progress == 0 ? null : progress, strokeWidth: 3),
      );
    } else if (downloaded != null || !book.isPdf) {
      trailing = Icon(Icons.offline_pin, color: scheme.primary);
    } else if (showDownloadButton) {
      trailing = IconButton(
        tooltip: 'تحميل',
        icon: const Icon(Icons.download),
        onPressed: () async {
          try {
            await ref.read(bookLibraryProvider.notifier).download(book);
          } on DownloadException catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
          }
        },
      );
    }
    return ListTile(
      key: Key('book_${book.id}'),
      leading: Icon(book.isPdf ? Icons.picture_as_pdf : Icons.chrome_reader_mode, color: scheme.primary),
      title: Text(book.title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: trailing,
      onTap: () => context.push('/book/${book.id}'),
    );
  }
}

/// Lets the student pick a PDF on the device and add it to a subject.
Future<void> importBookFromDevice(
  BuildContext context,
  WidgetRef ref, {
  required String subjectId,
  required int semester,
}) async {
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
  if (picked.isEmpty || !context.mounted) return;
  final file = picked.single;
  final title = TextEditingController(text: file.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''));
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('اسم الكتاب'),
      content: TextField(controller: title, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إضافة')),
      ],
    ),
  );
  final name = title.text.trim();
  title.dispose();
  if (confirmed != true || !context.mounted) return;
  try {
    await ref
        .read(bookLibraryProvider.notifier)
        .importFile(
          writeTo: file.xFile.saveTo,
          subjectId: subjectId,
          title: name.isEmpty ? file.name : name,
          semester: semester,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة الكتاب، ويعمل بدون إنترنت.')));
    }
  } on DownloadException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
