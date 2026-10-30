import 'dart:math' as math;

import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/textbook_text_display.dart';

/// 原书行分类、正文结构和注音证据的唯一处理流程，生成与阅读共用。
class TextbookReadingPipeline {
  String plainText(String value) => value.replaceAll(RegExp(r'[\s·•…*＊]'), '');
  String titleKey(String value) =>
      plainText(value).replaceFirst(RegExp(r'^\d+[.、]?'), '');

  Map<int, double> _pageMargins(List<TextbookSourceLine> rows) => {
        for (final page in rows.map((row) => row.page).toSet())
          page: () {
            final lefts = rows
                .where((row) => row.page == page)
                .map((row) => row.left)
                .toList()
              ..sort();
            return lefts[(lefts.length * .2).floor()];
          }(),
      };

  Map<TextbookSourceLine, double> _blockMargins(
    List<TextbookSourceLine> rows,
  ) {
    final pageMargins = _pageMargins(rows);
    final starts = _stanzaStarts(rows, verse: false);
    final blocks = <List<TextbookSourceLine>>[];
    for (final (index, row) in rows.indexed) {
      if (blocks.isEmpty ||
          row.page != blocks.last.last.page ||
          starts.contains(index)) {
        blocks.add([]);
      }
      blocks.last.add(row);
    }
    final margins = <TextbookSourceLine, double>{};
    for (final block in blocks) {
      // 插图会平移整个文字块。多行块使用自己的左边界；单行仍需
      // 同页正文提供依据，不能把真正的两格段首缩进当成块边距。
      final margin = block.length > 1
          ? _pageMargins(block)[block.first.page]!
          : pageMargins[block.first.page]!;
      for (final row in block) {
        margins[row] = margin;
      }
    }
    return margins;
  }

  bool _verseLines(List<TextbookSourceLine> rows) {
    if (rows.length < 2) return false;
    final clauseEnd = RegExp(r'[，。！？；：、…][”’」』）】》]*$');
    if (rows.any(
      (row) => !clauseEnd.hasMatch(row.text.trim()) || row.hasParagraphIndent,
    )) {
      return false;
    }
    final margins = _blockMargins(rows);
    return rows.every((row) => (row.left - margins[row]!).abs() < row.width);
  }

  Set<int> _stanzaStarts(List<TextbookSourceLine> rows, {required bool verse}) {
    final spacings = <int, double>{};
    for (final page in rows.map((row) => row.page).toSet()) {
      final intervals = <double>[
        for (var i = 1; i < rows.length; i++)
          if (rows[i].page == page &&
              rows[i - 1].page == page &&
              rows[i].top > rows[i - 1].top)
            rows[i].top - rows[i - 1].top,
      ]..sort();
      if (intervals.isNotEmpty) {
        spacings[page] = intervals[intervals.length ~/ 2];
      }
    }
    final starts = <int>{
      for (var i = 1; i < rows.length; i++)
        if (rows[i].page == rows[i - 1].page &&
            rows[i].top - rows[i - 1].top >
                (spacings[rows[i].page] ?? double.infinity) * 1.35)
          i,
    };
    if (!verse) return starts;
    // 跨页不天然等于分节。仅在两侧可见节长一致、且原页有重复节长证据时延续分节。
    final lengths = <int>[];
    for (final page in rows.map((row) => row.page).toSet()) {
      final pageStart = rows.indexWhere((row) => row.page == page);
      var prior = pageStart;
      for (final index
          in starts.where((index) => rows[index].page == page).toList()
            ..sort()) {
        lengths.add(index - prior);
        prior = index;
      }
    }
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].page == rows[i - 1].page) continue;
      final before = starts.where((index) => index < i).toList()..sort();
      final after = starts
          .where((index) => index > i && rows[index].page == rows[i].page)
          .toList()
        ..sort();
      if (before.isEmpty || after.isEmpty) continue;
      final length = i - before.last;
      if (after.first - i == length &&
          lengths.where((value) => value == length).length >= 2) {
        starts.add(i);
      }
    }
    return starts;
  }

  /// 从原页恢复旧课程丢失的诗行和节间距；匹配失败时不把原书其他文字套到编辑稿上。
  TextbookReadingLayout readingLayout(
    TextbookCourseParagraph paragraph,
    List<TextbookPageText> pages, {
    bool preserveLines = false,
    List<TextbookCourseParagraph> paragraphs = const [],
  }) {
    final fallback = textbookReadingLayoutForText(
      paragraph.text,
      preserveLines: preserveLines,
    );
    final orderedPages = pages.toList()
      ..sort((a, b) => a.page.compareTo(b.page));
    final source = [for (final page in orderedPages) ...lines(page)];
    String normalized(String text) => text.replaceAll(RegExp(r'\s|\u3000'), '');
    final savedLines = <({String text, int rawIndex})>[];
    var rawIndex = 0;
    for (final line in paragraph.text.split('\n')) {
      final runes = line.runes.toList();
      final first = runes
          .indexWhere((rune) => String.fromCharCode(rune).trim().isNotEmpty);
      if (first >= 0) {
        savedLines.add((text: normalized(line), rawIndex: rawIndex + first));
      }
      rawIndex += runes.length + 1;
    }
    final matched = <TextbookSourceLine>[];
    var cursor = 0;
    var previous = -1;
    for (final line in savedLines) {
      while (cursor < source.length &&
          normalized(source[cursor].text) != line.text) {
        cursor++;
      }
      if (cursor == source.length) return fallback;
      if (previous >= 0 &&
          source[previous].page == source[cursor].page &&
          source.sublist(previous + 1, cursor).any(
                (row) =>
                    hasHan(row.text) &&
                    row.height >= source[cursor].height * .72,
              )) {
        return fallback;
      }
      previous = cursor;
      matched.add(source[cursor++]);
    }
    final verse = _verseLines(matched);
    var leadingIndentCells = 0;
    if (!verse && matched.isNotEmpty) {
      final firstLine = paragraph.text
          .split('\n')
          .firstWhere((line) => line.trim().isNotEmpty);
      if (firstLine == firstLine.trimLeft()) {
        final first = matched.first;
        final savedBodyLines = {
          for (final paragraph in paragraphs)
            for (final line in paragraph.text.split('\n')) normalized(line),
        };
        final body = source
            .where(
              (row) =>
                  row.page == first.page &&
                  row.height >= first.height * .72 &&
                  row.height <= first.height * 1.4 &&
                  savedBodyLines.contains(normalized(row.text)),
            )
            .toList();
        final margin = _blockMargins(body)[first];
        if (first.hasParagraphIndent ||
            margin != null && first.left - margin > first.width * 1.5) {
          leadingIndentCells = 2;
        }
      }
    }
    if (!preserveLines && !verse) {
      return TextbookReadingLayout(
        breaks: fallback.breaks,
        leadingIndentCells: leadingIndentCells,
      );
    }
    final stanzas = _stanzaStarts(matched, verse: true);
    return TextbookReadingLayout(
      retainLeadingIndent: !verse,
      leadingIndentCells: leadingIndentCells,
      breaks: Map.unmodifiable({
        ...fallback.breaks,
        for (var i = 1; i < savedLines.length; i++)
          savedLines[i].rawIndex: stanzas.contains(i) ||
                  fallback.breaks[savedLines[i].rawIndex] ==
                      TextbookReadingBreak.stanza
              ? TextbookReadingBreak.stanza
              : TextbookReadingBreak.line,
      }),
    );
  }

  bool hasHan(String text) => text.runes
      .any((r) => (r >= 0x3400 && r <= 0x9fff) || r >= 0x20000 && r <= 0x323af);

  TextbookReadingAnalysis analyze(
    TextbookCourseLesson skeleton,
    TextbookDraftPlan plan,
    List<TextbookPageText> pages, {
    List<TextbookDraftCandidate> vocabulary = const [],
  }) {
    final candidates = <TextbookDraftCandidate>[];
    // 同课识字表可能跨行或跨页，课内生字条仍按完整顺序匹配。
    final recognitionText = vocabulary
        .where((candidate) => candidate.category == 'recognitionCharacters')
        .map((candidate) => candidate.text)
        .join();
    final body = <TextbookSourceLine>[];
    final instructions = <TextbookSourceLine>[];
    var anchored = false;
    var afterBody = skeleton.kind != 'text' &&
        skeleton.kind != 'literacy' &&
        skeleton.kind != 'poetry' &&
        skeleton.kind != 'reading';
    var ended = false;
    for (final page in pages) {
      final rows = lines(page);
      if (page.status != 'text_extracted' || rows.isEmpty) {
        candidates.add(
          TextbookDraftCandidate(
            id: '${plan.id}-page-${page.page}',
            text: page.text.trim().isEmpty
                ? 'PDF 第${page.page}页没有可读取的文字'
                : page.text,
            reason: '文字层异常，请核对原页；未采用此页作为正文',
            pages: [page.page],
          ),
        );
        continue;
      }
      final titleAt =
          rows.indexWhere((r) => matchesHeading(r.text, plan.title));
      if (!anchored && titleAt >= 0) anchored = true;
      if (!anchored) {
        candidates.add(
          TextbookDraftCandidate(
            id: '${plan.id}-anchor-${page.page}',
            text: rows.map((r) => r.text).join('\n'),
            reason: '尚未匹配正文标题，请确认课文起点',
            pages: [page.page],
          ),
        );
        continue;
      }
      final sizes = rows
          .where(
            (r) =>
                hasHan(r.text) &&
                !matchesHeading(r.text, plan.title) &&
                r.glyphs.length >= 3,
          )
          .map((r) => r.height)
          .toList()
        ..sort();
      final normal = sizes.isEmpty ? .025 : sizes[sizes.length ~/ 2];
      final hanWidths = rows
          .where((row) => !matchesHeading(row.text, plan.title))
          .expand((row) => row.glyphs)
          .where((glyph) => hasHan(glyph.text))
          .map((glyph) => glyph.width)
          .toList()
        ..sort();
      final normalWidth =
          hanWidths.isEmpty ? 0.0 : hanWidths[hanWidths.length ~/ 2];
      for (var i = titleAt >= 0 ? titleAt + 1 : 0; i < rows.length; i++) {
        final row = rows[i];
        if (plan.nextTitle != null &&
            matchesHeading(row.text, plan.nextTitle!)) {
          ended = true;
          break;
        }
        if (row.top > .95 || RegExp(r'^\s*\d+\s*$').hasMatch(row.text)) {
          continue;
        }
        if (!hasHan(row.text)) {
          if (!hasHan(skeleton.title) && row.text.trim().isNotEmpty) {
            candidates.add(_candidate(plan, row, '拼音课原文，需核对音节和内容归属'));
          }
          continue;
        }
        final text = row.text.trim();
        final han = text.runes.map(String.fromCharCode).where(hasHan).toList();
        final strip = han.join();
        final recognitionStrip = body.isNotEmpty &&
            han.length >= 4 &&
            !RegExp(r'[，。！？：；]').hasMatch(text) &&
            recognitionText.contains(strip);
        final writingGrid = (body.isNotEmpty || afterBody) &&
            han.length >= 2 &&
            han.length.isEven &&
            !RegExp(r'[，。！？：；]').hasMatch(text) &&
            [for (var j = 0; j < han.length; j += 2) j].every(
              (j) =>
                  han[j] == han[j + 1] &&
                  vocabulary.any(
                    (v) =>
                        v.category == 'writingCharacters' &&
                        v.text.contains(han[j]),
                  ),
            );
        if (recognitionStrip || writingGrid) {
          afterBody = true;
          continue;
        }
        if (RegExp(r'^[①②③④⑤⑥⑦⑧⑨]').hasMatch(text)) {
          candidates.add(_candidate(plan, row, '原书脚注，未并入正文'));
          continue;
        }
        if (RegExp(
          r'^(朗读|默读|背诵|读一读|读读|说一说|想一想|写一写|小练笔|选做|思考|练习|和同学|读课文|分角色|照样子|猜一猜|有感情地朗读)',
        ).hasMatch(text)) {
          afterBody = true;
        }
        if (afterBody) {
          instructions.add(row);
          continue;
        }
        final widths = row.glyphs
            .where((glyph) => hasHan(glyph.text))
            .map((glyph) => glyph.width)
            .toList()
          ..sort();
        final heights = row.glyphs
            .where((glyph) => hasHan(glyph.text))
            .map((glyph) => glyph.height)
            .toList()
          ..sort();
        // 图注行的外框可能被邻列拼音撑大，按汉字本身的宽高核对字号。
        final smallGlyphs = widths.isNotEmpty &&
            widths[widths.length ~/ 2] < normalWidth * .8 &&
            heights[heights.length ~/ 2] < normal * .72;
        if (row.height < normal * .72 ||
            row.height > normal * 1.5 ||
            smallGlyphs ||
            text.replaceAll(RegExp(r'[^\u3400-\u9fff]'), '').length < 2 ||
            matchesHeading(text, plan.title)) {
          candidates.add(_candidate(plan, row, '字号或文字块用途尚待核对'));
          continue;
        }
        body.add(row);
      }
      if (ended) break;
    }
    return TextbookReadingAnalysis(
      paragraphs: _paragraphs(body, poetry: skeleton.kind == 'poetry'),
      instructions: instructions,
      candidates: candidates,
      hasTitle: anchored,
    );
  }

  List<TextbookSourceParagraph> _paragraphs(
    List<TextbookSourceLine> body, {
    required bool poetry,
  }) {
    final groups = <List<TextbookSourceLine>>[];
    if (body.isEmpty) return const [];
    final margins = _blockMargins(body);
    final stanzas = _stanzaStarts(
      body,
      verse: poetry || _verseLines(body),
    );
    for (final (index, row) in body.indexed) {
      final prior = groups.isEmpty ? null : groups.last.last;
      final margin = margins[row]!;
      final width = row.glyphs.map((g) => g.width).reduce((a, b) => a + b) /
          row.glyphs.length;
      // 原书段首缩进可能只存在于几何坐标，按相对本块正文左边界的
      // 外扩量识别首行缩进；整块为插图让位不应逐行开启新段落。
      final geometricIndent = row.left - margin > width * 1.5;
      final newParagraph = prior == null ||
          row.hasParagraphIndent ||
          geometricIndent ||
          (row.left - margin > width * 2.5 &&
              row.left - prior.left > width * 1.5 &&
              RegExp(r'[。！？…][”」』）]?$').hasMatch(prior.text.trim())) ||
          stanzas.contains(index);
      if (newParagraph) groups.add([]);
      groups.last.add(row);
    }

    return [
      for (final group in groups)
        TextbookSourceParagraph(
          group,
          leadingIndent: group.first.left - margins[group.first]! >
              group.first.width * 1.5,
        ),
    ];
  }

  TextbookDraftCandidate _candidate(
    TextbookDraftPlan plan,
    TextbookSourceLine row,
    String reason,
  ) =>
      TextbookDraftCandidate(
        id: '${plan.id}-c-${row.page}-${row.glyphs.first.index}',
        text: row.text,
        reason: reason,
        pages: [row.page],
      );
  bool matchesHeading(String text, String title) {
    final expected = titleKey(title);
    final actual = titleKey(text);
    return expected.isNotEmpty &&
        (actual == expected ||
            actual.startsWith(expected) &&
                actual.length <= expected.length + 2);
  }

  String? pinyinFor(
    TextbookPageGlyph han,
    TextbookSourceLine line,
    List<TextbookPageText> pages,
  ) {
    final page = pages.firstWhere((p) => p.page == line.page);
    bool above(TextbookPageGlyph glyph) =>
        glyph.bottom <= han.top + han.height * .2 &&
        han.top - glyph.bottom < han.height &&
        glyph.height < han.height * .85;
    // 文字层有时逐字保存“汉字\n拼音”；长音节会超出汉字外框，
    // 优先用原始码点归属，并以整组坐标验证，避免截断或偷取邻字字母。
    final following = String.fromCharCodes(line.original.skip(han.index + 1));
    final match = RegExp(
      r'^([ \t]*\r?\n[ \t]*)([a-zA-Züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜêńňǹḿ\u0300-\u036f]+[1-5]?)[ \t]*(?:\r?\n|$)',
    ).firstMatch(following);
    if (match != null) {
      final hint = match[2]!;
      final start = han.index + 1 + match[1]!.runes.length;
      final end = start + hint.runes.length;
      final positioned = page.glyphs
          .where((glyph) => glyph.index >= start && glyph.index < end)
          .toList();
      if (positioned.length == hint.runes.length && positioned.every(above)) {
        final left = positioned.map((glyph) => glyph.left).reduce(math.min);
        final right = positioned.map((glyph) => glyph.right).reduce(math.max);
        final center = (left + right) / 2;
        if (center >= han.left - han.width * .25 &&
            center <= han.right + han.width * .25) {
          return hint;
        }
      }
    }
    final nearby = page.glyphs
        .where(
          (g) =>
              above(g) &&
              g.centerX >= han.left - han.width * .25 &&
              g.centerX <= han.right + han.width * .25 &&
              RegExp(r'[a-zA-Züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜêńňǹḿ\u0300-\u036f1-5]')
                  .hasMatch(g.text),
        )
        .toList()
      ..sort((a, b) => a.left.compareTo(b.left));
    return nearby.isEmpty ? null : nearby.map((g) => g.text).join();
  }

  List<TextbookSourceLine> lines(TextbookPageText page, {bool table = false}) {
    final original = page.text.runes.toList();
    final glyphs = page.glyphs
        .where(
          (g) =>
              g.text.trim().isNotEmpty &&
              g.height > 0 &&
              g.centerX >= 0 &&
              g.centerX <= 1 &&
              (g.top + g.bottom) / 2 >= 0 &&
              (g.top + g.bottom) / 2 <= 1,
        )
        .toList()
      ..sort(
        (a, b) => ((a.top + a.bottom) / 2).compareTo((b.top + b.bottom) / 2),
      );
    final hanHeights = glyphs
        .where((g) => hasHan(g.text))
        .map((g) => g.height)
        .toList()
      ..sort();
    final typicalHeight =
        hanHeights.isEmpty ? .02 : hanHeights[hanHeights.length ~/ 2];
    final hanWidths = glyphs
        .where((g) => hasHan(g.text))
        .map((g) => g.width)
        .toList()
      ..sort();
    final typicalWidth =
        hanWidths.isEmpty ? typicalHeight : hanWidths[hanWidths.length ~/ 2];
    final punctuation = RegExp(r'^[\p{P}\p{S}]$', unicode: true);
    final rows = <TextbookSourceLine>[];
    // Punctuation ink boxes are much shorter than Han characters. Attach them
    // after constructing the text baselines, rather than losing them as rows.
    for (final glyph in glyphs.where((g) => !punctuation.hasMatch(g.text))) {
      final center = (glyph.top + glyph.bottom) / 2;
      final row = rows
          .where(
            (r) =>
                !(glyph.height > typicalHeight * 1.8 &&
                        r.height < typicalHeight * 1.4 ||
                    r.height > typicalHeight * 1.8 &&
                        glyph.height < typicalHeight * 1.4) &&
                (r.center - center).abs() <
                    (hasHan(glyph.text) && r.glyphs.any((g) => hasHan(g.text))
                        ? math.max(
                              math.min(r.height, glyph.height),
                              typicalHeight * .85,
                            ) *
                            .55
                        : math.min(r.height, glyph.height) * .55),
          )
          .lastOrNull;
      if (row == null) {
        rows.add(TextbookSourceLine(page.page, [glyph], original));
      } else {
        row.glyphs.add(glyph);
      }
    }
    for (final glyph in glyphs.where((g) => punctuation.hasMatch(g.text))) {
      final center = (glyph.top + glyph.bottom) / 2;
      final matches = rows
          .where(
            (r) =>
                glyph.right >= r.left - typicalWidth * 1.5 &&
                glyph.left <= r.right + typicalWidth * 1.5 &&
                (r.center - center).abs() <=
                    math.max(r.height, glyph.height) * .9,
          )
          .toList()
        ..sort((a, b) {
          final aHan = a.glyphs.any((g) => hasHan(g.text));
          final bHan = b.glyphs.any((g) => hasHan(g.text));
          if (aHan != bHan) return aHan ? -1 : 1;
          return (a.center - center).abs().compareTo((b.center - center).abs());
        });
      if (matches.isEmpty) {
        rows.add(TextbookSourceLine(page.page, [glyph], original));
      } else {
        matches.first.glyphs.add(glyph);
      }
    }
    for (final row in rows) {
      row.glyphs.sort((a, b) => a.left.compareTo(b.left));
    }
    rows.sort((a, b) => a.top.compareTo(b.top));
    // 课文和习题保持从上到下的阅读顺序；双栏重排只适用于册末字词表。
    if (!table) return rows;
    // A repeated gutter, rather than a fixed half-page split, supplies column
    // evidence. This also keeps each numbered appendix row in its own column.
    final gutters = <({double left, double right, TextbookSourceLine row})>[];
    for (final row in rows) {
      if (!row.glyphs.any((g) => hasHan(g.text))) continue;
      for (var i = 1; i < row.glyphs.length - 1; i++) {
        final left = row.glyphs[i - 1].right;
        final right = row.glyphs[i].left;
        if (i >= 2 && right - left > typicalHeight * 3) {
          gutters.add((left: left, right: right, row: row));
        }
      }
    }
    if (gutters.length < 2) return rows;
    final centers = gutters.map((g) => (g.left + g.right) / 2).toList()..sort();
    final cut = centers[centers.length ~/ 2];
    final evidence =
        gutters.where((g) => g.left < cut && g.right > cut).toList();
    if (evidence.length < 2) return rows;
    final firstTop = evidence.map((g) => g.row.top).reduce(math.min);
    final headers = <TextbookSourceLine>[],
        left = <TextbookSourceLine>[],
        right = <TextbookSourceLine>[],
        footer = <TextbookSourceLine>[];
    for (final row in rows) {
      if (table &&
          row.top < firstTop &&
          RegExp(r'^(识字表|写字表|词语表)[①②]?$').hasMatch(plainText(row.text))) {
        headers.add(row);
        continue;
      }
      final split = evidence.any((g) => identical(g.row, row));
      final a = row.glyphs.where((g) => g.centerX < cut).toList();
      final b = row.glyphs.where((g) => g.centerX >= cut).toList();
      if (split || (table && row.top >= firstTop) || a.isEmpty || b.isEmpty) {
        if (a.isNotEmpty) left.add(TextbookSourceLine(page.page, a, original));
        if (b.isNotEmpty) right.add(TextbookSourceLine(page.page, b, original));
      } else if (row.top < firstTop) {
        headers.add(row);
      } else {
        footer.add(row);
      }
    }
    return [...headers, ...left, ...right, ...footer];
  }
}

class TextbookReadingAnalysis {
  const TextbookReadingAnalysis({
    required this.paragraphs,
    required this.instructions,
    required this.candidates,
    required this.hasTitle,
  });
  final List<TextbookSourceParagraph> paragraphs;
  final List<TextbookSourceLine> instructions;
  final List<TextbookDraftCandidate> candidates;
  final bool hasTitle;
}

class TextbookSourceParagraph {
  const TextbookSourceParagraph(this.lines, {required this.leadingIndent});
  final List<TextbookSourceLine> lines;
  final bool leadingIndent;
}

class TextbookSourceLine {
  TextbookSourceLine(this.page, this.glyphs, this.original);
  final int page;
  final List<TextbookPageGlyph> glyphs;
  final List<int> original;
  bool get hasParagraphIndent {
    final at = glyphs.first.index;
    return RegExp(r'(?:^|[\r\n])[ \t\u2003]{2,}$').hasMatch(
      String.fromCharCodes(original.sublist(math.max(0, at - 12), at)),
    );
  }

  double get top => glyphs.map((g) => g.top).reduce(math.min);
  double get bottom => glyphs.map((g) => g.bottom).reduce(math.max);
  double get center => (top + bottom) / 2;
  double get height => bottom - top;
  double get left => glyphs.map((g) => g.left).reduce(math.min);
  double get right => glyphs.map((g) => g.right).reduce(math.max);
  double get width =>
      glyphs.map((g) => g.width).reduce((a, b) => a + b) / glyphs.length;
  String get text {
    final out = StringBuffer();
    TextbookPageGlyph? prior;
    for (final g in glyphs) {
      final explicitSpace = prior != null &&
          g.index > prior.index + 1 &&
          RegExp(r'^[ \t\u2000-\u200a]+$').hasMatch(
            String.fromCharCodes(original.sublist(prior.index + 1, g.index)),
          );
      if (prior != null &&
          (explicitSpace ||
              g.left - prior.right > math.max(g.width, prior.width) * 1.8)) {
        out.write(' ');
      }
      out.write(g.text);
      prior = g;
    }
    return out.toString();
  }
}
