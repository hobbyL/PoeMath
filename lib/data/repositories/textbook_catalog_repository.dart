import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:poemath/core/services/bounded_http_client.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook_catalog.dart';

class TextbookCatalogRemoteConfig {
  const TextbookCatalogRemoteConfig({
    required this.owner,
    required this.repository,
    this.branch = 'main',
    this.catalogPath = 'catalog.json',
  });

  const TextbookCatalogRemoteConfig.disabled()
    : owner = '',
      repository = '',
      branch = '',
      catalogPath = '';

  static const publicLibrary = TextbookCatalogRemoteConfig(
    owner: 'hobbyL',
    repository: 'TextbookLibrary',
  );

  final String owner;
  final String repository;
  final String branch;
  final String catalogPath;

  bool get enabled =>
      RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(owner) &&
      RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(repository) &&
      branch.isNotEmpty &&
      catalogPath.isNotEmpty &&
      !catalogPath.startsWith('/') &&
      !catalogPath.contains('\\') &&
      catalogPath
          .split('/')
          .every((part) => part.isNotEmpty && part != '.' && part != '..');

  String get repositoryId => '$owner/$repository';

  Uri get manifestUrl {
    final path = [
      owner,
      repository,
      branch,
      ...catalogPath.split('/'),
    ].map(Uri.encodeComponent).join('/');
    return Uri.parse('https://raw.githubusercontent.com/$path');
  }

  String get cacheKey =>
      'textbook_catalog_snapshot_v1:$repositoryId:$branch:$catalogPath';
}

class TextbookCatalogException implements Exception {
  const TextbookCatalogException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _CachedCatalog {
  const _CachedCatalog({
    required this.body,
    required this.etag,
    required this.entries,
  });

  final String body;
  final String? etag;
  final List<TextbookCatalogEntry> entries;
}

class TextbookCatalogRepository {
  const TextbookCatalogRepository({
    this.config = const TextbookCatalogRemoteConfig.disabled(),
    this.clientFactory,
    this.cache,
  });

  static const _cacheFormatVersion = 1;
  static const _maxCatalogBytes = 2 * 1024 * 1024;

  final TextbookCatalogRemoteConfig config;
  final http.Client Function()? clientFactory;
  final Box<dynamic>? cache;

  Box<dynamic> get _cache => cache ?? HiveBoxes.meta;

  Future<List<TextbookCatalogEntry>> load() async {
    final bundled = await _loadBundled();
    if (!config.enabled) return bundled;
    final cached = _readCachedCatalog();
    final legacy = [for (final entry in bundled) entry.withDownloadable(false)];
    return _mergeByPdfIdentity(legacy, cached?.entries ?? const []);
  }

  Future<bool> refreshRemote() async {
    if (!config.enabled) return false;
    final cached = _readCachedCatalog();
    final inner = clientFactory?.call() ?? http.Client();
    final client = BoundedHttpClient(
      inner,
      timeout: const Duration(seconds: 15),
      maxResponseBytes: _maxCatalogBytes,
    );
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      final etag = cached?.etag;
      if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;
      final response = await client.request(
        'GET',
        config.manifestUrl,
        headers: headers,
        followRedirects: false,
        deadline: const Duration(seconds: 15),
      );
      if (response.statusCode == 304) {
        if (cached == null) {
          throw const TextbookCatalogException('教材目录返回 304，但本机没有有效缓存');
        }
        return false;
      }
      if (response.statusCode != 200) {
        throw TextbookCatalogException('教材目录暂时无法读取（${response.statusCode}）');
      }
      final body = response.body;
      final entries = _parseRemoteManifest(body);
      final snapshot = jsonEncode({
        'version': _cacheFormatVersion,
        'body': body,
        'etag': response.headers['etag'],
      });
      await _cache.put(config.cacheKey, snapshot);
      return entries.isNotEmpty || body.isNotEmpty;
    } on TextbookCatalogException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '教材目录刷新失败：${error.runtimeType}',
        tag: 'TextbookCatalog',
        stackTrace: stackTrace,
      );
      throw TextbookCatalogException('教材目录刷新失败：${error.runtimeType}');
    } finally {
      client.close();
      inner.close();
    }
  }

  Future<List<TextbookCatalogEntry>> _loadBundled() async {
    final sources = await Future.wait([
      rootBundle.loadString('assets/data/textbook_catalog.json'),
      rootBundle.loadString('assets/data/math_textbook_catalog.json'),
    ]);
    final entries = <TextbookCatalogEntry>[];
    for (final source in sources) {
      final json = jsonDecode(source) as Map<String, dynamic>;
      if (!const [1, 2, 3].contains(json['schemaVersion'])) {
        throw const FormatException('教材目录版本不支持');
      }
      entries.addAll(
        (json['books'] as List).map(
          (raw) => TextbookCatalogEntry.fromJson(raw as Map<String, dynamic>),
        ),
      );
    }
    final ids = entries.map((entry) => entry.book.pdfSha256).toSet();
    if (ids.length != entries.length) {
      throw const FormatException('教材目录存在重复资源');
    }
    return List.unmodifiable(entries);
  }

  _CachedCatalog? _readCachedCatalog() {
    dynamic raw;
    try {
      raw = _cache.get(config.cacheKey);
    } on Object catch (error) {
      AppLogger.w('读取教材目录缓存失败：$error', tag: 'TextbookCatalog');
      return null;
    }
    if (raw is! String) return null;
    try {
      final cached = jsonDecode(raw) as Map<String, dynamic>;
      if (cached['version'] != _cacheFormatVersion ||
          cached['body'] is! String ||
          (cached['etag'] != null && cached['etag'] is! String)) {
        throw const FormatException('教材目录缓存格式不支持');
      }
      final body = cached['body'] as String;
      return _CachedCatalog(
        body: body,
        etag: cached['etag'] as String?,
        entries: _parseRemoteManifest(body),
      );
    } on Object catch (error) {
      AppLogger.w('忽略无效教材目录缓存：$error', tag: 'TextbookCatalog');
      return null;
    }
  }

  List<TextbookCatalogEntry> _parseRemoteManifest(String body) {
    if (utf8.encode(body).length > _maxCatalogBytes) {
      throw const TextbookCatalogException('教材目录超过允许大小');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != 1 ||
        decoded['repository'] != config.repositoryId ||
        decoded['books'] is! List) {
      throw const TextbookCatalogException('教材目录格式或仓库身份无效');
    }
    final entries = <TextbookCatalogEntry>[];
    final pdfIds = <String>{};
    final editionIds = <String>{};
    for (final raw in decoded['books'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const TextbookCatalogException('教材目录条目格式无效');
      }
      final pdfText = raw['pdfText'];
      final pageCount = raw['pageCount'];
      if (pdfText is! Map<String, dynamic> ||
          pdfText['hasTextLayer'] is! bool ||
          pdfText['pagesWithText'] is! int ||
          pdfText['characterCount'] is! int ||
          pageCount is! int ||
          (pdfText['pagesWithText'] as int) < 0 ||
          (pdfText['pagesWithText'] as int) > pageCount ||
          (pdfText['characterCount'] as int) < 0 ||
          pdfText['hasTextLayer'] != ((pdfText['pagesWithText'] as int) > 0)) {
        throw const TextbookCatalogException('PDF 可提取文字统计无效');
      }
      final adaptedJson = {
        ...raw,
        'supportsMathCourseGeneration': raw['subject'] == 'math'
            ? pdfText['hasTextLayer'] as bool
            : true,
      };
      final entry = TextbookCatalogEntry.fromJson(
        adaptedJson,
        expectedRepository: config.repositoryId,
      );
      final book = entry.book;
      final semesterPath = book.semester == '上' ? 'upper' : 'lower';
      final gradePath = book.grade.toString().padLeft(2, '0');
      final expectedDirectory =
          'books/${book.subject.name}/grade-$gradePath/$semesterPath';
      final sourcePathSegments = entry.sourcePath?.split('/') ?? const <String>[];
      final sourceFilename = sourcePathSegments.length == 5
          ? sourcePathSegments.last
          : '';
      final sourcePathMatches =
          sourcePathSegments.length == 5 &&
          sourcePathSegments.take(4).join('/') == expectedDirectory &&
          sourceFilename.toLowerCase().endsWith('.pdf') &&
          sourceFilename.length > 4;
      if (entry.sourceKind != TextbookCatalogSourceKind.githubRaw ||
          !sourcePathMatches ||
          entry.coverPath != 'covers/${book.pdfSha256}.webp') {
        throw TextbookCatalogException('书目来源、目录路径或封面信息无效：${book.editionId}');
      }
      final editionKey =
          '${book.subject.name}:${book.grade}:${book.semester}:${book.editionId}';
      if (!pdfIds.add(book.pdfSha256) || !editionIds.add(editionKey)) {
        throw TextbookCatalogException('教材目录存在重复版本：${book.editionId}');
      }
      entries.add(entry);
    }
    return List.unmodifiable(entries);
  }

  static List<TextbookCatalogEntry> _mergeByPdfIdentity(
    List<TextbookCatalogEntry> bundled,
    List<TextbookCatalogEntry> remote,
  ) {
    final entries = <String, TextbookCatalogEntry>{
      for (final entry in bundled) entry.book.pdfSha256: entry,
    };
    for (final entry in remote) {
      entries[entry.book.pdfSha256] = entry;
    }
    return List.unmodifiable(entries.values);
  }
}
