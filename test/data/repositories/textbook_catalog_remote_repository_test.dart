import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/textbook_catalog_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = TextbookCatalogRemoteConfig.publicLibrary;
  late Directory directory;
  late Box<dynamic> cache;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('textbook_catalog_');
    Hive.init(directory.path);
    cache = await Hive.openBox<dynamic>('catalog');
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  http.Response jsonResponse(Map<String, dynamic> body, {int status = 200}) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic> manifest({String? sourceRepository}) => {
    'schemaVersion': 1,
    'repository': config.repositoryId,
    'books': [
      {
        'subject': 'math',
        'grade': 1,
        'semester': '上',
        'title': '人教版数学',
        'publisher': '人民教育出版社',
        'editionId': 'pep-math-1a-approval-2024',
        'curriculumStandard': null,
        'approvalYear': 2024,
        'editionLabel': '教育部审定2024',
        'editionNotes': '封面标注教育部审定2024。',
        'publicationDate': null,
        'editionNumber': null,
        'printingDate': null,
        'printingNumber': null,
        'sha256': 'a' * 64,
        'bytes': 1200,
        'pageCount': 10,
        'downloadUrl':
            'https://raw.githubusercontent.com/${config.repositoryId}/${'b' * 40}/books/math/grade-01/upper/pep-math-1a-approval-2024.pdf',
        'sourceRepository': sourceRepository ?? config.repositoryId,
        'sourceCommit': 'b' * 40,
        'sourcePath': 'books/math/grade-01/upper/pep-math-1a-approval-2024.pdf',
        'gitBlobSha': 'c' * 40,
        'checkedAt': '2026-11-23T00:00:00Z',
        'evidencePdfPages': [1],
        'coverPath': 'covers/${'a' * 64}.webp',
        'coverSha256': 'd' * 64,
        'coverSourcePdfPage': 1,
        'downloadable': true,
        'pdfText': {
          'hasTextLayer': false,
          'pagesWithText': 0,
          'characterCount': 0,
        },
        'redistributionPermissionVerified': true,
        'redistributionEvidence': '测试授权记录',
      },
    ],
  };

  test('200 保存完整校验后的快照并隐藏内置下载条目', () async {
    final repository = TextbookCatalogRepository(
      config: config,
      cache: cache,
      clientFactory: () => MockClient((request) async {
        expect(request.url, config.manifestUrl);
        expect(request.followRedirects, isFalse);
        return jsonResponse(manifest());
      }),
    );

    expect(await repository.refreshRemote(), isTrue);
    final catalog = await repository.load();
    final remote = catalog
        .where((entry) => entry.sourceRepository == config.repositoryId)
        .toList();
    expect(remote, hasLength(1));
    expect(remote.single.downloadable, isTrue);
    expect(remote.single.supportsMathCourseGeneration, isFalse);
    expect(remote.single.coverUrl.toString(), contains('covers'));
    expect(
      catalog
          .where((entry) => entry.sourceRepository != config.repositoryId)
          .every((entry) => !entry.downloadable),
      isTrue,
    );
  });

  test('版次 ID 与原始文件名分离，保留含中文和空格的 PDF 路径', () async {
    final body = manifest();
    final book = (body['books'] as List).single as Map<String, dynamic>;
    const sourcePath =
        'books/math/grade-01/upper/数学 人教版 一年级 上册 2024版.pdf';
    final encodedPath = sourcePath.split('/').map(Uri.encodeComponent).join('/');
    book['sourcePath'] = sourcePath;
    book['downloadUrl'] =
        'https://raw.githubusercontent.com/${config.repositoryId}/${'b' * 40}/$encodedPath';
    final repository = TextbookCatalogRepository(
      config: config,
      cache: cache,
      clientFactory: () => MockClient((_) async => jsonResponse(body)),
    );

    await repository.refreshRemote();

    final entry = (await repository.load()).singleWhere(
      (entry) => entry.sourceRepository == config.repositoryId,
    );
    expect(entry.book.editionId, 'pep-math-1a-approval-2024');
    expect(entry.sourcePath, sourcePath);
    expect(entry.downloadUrl.pathSegments.last, contains('数学'));
  });

  test('可下载书目不因再分发核验字段未确认而被 App 拒绝', () async {
    final body = manifest();
    final book = (body['books'] as List).single as Map<String, dynamic>;
    book['redistributionPermissionVerified'] = false;
    book['redistributionEvidence'] = '';
    final repository = TextbookCatalogRepository(
      config: config,
      cache: cache,
      clientFactory: () => MockClient((_) async => jsonResponse(body)),
    );

    expect(await repository.refreshRemote(), isTrue);

    final entry = (await repository.load()).singleWhere(
      (entry) => entry.sourceRepository == config.repositoryId,
    );
    expect(entry.downloadable, isTrue);
    expect(entry.redistributionPermissionVerified, isFalse);
    expect(entry.redistributionEvidence, isEmpty);
  });

  test('304 复用最近一次有效目录并带上 ETag', () async {
    var requests = 0;
    final repository = TextbookCatalogRepository(
      config: config,
      cache: cache,
      clientFactory: () => MockClient((request) async {
        requests++;
        if (requests == 1) {
          return http.Response(
            jsonEncode(manifest()),
            200,
            headers: {
              'etag': '"catalog-v1"',
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        expect(
          request.headers['If-None-Match'] ?? request.headers['if-none-match'],
          '"catalog-v1"',
        );
        return http.Response('', 304);
      }),
    );

    expect(await repository.refreshRemote(), isTrue);
    final stored = jsonDecode(
      cache.get(config.cacheKey) as String,
    ) as Map<String, dynamic>;
    expect(stored['etag'], '"catalog-v1"');
    expect(await repository.refreshRemote(), isFalse);
    expect(
      (await repository.load()).where((entry) => entry.downloadable),
      hasLength(1),
    );
  });

  test('无效新清单不覆盖上次成功缓存', () async {
    var requests = 0;
    final repository = TextbookCatalogRepository(
      config: config,
      cache: cache,
      clientFactory: () => MockClient((_) async {
        requests++;
        return jsonResponse(
          requests == 1 ? manifest() : manifest(sourceRepository: 'other/repo'),
        );
      }),
    );

    await repository.refreshRemote();
    await expectLater(
      repository.refreshRemote(),
      throwsA(isA<TextbookCatalogException>()),
    );
    final catalog = await repository.load();
    expect(
      catalog
          .singleWhere((entry) => entry.sourceRepository == config.repositoryId)
          .book
          .pdfSha256,
      'a' * 64,
    );
  });

  test('首次远程读取失败时不展示内置目录下载项', () async {
    final repository = TextbookCatalogRepository(
      config: config,
      cache: cache,
      clientFactory: () => MockClient((_) async => http.Response('', 404)),
    );

    await expectLater(
      repository.refreshRemote(),
      throwsA(isA<TextbookCatalogException>()),
    );
    final catalog = await repository.load();
    expect(catalog, isNotEmpty);
    expect(catalog.where((entry) => entry.downloadable), isEmpty);
    expect(
      catalog.any((entry) => entry.book.subject == TextbookSubject.math),
      isTrue,
    );
  });

  test('拒绝错误仓库、路径和重定向', () async {
    for (final invalid in [
      manifest(sourceRepository: 'other/repo'),
      {
        ...manifest(),
        'books': [
          {
            ...(manifest()['books'] as List).single as Map<String, dynamic>,
            'sourcePath': '../outside.pdf',
          },
        ],
      },
      {
        ...manifest(),
        'books': [
          {
            ...(manifest()['books'] as List).single as Map<String, dynamic>,
            'sourcePath':
                'books/math/grade-01/lower/pep-math-1a-approval-2024.pdf',
            'downloadUrl':
                'https://raw.githubusercontent.com/${config.repositoryId}/${'b' * 40}/books/math/grade-01/lower/pep-math-1a-approval-2024.pdf',
          },
        ],
      },
    ]) {
      final repository = TextbookCatalogRepository(
        config: config,
        cache: cache,
        clientFactory: () => MockClient((_) async => jsonResponse(invalid)),
      );
      await expectLater(
        repository.refreshRemote(),
        throwsA(isA<TextbookCatalogException>()),
      );
    }

    final redirect = TextbookCatalogRepository(
      config: config,
      cache: cache,
      clientFactory: () => MockClient((_) async => http.Response('', 302)),
    );
    await expectLater(
      redirect.refreshRemote(),
      throwsA(isA<TextbookCatalogException>()),
    );
    expect(cache.get(config.cacheKey), isNull);
  });
}
