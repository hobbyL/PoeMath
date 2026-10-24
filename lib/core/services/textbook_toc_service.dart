import 'dart:math' as math;

import 'package:poemath/core/services/textbook_content_cache.dart';
import 'package:poemath/data/models/textbook_toc.dart';

final _spaces = RegExp(r'\s+');
final _han = RegExp(r'[\u3400-\u9FFF]');
final _pinyin = RegExp(r'[A-Za-z\u00C0-\u024F\u0300-\u036F\u1E00-\u1EFF]');
final _leaders = RegExp(r'(?:[.．…·•⋯_—\-]\s*){2,}');
final _number = RegExp(r'^\d{1,5}$');
final _tocHeading = RegExp(r'^(目录|目錄|目次|contents|tableofcontents)$');
final _unit = RegExp(r'^第[一二三四五六七八九十百零〇0-9]+单元(?:[·•・]?\s*(?:识字|阅读))?$');
final _appendix = RegExp(r'^(?:识字表|写字表|词语表|常用偏旁名称表|附录.*)$');

bool _isGroup(String title) =>
    _unit.hasMatch(title.replaceAll(_spaces, '')) ||
    RegExp(r'^(古诗词诵读|习作例文|快乐读书吧)[：:]?$').hasMatch(title);

/// 本机文字目录识别；完成结果可按原书身份持久化复用。
class TextbookTocService {
  TextbookTocService({
    required this.pageCount,
    required this.loadOutline,
    required this.loadPage,
    this.cache,
  });

  final int pageCount;
  final Future<List<TextbookTocEntry>> Function() loadOutline;
  final Future<TextbookTocPage> Function(int page) loadPage;
  final TextbookContentCache? cache;
  TextbookTocResult? _cached;
  int? _cacheRevision;

  Stream<TextbookTocProgress> scan({bool refresh = false}) async* {
    final revision = cache?.revision;
    if (revision != _cacheRevision) {
      _cached = null;
      _cacheRevision = revision;
    }
    if (!refresh && _cached == null) _cached = await cache?.readToc();
    if (!refresh && _cached != null) {
      yield _progress(TextbookTocPhase.ready, pageCount, _cached);
      return;
    }
    yield _progress(TextbookTocPhase.locating, 0);
    List<TextbookTocEntry> outline;
    try {
      outline = (await loadOutline())
          .where((entry) => entry.title.trim().isNotEmpty)
          .map(
            (entry) => TextbookTocEntry(
              title: entry.title.trim(),
              page: entry.page != null &&
                      entry.page! >= 1 &&
                      entry.page! <= pageCount
                  ? entry.page
                  : null,
              level: entry.level.clamp(0, 6),
            ),
          )
          .toList();
    } on Object {
      // 部分 PDF 无法读取书签，但文字目录仍可能可用。
      outline = [];
    }
    final usable = outline.where((entry) => entry.page != null).toList();
    final fileSegments = usable.isNotEmpty &&
        usable.every(
          (entry) => RegExp(r'(^\d{4,}[-_]|\.pdf$|_DJD$)', caseSensitive: false)
              .hasMatch(entry.title),
        );
    if (usable.isNotEmpty && !fileSegments) {
      _cached = TextbookTocResult(
        entries: List.unmodifiable(outline),
        source: TextbookTocSource.bookmarks,
      );
      await cache?.writeToc(_cached!, generation: revision);
      yield _progress(TextbookTocPhase.ready, pageCount, _cached);
      return;
    }

    final candidates = <_DirectoryPage>[];
    var hasText = false;
    for (var page = 1; page <= pageCount; page++) {
      final text = await loadPage(page);
      hasText |= text.text.trim().isNotEmpty;
      final rows = _rows(text);
      final heading = rows.any(
        (row) => _tocHeading
            .hasMatch(row.text.replaceAll(_spaces, '').toLowerCase()),
      );
      final entries = _entries(rows);
      if (heading || entries.length >= 2) {
        candidates.add(_DirectoryPage(page, heading, entries));
      }
      yield _progress(TextbookTocPhase.locating, page);
    }
    final directory = _chooseDirectory(candidates);
    if (directory.isEmpty) {
      _cached = TextbookTocResult(
        entries: List.unmodifiable(outline),
        source: outline.isEmpty
            ? TextbookTocSource.text
            : TextbookTocSource.bookmarks,
        hasText: hasText,
      );
      await cache?.writeToc(_cached!, generation: revision);
      yield _progress(TextbookTocPhase.ready, pageCount, _cached);
      return;
    }

    final directoryPages = directory.map((page) => page.page).toSet();
    final entries = <_Candidate>[];
    final seen = <String>{};
    for (final page in directory) {
      for (final entry in page.entries) {
        if (entry.printedPage == null ||
            seen.add('${entry.title}:${entry.printedPage}')) {
          entries.add(entry);
        }
      }
    }
    final matches = [for (final _ in entries) <int>{}];
    final confirmed = [for (final _ in entries) <int>{}];
    final footers = <int, int>{};
    for (var page = 1; page <= pageCount; page++) {
      if (!directoryPages.contains(page)) {
        final text = await loadPage(page);
        final rows = _rows(text);
        final footer = rows
            .where((row) => row.top > 0.87 && _number.hasMatch(row.text.trim()))
            .map((row) => int.parse(row.text.trim()))
            .toSet();
        if (footer.length == 1) footers[page] = footer.single;
        for (var index = 0; index < entries.length; index++) {
          final entry = entries[index];
          if (entry.printedPage == null) continue;
          final chinese = _han.hasMatch(entry.title);
          final needle = _normalize(entry.title, chinese);
          if (needle.isEmpty) continue;
          final headingMatch = rows.any((row) {
            final value = _normalize(_cleanTitle(row.text), chinese);
            return row.top < 0.7 && value == needle;
          });
          if (headingMatch) {
            matches[index].add(page);
            if (footers[page] == entry.printedPage) confirmed[index].add(page);
          }
        }
      }
      yield _progress(TextbookTocPhase.resolving, page);
    }

    // 多个不同标题、不同印刷页提供相同偏移才采用，绝不写死 +5。
    final titleCounts = <String, int>{};
    for (final entry in entries) {
      final key = _normalize(entry.title, _han.hasMatch(entry.title));
      titleCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    final votes = <int, Set<int>>{};
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (entry.printedPage == null) continue;
      final key = _normalize(entry.title, _han.hasMatch(entry.title));
      final pages =
          confirmed[index].isNotEmpty ? confirmed[index] : matches[index];
      if (titleCounts[key] == 1 && pages.length == 1) {
        final offset = pages.single - entry.printedPage!;
        (votes[offset] ??= {}).add(entry.printedPage!);
      }
    }
    final ranked = votes.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final offset = ranked.isNotEmpty &&
            ranked.first.value.length >= 2 &&
            (ranked.length == 1 ||
                ranked.first.value.length > ranked[1].value.length)
        ? ranked.first.key
        : null;
    final resolved = <TextbookTocEntry>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      int? target;
      if (confirmed[index].length == 1) {
        target = confirmed[index].single;
      } else if (offset != null && entry.printedPage != null) {
        final expected = entry.printedPage! + offset;
        if (expected >= 1 &&
            expected <= pageCount &&
            !directoryPages.contains(expected) &&
            (matches[index].contains(expected) ||
                footers[expected] == entry.printedPage)) {
          target = expected;
        }
      } else if (matches[index].length == 1) {
        target = matches[index].single;
      }
      resolved.add(
        TextbookTocEntry(
          title: entry.title,
          printedPage: entry.printedPage,
          page: target,
          level: entry.level,
          lessonNumber: entry.lessonNumber,
          isGroup: entry.isGroup,
        ),
      );
    }
    _cached = TextbookTocResult(
      entries: List.unmodifiable(_hierarchy(resolved)),
      source: TextbookTocSource.text,
      directoryPages: List.unmodifiable(directoryPages),
      hasText: hasText,
    );
    await cache?.writeToc(_cached!, generation: revision);
    yield _progress(TextbookTocPhase.ready, pageCount, _cached);
  }

  TextbookTocProgress _progress(
    TextbookTocPhase phase,
    int scanned, [
    TextbookTocResult? result,
  ]) =>
      TextbookTocProgress(
        phase: phase,
        scanned: scanned,
        total: pageCount,
        result: result,
      );
}

String _normalize(String value, bool chinese) {
  value = value.toLowerCase().replaceAll(_spaces, '');
  if (chinese) value = value.replaceAll(_pinyin, '');
  return value.replaceAll(RegExp(r'[^\u3400-\u9FFFa-z\u00C0-\u024F0-9]'), '');
}

/// 目录的阅读顺序已经恢复；换页/换栏不重置当前单元。
List<TextbookTocEntry> _hierarchy(List<TextbookTocEntry> entries) {
  final structured = entries.any((entry) => entry.isGroup);
  var inUnit = false;
  var section = false;
  int? categoryLevel;
  int? collectionIndent;
  var collectionLevel = 0;
  final result = <TextbookTocEntry>[];
  for (final entry in entries) {
    final title = entry.title;
    var level = structured ? (inUnit || section ? 1 : 0) : entry.level;
    if (_unit.hasMatch(title.replaceAll(_spaces, ''))) {
      inUnit = true;
      section = false;
      categoryLevel = collectionIndent = null;
      level = 0;
    } else if (title == '古诗词诵读' || _appendix.hasMatch(title)) {
      inUnit = false;
      section = title == '古诗词诵读';
      categoryLevel = collectionIndent = null;
      level = 0;
    } else if (entry.isGroup) {
      categoryLevel = level;
      collectionIndent = null;
    } else if (entry.lessonNumber != null) {
      categoryLevel = null;
      collectionIndent = RegExp(r'^(古诗[一二三四五六七八九十0-9]+首|文言文[一二三四五六七八九十0-9]+则)$')
              .hasMatch(title)
          ? entry.level
          : null;
      collectionLevel = level;
    } else if (RegExp(r'^(语文园地|口语交际|习作[：:]|综合性学习|回忆往事|依依惜别|快乐读书吧)')
        .hasMatch(title)) {
      categoryLevel = collectionIndent = null;
    } else if (categoryLevel != null) {
      level = categoryLevel + 1;
    } else if (collectionIndent != null && entry.level > collectionIndent) {
      level = collectionLevel + 1;
    } else {
      collectionIndent = null;
    }
    result.add(
      TextbookTocEntry(
        title: title,
        page: entry.page,
        printedPage: entry.printedPage,
        level: level,
        lessonNumber: entry.lessonNumber,
        isGroup: entry.isGroup,
      ),
    );
  }
  return result;
}

String _cleanTitle(String value) => value
    .replaceAll(_leaders, ' ')
    .replaceFirst(RegExp(r'^\s*[◎*＊★☆]?\s*(?:\d\s*)+[.、．\s]*'), '')
    .replaceFirst(RegExp(r'^\s*[◎*＊★☆]\s*'), '')
    .replaceAll(RegExp(r'(?<=[\u3400-\u9FFF])\s+(?=[\u3400-\u9FFF])'), '')
    .replaceAllMapped(RegExp(r'\s*([（）：，、])\s*'), (match) => match[1]!)
    .trim();

class _Run {
  _Run(this.text, this.left, this.right);
  String text;
  final double left;
  double right;
}

class _Row {
  _Row(this.top, this.height, this.runs);
  final double top;
  final double height;
  final List<_Run> runs;
  String get text => runs.map((run) => run.text).join(' ');
}

List<_Row> _rows(TextbookTocPage page) {
  final glyphs = page.glyphs
      .where((glyph) => glyph.text.trim().isNotEmpty && glyph.height > 0)
      .toList()
    ..sort((a, b) => (a.top + a.height / 2).compareTo(b.top + b.height / 2));
  if (glyphs.isEmpty) {
    final lines = page.text.split(RegExp(r'[\r\n]+'));
    return [
      for (var i = 0; i < lines.length; i++)
        _Row(i / math.max(1, lines.length), 0.02, [
          for (final match in RegExp(r'\S+').allMatches(
            lines[i].replaceAll(_leaders, '  '),
          ))
            _Run(
              match.group(0)!,
              _number.hasMatch(match.group(0)!) ? 0.95 : 0,
              _number.hasMatch(match.group(0)!) ? 1 : 0.5,
            ),
        ]),
    ];
  }
  // 用正文典型字号设置容差，避免“一”、句点的极薄墨迹把同一行拆开。
  final heights = glyphs
      .where(
        (glyph) => RegExp(r'[\u3400-\u9FFFA-Za-z0-9]').hasMatch(glyph.text),
      )
      .map((glyph) => glyph.height)
      .toList()
    ..sort();
  final lineHeight = heights.isEmpty ? 0.015 : heights[heights.length ~/ 2];
  final groups = <List<TextbookTocGlyph>>[];
  var rowCenter = 0.0;
  for (final glyph in glyphs) {
    // 巨大的斜排水印不应穿插到正常字号的目录行中。
    if (glyph.height > lineHeight * 3) continue;
    final center = glyph.top + glyph.height / 2;
    final group = groups.lastOrNull;
    if (group != null && (center - rowCenter).abs() <= lineHeight * 0.45) {
      rowCenter = (rowCenter * group.length + center) / (group.length + 1);
      group.add(glyph);
    } else {
      groups.add([glyph]);
      rowCenter = center;
    }
  }
  return groups.map((group) {
    group.sort((a, b) => a.left.compareTo(b.left));
    final runs = <_Run>[];
    for (final glyph in group) {
      final last = runs.lastOrNull;
      if (last == null || glyph.left - last.right > glyph.height * 1.8) {
        runs.add(_Run(glyph.text, glyph.left, glyph.right));
      } else {
        if (glyph.left - last.right > glyph.height * 0.18 &&
            !(RegExp(r'\d$').hasMatch(last.text) &&
                RegExp(r'^\d$').hasMatch(glyph.text))) {
          last.text += ' ';
        }
        last.text += glyph.text;
        last.right = math.max(last.right, glyph.right);
      }
    }
    return _Row(
      group.map((glyph) => glyph.top).reduce(math.min),
      group.map((glyph) => glyph.height).reduce(math.max),
      runs,
    );
  }).toList();
}

class _Candidate {
  _Candidate(
    this.title,
    this.printedPage,
    this.left,
    this.top,
    this.column, {
    this.lessonNumber,
  });
  final String title;
  final int? printedPage;
  final int? lessonNumber;
  bool get isGroup => _isGroup(title);
  final double left;
  final double top;
  double column;
  int level = 0;
}

List<_Candidate> _candidates(List<_Row> rows) {
  final result = <_Candidate>[];
  for (final row in rows) {
    final pending = <_Run>[];
    final parts = <_Run>[];
    for (final run in row.runs) {
      final text = run.text.replaceAll(_leaders, ' ');
      for (final part in RegExp(r'\S+').allMatches(text)) {
        parts.add(
          _Run(
            part.group(0)!,
            run.left + (run.right - run.left) * part.start / text.length,
            run.left + (run.right - run.left) * part.end / text.length,
          ),
        );
      }
    }
    for (final run in parts) {
      final value = run.text;
      if (_number.hasMatch(value) &&
          pending.any(
            (part) => RegExp(r'[\u3400-\u9FFFA-Za-zü]').hasMatch(part.text),
          )) {
        final raw = pending.map((part) => part.text).join(' ');
        final title = _cleanTitle(raw);
        final number = RegExp(r'^\s*[◎*＊★☆]?\s*((?:\d\s*)+)').firstMatch(raw);
        if (title.isNotEmpty && title.length <= 100 && int.parse(value) > 0) {
          result.add(
            _Candidate(
              title,
              int.parse(value),
              pending.first.left,
              row.top,
              run.right,
              lessonNumber: number == null
                  ? null
                  : int.tryParse(number[1]!.replaceAll(_spaces, '')),
            ),
          );
        }
        pending.clear();
      } else if (value.isNotEmpty) {
        pending.add(_Run(value, run.left, run.right));
      }
    }
    final heading = _cleanTitle(pending.map((part) => part.text).join(' '));
    if (pending.isNotEmpty && _isGroup(heading)) {
      result.add(
        _Candidate(
          heading,
          null,
          pending.first.left,
          row.top,
          pending.last.right,
        ),
      );
    }
  }
  return result;
}

List<_Candidate> _entries(List<_Row> rows) {
  var result = _candidates(rows);
  // 页码列重复出现形成可靠栏界；先切开各栏，再解释行内的课号/页码。
  // 否则左栏无页码的单元标题会吞入右栏同高的课号或诗歌标题。
  final endpoints = <double, int>{};
  for (final entry in result) {
    if (entry.printedPage == null) continue;
    final column = endpoints.keys
        .where((x) => (x - entry.column).abs() < 0.04)
        .firstOrNull;
    endpoints.update(
      column ?? entry.column,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final stable = endpoints.entries
      .where((column) => column.value >= 3)
      .map((column) => column.key)
      .toList()
    ..sort();
  if (stable.length >= 2) {
    final cuts = stable.take(stable.length - 1).map((x) => x + 0.03).toList();
    final separated = <_Row>[];
    for (final row in rows) {
      for (var column = 0; column <= cuts.length; column++) {
        final left = column == 0 ? double.negativeInfinity : cuts[column - 1];
        final right = column == cuts.length ? double.infinity : cuts[column];
        separated.add(
          _Row(
            row.top,
            row.height,
            row.runs
                .where((run) => run.left >= left && run.left < right)
                .toList(),
          ),
        );
      }
    }
    result = _candidates(separated);
  }
  // 按页码列分栏，然后各栏从上到下，避免把双栏同高条目串在一起。
  final columns = <double>[];
  for (final entry in [...result]
    ..removeWhere((entry) => entry.printedPage == null)
    ..sort((a, b) => a.column.compareTo(b.column))) {
    final column = columns
        .where((value) => (value - entry.column).abs() < 0.07)
        .firstOrNull;
    entry.column = column ?? entry.column;
    if (column == null) columns.add(entry.column);
  }
  for (final entry in result.where((entry) => entry.printedPage == null)) {
    entry.column = columns.firstWhere(
      (right) => right >= entry.left,
      orElse: () => entry.column,
    );
  }
  result.sort((a, b) {
    final column = a.column.compareTo(b.column);
    return column == 0 ? a.top.compareTo(b.top) : column;
  });
  for (final column in columns) {
    final group = result.where((entry) => entry.column == column).toList();
    final left = group.map((entry) => entry.left).reduce(math.min);
    for (final entry in group) {
      entry.level = ((entry.left - left) / 0.025).floor().clamp(0, 3);
    }
  }
  return result;
}

class _DirectoryPage {
  _DirectoryPage(this.page, this.heading, this.entries);
  final int page;
  final bool heading;
  final List<_Candidate> entries;
}

List<_DirectoryPage> _chooseDirectory(List<_DirectoryPage> pages) {
  final groups = <List<_DirectoryPage>>[];
  for (final page in pages) {
    if (groups.isEmpty || groups.last.last.page + 1 != page.page) {
      groups.add([page]);
    } else {
      groups.last.add(page);
    }
  }
  int score(List<_DirectoryPage> group) {
    final entries = group
        .expand((page) => page.entries)
        .where((entry) => entry.printedPage != null)
        .toList();
    if (entries.isEmpty) return 0;
    if (group.any((page) => page.heading)) return 10000 + entries.length;
    if (entries.length < 6 ||
        entries.map((entry) => entry.printedPage).toSet().length < 4) {
      return 0;
    }
    var increasing = 0;
    for (var i = 1; i < entries.length; i++) {
      if (entries[i].printedPage! >= entries[i - 1].printedPage!) increasing++;
    }
    return increasing / (entries.length - 1) >= 0.8 ? entries.length : 0;
  }

  groups.sort((a, b) => score(b).compareTo(score(a)));
  if (groups.isEmpty || score(groups.first) == 0) return [];
  final best = groups.first;
  final heading = best.indexWhere((page) => page.heading);
  return heading > 0 ? best.sublist(heading) : best;
}
