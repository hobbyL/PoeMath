import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/textbook_course_generation_service.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';

/// Opt-in local acceptance: no copyrighted PDF/text fixture belongs in git.
/// flutter test ... --dart-define=TEXTBOOK_PDF_DIRECTORY=/private/tmp/...
///   --dart-define=TEXTBOOK_PDFIUM_LIBRARY=/absolute/path/libpdfium.dylib
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pdfDirectory = String.fromEnvironment('TEXTBOOK_PDF_DIRECTORY');
  const pdfiumLibrary = String.fromEnvironment('TEXTBOOK_PDFIUM_LIBRARY');
  final enabled = pdfDirectory.isNotEmpty && pdfiumLibrary.isNotEmpty;
  final catalog =
      jsonDecode(File('assets/data/textbook_catalog.json').readAsStringSync())
          as Map<String, dynamic>;
  final entries = (catalog['books'] as List)
      .map((b) => TextbookCatalogEntry.fromJson(b as Map<String, dynamic>))
      .toList();
  final matrix = <Map<String, Object?>>[];
  setUpAll(() {
    if (!enabled) return;
    Pdfrx.pdfiumModulePath = pdfiumLibrary;
    Pdfrx.cacheDirectoryPath = '$pdfDirectory/native-cache';
  });
  tearDownAll(() async {
    if (!enabled) return;
    await File('$pdfDirectory/generation-matrix.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(matrix));
  });
  for (final entry in entries) {
    final book = entry.book;
    final name =
        'grade${book.grade}-${book.semester == '上' ? 'first' : 'second'}';
    test(
      '真实PDF完全本机整理：$name',
      () async {
        final input = File('$pdfDirectory/$name.pdf');
        expect(await input.length(), book.fileSize);
        expect(
          (await sha256.bind(input.openRead()).first).toString(),
          book.pdfSha256,
        );
        final root = await Directory('$pdfDirectory/generated/$name')
            .create(recursive: true);
        final repository =
            TextbookCourseRepository(directoryProvider: () async => root);
        final service = TextbookCourseGenerationService(
          repository,
          TextbookFileService(directoryProvider: () async => root),
        );
        final watch = Stopwatch()..start();
        int? firstLessonMs;
        await service.run(
          book,
          entry,
          input.path,
          TextbookDraftToken(),
          (p) {
            if (p.done > 0) firstLessonMs ??= watch.elapsedMilliseconds;
          },
          () {},
          refresh: true,
        );
        watch.stop();
        final document = (await repository.loadDocument(book))!;
        final lessons = document.pack.lessons;
        final generation = document.generation!;
        final record = <String, Object?>{
          'volume': name,
          'pdfSha256': book.pdfSha256,
          'pdfPages': book.pageCount,
          'lessons': lessons.length,
          'completed': generation.completed.length,
          'phase': generation.phase,
          'paragraphs': lessons.fold<int>(0, (n, l) => n + l.paragraphs.length),
          'withBody': lessons.where((l) => l.paragraphs.isNotEmpty).length,
          'withPinyin': lessons
              .expand((l) => l.paragraphs)
              .where((p) => p.pinyin != null)
              .length,
          'recognition': lessons.fold<int>(
              0, (n, l) => n + l.recognitionCharacters.length,),
          'writing':
              lessons.fold<int>(0, (n, l) => n + l.writingCharacters.length),
          'words': lessons.fold<int>(0, (n, l) => n + l.words.length),
          'recitations':
              lessons.fold<int>(0, (n, l) => n + l.recitations.length),
          'exercises': lessons.fold<int>(0, (n, l) => n + l.exercises.length),
          'candidates':
              generation.candidates.values.fold<int>(0, (n, c) => n + c.length),
          'errors': generation.errors,
          'milliseconds': watch.elapsedMilliseconds,
          'firstLessonMs': firstLessonMs,
          'rssBytes': ProcessInfo.currentRss,
          'peakRssBytes': ProcessInfo.maxRss,
          'cacheBytes': await root
              .list(recursive: true)
              .where((f) => f is File && f.path.contains('/cache/'))
              .asyncMap((f) => (f as File).length())
              .fold<int>(0, (n, bytes) => n + bytes),
        };
        matrix.add(record);
        // Metadata only; never print extracted textbook content.
        // ignore: avoid_print
        print(jsonEncode(record));
        expect(generation.errors, isEmpty);
        expect(generation.completed.length, generation.plans.length);
        expect(generation.phase, 'ready');
        expect(lessons.expand((l) => l.paragraphs), isNotEmpty);
        expect(
          lessons.expand((l) => l.targets).every((n) => !n.isApproved),
          isTrue,
        );
        final reopened =
            TextbookCourseRepository(directoryProvider: () async => root);
        expect(
            (await reopened.loadDocument(book))!.toJson(), document.toJson(),);
      },
      skip: !enabled,
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
