import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/data/models/textbook_page_text.dart';

/// 可重建的本机派生数据；不保存查询词，不进入学习备份。
class TextbookContentCache {
  TextbookContentCache({
    required this.book,
    required Future<Directory> Function() directoryProvider,
  }) : _directoryProvider = directoryProvider {
    if (!Textbook.isValidId(book.pdfSha256)) {
      throw ArgumentError.value(book.pdfSha256, 'pdfSha256');
    }
  }

  static const formatVersion = 1;
  // 修改目录识别算法或层级规则时递增，保留可复用的逐页文字。
  static const tocVersion = 1;
  static const _maxFileBytes = 2 * 1024 * 1024;
  static const _maxBookTextBytes = 32 * 1024 * 1024;
  static const _maxMemoryCharacters = 4 * 1024 * 1024;
  static const layoutVersion = 2;
  static const _maxBookLayoutBytes = 64 * 1024 * 1024;
  static const _maxMemoryLayouts = 4;
  final Textbook book;
  final Future<Directory> Function() _directoryProvider;
  final _texts = <int, String>{};
  final _pending = <int, Future<String>>{};
  final _layouts = <int, TextbookPageText>{};
  final _pendingLayouts = <int, Future<TextbookPageText>>{};
  int _characters = 0;
  int _generation = 0;
  Future<void> _writes = Future<void>.value();
  TextbookTocResult? _toc;

  int get revision => _generation;

  Future<Directory> _directory() async => Directory(
        '${(await _directoryProvider()).path}/textbooks/cache/${book.pdfSha256}',
      );

  Map<String, Object?> _envelope(Object data) => {
        'version': formatVersion,
        'sha256': book.pdfSha256,
        'pageCount': book.pageCount,
        'pdfSize': book.fileSize,
        'data': data,
      };

  Future<Object?> _read(String name) async {
    try {
      final file = File('${(await _directory()).path}/$name.json');
      if (!await file.exists() || await file.length() > _maxFileBytes) {
        return null;
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic> ||
          value['version'] != formatVersion ||
          value['sha256'] != book.pdfSha256 ||
          value['pageCount'] != book.pageCount ||
          value['pdfSize'] != book.fileSize) {
        return null;
      }
      return value['data'];
    } on Object {
      // 缓存缺失、损坏或不可读都回退原PDF，不阻断目录和搜索。
      return null;
    }
  }

  Future<void> _write(String name, Object data, int generation) {
    final result = _writes.then((_) async {
      File? pending;
      try {
        if (generation != _generation) return;
        final bytes = utf8.encode(jsonEncode(_envelope(data)));
        if (bytes.length > _maxFileBytes ||
            (name.startsWith('page-') &&
                bytes.length > _maxBookTextBytes ~/ book.pageCount) ||
            (name.startsWith('layout-') &&
                bytes.length > _maxBookLayoutBytes ~/ book.pageCount)) {
          return;
        }
        final directory = await (await _directory()).create(recursive: true);
        if (generation != _generation) return;
        final target = File('${directory.path}/$name.json');
        pending = File(
          '${target.path}.${Random.secure().nextInt(1 << 32)}.pending',
        );
        await pending.writeAsBytes(bytes, flush: true);
        if (generation != _generation) return;
        await pending.rename(target.path);
        pending = null;
      } on Object {
        // 空间不足等写入失败只损失缓存，本次结果继续可用。
      } finally {
        if (pending != null) {
          try {
            if (await pending.exists()) await pending.delete();
          } on Object {
            // 不让临时缓存清理失败污染后续写入队列。
          }
        }
      }
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  void _remember(int page, String text) {
    _characters -= _texts.remove(page)?.length ?? 0;
    if (text.length > _maxMemoryCharacters) return;
    _texts[page] = text;
    _characters += text.length;
    while (_characters > _maxMemoryCharacters) {
      _characters -= _texts.remove(_texts.keys.first)!.length;
    }
  }

  /// 先查内存/磁盘；关闭搜索前已完成的页也可在下次复用。
  Future<String> pageText(int page, Future<String> Function() load) {
    RangeError.checkValueInInterval(page, 1, book.pageCount, 'page');
    final text = _texts.remove(page);
    if (text != null) {
      _texts[page] = text;
      return Future.value(text);
    }
    final existing = _pending[page];
    if (existing != null) return existing;
    final generation = _generation;
    late final Future<String> result;
    result = (() async {
      try {
        final stored = await _read('page-$page');
        if (stored is String && generation == _generation) {
          _remember(page, stored);
          return stored;
        }
        final loaded = await load();
        if (generation == _generation) {
          await rememberText(page, loaded, generation: generation);
        }
        return loaded;
      } finally {
        if (identical(_pending[page], result)) _pending.remove(page);
      }
    })();
    _pending[page] = result;
    return result;
  }

  /// 目录提取字符框时顺便保存原文，后续搜索不用再次提取文字。
  Future<void> rememberText(int page, String text, {int? generation}) async {
    RangeError.checkValueInInterval(page, 1, book.pageCount, 'page');
    final revision = generation ?? _generation;
    if (revision != _generation || _texts[page] == text) return;
    _remember(page, text);
    await _write('page-$page', text, revision);
  }

  /// 与纯文字共用写入队列和失效代次，清理后旧布局不能复活。
  Future<TextbookPageText> pageLayout(
    int page,
    Future<TextbookPageText> Function() load,
  ) {
    RangeError.checkValueInInterval(page, 1, book.pageCount, 'page');
    final cached = _layouts.remove(page);
    if (cached != null) {
      _layouts[page] = cached;
      return Future.value(cached);
    }
    final existing = _pendingLayouts[page];
    if (existing != null) return existing;
    final generation = _generation;
    late final Future<TextbookPageText> result;
    result = (() async {
      try {
        TextbookPageText? value;
        final raw = await _read('layout-$page');
        if (raw is Map<String, dynamic> &&
            raw['layoutVersion'] == layoutVersion) {
          try {
            value =
                TextbookPageText.fromJson(raw['page'] as Map<String, dynamic>);
            if (value.page != page) value = null;
          } on Object {
            value = null;
          }
        }
        if (generation != _generation) throw StateError('原书缓存已失效');
        if (value == null) {
          value = await load();
          if (generation != _generation) throw StateError('原书缓存已失效');
          if (value.page != page) throw const FormatException('原书页码不一致');
          await _write(
            'layout-$page',
            {
              'layoutVersion': layoutVersion,
              'page': value.toJson(),
            },
            generation,
          );
        }
        if (generation != _generation) throw StateError('原书缓存已失效');
        if (value.glyphs.length <= 20000) {
          _layouts[page] = value;
          while (_layouts.length > _maxMemoryLayouts) {
            _layouts.remove(_layouts.keys.first);
          }
        }
        await rememberText(page, value.text, generation: generation);
        return value;
      } finally {
        if (identical(_pendingLayouts[page], result)) {
          _pendingLayouts.remove(page);
        }
      }
    })();
    _pendingLayouts[page] = result;
    return result;
  }

  Future<TextbookTocResult?> readToc() async {
    if (_toc != null) return _toc;
    final generation = _generation;
    final value = await _read('toc');
    if (generation != _generation) return null;
    final result = decodeTextbookToc(value, pageCount: book.pageCount);
    return _toc = result;
  }

  Future<void> writeToc(TextbookTocResult result, {int? generation}) async {
    final revision = generation ?? _generation;
    if (revision != _generation) return;
    _toc = result;
    await _write('toc', encodeTextbookToc(result), revision);
  }

  /// 删除前失效所有在途任务，再等已开始的原子写入结束，防止缓存复活。
  Future<void> clear() {
    _generation++;
    _toc = null;
    _texts.clear();
    _pending.clear();
    _layouts.clear();
    _pendingLayouts.clear();
    _characters = 0;
    final result = _writes.then((_) async {
      final directory = await _directory();
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}

Map<String, Object?> encodeTextbookToc(TextbookTocResult result) => {
      'tocVersion': TextbookContentCache.tocVersion,
      'source': result.source.name,
      'directoryPages': result.directoryPages,
      'hasText': result.hasText,
      'entries': [
        for (final entry in result.entries)
          {
            'title': entry.title,
            'page': entry.page,
            'printedPage': entry.printedPage,
            'level': entry.level,
            'lessonNumber': entry.lessonNumber,
            'isGroup': entry.isGroup,
          },
      ],
    };

TextbookTocResult? decodeTextbookToc(Object? value, {required int pageCount}) {
  if (value is! Map<String, dynamic> ||
      value['tocVersion'] != TextbookContentCache.tocVersion ||
      value['hasText'] is! bool ||
      value['entries'] is! List ||
      value['directoryPages'] is! List) {
    return null;
  }
  final source = TextbookTocSource.values
      .where((source) => source.name == value['source'])
      .firstOrNull;
  if (source == null) return null;
  bool validPage(Object? page) => page is int && page >= 1 && page <= pageCount;
  final directory = value['directoryPages'] as List<dynamic>;
  if (!directory.every(validPage)) return null;
  final entries = <TextbookTocEntry>[];
  for (final raw in value['entries'] as List<dynamic>) {
    if (raw is! Map<String, dynamic> ||
        raw['title'] is! String ||
        (raw['title'] as String).trim().isEmpty ||
        (raw['page'] != null && !validPage(raw['page'])) ||
        (raw['printedPage'] != null &&
            (raw['printedPage'] is! int || (raw['printedPage'] as int) < 1)) ||
        raw['level'] is! int ||
        (raw['level'] as int) < 0 ||
        (raw['level'] as int) > 6 ||
        raw['isGroup'] is! bool ||
        (raw['lessonNumber'] != null &&
            (raw['lessonNumber'] is! int ||
                (raw['lessonNumber'] as int) < 1))) {
      return null;
    }
    entries.add(
      TextbookTocEntry(
        title: raw['title'] as String,
        page: raw['page'] as int?,
        printedPage: raw['printedPage'] as int?,
        level: raw['level'] as int,
        lessonNumber: raw['lessonNumber'] as int?,
        isGroup: raw['isGroup'] as bool,
      ),
    );
  }
  return TextbookTocResult(
    source: source,
    entries: List.unmodifiable(entries),
    directoryPages: List<int>.unmodifiable(directory),
    hasText: value['hasText'] as bool,
  );
}
