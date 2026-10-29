import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/domain/textbook_narration.dart';
import 'package:poemath/domain/textbook_pinyin.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';

import '../../helpers/textbook_course_fixture.dart';

TextbookCourseParagraph _paragraph(
  String id,
  String text, [
  List<String>? pinyin,
]) {
  final raw = courseFixture();
  final lesson = (raw['lessons'] as List).single as Map;
  lesson['paragraphs'] = [courseFixtureText(id, text, pinyin)];
  lesson['recitations'] = <Object>[];
  (lesson['coverage'] as Map)['recitations'] = 'notApplicable';
  return TextbookCoursePack.fromJson(raw).lessons.single.paragraphs.single;
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpParagraph(
  WidgetTester tester,
  TextbookCourseParagraph paragraph, {
  required bool showPinyin,
  required double scale,
  required double width,
  List<TextbookNarrationSpan> activeRanges = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: TextbookCourseParagraphsContent(
                paragraphs: [paragraph],
                showPinyin: showPinyin,
                activeRanges: activeRanges,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _advance(WidgetTester tester, String character, double scale) {
  final style = tester.widget<Text>(find.text(character).first).style!;
  final painter = TextPainter(
    textScaler: TextScaler.linear(scale),
    textDirection: TextDirection.ltr,
  );
  double measure(TextStyle style) {
    painter.text = TextSpan(text: character, style: style);
    painter.layout();
    return painter.width;
  }

  final normal = measure(style);
  final bold = measure(style.copyWith(fontWeight: FontWeight.w700));
  painter.dispose();
  return normal > bold ? normal : bold;
}

Finder _character(TextbookCourseParagraph paragraph, int rawIndex) =>
    find.byKey(ValueKey('narration-character-${paragraph.id}-$rawIndex'));

void main() {
  for (final showPinyin in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('引语前的文字利用行尾空间，左引号随下字换行（拼音=$showPinyin，字号=$scale）',
          (tester) async {
        _setViewport(tester);
        final paragraph = _paragraph(
          'quote-wrap',
          '就迎上去，问：“早！”',
          [
            'jiù',
            'yíng',
            'shàng',
            'qù',
            '，',
            'wèn',
            '：',
            '“',
            'zǎo',
            '！',
            '”',
          ],
        );

        Future<void> pumpAtWidth(double width) => _pumpParagraph(
              tester,
              paragraph,
              showPinyin: showPinyin,
              scale: scale,
              width: width,
            );

        await pumpAtWidth(1500);
        final cellWidth = tester.getTopLeft(find.text('迎')).dx -
            tester.getTopLeft(find.text('就')).dx;
        // 字格与每个标点独立度量，不能跟随错误布局放大验收阈值。
        final prefixWidth = '就迎上去问'.runes.length * cellWidth +
            _advance(tester, '，', scale) +
            _advance(tester, '：', scale);
        await pumpAtWidth(prefixWidth + 0.01);
        final firstLineY = tester.getCenter(find.text('就')).dy;
        expect(tester.getCenter(find.text('问')).dy, closeTo(firstLineY, 0.1));
        expect(tester.getCenter(find.text('：')).dy, closeTo(firstLineY, 0.1));
        final quotationY = tester.getCenter(find.text('早')).dy;
        expect(quotationY, greaterThan(firstLineY));
        for (final punctuation in ['“', '！', '”']) {
          expect(
            tester.getCenter(find.text(punctuation)).dy,
            closeTo(quotationY, 0.1),
          );
        }
        expect(tester.takeException(), isNull);
      });

      for (final example in [
        (prefix: '甲乙，', tail: '乙，', marks: '，'),
        (prefix: '甲乙。', tail: '乙。', marks: '。'),
        (prefix: '甲乙（丙）', tail: '（丙）', marks: '（）'),
        (prefix: '甲乙（【《丙》】）', tail: '（【《丙》】）', marks: '（【《》】）'),
        (prefix: '甲乙「丙。」', tail: '「丙。」', marks: '「。」'),
        (prefix: '甲乙[丙?!]', tail: '[丙?!]', marks: '[?!]'),
        (prefix: '甲乙"丙!"', tail: '"丙!"', marks: '"!"'),
        (prefix: '甲乙……', tail: '乙……', marks: '……'),
        (prefix: '甲乙——', tail: '——', marks: '——'),
        (prefix: '甲乙〜', tail: '〜', marks: '〜'),
        (prefix: '甲乙～', tail: '～', marks: '～'),
        (prefix: '甲乙@', tail: '@', marks: '@'),
      ]) {
        testWidgets(
            '标点统一度量且只在合法位置换行 ${example.prefix}（拼音=$showPinyin，字号=$scale）',
            (tester) async {
          _setViewport(tester);
          final paragraph = _paragraph('punctuation', '${example.prefix}丁');
          Future<void> pump(double width) => _pumpParagraph(
                tester,
                paragraph,
                showPinyin: showPinyin,
                scale: scale,
                width: width,
              );
          await pump(1500);
          final cellWidth = tester.getTopLeft(find.text('乙')).dx -
              tester.getTopLeft(find.text('甲')).dx;
          final marks = example.marks.runes.map(String.fromCharCode).toList();
          final prefixLength = example.prefix.runes.length;
          final width = (prefixLength - marks.length) * cellWidth +
              marks.fold<double>(
                0,
                (width, mark) => width + _advance(tester, mark, scale),
              );
          await pump(width + 0.01);
          final firstY = tester.getCenter(_character(paragraph, 0)).dy;
          final flow = tester.getRect(
            find.byKey(const ValueKey('punctuation-flow')),
          );
          for (var index = 0; index < prefixLength; index++) {
            final rect = tester.getRect(_character(paragraph, index));
            expect(rect.center.dy, closeTo(firstY, 0.1));
            expect(rect.right, lessThanOrEqualTo(flow.right + 0.1));
          }
          expect(
            tester.getCenter(find.text('丁')).dy,
            greaterThan(firstY),
          );
          await pump(width - 0.01);
          final tailStart = prefixLength - example.tail.runes.length;
          final tailY = tester.getCenter(_character(paragraph, tailStart)).dy;
          expect(
            tailY,
            greaterThan(tester.getCenter(_character(paragraph, 0)).dy),
          );
          for (var index = tailStart; index < prefixLength; index++) {
            expect(
              tester.getCenter(_character(paragraph, index)).dy,
              closeTo(tailY, 0.1),
            );
          }
          for (final mark in marks.toSet()) {
            expect(
              find.text(mark),
              findsNWidgets(marks.where((item) => item == mark).length),
              reason: '拼音行不能重复显示标点占位 token',
            );
          }
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('嵌套引语正文可以继续按字换行（拼音=$showPinyin，字号=$scale）', (tester) async {
        _setViewport(tester);
        final paragraph = _paragraph('nested', '甲（“乙丙！”）丁');
        await _pumpParagraph(
          tester,
          paragraph,
          showPinyin: showPinyin,
          scale: scale,
          width: 1500,
        );
        final cellWidth = tester.getTopLeft(find.text('丙')).dx -
            tester.getTopLeft(find.text('乙')).dx;
        final width = cellWidth * 2 +
            _advance(tester, '（', scale) +
            _advance(tester, '“', scale);
        await _pumpParagraph(
          tester,
          paragraph,
          showPinyin: showPinyin,
          scale: scale,
          width: width + 0.01,
        );
        expect(
          tester.getCenter(find.text('乙')).dy,
          closeTo(tester.getCenter(find.text('甲')).dy, 0.1),
        );
        final secondY = tester.getCenter(find.text('丙')).dy;
        expect(secondY, greaterThan(tester.getCenter(find.text('甲')).dy));
        for (final mark in ['！', '”', '）']) {
          expect(tester.getCenter(find.text(mark)).dy, closeTo(secondY, 0.1));
        }
        expect(tester.takeException(), isNull);
      });

      for (final width in [160.0, 280.0, 420.0]) {
        testWidgets('PDF 续行空白不占字格且保留注音与原文索引（宽=$width，拼音=$showPinyin，字号=$scale）',
            (tester) async {
          _setViewport(tester);
          const cleanText = '　　甲乙，丙丁“戊己？”庚𠀀A, B！';
          const sourceText =
              '　　甲 \t乙， \t\r\n　 丙\t丁“ \n戊  己？”\r\n　庚𠀀A,\r\n  B！';
          final clean = _paragraph('clean', cleanText);
          final source = _paragraph('source', sourceText);
          Future<void> pump(
            TextbookCourseParagraph paragraph, {
            List<TextbookNarrationSpan> ranges = const [],
          }) =>
              _pumpParagraph(
                tester,
                paragraph,
                showPinyin: showPinyin,
                scale: scale,
                width: width,
                activeRanges: ranges,
              );
          await pump(clean);
          final positions = [
            for (final (index, rune) in clean.text.runes.indexed)
              if (String.fromCharCode(rune).trim().isNotEmpty)
                tester.getTopLeft(_character(clean, index)),
          ];
          await pump(source);
          final pinyin = textbookCoursePinyinForReview(source);
          var token = 0;
          for (final (index, rune) in source.text.runes.indexed) {
            final text = String.fromCharCode(rune);
            if (text.trim().isEmpty) continue;
            final character = _character(source, index);
            expect(tester.getTopLeft(character), positions[token]);
            final semantics = tester.widget<Semantics>(
              find
                  .ancestor(of: character, matching: find.byType(Semantics))
                  .first,
            );
            expect(
              semantics.properties.label,
              showPinyin ? '$text ${pinyin[token]}' : text,
            );
            token++;
          }
          expect(source.text, sourceText);
          final rareIndex = source.text.runes.toList().indexOf(0x20000);
          await pump(
            source,
            ranges: [
              TextbookNarrationSpan(source.id, rareIndex, rareIndex + 1),
            ],
          );
          expect(
            tester.getTopLeft(_character(source, rareIndex)),
            positions[cleanText.runes.toList().indexOf(0x20000) - 2],
          );
          expect(
            tester
                .widget<Text>(_character(source, rareIndex))
                .style!
                .backgroundColor,
            isNotNull,
          );
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('最小标点组超出屏宽时仍可完整查看（拼音=$showPinyin，字号=$scale）', (tester) async {
        _setViewport(tester);
        final paragraph = _paragraph('narrow', '（【《甲》】）乙');
        await _pumpParagraph(
          tester,
          paragraph,
          showPinyin: showPinyin,
          scale: scale,
          width: 40,
        );
        final horizontalScroll = find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        );
        final scroll = find.ancestor(
          of: _character(paragraph, 6),
          matching: horizontalScroll,
        );
        expect(scroll, findsOneWidget);
        for (var index = 0; index < paragraph.text.runes.length; index++) {
          expect(_character(paragraph, index), findsOneWidget);
        }
        await tester.drag(scroll, const Offset(-1000, 0));
        await tester.pumpAndSettle();
        final viewport = tester.getRect(scroll);
        final lastMark = tester.getRect(_character(paragraph, 6));
        expect(lastMark.left, greaterThanOrEqualTo(viewport.left - 0.1));
        expect(lastMark.right, lessThanOrEqualTo(viewport.right + 0.1));
        expect(tester.takeException(), isNull);
      });

      testWidgets('英文词间空格保留，直引号及单词内撇号正确断行（拼音=$showPinyin，字号=$scale）',
          (tester) async {
        _setViewport(tester);
        final clean = _paragraph('english-clean', '甲"don\'t stop!"乙');
        final source =
            _paragraph('english-source', '甲 " don\'t\r\nstop! \n" 乙');
        Future<void> pump(TextbookCourseParagraph paragraph) => _pumpParagraph(
              tester,
              paragraph,
              showPinyin: showPinyin,
              scale: scale,
              width: 280,
            );
        await pump(clean);
        final positions = [
          for (final (index, rune) in clean.text.runes.indexed)
            if (String.fromCharCode(rune).trim().isNotEmpty)
              tester.getTopLeft(_character(clean, index)),
        ];
        await pump(source);
        var token = 0;
        for (final (index, rune) in source.text.runes.indexed) {
          if (String.fromCharCode(rune).trim().isEmpty) continue;
          expect(
            tester.getTopLeft(_character(source, index)),
            positions[token++],
          );
        }
        final sourceRunes = source.text.runes.toList();
        final quotes = [
          for (final (index, rune) in sourceRunes.indexed)
            if (rune == 0x22) index,
        ];
        expect(
          tester.getCenter(_character(source, quotes.first)).dy,
          tester.getCenter(_character(source, sourceRunes.indexOf(0x64))).dy,
        );
        expect(
          tester.getCenter(_character(source, quotes.last)).dy,
          tester.getCenter(_character(source, sourceRunes.indexOf(0x21))).dy,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('连续句末标点利用实际宽度，文字和右引号留在行尾（拼音=$showPinyin，字号=$scale）',
          (tester) async {
        _setViewport(tester);
        final paragraph = _paragraph('quote-end', '“鲤鱼阿姨，我们的妈妈在哪里？”接着问');
        Future<void> pumpAtWidth(double width, {bool highlighted = false}) =>
            _pumpParagraph(
              tester,
              paragraph,
              showPinyin: showPinyin,
              scale: scale,
              width: width,
              activeRanges: highlighted
                  ? const [TextbookNarrationSpan('quote-end', 13, 16)]
                  : const [],
            );
        await pumpAtWidth(1500);
        final cellWidth = tester.getTopLeft(find.text('鱼')).dx -
            tester.getTopLeft(find.text('鲤')).dx;
        final quotationWidth = '鲤鱼阿姨我们的妈妈在哪里'.runes.length * cellWidth +
            ['“', '，', '？', '”'].fold<double>(
              0,
              (width, mark) => width + _advance(tester, mark, scale),
            );
        // 空间能容纳完整的引语及标点字形，不能再给每个标点预留整字格。
        await pumpAtWidth(quotationWidth + 0.01);
        final firstLineY = tester.getCenter(find.text('鲤')).dy;
        final right =
            tester.getRect(find.byKey(const ValueKey('quote-end-flow'))).right;
        for (final character in ['里', '？', '”']) {
          final rect = tester.getRect(find.text(character));
          expect(rect.center.dy, closeTo(firstLineY, 0.1));
          expect(rect.right, lessThanOrEqualTo(right + 0.1));
        }
        expect(tester.getCenter(find.text('接')).dy, greaterThan(firstLineY));
        await pumpAtWidth(
          quotationWidth + 0.01,
          highlighted: true,
        );
        for (final character in ['里', '？', '”']) {
          expect(
            tester.getCenter(find.text(character)).dy,
            closeTo(firstLineY, 0.1),
          );
          expect(
            tester.widget<Text>(find.text(character)).style!.backgroundColor,
            isNotNull,
          );
        }
        // 真正放不下时整组换行，问号和右引号不能单独出现在下一行。
        await pumpAtWidth(quotationWidth - 0.01);
        final nextLineY = tester.getCenter(find.text('里')).dy;
        expect(nextLineY, greaterThan(tester.getCenter(find.text('鲤')).dy));
        for (final punctuation in ['？', '”']) {
          expect(
            tester.getCenter(find.text(punctuation)).dy,
            closeTo(nextLineY, 0.1),
          );
        }
        for (var index = 0; index < paragraph.text.runes.length; index++) {
          expect(
            find.byKey(ValueKey('narration-character-quote-end-$index')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
