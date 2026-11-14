import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/math_textbook_generation_service.dart';
import 'package:poemath/core/services/math_textbook_pdf_graphics.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/services/textbook_pdf_page_loader.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';

class _LocalFiles extends TextbookFileService {
  _LocalFiles(this.input, Directory root)
    : super(directoryProvider: () async => root);
  final String input;
  @override
  Future<String?> installedPath(Textbook book) async => input;
}

/// 显式提供本机原书才运行；PDF、原文、图像和解析草稿不进入 Git。
/// 使用应用的生成服务、页面加载器、原生绘图适配器和草稿仓储。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const inputDirectory = String.fromEnvironment('MATH_TEXTBOOK_PDF_DIRECTORY');
  const evidenceDirectory = String.fromEnvironment(
    'MATH_TEXTBOOK_EVIDENCE_DIRECTORY',
  );
  const library = String.fromEnvironment('TEXTBOOK_PDFIUM_LIBRARY');
  final enabled =
      inputDirectory.isNotEmpty &&
      evidenceDirectory.isNotEmpty &&
      library.isNotEmpty;
  final matrix = <Map<String, Object?>>[];
  setUpAll(() {
    if (!enabled) return;
    Pdfrx.pdfiumModulePath = library;
    Pdfrx.cacheDirectoryPath = '$evidenceDirectory/native-cache';
  });
  tearDownAll(() async {
    if (enabled) {
      await File('$evidenceDirectory/matrix.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(matrix));
    }
  });

  for (final sample in [
    (
      id: 'g3',
      grade: 3,
      semester: '上',
      pages: 122,
      bytes: 29858964,
      sha: '117c0e0545218aadab20001250e937ce60b959681dda7006396f7db6eaf368b6',
      start: 41,
      end: 45,
      title: '万以内的加法（含练习八）',
    ),
    (
      id: 'g5',
      grade: 5,
      semester: '下',
      pages: 131,
      bytes: 14621452,
      sha: '657e1547074668dbb50f2bf37f13c20f292127be64c26c5334190aa34d06de83',
      start: 50,
      end: 53,
      title: '分数的意义（含练习十一）',
    ),
  ]) {
    test(
      '完整小节原生整理并重新打开：${sample.id}',
      () async {
        final input = File('$inputDirectory/${sample.id}.pdf');
        expect(await input.length(), sample.bytes);
        expect(
          (await sha256.bind(input.openRead()).first).toString(),
          sample.sha,
        );
        final root = await Directory(
          '$evidenceDirectory/${sample.id}/run-${DateTime.now().microsecondsSinceEpoch}',
        ).create(recursive: true);
        final book = Textbook(
          pdfSha256: sample.sha,
          title: sample.title,
          grade: sample.grade,
          semester: sample.semester,
          publisher: '人民教育出版社',
          editionNote: '本机原书验证，未代表版次全面核验',
          originalFileName: '${sample.id}.pdf',
          pageCount: sample.pages,
          fileSize: sample.bytes,
          importedAt: DateTime.utc(2026, 11, 13),
          subject: TextbookSubject.math,
        );
        final repository = MathTextbookCourseRepository(
          directoryProvider: () async => root,
        );
        final files = _LocalFiles(input.path, root);
        final service = MathTextbookGenerationService(repository, files);
        final progress = <int>[];
        final watch = Stopwatch()..start();
        final course = await service.generate(
          book: book,
          title: sample.title,
          startPage: sample.start,
          endPage: sample.end,
          token: TextbookDraftToken(),
          authorize: () {},
          onProgress: (done, _) => progress.add(done),
        );
        watch.stop();
        final lesson = course.lessons.single;
        final expressions = lesson.blocks
            .expand((b) => b.spans)
            .map((s) => s.expression)
            .whereType<MathTextbookExpression>()
            .toList();
        final directory = await Directory('$evidenceDirectory/${sample.id}')
            .create(recursive: true);
        await File('${directory.path}/course.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(course.toJson()),
        );
        final document = await PdfDocument.openFile(input.path);
        final pageStats = <Map<String, Object?>>[];
        try {
          for (var number = sample.start; number <= sample.end; number++) {
            final page = document.pages[number - 1];
            final layout = await loadTextbookPdfPage(
              document: document,
              number: number,
              checkAvailable: () {},
            );
            // 同时排队阅读器渲染和读取绘图，验证公开句柄保护不与 PDFium worker 竞争。
            final render = page.render(
              fullWidth: page.width * 2,
              fullHeight: page.height * 2,
            );
            final graphics = await document.useNativeDocumentHandle(
              (handle) =>
                  readMathTextbookGraphics(handle, number, modulePath: library),
            );
            final rendered = await render;
            expect(rendered, isNotNull);
            final image = await rendered!.createImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('${directory.path}/page-$number.png')
                .writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
            rendered.dispose();
            pageStats.add({
              'page': number,
              'glyphs': layout.glyphs.length,
              'horizontalLines': graphics.lines.length,
              'graphicRegions': graphics.regions.length,
              'graphicsComplete': graphics.complete,
              'contentBlocks': lesson.blocks
                  .where(
                    (b) =>
                        b.sources.any((s) => s.page == number) &&
                        b.kind != MathTextbookBlockKind.sourcePage,
                  )
                  .length,
            });
            final formula = lesson.blocks
                .where(
                  (b) =>
                      b.sources.first.page == number &&
                      b.spans.any((s) => s.expression != null),
                )
                .firstOrNull;
            if (formula != null) {
              final cropped = await renderMathTextbookRegion(
                input.path,
                formula.sources.first,
                MathTextbookRenderToken(),
              );
              final png = await cropped.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('${directory.path}/crop-$number.png')
                  .writeAsBytes(png!.buffer.asUint8List());
              await File('${directory.path}/crop-$number.json')
                  .writeAsString(jsonEncode(formula.sources.first.toJson()));
              cropped.dispose();
            }
          }
        } finally {
          await document.dispose();
        }
        final record = <String, Object?>{
          'book': sample.id,
          'sha256': sample.sha,
          'pdfPages': sample.pages,
          'startPage': sample.start,
          'endPage': sample.end,
          'title': sample.title,
          'milliseconds': watch.elapsedMilliseconds,
          'contentBlocks': lesson.blocks
              .where((b) => b.kind != MathTextbookBlockKind.sourcePage)
              .length,
          'formulaExpressions': expressions.length,
          'fractions': expressions.whereType<MathTextbookFraction>().length,
          'mixedNumbers': expressions
              .whereType<MathTextbookMixedNumber>()
              .length,
          'powers': expressions.whereType<MathTextbookPower>().length,
          'verticalAdditions': expressions
              .whereType<MathTextbookVerticalAddition>()
              .length,
          'illustrations': lesson.blocks
              .where((b) => b.kind == MathTextbookBlockKind.illustration)
              .length,
          'exerciseMarkers': lesson.blocks
              .where((b) => b.exerciseNumber != null)
              .map((b) => b.exerciseNumber)
              .toList(),
          'pageStats': pageStats,
          'reviewed': lesson.isApproved(book.pdfSha256),
          'parentRepairMilliseconds': null,
        };
        matrix.add(record);
        // 输出统计，原文仅写到显式指定的本机证据目录。
        // ignore: avoid_print
        print(jsonEncode(record));
        expect(progress, [
          for (var i = 1; i <= sample.end - sample.start + 1; i++) i,
        ]);
        expect(
          lesson.blocks
              .where((b) => b.kind == MathTextbookBlockKind.sourcePage)
              .map((b) => b.sources.single.page),
          [for (var p = sample.start; p <= sample.end; p++) p],
        );
        expect(lesson.review, isNull);
        expect(pageStats.every((p) => p['graphicsComplete'] == true), isTrue);
        expect(
          (await MathTextbookCourseRepository(
            directoryProvider: () async => root,
          ).load(book))!.toJson(),
          course.toJson(),
        );
        if (sample.id == 'g3') {
          expect(
            expressions.whereType<MathTextbookVerticalAddition>().any(
              (v) => v.rows.join('+') == '445+298+743',
            ),
            isTrue,
          );
        } else {
          expect(
            expressions.whereType<MathTextbookFraction>().any(
              (f) => f.numerator == '1' && f.denominator == '4',
            ),
            isTrue,
          );
        }
      },
      skip: !enabled,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
