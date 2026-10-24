import 'dart:convert';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/repositories/textbook_catalog_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真实目录覆盖12册且保留来源、校验身份与实际版本证据', () async {
    final books = await const TextbookCatalogRepository().load();
    expect(
        books
            .map((entry) => '${entry.book.grade}${entry.book.semester}')
            .toList(),
        [
          '1上',
          '1下',
          '2上',
          '2下',
          '3上',
          '3下',
          '4上',
          '4下',
          '5上',
          '5下',
          '6上',
          '6下',
        ]);
    expect(books.where((entry) => entry.editionLabel == '2022课标修订').length, 9);
    expect(
      books
          .singleWhere((entry) => entry.book.volumeLabel == '四年级下册')
          .editionLabel,
      '旧版（2022课标修订前）',
    );
    for (final grade in [5, 6]) {
      expect(
        books
            .singleWhere(
              (entry) =>
                  entry.book.grade == grade && entry.book.semester == '下',
            )
            .editionLabel,
        '2019年12月第1版（旧版）',
      );
    }
    expect(
      books.fold<int>(0, (sum, entry) => sum + entry.book.fileSize),
      208724096,
    );
    final sixth =
        books.singleWhere((entry) => entry.book.volumeLabel == '六年级上册');
    expect(
      sixth.book.pdfSha256,
      'e828449236d0c1b347e5cd6291d58b0febe83a3e21b2b7428697d8006af49ece',
    );
    expect(sixth.book.pageCount, 138);
    expect(sixth.evidencePdfPages, [3, 136]);
    expect(sixth.book.editionNote, contains('未载明出版年月'));
    expect(
      sixth.downloadUrl.pathSegments.take(3),
      ['hantang', 'yuwen', sixth.sourceCommit],
    );
  });

  test('12册封面均可离线解码且绑定目录中的原PDF身份与封面SHA', () async {
    final books = await const TextbookCatalogRepository().load();
    for (final entry in books) {
      expect(
        entry.coverAsset,
        'assets/textbooks/covers/${entry.book.pdfSha256}.webp',
      );
      final data = await rootBundle.load(entry.coverAsset!);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(sha256.convert(bytes).toString(), entry.coverSha256);
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.height, 768);
          expect(frame.image.width, inInclusiveRange(500, 600));
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
  });

  test('无效哈希、明文地址、未固定来源与证据页越界拒绝进入目录', () async {
    final json = jsonDecode(
      await rootBundle.loadString('assets/data/textbook_catalog.json'),
    ) as Map<String, dynamic>;
    final raw = ((json['books'] as List).first as Map<String, dynamic>);
    for (final change in <Map<String, dynamic>>[
      {'sha256': 'not-a-sha'},
      {
        'downloadUrl':
            (raw['downloadUrl'] as String).replaceFirst('https:', 'http:'),
      },
      {'sourceCommit': 'main'},
      {'coverAsset': 'assets/textbooks/covers/another-book.webp'},
      {'coverSha256': 'not-a-sha'},
      {'coverSha256': null},
      {'coverAsset': null},
      {'coverSourcePdfPage': 2},
      {
        'evidencePdfPages': [0],
      },
      {
        'evidencePdfPages': [99999],
      },
    ]) {
      expect(
        () => TextbookCatalogEntry.fromJson({...raw, ...change}),
        throwsFormatException,
      );
    }
  });
}
