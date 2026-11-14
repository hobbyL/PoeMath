import 'dart:math' as math;

import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/domain/math_textbook_editing.dart';

/// 数学专用二维版面整理。输入完整页；选区仅由页面证据产生。
class MathTextbookDraftParser {
  const MathTextbookDraftParser();

  MathTextbookLesson parse({
    required String title,
    required int startPage,
    required int endPage,
    required List<MathTextbookPageLayout> pages,
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
      final pageBlocks = _parsePage(page, lessonId);
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
  ) {
    final number = page.text.page;
    final prefix = '$lessonId-p$number';
    if (page.text.glyphs.length > 6000 ||
        page.graphics.lines.length > 2000 ||
        page.graphics.regions.length > 4000) {
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
          warnings: const ['本页版面较复杂，已保留整页，请对照补齐'],
        ),
      ];
    }
    final glyphs = page.text.glyphs
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
    final consumed = <int>{};
    final tokens = <_Token>[];
    final blocks = <MathTextbookBlock>[];
    var serial = 0;
    String id() => '$prefix-${serial++}';

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
      if (!_numericRow(above) || !_numericRow(below)) continue;
      final hasOperator = glyphs.any(
        (g) =>
            !consumed.contains(g.index) &&
            const ['+', '−', '-', '×', '÷'].contains(g.text) &&
            g.centerX >= line.left &&
            g.centerX <= line.right &&
            (_cy(g) - line.y).abs() < g.height * 1.6,
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
                    exponent.left - g.right < g.height * 2 &&
                    exponent.height < g.height * 0.85 &&
                    _cy(g) - _cy(exponent) > g.height * 0.30 &&
                    _cy(g) - _cy(exponent) < g.height,
              )
              .toList()
            ..sort((a, b) => b.right.compareTo(a.right));
      if (letters.isEmpty) continue;
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

    _verticalAdditions(page, glyphs, consumed, blocks, id);

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
        final spans = <MathTextbookSpan>[];
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
        final marker = _exerciseNumber(text, combined, page);
        blocks.add(
          MathTextbookBlock(
            id: id(),
            kind: marker != null
                ? MathTextbookBlockKind.exercise
                : spans.every((s) => s.expression != null)
                ? MathTextbookBlockKind.formula
                : MathTextbookBlockKind.text,
            spans: spans,
            sources: [
              _pad(combined.map((t) => t.region).reduce((a, b) => a.merge(b))),
            ],
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
                  b.exerciseNumber != null && RegExp(r'^\d+$').hasMatch(b.text),
            )
            .toList()) {
      final source = marker.sources.single;
      final candidates =
          blocks
              .where(
                (b) =>
                    b != marker &&
                    b.exerciseNumber == null &&
                    b.sources.single.left > source.right &&
                    b.sources.single.left - source.right < .12 &&
                    (b.sources.single.top - source.top).abs() < .02,
              )
              .toList()
            ..sort(
              (a, b) => a.sources.single.left.compareTo(b.sources.single.left),
            );
      if (candidates.isEmpty) continue;
      final body = candidates.first;
      blocks[blocks.indexOf(marker)] = MathTextbookBlock(
        id: marker.id,
        kind: MathTextbookBlockKind.exercise,
        spans: [
          ...marker.spans,
          if (body.spans.isNotEmpty) const MathTextbookSpan.text(' '),
          ...body.spans,
        ],
        sources: [source.merge(body.sources.single)],
        exerciseNumber: marker.exerciseNumber,
        warnings: body.warnings,
      );
      blocks.remove(body);
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
    final ordered = _readingOrder(blocks, 0);
    final merged = <MathTextbookBlock>[];
    for (final block in ordered) {
      final previous = merged.lastOrNull;
      if (previous != null &&
          block.kind == MathTextbookBlockKind.text &&
          (previous.kind == MathTextbookBlockKind.text ||
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

  void _verticalAdditions(
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

bool _numericRow(List<TextbookPageGlyph> row) {
  if (row.isEmpty) return false;
  final sorted = [...row]..sort((a, b) => a.left.compareTo(b.left));
  final height = _median(row.map((g) => g.height));
  if (row.map(_cy).reduce(math.max) - row.map(_cy).reduce(math.min) >
      height * 0.4) {
    return false;
  }
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].left - sorted[i - 1].right >
        _median(row.map((g) => g.width)) * 0.7) {
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
