import 'dart:math' as math;

import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/math_textbook_editing.dart';
import 'package:poemath/domain/textbook_printed_page.dart';

/// 数学专用二维版面整理。输入完整页；选区仅由页面证据产生。
class MathTextbookDraftParser {
  const MathTextbookDraftParser({this.legacyLayout = false});

  /// Only used to reproduce an earlier automatic draft before replacing it.
  final bool legacyLayout;

  MathTextbookLesson parse({
    required String title,
    required int startPage,
    required int endPage,
    required List<MathTextbookPageLayout> pages,
    bool classifyContent = true,
  }) {
    if (startPage < 1 ||
        endPage < startPage ||
        endPage - startPage >= 40 ||
        pages.length != endPage - startPage + 1 ||
        pages.map((p) => p.text.page).toSet().length != pages.length) {
      throw const FormatException('课时页范围无效或页面不完整');
    }
    final byNumber = {for (final page in pages) page.text.page: page};
    final lessonId = 'math-$startPage-$endPage';
    final blocks = <MathTextbookBlock>[];
    for (var number = startPage; number <= endPage; number++) {
      final page = byNumber[number];
      if (page == null) throw const FormatException('课时页面缺失');
      final pageBlocks = _parsePage(page, lessonId, classifyContent);
      // 只有原书明确写出续页关系才自动合并；其他跨页关系由家长指定。
      if (blocks.isNotEmpty &&
          pageBlocks.isNotEmpty &&
          RegExp(r'^[（(]?(?:接上页|续上页)[）)]?').hasMatch(pageBlocks.first.text)) {
        final previousIndex = blocks.lastIndexWhere(
          (b) => b.kind != MathTextbookBlockKind.sourcePage,
        );
        if (previousIndex >= 0) {
          final previous = blocks[previousIndex];
          final next = pageBlocks.removeAt(0);
          blocks[previousIndex] = _join(previous, next);
        }
      }
      blocks.addAll(pageBlocks);
    }
    return MathTextbookLesson.fromJson(
      MathTextbookLesson(
        id: lessonId,
        title: title.trim(),
        startPage: startPage,
        endPage: endPage,
        blocks: blocks,
      ).toJson(),
    );
  }

  List<MathTextbookBlock> _parsePage(
    MathTextbookPageLayout page,
    String lessonId,
    bool classifyContent,
  ) {
    final number = page.text.page;
    final prefix = '$lessonId-p$number';
    final restoreLayout = classifyContent && !legacyLayout;
    final complex =
        page.text.glyphs.length > 6000 ||
        page.graphics.lines.length > 2000 ||
        page.graphics.regions.length > 4000;
    if (complex || restoreLayout && !page.graphics.complete) {
      return [
        MathTextbookBlock(
          id: '$prefix-source',
          kind: MathTextbookBlockKind.sourcePage,
          spans: const [],
          sources: [
            MathTextbookRegion(
              page: number,
              left: 0,
              top: 0,
              right: 1,
              bottom: 1,
            ),
          ],
          warnings: [
            if (complex) '本页版面较复杂，已保留整页，请对照补齐',
            if (restoreLayout && !page.graphics.complete) '本页绘图证据未完整读取，已保留整页',
          ],
        ),
      ];
    }
    var glyphs = page.text.glyphs
        .where(
          (g) =>
              g.text.trim().isNotEmpty &&
              g.width > 0 &&
              g.height > 0 &&
              g.centerX >= 0 &&
              g.centerX <= 1 &&
              (g.top + g.bottom) / 2 >= 0 &&
              (g.top + g.bottom) / 2 <= 1,
        )
        .toList();
    if (restoreLayout) glyphs = _deduplicateOverlappingGlyphs(glyphs);
    final consumed = <int>{};
    final tokens = <_Token>[];
    final blocks = <MathTextbookBlock>[];
    var serial = 0;
    String id() => '$prefix-${serial++}';
    final bodyHeight = _median(
      glyphs
          .where((g) => RegExp(r'[\u3400-\u9fff]').hasMatch(g.text))
          .map((g) => g.height),
    );

    // Reserve the complete vertical work before looking for fractions. A carry
    // above a partly written result must not become its numerator.
    if (restoreLayout) {
      _verticalArithmetic(page, glyphs, consumed, blocks, id);
    }

    // 分数线是独立绘图证据；拒绝把竖式的宽列间距误当连续数字。
    for (final line in page.graphics.lines.where((l) => l.dark)) {
      final around = glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                _digit(g.text) &&
                g.centerX >= line.left &&
                g.centerX <= line.right &&
                (_cy(g) - line.y).abs() < g.height * 1.6,
          )
          .toList();
      final above = around
          .where((g) => _cy(g) < line.y - g.height * 0.15)
          .toList();
      final below = around
          .where((g) => _cy(g) > line.y + g.height * 0.15)
          .toList();
      final height = _median(around.map((g) => g.height));
      // Ink bounds of a narrow "1" leave a larger gap than its advance width.
      // The bar and font height still constrain a contiguous fraction row.
      final digitGap = restoreLayout
          ? height / (page.text.width / page.text.height) * .55
          : null;
      if (!_numericRow(above, maxGap: digitGap) ||
          !_numericRow(below, maxGap: digitGap)) {
        continue;
      }
      if (restoreLayout) {
        final numeratorRegion = _bounds(number, above);
        final denominatorRegion = _bounds(number, below);
        final centered =
            (numeratorRegion.centerX - denominatorRegion.centerX).abs() <=
            math.max(
              (line.right - line.left) * .12,
              height / (page.text.width / page.text.height) * .25,
            );
        if (!centered ||
            _divisionBracket(page, line, below, glyphs, consumed)) {
          continue;
        }
      }
      final hasOperator = glyphs.any(
        (g) =>
            !consumed.contains(g.index) &&
            const ['+', '−', '-', '×', '÷'].contains(g.text) &&
            g.centerX >= line.left &&
            g.centerX <= line.right &&
            (_cy(g) - line.y).abs() <
                (restoreLayout ? math.max(height, g.height) : g.height) * 1.6,
      );
      if (hasOperator) continue;
      above.sort((a, b) => a.left.compareTo(b.left));
      below.sort((a, b) => a.left.compareTo(b.left));
      final numerator = above.map((g) => g.text).join();
      final denominator = below.map((g) => g.text).join();
      if (denominator.length > 12 ||
          numerator.length > 12 ||
          int.tryParse(denominator) == 0) {
        continue;
      }
      final selected = [...above, ...below];
      final token = _Token.math(
        MathTextbookFraction(numerator, denominator),
        _bounds(number, selected),
        line.y,
        _median(selected.map((g) => g.height)),
        selected.map((g) => g.index).toSet(),
      );
      tokens.add(token);
      consumed.addAll(token.indices);
    }

    for (final exponent in glyphs.where(
      (g) => (g.text == '2' || g.text == '3') && !consumed.contains(g.index),
    )) {
      if (consumed.contains(exponent.index)) continue;
      final letters =
          glyphs
              .where(
                (g) =>
                    !consumed.contains(g.index) &&
                    RegExp(r'^[a-zA-Z]$').hasMatch(g.text) &&
                    g.centerX < exponent.centerX &&
                    (restoreLayout || exponent.left - g.right < g.height * 2) &&
                    exponent.height < g.height * (restoreLayout ? .9 : .85) &&
                    _cy(g) - _cy(exponent) > g.height * 0.30 &&
                    _cy(g) - _cy(exponent) < g.height,
              )
              .toList()
            ..sort((a, b) => b.right.compareTo(a.right));
      if (letters.isEmpty) continue;
      if (restoreLayout &&
          exponent.left - letters.first.right >= letters.first.height * 2) {
        continue;
      }
      final base = <TextbookPageGlyph>[letters.first];
      for (final letter in letters.skip(1)) {
        if (base.last.left - letter.right > letter.height * 0.5 ||
            (_cy(letter) - _cy(base.first)).abs() > letter.height * 0.25) {
          break;
        }
        base.add(letter);
      }
      base.sort((a, b) => a.left.compareTo(b.left));
      if (base.length > 8) continue;
      final selected = [...base, exponent];
      final token = _Token.math(
        MathTextbookPower(
          base.map((g) => g.text).join(),
          int.parse(exponent.text),
        ),
        _bounds(number, selected),
        _cy(base.first),
        _median(base.map((g) => g.height)),
        selected.map((g) => g.index).toSet(),
      );
      tokens.add(token);
      consumed.addAll(token.indices);
    }

    if (!restoreLayout) {
      _legacyVerticalAdditions(page, glyphs, consumed, blocks, id);
    }

    // 不完整或暂不支持的竖式按整个列式保留，不能把每一列拆成独立图片。
    for (final line in page.graphics.lines.where(
      (l) => l.dark && l.right - l.left < .35,
    )) {
      final operator = glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                const ['+', '−', '-', '×', '÷'].contains(g.text) &&
                g.centerX >= line.left &&
                g.centerX <= line.right &&
                _cy(g) < line.y &&
                line.y - _cy(g) < g.height * 2.8,
          )
          .firstOrNull;
      if (operator == null) continue;
      final members = glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                g.centerX >= line.left - .004 &&
                g.centerX <= line.right + .004 &&
                _cy(g) > line.y - operator.height * 5 &&
                _cy(g) < line.y + operator.height * 3,
          )
          .toList();
      if (members.where((g) => _digit(g.text)).length < 2 ||
          members.any((g) => RegExp(r'[\u3400-\u9fff]').hasMatch(g.text))) {
        continue;
      }
      blocks.add(
        MathTextbookBlock(
          id: id(),
          kind: MathTextbookBlockKind.illustration,
          spans: const [],
          sources: [_pad(_bounds(number, members))],
          warnings: const ['竖式尚未完整恢复，请按原书核对列位和横线'],
        ),
      );
      consumed.addAll(members.map((g) => g.index));
    }

    // 有上下排布却未能恢复的内容仍按二维原书展示，不能拼成一个整数。
    for (final line in page.graphics.lines.where(
      (l) => l.dark && l.right - l.left < 0.25,
    )) {
      final around = glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                g.centerX >= line.left - 0.005 &&
                g.centerX <= line.right + 0.005 &&
                (_cy(g) - line.y).abs() < g.height * 2,
          )
          .toList();
      if (!around.any((g) => _cy(g) < line.y) ||
          !around.any((g) => _cy(g) > line.y)) {
        continue;
      }
      if (around.any((g) => RegExp(r'[\u3400-\u9fff]').hasMatch(g.text))) {
        continue;
      }
      final region = _bounds(number, around);
      blocks.add(
        MathTextbookBlock(
          id: id(),
          kind: MathTextbookBlockKind.illustration,
          spans: const [],
          sources: [_pad(region)],
          warnings: const ['上下排列或竖式结构待核对，请保留原书写法'],
        ),
      );
      consumed.addAll(around.map((g) => g.index));
    }

    // 无可用分数线的数字列也不能作为普通行拼接。
    for (final glyph in glyphs.where((g) => _digit(g.text))) {
      if (consumed.contains(glyph.index)) continue;
      final ownRow = _rowNeighbors(glyph, glyphs, consumed);
      if (ownRow.any((g) => !_digit(g.text))) continue;
      final stacked = glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                _digit(g.text) &&
                (g.centerX - glyph.centerX).abs() <
                    math.max(g.width, glyph.width) * 0.35 &&
                (_cy(g) - _cy(glyph)).abs() <
                    math.max(g.height, glyph.height) * 3.5,
          )
          .toList();
      if (!stacked.any(
        (g) => (_cy(g) - _cy(glyph)).abs() > glyph.height * 0.7,
      )) {
        continue;
      }
      final rows = stacked
          .map((g) => _rowNeighbors(g, glyphs, consumed))
          .where((row) => row.every((g) => _digit(g.text)))
          .toList();
      final completeRows = {
        for (final row in rows)
          for (final g in row) g.index: g,
      }.values.toList();
      if (!completeRows.any(
        (g) => (_cy(g) - _cy(glyph)).abs() > glyph.height * .7,
      )) {
        continue;
      }
      final region = _pad(_bounds(number, completeRows));
      final members = glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                region.containsCenter(_glyphRegion(number, g)),
          )
          .toList();
      blocks.add(
        MathTextbookBlock(
          id: id(),
          kind: MathTextbookBlockKind.illustration,
          spans: const [],
          sources: [region],
          warnings: const ['数字列的关系尚未确定，请对照原书核对'],
        ),
      );
      consumed.addAll(members.map((g) => g.index));
    }

    tokens.addAll(
      glyphs
          .where((g) => !consumed.contains(g.index))
          .map(
            (g) => _Token.text(
              g.text,
              _glyphRegion(number, g),
              _cy(g),
              g.height,
              {g.index},
            ),
          ),
    );
    final rows = <List<_Token>>[];
    // 用正常高度的字先建立行，再归入引号、标点和“一”等短字形。
    tokens.sort((a, b) {
      final height = b.height.compareTo(a.height);
      return height != 0 ? height : a.baseline.compareTo(b.baseline);
    });
    for (final token in tokens) {
      final candidates = rows
          .where(
            (row) =>
                (row.first.baseline - token.baseline).abs() <
                math.max(row.first.height, token.height) * 0.6,
          )
          .toList();
      if (candidates.isEmpty) {
        rows.add([token]);
      } else {
        candidates.sort(
          (a, b) => (a.first.baseline - token.baseline).abs().compareTo(
            (b.first.baseline - token.baseline).abs(),
          ),
        );
        candidates.first.add(token);
      }
    }
    rows.sort((a, b) => a.first.baseline.compareTo(b.first.baseline));
    for (final row in rows) {
      row.sort((a, b) => a.region.left.compareTo(b.region.left));
      final segments = <List<_Token>>[];
      for (final token in row) {
        if (segments.isEmpty ||
            token.region.left - segments.last.last.region.right >
                math.max(token.height * 1.8, 0.028)) {
          segments.add([token]);
        } else {
          segments.last.add(token);
        }
      }
      for (final segment in segments) {
        final combined = _mixedNumbers(segment);
        final lineHeight = segment.map((t) => t.height).reduce(math.max);
        var spans = <MathTextbookSpan>[];
        _Token? previous;
        for (final token in combined) {
          final sourceAdjacent =
              previous != null &&
              previous.indices.length == 1 &&
              token.indices.length == 1 &&
              token.indices.single == previous.indices.single + 1;
          final separated =
              previous != null &&
              !sourceAdjacent &&
              token.region.left - previous.region.right > lineHeight * 0.65;
          if (separated) _appendText(spans, ' ');
          if (token.expression != null) {
            spans.add(MathTextbookSpan.math(token.expression!));
          } else {
            _appendText(spans, token.text!);
          }
          previous = token;
        }
        final text = spans.map((s) => s.readable).join();
        final explicitExample = classifyContent
            ? RegExp(r'^例\s*([0-9]{1,2})(?!\d)').firstMatch(text)
            : null;
        final marker =
            explicitExample?[1] ?? _exerciseNumber(text, combined, page);
        final badge = classifyContent && marker != null
            ? page.graphics.regions
                  .where(
                    (region) =>
                        region.containsCenter(combined.first.region) &&
                        _numberBadge(
                          region,
                          glyphs,
                          page.text.width / page.text.height,
                        ),
                  )
                  .firstOrNull
            : null;
        final example =
            classifyContent &&
            marker != null &&
            (explicitExample != null ||
                bodyHeight > 0 &&
                    combined.first.height >= bodyHeight * .95 &&
                    badge != null);
        final heading =
            classifyContent &&
            marker == null &&
            (_sectionHeading(text) ||
                bodyHeight > 0 &&
                    lineHeight > bodyHeight * 1.2 &&
                    text.length <= 45 &&
                    RegExp(r'[\u3400-\u9fff]').hasMatch(text) &&
                    !RegExp(r'[。！？?!=]').hasMatch(text));
        var source = combined.map((t) => t.region).reduce((a, b) => a.merge(b));
        if (badge != null) source = source.merge(badge);
        if (restoreLayout) {
          spans = _inlineMathSpans(spans, mathContext: marker != null);
        }
        blocks.add(
          MathTextbookBlock(
            id: id(),
            kind: heading
                ? MathTextbookBlockKind.heading
                : example
                ? MathTextbookBlockKind.example
                : marker != null
                ? MathTextbookBlockKind.exercise
                : spans.every((s) => s.expression != null)
                ? MathTextbookBlockKind.formula
                : MathTextbookBlockKind.text,
            spans: spans,
            sources: [_pad(source)],
            exerciseNumber: marker,
          ),
        );
      }
    }

    // 圆形题号常与题干留出较宽间隙；先连接同行第一处内容，避免被当成独立左栏。
    for (final marker
        in blocks
            .where(
              (b) =>
                  b.exerciseNumber != null &&
                  (RegExp(r'^\d+$').hasMatch(b.text) ||
                      restoreLayout &&
                          RegExp(r'^\d+\s*[（(]\s*$').hasMatch(b.text)),
            )
            .toList()) {
      var current = marker;
      do {
        final source = current.sources.single;
        final candidates =
            blocks
                .where(
                  (b) =>
                      b != current &&
                      (b.exerciseNumber == null ||
                          restoreLayout &&
                              RegExp(r'^[（(]\d+[）)]').hasMatch(b.text)) &&
                      b.sources.single.left > source.right &&
                      b.sources.single.left - source.right < .12 &&
                      (b.sources.single.top - source.top).abs() < .02,
                )
                .toList()
              ..sort(
                (a, b) =>
                    a.sources.single.left.compareTo(b.sources.single.left),
              );
        if (candidates.isEmpty) break;
        final body = candidates.first;
        final joined = MathTextbookBlock(
          id: current.id,
          kind: current.kind,
          spans: [
            ...current.spans,
            if (body.spans.isNotEmpty) const MathTextbookSpan.text(' '),
            ...body.spans,
          ],
          sources: [source.merge(body.sources.single)],
          exerciseNumber: current.exerciseNumber,
          warnings: restoreLayout
              ? {...current.warnings, ...body.warnings}.toList()
              : body.warnings,
          sourceLayout: current.sourceLayout || body.sourceLayout,
        );
        blocks[blocks.indexOf(current)] = joined;
        blocks.remove(body);
        current = joined;
        // A blank can separate the badge, opening bracket and prompt into
        // three segments. Continue only until that bracket has its body.
      } while (restoreLayout &&
          RegExp(r'^\d+\s*[（(]\s*$').hasMatch(current.text));
    }

    if (restoreLayout) {
      for (var index = 0; index < blocks.length; index++) {
        final block = blocks[index];
        if (block.kind != MathTextbookBlockKind.heading ||
            _sectionHeading(block.text)) {
          continue;
        }
        final source = block.sources.single;
        final besideQuestion = blocks.any((other) {
          if (other.exerciseNumber == null ||
              other.kind != MathTextbookBlockKind.exercise &&
                  other.kind != MathTextbookBlockKind.example) {
            return false;
          }
          final marker = other.sources.single;
          return marker.left < source.left &&
              (marker.centerY - source.centerY).abs() <
                  math.max(marker.height, source.height) * .6;
        });
        // Large handwritten print beside a numbered example is its prompt,
        // not a new section. Small drawing labels can distort the body median.
        if (besideQuestion) blocks[index] = _plainTextBlock(block);
      }
      for (var index = 0; index < blocks.length; index++) {
        final block = blocks[index];
        if (block.exerciseNumber == null ||
            !RegExp(r'^[0-9\s.、()（）①-⑳]+$').hasMatch(block.text)) {
          continue;
        }
        // Picture positions and isolated number badges do not supply a prompt.
        // Keep their glyphs in the surrounding illustration/question instead.
        if (!_pictorialQuestion(block, blocks, page)) {
          blocks[index] = _plainTextBlock(block);
        }
      }
    }

    // 线条和图像按重叠区域聚合，保留表格与图形；不猜测图形语义。
    final graphics = <MathTextbookRegion>[];
    for (final region in page.graphics.regions) {
      if (region.width < 0.018 || region.height < 0.012) continue;
      if (_numberBadge(region, glyphs, page.text.width / page.text.height)) {
        continue;
      }
      if (tokens.any(
        (t) =>
            t.expression != null &&
            t.region.containsCenter(region) &&
            region.width < t.region.width * 1.2 &&
            region.height < t.region.height * 1.2,
      )) {
        continue;
      }
      var joined = region;
      for (var i = graphics.length - 1; i >= 0; i--) {
        if (_overlap(joined, graphics[i], margin: 0.012)) {
          joined = joined.merge(graphics.removeAt(i));
        }
      }
      graphics.add(joined);
    }
    for (final region in graphics) {
      final contained = blocks
          .where(
            (b) =>
                b.sources.length == 1 &&
                (!classifyContent ||
                    b.kind != MathTextbookBlockKind.heading &&
                        b.exerciseNumber == null) &&
                b.sources.first.left >= region.left - .006 &&
                b.sources.first.right <= region.right + .006 &&
                b.sources.first.top >= region.top - .004 &&
                b.sources.first.bottom <= region.bottom + .004,
          )
          .toList();
      final orderedLabels = _readingOrder(contained, 0);
      blocks.removeWhere((b) => contained.contains(b));
      blocks.add(
        MathTextbookBlock(
          id: id(),
          kind: MathTextbookBlockKind.illustration,
          spans: [
            for (var i = 0; i < orderedLabels.length; i++) ...[
              if (i > 0 && orderedLabels[i].spans.isNotEmpty)
                const MathTextbookSpan.text('\n'),
              ...orderedLabels[i].spans,
            ],
          ],
          sources: [_pad(region)],
          warnings: {
            '图形、表格及标注关系需对照原书核对',
            ...contained.expand((b) => b.warnings),
          }.toList(),
          exerciseNumber: contained
              .map((b) => b.exerciseNumber)
              .whereType<String>()
              .firstOrNull,
        ),
      );
    }
    final printedPage = classifyContent ? printedTextbookPage(page.text) : null;
    if (printedPage != null) {
      blocks.removeWhere((block) {
        final region = block.sources.single;
        return block.text.trim() == '$printedPage' &&
            region.top > .88 &&
            region.width < .13 &&
            (region.right < .25 || region.left > .75);
      });
    }
    final ordered = _readingOrder(blocks, 0);
    final merged = <MathTextbookBlock>[];
    for (final block in ordered) {
      final previous = merged.lastOrNull;
      if (previous != null &&
          block.kind == MathTextbookBlockKind.text &&
          (previous.kind == MathTextbookBlockKind.text ||
              previous.kind == MathTextbookBlockKind.example ||
              previous.kind == MathTextbookBlockKind.exercise) &&
          (previous.sources.last.left - block.sources.first.left).abs() <
              0.025 &&
          block.sources.first.top >= previous.sources.last.top &&
          block.sources.first.top - previous.sources.last.bottom < 0.016 &&
          block.sources.first.top - previous.sources.last.bottom > -0.008 &&
          !RegExp(r'^(?:练习|做一做|想一想|讨论)').hasMatch(block.text)) {
        merged[merged.length - 1] = _join(previous, block);
      } else {
        merged.add(block);
      }
    }
    // 每页始终保留完整来源。正文不足、图形提取失败不会成为静默空页。
    merged.add(
      MathTextbookBlock(
        id: '$prefix-source',
        kind: MathTextbookBlockKind.sourcePage,
        spans: const [],
        sources: [
          MathTextbookRegion(
            page: number,
            left: 0,
            top: 0,
            right: 1,
            bottom: 1,
            printedPage: printedPage?.toString(),
          ),
        ],
        warnings: [
          if (glyphs.isEmpty) '本页没有可用文字，需根据原书补齐',
          if (page.text.status != 'text_extracted') '本页文字提取状态需要核对',
          if (!page.graphics.complete) '本页绘图证据未完整读取，已保留整页',
        ],
      ),
    );
    return merged;
  }

  void _verticalArithmetic(
    MathTextbookPageLayout page,
    List<TextbookPageGlyph> glyphs,
    Set<int> consumed,
    List<MathTextbookBlock> blocks,
    String Function() id,
  ) {
    final aspect = page.text.width / page.text.height;
    for (final line in page.graphics.lines.where((l) => l.dark)) {
      final operations = glyphs.where((g) {
        final size = math.max(g.height, g.width * aspect);
        return !consumed.contains(g.index) &&
            ['+', '-', '−', '×'].contains(g.text) &&
            g.centerX >= line.left &&
            g.centerX < line.right &&
            line.y > _cy(g) &&
            line.y - _cy(g) < size * 3.5;
      }).toList();
      if (operations.length != 1) continue;
      final operation = operations.single;
      final size = math.max(operation.height, operation.width * aspect);
      final digits = glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                _digit(g.text) &&
                g.centerX > operation.centerX &&
                g.centerX <= line.right &&
                _cy(g) > line.y - size * 9 &&
                _cy(g) < line.y + size * 4,
          )
          .toList();
      if (digits.length < 2) continue;
      final height = _median(digits.map((g) => g.height));
      final rows = <List<TextbookPageGlyph>>[];
      for (final glyph
          in (digits.where((g) => g.height >= height * .8).toList()
            ..sort((a, b) => _cy(a).compareTo(_cy(b))))) {
        if (rows.isEmpty ||
            (_cy(glyph) - _cy(rows.last.first)).abs() > height * .5) {
          rows.add([glyph]);
        } else {
          rows.last.add(glyph);
        }
      }
      // Nearby horizontal equations can share the same x coordinates. Their
      // explicit relation sign separates them from the vertical operand rows.
      final arithmeticRows = rows.where(
        (row) => !_rowNeighbors(
          row.first,
          glyphs,
          consumed,
        ).any((g) => g.text == '=' || g.text == '≈'),
      );
      final above = arithmeticRows.where((r) => _cy(r.first) < line.y).toList();
      final below = arithmeticRows.where((r) => _cy(r.first) > line.y).toList();
      // This structure owns exactly two operands and at most one result row.
      // More rows are source work, even when a later separator was not read.
      if (above.length != 2 || below.length > 1) continue;
      final chosen = <List<TextbookPageGlyph>>[
        above[above.length - 2],
        above.last,
        if (below.isNotEmpty) below.first else [],
      ];
      if ((_cy(chosen[1].first) - _cy(operation)).abs() > height * .7 ||
          _cy(chosen[1].first) - _cy(chosen[0].first) > height * 3.5) {
        continue;
      }
      // A multi-row product or a division ladder must stay complete in its
      // original region; the first partial product is not the final answer.
      if (page.graphics.lines.any(
        (other) =>
            other != line &&
            other.dark &&
            other.y > line.y + height * .5 &&
            other.y < line.y + height * 6 &&
            math.min(other.right, line.right) -
                    math.max(other.left, line.left) >
                (line.right - line.left) * .7,
      )) {
        continue;
      }
      for (final row in chosen.where((r) => r.isNotEmpty)) {
        final top = row.map((g) => g.top).reduce(math.min);
        final bottom = row.map((g) => g.bottom).reduce(math.max);
        row.addAll(
          glyphs.where(
            (g) =>
                !consumed.contains(g.index) &&
                g.text == '.' &&
                g.centerX > operation.centerX &&
                g.centerX <= line.right &&
                _cy(g) >= top &&
                _cy(g) <= bottom + height * .12,
          ),
        );
        row.sort((a, b) => a.left.compareTo(b.left));
      }
      final columns = <double>[];
      final characters = chosen.expand((r) => r).toList()
        ..sort((a, b) => a.centerX.compareTo(b.centerX));
      for (final glyph in characters) {
        if (columns.isEmpty || glyph.centerX - columns.last > height * .32) {
          columns.add(glyph.centerX);
        }
      }
      if (columns.isEmpty || columns.length > 12) continue;
      int columnOf(double x) {
        var closest = 0;
        for (var column = 1; column < columns.length; column++) {
          if ((columns[column] - x).abs() < (columns[closest] - x).abs()) {
            closest = column;
          }
        }
        return closest;
      }

      final grid = <String>[];
      var aligned = true;
      for (final row in chosen) {
        final cells = List.filled(columns.length, ' ');
        for (final glyph in row) {
          final column = columnOf(glyph.centerX);
          if (cells[column] != ' ' ||
              (glyph.centerX - columns[column]).abs() > height * .4) {
            aligned = false;
            break;
          }
          cells[column] = glyph.text;
        }
        grid.add(cells.join());
      }
      if (!aligned) continue;
      final selectedIndices = characters.map((g) => g.index).toSet();
      final notes =
          glyphs
              .where(
                (g) =>
                    !consumed.contains(g.index) &&
                    !selectedIndices.contains(g.index) &&
                    (_digit(g.text) || g.text == '.') &&
                    g.height < height * .8 &&
                    g.centerX >= columns.first - height * .4 &&
                    g.centerX <= line.right + height * .4 &&
                    _cy(g) >=
                        chosen[0].map((c) => c.top).reduce(math.min) -
                            height * 1.6 &&
                    _cy(g) < line.y,
              )
              .toList()
            ..sort((a, b) => _cy(a).compareTo(_cy(b)));
      final bands = <List<TextbookPageGlyph>>[];
      for (final note in notes) {
        if (bands.isEmpty ||
            (_cy(note) - _cy(bands.last.first)).abs() > height * .22) {
          bands.add([note]);
        } else {
          bands.last.add(note);
        }
      }
      final annotations = <MathTextbookVerticalAnnotation>[];
      final levels = <int, int>{};
      for (final band in bands) {
        band.sort((a, b) => a.left.compareTo(b.left));
        final groups = <List<TextbookPageGlyph>>[];
        for (final glyph in band) {
          if (groups.isEmpty ||
              glyph.left - groups.last.last.right >
                  math.max(glyph.width, groups.last.last.width) * 1.3) {
            groups.add([glyph]);
          } else {
            groups.last.add(glyph);
          }
        }
        final y = _cy(band.first);
        final row = y < _cy(chosen[0].first)
            ? 0
            : y < _cy(chosen[1].first)
            ? 1
            : 2;
        final level = levels[row] ?? 0;
        levels[row] = level + 1;
        for (final group in groups) {
          final region = _bounds(page.text.page, group);
          // Printed carries sit just to the right of the receiving digit.
          // Borrowed values above an operand remain centered on its column.
          final carryColumn = columns.lastIndexWhere(
            (x) => x <= region.centerX,
          );
          final column = row == 2 && carryColumn >= 0
              ? carryColumn
              : columnOf(region.centerX);
          if ((region.centerX - columns[column]).abs() > height * 1.25) {
            aligned = false;
            break;
          }
          annotations.add(
            MathTextbookVerticalAnnotation(
              value: group.map((g) => g.text).join(),
              row: row,
              columnFromRight: columns.length - column - 1,
              level: level,
            ),
          );
        }
      }
      if (!aligned) continue;
      final symbol = operation.text == '−' ? '-' : operation.text;
      final ordinaryAddition =
          symbol == '+' &&
          grid.every((r) => RegExp(r'^ *\d+$').hasMatch(r)) &&
          !grid.last.startsWith(' ') &&
          annotations.every(
            (a) =>
                a.row == 2 &&
                a.level == 0 &&
                RegExp(r'^[1-9]$').hasMatch(a.value),
          );
      final MathTextbookExpression expression;
      try {
        expression = MathTextbookExpression.fromJson(
          (ordinaryAddition
                  ? MathTextbookVerticalAddition(
                      grid.map((r) => r.trim()).toList(),
                      [
                        for (final a in annotations)
                          MathTextbookCarry(
                            int.parse(a.value),
                            a.columnFromRight,
                          ),
                      ],
                    )
                  : MathTextbookVerticalArithmetic(
                      grid,
                      operation: symbol,
                      annotations: annotations,
                    ))
              .toJson(),
        );
      } on FormatException {
        continue;
      }
      final placeholders = glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                ['(', ')', '（', '）'].contains(g.text) &&
                g.centerX >= line.left &&
                g.centerX <= line.right &&
                _cy(g) > line.y &&
                _cy(g) < line.y + height * 3,
          )
          .toList();
      final selected = [operation, ...characters, ...notes, ...placeholders];
      var region = _bounds(page.text.page, selected).merge(
        MathTextbookRegion(
          page: page.text.page,
          left: line.left,
          right: line.right,
          top: math.max(0.0, line.y - height * .05),
          bottom: math.min(
            1.0,
            line.y + height * (chosen[2].isEmpty ? 1.8 : .05),
          ),
        ),
      );
      // PDF paths can carry dots, strike-throughs and other written work.
      // Bounds prove that extra ink exists, not what that ink means: keep the
      // source crop instead of guessing an annotation from its rectangle.
      final decorations = page.graphics.regions
          .where(
            (r) =>
                r.width * aspect <= height * 2 &&
                r.height <= height * 1.75 &&
                r.left >= line.left - height * .4 &&
                r.right <= line.right + height * .4 &&
                r.top >= region.top - height * 1.6 &&
                r.bottom <= region.bottom + height * .25,
          )
          .toList();
      for (final decoration in decorations) {
        region = region.merge(decoration);
      }
      final keepLayout =
          grid.last.contains(' ') ||
          annotations.any((a) => a.row < 2 || a.value == '.') ||
          decorations.isNotEmpty;
      blocks.add(
        MathTextbookBlock(
          id: id(),
          kind: MathTextbookBlockKind.formula,
          spans: [MathTextbookSpan.math(expression)],
          sources: [_pad(region)],
          sourceLayout: keepLayout,
          warnings: keepLayout ? const ['空位、借位或绘图标注按原书版面保留'] : const [],
        ),
      );
      consumed.addAll(selected.map((g) => g.index));
    }
  }

  // Frozen detection for exact v0/v1 automatic-draft reproduction only.
  void _legacyVerticalAdditions(
    MathTextbookPageLayout page,
    List<TextbookPageGlyph> glyphs,
    Set<int> consumed,
    List<MathTextbookBlock> blocks,
    String Function() id,
  ) {
    for (final line in page.graphics.lines.where((l) => l.dark)) {
      final pluses = glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                g.text == '+' &&
                g.centerX >= line.left &&
                g.centerX < line.right &&
                line.y > _cy(g) &&
                line.y - _cy(g) < g.height * 2,
          )
          .toList();
      if (pluses.length != 1) continue;
      final plus = pluses.single;
      final digits = glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                _digit(g.text) &&
                g.centerX > plus.centerX &&
                g.centerX <= line.right &&
                _cy(g) > line.y - plus.height * 6 &&
                _cy(g) < line.y + plus.height * 3,
          )
          .toList();
      if (digits.length < 3) continue;
      final height = _median(digits.map((g) => g.height));
      final rows = <List<TextbookPageGlyph>>[];
      for (final g
          in (digits.where((g) => g.height >= height * 0.8).toList()
            ..sort((a, b) => _cy(a).compareTo(_cy(b))))) {
        if (rows.isEmpty ||
            (_cy(g) - _cy(rows.last.first)).abs() > height * 0.5) {
          rows.add([g]);
        } else {
          rows.last.add(g);
        }
      }
      final above = rows.where((row) => _cy(row.first) < line.y).toList();
      final below = rows.where((row) => _cy(row.first) > line.y).toList();
      if (above.length < 2 || below.isEmpty) continue;
      final selectedRows = [above[above.length - 2], above.last, below.first];
      if ((_cy(selectedRows[1].first) - _cy(plus)).abs() > height * 0.5) {
        continue;
      }
      for (final row in selectedRows) {
        row.sort((a, b) => a.left.compareTo(b.left));
      }
      final widest = selectedRows.reduce((a, b) => a.length > b.length ? a : b);
      if (widest.length > 12) continue;
      final columns = widest.map((g) => g.centerX).toList();
      if (selectedRows.any(
        (row) => row.asMap().entries.any(
          (entry) =>
              (entry.value.centerX -
                      columns[columns.length - row.length + entry.key])
                  .abs() >
              height * 0.3,
        ),
      )) {
        continue;
      }
      final carryGlyphs = digits
          .where(
            (g) =>
                g.height < height * 0.8 &&
                _cy(g) > _cy(selectedRows[1].first) &&
                _cy(g) < line.y,
          )
          .toList();
      final carries = <MathTextbookCarry>[];
      for (final carry in carryGlyphs) {
        final column = columns.lastIndexWhere((x) => x <= carry.centerX);
        if (column >= 0 &&
            carry.centerX - columns[column] < height &&
            carry.text != '0') {
          carries.add(
            MathTextbookCarry(
              int.parse(carry.text),
              columns.length - column - 1,
            ),
          );
        }
      }
      if (carries.length != carryGlyphs.length ||
          carries.map((c) => c.columnFromRight).toSet().length !=
              carries.length) {
        continue;
      }
      final selected = [plus, ...selectedRows.expand((r) => r), ...carryGlyphs];
      final expression = MathTextbookVerticalAddition(
        selectedRows.map((row) => row.map((g) => g.text).join()).toList(),
        carries,
      );
      blocks.add(
        MathTextbookBlock(
          id: id(),
          kind: MathTextbookBlockKind.formula,
          spans: [MathTextbookSpan.math(expression)],
          sources: [_pad(_bounds(page.text.page, selected))],
        ),
      );
      consumed.addAll(selected.map((g) => g.index));
    }
  }
}

List<TextbookPageGlyph> _deduplicateOverlappingGlyphs(
  List<TextbookPageGlyph> glyphs,
) {
  final seen = <String, List<TextbookPageGlyph>>{};
  final kept = <TextbookPageGlyph>[];
  for (final glyph in glyphs) {
    final sameText = seen.putIfAbsent(glyph.text, () => []);
    final copy = sameText.any((other) {
      final width = math.min(glyph.width, other.width);
      final height = math.min(glyph.height, other.height);
      if ((glyph.centerX - other.centerX).abs() > width * .6 ||
          (_cy(glyph) - _cy(other)).abs() > height * .3 ||
          math.max(glyph.height, other.height) > height * 1.5) {
        return false;
      }
      final overlapWidth =
          math.min(glyph.right, other.right) - math.max(glyph.left, other.left);
      final overlapHeight =
          math.min(glyph.bottom, other.bottom) - math.max(glyph.top, other.top);
      return overlapWidth > width * .4 && overlapHeight > height * .7;
    });
    if (copy) continue;
    sameText.add(glyph);
    kept.add(glyph);
  }
  return kept;
}

final _inlineArithmetic = RegExp(
  r'(?:[−-]?\d+(?:\.\d+)?%?|[a-zA-Z]{1,8}|[?？□]|\([^()\r\n]{1,64}\))'
  r'(?:\s*[+\-−×÷=<>≤≥:/]\s*(?:\d+(?:\.\d+)?%?|[a-zA-Z]{1,8}|[?？□]|\([^()\r\n]{1,64}\))?)+',
);

List<MathTextbookSpan> _inlineMathSpans(
  List<MathTextbookSpan> spans, {
  required bool mathContext,
}) {
  final output = <MathTextbookSpan>[];
  for (final span in spans) {
    final text = span.text;
    if (text == null) {
      output.add(span);
      continue;
    }
    var end = 0;
    for (final match in _inlineArithmetic.allMatches(text)) {
      final source = match[0]!;
      if (!mathContext && !RegExp(r'[+−×÷=<>≤≥]').hasMatch(source)) continue;
      MathTextbookExpression expression;
      try {
        expression = parseMathTextbookExpression(source.replaceAll('？', '?'));
      } on FormatException {
        continue;
      }
      if (match.start > end) {
        output.add(MathTextbookSpan.text(text.substring(end, match.start)));
      }
      output.add(MathTextbookSpan.math(expression));
      end = match.end;
    }
    if (end < text.length) {
      output.add(MathTextbookSpan.text(text.substring(end)));
    }
  }
  return output.length > 1000 ? spans : output;
}

bool _sectionHeading(String text) => RegExp(
  r'^(?:练习[一二三四五六七八九十百0-9]+|做一做|想一想|说一说|试一试|'
  r'你知道吗[？?]?|生活中的数学|整理和复习|回顾与反思|阅读资料)$',
).hasMatch(text.replaceAll(RegExp(r'\s'), ''));

List<_Token> _mixedNumbers(List<_Token> tokens) {
  final output = <_Token>[];
  for (final token in tokens) {
    final previous = output.lastOrNull;
    final fraction = token.expression;
    if (previous?.text != null &&
        _digit(previous!.text!) &&
        fraction is MathTextbookFraction &&
        BigInt.parse(fraction.numerator) < BigInt.parse(fraction.denominator) &&
        token.region.left - previous.region.right < previous.height * 0.4 &&
        (token.baseline - previous.baseline).abs() < previous.height * 0.3) {
      final integer = <_Token>[output.removeLast()];
      while (output.isNotEmpty &&
          output.last.text != null &&
          _digit(output.last.text!) &&
          integer.first.region.left - output.last.region.right <
              previous.height * 0.3) {
        integer.insert(0, output.removeLast());
      }
      output.add(
        _Token.math(
          MathTextbookMixedNumber(integer.map((t) => t.text!).join(), fraction),
          integer.map((t) => t.region).fold(token.region, (a, b) => a.merge(b)),
          token.baseline,
          previous.height,
          {...token.indices, ...integer.expand((t) => t.indices)},
        ),
      );
    } else {
      output.add(token);
    }
  }
  return output;
}

List<TextbookPageGlyph> _rowNeighbors(
  TextbookPageGlyph glyph,
  List<TextbookPageGlyph> glyphs,
  Set<int> consumed,
) {
  final row =
      glyphs
          .where(
            (g) =>
                !consumed.contains(g.index) &&
                (_cy(g) - _cy(glyph)).abs() <=
                    math.max(g.height, glyph.height) * .6,
          )
          .toList()
        ..sort((a, b) => a.left.compareTo(b.left));
  final at = row.indexWhere((g) => g.index == glyph.index);
  if (at < 0) return [glyph];
  var left = at, right = at;
  while (left > 0 &&
      row[left].left - row[left - 1].right <=
          math.max(glyph.height * 1.8, .028)) {
    left--;
  }
  while (right < row.length - 1 &&
      row[right + 1].left - row[right].right <=
          math.max(glyph.height * 1.8, .028)) {
    right++;
  }
  return row.sublist(left, right + 1);
}

MathTextbookBlock _plainTextBlock(MathTextbookBlock block) => MathTextbookBlock(
  id: block.id,
  kind: MathTextbookBlockKind.text,
  spans: block.spans,
  sources: block.sources,
  warnings: block.warnings,
  parentNote: block.parentNote,
  sourceLayout: block.sourceLayout,
);

bool _pictorialQuestion(
  MathTextbookBlock block,
  List<MathTextbookBlock> blocks,
  MathTextbookPageLayout page,
) {
  final source = block.sources.single;
  final aspect = page.text.width / page.text.height;
  // A position label inside a drawing cannot become a new question, even if
  // it is circled. A real picture-only prompt has its drawing beside the badge.
  if (page.graphics.regions.any(
    (r) =>
        r.containsCenter(source) &&
        r.width * aspect > source.height * 2 &&
        r.height > source.height * 2,
  )) {
    return false;
  }
  if (!page.graphics.regions.any(
    (r) =>
        r.left > source.right &&
        r.top <= source.bottom + source.height * 2 &&
        r.bottom > source.top &&
        r.width * aspect > source.height * 3 &&
        r.height > source.height * 2,
  )) {
    return false;
  }
  final number = int.tryParse(block.exerciseNumber ?? '');
  if (number == null) return false;
  if (block.kind == MathTextbookBlockKind.example) return true;
  return blocks.any((other) {
    final adjacent = int.tryParse(other.exerciseNumber ?? '');
    if (other == block ||
        adjacent == null ||
        (adjacent - number).abs() != 1 ||
        RegExp(r'^[0-9\s.、()（）①-⑳]+$').hasMatch(other.text)) {
      return false;
    }
    final neighbor = other.sources.single;
    return (neighbor.left - source.left).abs() <= source.height * .35 &&
        neighbor.height >= source.height * .75 &&
        neighbor.height <= source.height * 1.5;
  });
}

bool _divisionBracket(
  MathTextbookPageLayout page,
  MathTextbookLine line,
  List<TextbookPageGlyph> below,
  List<TextbookPageGlyph> glyphs,
  Set<int> consumed,
) {
  final height = _median(below.map((g) => g.height));
  final horizontal = height / (page.text.width / page.text.height);
  final baseline = _median(below.map(_cy));
  if (!glyphs.any(
    (g) =>
        !consumed.contains(g.index) &&
        _digit(g.text) &&
        (baseline - _cy(g)).abs() <= height * .45 &&
        g.right <= line.left + horizontal * .25 &&
        line.left - g.right <= horizontal * 1.6,
  )) {
    return false;
  }
  final bottom = below.map((g) => g.bottom).reduce(math.max);
  // A curved/vertical path at the bar's left edge and a number beside it are
  // evidence of division work, not of a fraction. Keep its complete source.
  return page.graphics.regions.any(
    (r) =>
        r.left >= line.left - horizontal * 1.5 &&
        r.left <= line.left + horizontal * .35 &&
        r.right >= line.left - horizontal * .4 &&
        r.top >= line.y - height * .35 &&
        r.top <= line.y + height * .25 &&
        r.height >= height * .5 &&
        r.bottom >= baseline &&
        r.bottom <= bottom + height * .8,
  );
}

bool _numberBadge(
  MathTextbookRegion region,
  List<TextbookPageGlyph> glyphs,
  double pageAspect,
) {
  if (region.left > .2 || region.width > .08 || region.height > .065) {
    return false;
  }
  final aspect = region.width * pageAspect / region.height;
  if (aspect < .65 || aspect > 1.5) return false;
  final labels = glyphs
      .where((g) => region.containsCenter(_glyphRegion(region.page, g)))
      .toList();
  return labels.isNotEmpty &&
      labels.length <= 2 &&
      labels.every((g) => _digit(g.text)) &&
      region.height > labels.map((g) => g.height).reduce(math.max) * 1.05;
}

String? _exerciseNumber(
  String text,
  List<_Token> tokens,
  MathTextbookPageLayout page,
) {
  final explicit = RegExp(r'^(?:([0-9]{1,2})[.、](?!\d)|[（(]([0-9]{1,2})[）)])')
      .firstMatch(text);
  if (explicit != null) return explicit[1] ?? explicit[2];
  final circled = RegExp(r'^[①-⑳]').firstMatch(text);
  if (circled != null) return '${text.runes.first - 0x2460 + 1}';
  final leading = RegExp(r'^([0-9]{1,2})(?:\s|$)').firstMatch(text);
  if (leading == null || tokens.first.region.left > .2) return null;
  final badge = page.graphics.regions.any(
    (r) =>
        r.containsCenter(tokens.first.region) &&
        _numberBadge(
          r,
          page.text.glyphs.where((g) => g.text.trim().isNotEmpty).toList(),
          page.text.width / page.text.height,
        ),
  );
  return badge ? leading[1] : null;
}

List<MathTextbookBlock> _readingOrder(
  List<MathTextbookBlock> blocks,
  int depth,
) {
  if (blocks.length < 2 || depth > 16) return blocks;
  (bool, double, double)? cut;
  (bool, double, double)? headingCut;
  for (final horizontal in [true, false]) {
    final ranges =
        blocks
            .map(
              (b) => horizontal
                  ? (b.sources.first.top, b.sources.first.bottom)
                  : (b.sources.first.left, b.sources.first.right),
            )
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    var end = ranges.first.$2;
    for (final range in ranges.skip(1)) {
      final gap = range.$1 - end;
      if (gap > 0.006 && (cut == null || gap > cut.$3)) {
        cut = (horizontal, (end + range.$1) / 2, gap);
      }
      if (horizontal &&
          depth == 0 &&
          gap > .006 &&
          end < .17 &&
          blocks.where((b) => b.sources.first.bottom <= end).length == 1) {
        headingCut ??= (true, (end + range.$1) / 2, gap);
      }
      end = math.max(end, range.$2);
    }
  }
  cut = headingCut ?? cut;
  if (cut != null) {
    final axis = cut.$1;
    final at = cut.$2;
    final before = blocks
        .where(
          (b) =>
              (axis ? b.sources.first.centerY : b.sources.first.centerX) < at,
        )
        .toList();
    final after = blocks.where((b) => !before.contains(b)).toList();
    if (before.isNotEmpty && after.isNotEmpty) {
      return [
        ..._readingOrder(before, depth + 1),
        ..._readingOrder(after, depth + 1),
      ];
    }
  }
  return [...blocks]..sort((a, b) {
    // 离散行桶保证比较关系可传递，避免“相近则按 x”产生循环排序。
    final row = (a.sources.first.top / .01).round().compareTo(
      (b.sources.first.top / .01).round(),
    );
    if (row != 0) return row;
    final column = a.sources.first.left.compareTo(b.sources.first.left);
    return column != 0 ? column : a.id.compareTo(b.id);
  });
}

MathTextbookBlock _join(MathTextbookBlock first, MathTextbookBlock next) =>
    mergeMathTextbookBlocks(first, next);

void _appendText(List<MathTextbookSpan> spans, String value) {
  if (spans.isNotEmpty && spans.last.text != null) {
    spans[spans.length - 1] = MathTextbookSpan.text('${spans.last.text}$value');
  } else {
    spans.add(MathTextbookSpan.text(value));
  }
}

bool _digit(String value) => RegExp(r'^[0-9]+$').hasMatch(value);
double _cy(TextbookPageGlyph glyph) => (glyph.top + glyph.bottom) / 2;
double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return 0;
  return sorted.length.isOdd
      ? sorted[sorted.length ~/ 2]
      : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
}

bool _numericRow(List<TextbookPageGlyph> row, {double? maxGap}) {
  if (row.isEmpty) return false;
  final sorted = [...row]..sort((a, b) => a.left.compareTo(b.left));
  final height = _median(row.map((g) => g.height));
  if (row.map(_cy).reduce(math.max) - row.map(_cy).reduce(math.min) >
      height * 0.4) {
    return false;
  }
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].left - sorted[i - 1].right >
        math.max(_median(row.map((g) => g.width)) * 0.7, maxGap ?? 0)) {
      return false;
    }
  }
  return true;
}

MathTextbookRegion _glyphRegion(int page, TextbookPageGlyph g) =>
    MathTextbookRegion(
      page: page,
      left: g.left.clamp(0.0, 1.0),
      top: g.top.clamp(0.0, 1.0),
      right: g.right.clamp(0.0, 1.0),
      bottom: g.bottom.clamp(0.0, 1.0),
    );
MathTextbookRegion _bounds(int page, List<TextbookPageGlyph> glyphs) =>
    glyphs.map((g) => _glyphRegion(page, g)).reduce((a, b) => a.merge(b));
MathTextbookRegion _pad(MathTextbookRegion r) => MathTextbookRegion(
  page: r.page,
  left: (r.left - 0.006).clamp(0.0, 1.0),
  top: (r.top - 0.004).clamp(0.0, 1.0),
  right: (r.right + 0.006).clamp(0.0, 1.0),
  bottom: (r.bottom + 0.004).clamp(0.0, 1.0),
  printedPage: r.printedPage,
);
bool _overlap(
  MathTextbookRegion a,
  MathTextbookRegion b, {
  double margin = 0,
}) =>
    a.left < b.right + margin &&
    a.right + margin > b.left &&
    a.top < b.bottom + margin &&
    a.bottom + margin > b.top;

class _Token {
  _Token.text(this.text, this.region, this.baseline, this.height, this.indices)
    : expression = null;
  _Token.math(
    this.expression,
    this.region,
    this.baseline,
    this.height,
    this.indices,
  ) : text = null;
  final String? text;
  final MathTextbookExpression? expression;
  final MathTextbookRegion region;
  final double baseline;
  final double height;
  final Set<int> indices;
}
