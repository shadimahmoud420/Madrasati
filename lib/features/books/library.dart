import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/models.dart';

/// Folder holding downloaded and imported PDF books (overridden in `main()`).
final booksDirProvider = Provider<Directory>((ref) => throw UnimplementedError());
final httpClientProvider = Provider<http.Client>((ref) => http.Client());
final localBookStoreProvider = Provider<LocalBookStore>((ref) => LocalBookStore(ref.watch(appDatabaseProvider)));

class _Revision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Bumped when a book file is downloaded, imported or deleted.
final libraryRevisionProvider = NotifierProvider<_Revision, int>(_Revision.new);

/// Every book of the signed-in student's grade: official books from the
/// content pack plus PDFs added from the device.
final gradeBooksProvider = FutureProvider<List<Book>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final grade = ref.watch(currentGradeProvider);
  final local = ref.watch(localBookStoreProvider);
  final pack = await ref.watch(packProvider.future);
  if (grade == null) return const [];
  final subjectIds = {for (final s in grade.subjects) s.id};
  return [
    ...?pack?.books,
    for (final b in await local.all())
      if (subjectIds.contains(b.subjectId)) b,
  ];
});

/// Book id → size in bytes of each PDF available offline.
final downloadedBooksProvider = FutureProvider<Map<String, int>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final dir = ref.watch(booksDirProvider);
  if (!dir.existsSync()) return const {};
  return {
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('.pdf')) f.uri.pathSegments.last.replaceAll('.pdf', ''): f.lengthSync(),
  };
});

class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads official books for offline reading and imports PDFs the
/// student already has. Progress per book id is the state (0..1).
class BookLibrary extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  Directory get _dir => ref.read(booksDirProvider);

  File fileFor(Book book) => File('${_dir.path}/${book.id}.pdf');

  void _changed() => ref.read(libraryRevisionProvider.notifier).bump();

  /// Streams the PDF to a temporary file and renames it when complete, so a
  /// cut connection never leaves a broken book behind.
  Future<void> download(Book book) async {
    final url = book.pdfUrl;
    if (url == null || state.containsKey(book.id)) return;
    state = {...state, book.id: 0};
    _dir.createSync(recursive: true);
    final part = File('${fileFor(book).path}.part');
    try {
      final response = await ref
          .read(httpClientProvider)
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw DownloadException('تعذّر تحميل الكتاب (${response.statusCode}).');
      final total = response.contentLength ?? book.sizeBytes;
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) state = {...state, book.id: (received / total).clamp(0, 1)};
        }
      } finally {
        await sink.close();
      }
      if (!_looksLikePdf(part)) throw const DownloadException('الملف الذي وصل ليس كتابًا صالحًا.');
      part.renameSync(fileFor(book).path);
      _changed();
    } on DownloadException {
      rethrow;
    } on Exception {
      throw const DownloadException('انقطع الاتصال أثناء التحميل. حاول مرة أخرى عند توفر الإنترنت.');
    } finally {
      if (part.existsSync()) part.deleteSync();
      state = {...state}..remove(book.id);
    }
  }

  /// Adds a PDF from the device to the library as a book of [subjectId].
  /// [writeTo] copies the picked file to the given path.
  Future<Book> importFile({
    required Future<void> Function(String destination) writeTo,
    required String subjectId,
    required String title,
    int? semester,
  }) async {
    final id = 'local_${const Uuid().v4()}';
    _dir.createSync(recursive: true);
    final target = File('${_dir.path}/$id.pdf');
    await writeTo(target.path);
    if (!_looksLikePdf(target)) {
      if (target.existsSync()) target.deleteSync();
      throw const DownloadException('الملف المختار ليس بصيغة PDF.');
    }
    final book = Book(
      id: id,
      subjectId: subjectId,
      title: title,
      semester: semester,
      sizeBytes: target.lengthSync(),
      localOnly: true,
    );
    await ref.read(localBookStoreProvider).add(book, ref.read(clockProvider)());
    _changed();
    return book;
  }

  /// Frees space; official books can be downloaded again, imported ones are
  /// removed from the shelf.
  Future<void> delete(Book book) async {
    final f = fileFor(book);
    if (f.existsSync()) f.deleteSync();
    if (book.localOnly) await ref.read(localBookStoreProvider).remove(book.id);
    _changed();
  }

  static bool _looksLikePdf(File f) {
    if (!f.existsSync() || f.lengthSync() < 5) return false;
    final raf = f.openSync();
    try {
      return String.fromCharCodes(raf.readSync(5)) == '%PDF-';
    } finally {
      raf.closeSync();
    }
  }
}

final bookLibraryProvider = NotifierProvider<BookLibrary, Map<String, double>>(BookLibrary.new);

String formatSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  final mb = bytes / (1024 * 1024);
  return mb >= 1 ? '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} م.ب' : '${(bytes / 1024).round()} ك.ب';
}
