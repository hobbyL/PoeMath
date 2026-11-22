import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/textbook_catalog_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真实目录覆盖12册且保留来源、校验身份与实际版本证据', () async {
    final catalog = await const TextbookCatalogRepository().load();
    expect(catalog, hasLength(33));
    final books = catalog
        .where((entry) => entry.book.subject == TextbookSubject.chinese)
        .toList();
    expect(books, hasLength(12));
    expect(
      books
          .map((entry) => '${entry.book.grade}${entry.book.semester}')
          .toList(),
      ['1上', '1下', '2上', '2下', '3上', '3下', '4上', '4下', '5上', '5下', '6上', '6下'],
    );
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
    final sixth = books.singleWhere(
      (entry) => entry.book.volumeLabel == '六年级上册',
    );
    expect(
      sixth.book.pdfSha256,
      'e828449236d0c1b347e5cd6291d58b0febe83a3e21b2b7428697d8006af49ece',
    );
    expect(sixth.book.pageCount, 138);
    expect(sixth.evidencePdfPages, [3, 136]);
    expect(sixth.book.editionNote, contains('未载明出版年月'));
    expect(sixth.downloadUrl.pathSegments.take(3), [
      'hantang',
      'yuwen',
      sixth.sourceCommit,
    ]);

    final math = catalog
        .where((entry) => entry.book.subject == TextbookSubject.math)
        .toList();
    final downloadable = math.where((entry) => entry.downloadable).toList();
    final current2024 = downloadable
        .where((entry) => entry.approvalYear == 2024)
        .toList();
    final current2022 = downloadable
        .where((entry) => entry.approvalYear == 2022)
        .toList();
    final retired = math.where((entry) => !entry.downloadable).toList();
    expect(math, hasLength(21));
    expect(downloadable, hasLength(12));
    expect(current2024, hasLength(9));
    expect(current2022, hasLength(3));
    expect(retired, hasLength(9));
    expect(
      current2024.every(
        (entry) =>
            entry.editionLabel == '教育部审定2024' &&
            !entry.supportsMathCourseGeneration,
      ),
      isTrue,
    );
    expect(
      current2024.every(
        (entry) =>
            entry.publicationDate == null &&
            entry.editionNumber == null &&
            entry.printingDate == null &&
            entry.printingNumber == null &&
            entry.book.curriculumStandard == null,
      ),
      isTrue,
    );
    expect(
      current2022.every(
        (entry) =>
            entry.book.semester == '下' &&
            entry.approvalYear == 2022 &&
            entry.book.editionNote.contains('审定2022'),
      ),
      isTrue,
    );
    expect(
      retired.every(
        (entry) =>
            entry.supportsMathCourseGeneration &&
            entry.sourceKind == TextbookCatalogSourceKind.githubRaw,
      ),
      isTrue,
    );
    expect(
      downloadable
          .map((entry) => '${entry.book.grade}${entry.book.semester}')
          .toSet(),
      {'1上', '1下', '2上', '2下', '3上', '3下', '4上', '4下', '5上', '5下', '6上', '6下'},
    );
    expect(
      current2024.every(
        (entry) =>
            entry.sourceKind == TextbookCatalogSourceKind.mathApi &&
            entry.fallbackDownloadUrl == null &&
            entry.downloadUrl.host == 'www.gostudy.net.cn',
      ),
      isTrue,
    );
  });

  test('完整目录33册封面均可离线解码且绑定原PDF身份与封面SHA', () async {
    final books = await const TextbookCatalogRepository().load();
    for (final entry in books) {
      expect(
        entry.coverAsset,
        'assets/textbooks/covers/${entry.book.pdfSha256}.webp',
      );
      final data = await rootBundle.load(entry.coverAsset!);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
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
        'downloadUrl': (raw['downloadUrl'] as String).replaceFirst(
          'https:',
          'http:',
        ),
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

  test('数学 API 来源仅接受精确 HTTPS 主机、路径与对应册次', () async {
    final json = jsonDecode(
      await rootBundle.loadString('assets/data/math_textbook_catalog.json'),
    ) as Map<String, dynamic>;
    final raw = (json['books'] as List).cast<Map<String, dynamic>>().firstWhere(
      (entry) => entry['sourceKind'] == 'mathApi',
    );
    final accepted = TextbookCatalogEntry.fromJson(raw);
    expect(accepted.sourceKind, TextbookCatalogSourceKind.mathApi);
    expect(accepted.fallbackDownloadUrl, isNull);

    final uri = Uri.parse(raw['downloadUrl'] as String);
    final invalidUrls = [
      uri.replace(scheme: 'http'),
      uri.replace(host: 'gostudy.net.cn'),
      uri.replace(host: 'www.gostudy.net.cn.evil.example'),
      uri.replace(port: 8443),
      uri.replace(queryParameters: {'download': '1'}),
      uri.replace(fragment: 'pdf'),
      Uri.parse('https://user@${uri.host}${uri.path}'),
      uri.replace(path: '/api/textbooks/math/2/${uri.pathSegments.last}'),
      Uri.parse('${uri.toString()}/extra'),
    ];
    for (final invalidUrl in invalidUrls) {
      expect(
        () => TextbookCatalogEntry.fromJson({
          ...raw,
          'downloadUrl': invalidUrl.toString(),
        }),
        throwsFormatException,
        reason: invalidUrl.toString(),
      );
    }
    for (final invalid in <Map<String, dynamic>>[
      {'subject': 'chinese'},
      {'sourceRepository': 'someone/repo'},
      {'sourceCommit': 'a' * 40},
      {'sourcePath': 'book.pdf'},
      {'gitBlobSha': 'a' * 40},
      {'grade': 2},
      {'semester': '下'},
    ]) {
      expect(
        () => TextbookCatalogEntry.fromJson({...raw, ...invalid}),
        throwsFormatException,
        reason: invalid.toString(),
      );
    }
  });
}
