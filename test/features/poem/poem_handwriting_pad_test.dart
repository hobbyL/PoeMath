// test/features/poem/poem_handwriting_pad_test.dart
//
// 诗词默写手写板契约：
// - 有笔顺数据：写对自动回调通过（每字只回调一次）；
// - 几何错误逐笔标红，笔数不符只给笔数提示，可重写；
// - 核对不过可「就这样」带错推进；
// - 无笔顺数据：降级「下一个」直通；
// - 空笔迹不可提交。

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/poem_theme.dart';
import 'package:poemath/domain/writing_stroke_data.dart';
import 'package:poemath/features/poem/widgets/poem_handwriting_pad.dart';
import 'package:poemath/features/poem/widgets/poem_stroke_numbers.dart';
import 'package:poemath/features/textbook/writing/writing_canvas.dart';

import '../../helpers/theme_contrast.dart';

const _padImageKey = ValueKey('poem-pad-image');

/// 单笔参考字「一」（横向中线一笔）。
CharacterStrokeData _hengData() => const CharacterStrokeData(
  character: '一',
  strokes: ['M 256 512 L 768 512'],
  medians: [
    [math.Point<double>(256, 512), math.Point<double>(768, 512)],
  ],
);

/// 三笔参考字，用上下两笔的不同错误验证着色与逐笔原因。
const _threeStrokeData = CharacterStrokeData(
  character: '三',
  strokes: [
    'M 256 256 L 768 256',
    'M 256 512 L 768 512',
    'M 256 768 L 768 768',
  ],
  medians: [
    [math.Point<double>(256, 256), math.Point<double>(768, 256)],
    [math.Point<double>(256, 512), math.Point<double>(768, 512)],
    [math.Point<double>(256, 768), math.Point<double>(768, 768)],
  ],
);

/// 验证实际画出的笔迹颜色，覆盖结果到画布再到画笔的完整链路。
Future<void> _expectInkColors(
  WidgetTester tester,
  Map<Offset, Color> expected,
) async {
  final boundaryFinder = find.byKey(_padImageKey);
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  final origin =
      tester.getTopLeft(find.byKey(const ValueKey('writing-canvas'))) -
      tester.getTopLeft(boundaryFinder);
  final pixels = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return (
        width: image.width,
        bytes: (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
      );
    } finally {
      image.dispose();
    }
  }))!;
  for (final entry in expected.entries) {
    final position = origin + entry.key;
    final offset =
        (position.dy.round() * pixels.width + position.dx.round()) * 4;
    final color = Color.fromARGB(
      pixels.bytes.getUint8(offset + 3),
      pixels.bytes.getUint8(offset),
      pixels.bytes.getUint8(offset + 1),
      pixels.bytes.getUint8(offset + 2),
    );
    expect(color, entry.value, reason: '${entry.key} 处笔迹颜色');
  }
}

void main() {
  Future<void> pumpPad(
    WidgetTester tester, {
    required CharacterStrokeData? strokeData,
    required ValueChanged<PoemHandwrittenChar> onConfirmed,
    PoemHandwrittenChar? initialInk,
    ThemeData? theme,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: _padImageKey,
              child: SingleChildScrollView(
                child: PoemHandwritingPad(
                  character: strokeData?.character ?? '一',
                  strokeData: strokeData,
                  side: 240,
                  initialInk: initialInk,
                  onConfirmed: onConfirmed,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 在画布上写一笔横（从左到右、穿过中线，几何上应判定为正确的「一」）。
  Future<void> dragHeng(WidgetTester tester) async {
    final canvas = find
        .descendant(
          of: find.byType(WritingCanvas),
          matching: find.byType(CustomPaint),
        )
        .first;
    final center = tester.getCenter(canvas);
    final gesture = await tester.startGesture(center + const Offset(-60, 0));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('写一笔横核对通过且只回调一次（笔迹随结果上交）', (tester) async {
    var confirmed = 0;
    PoemHandwrittenChar? result;
    await pumpPad(
      tester,
      strokeData: _hengData(),
      onConfirmed: (r) {
        confirmed++;
        result = r;
      },
    );

    await dragHeng(tester);
    expect(confirmed, 0, reason: '核对前不应回调');
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    expect(result?.passed, isTrue);
    expect(result?.character, '一');
    expect(result?.strokes, hasLength(1), reason: '笔迹随结果上交');
  });

  testWidgets('单笔方向错误标红，重写后恢复正常颜色并可通过', (tester) async {
    final theme = PoemTheme.light();
    final scheme = theme.colorScheme;
    var confirmed = 0;
    await pumpPad(
      tester,
      theme: theme,
      strokeData: _hengData(),
      initialInk: const PoemHandwrittenChar(
        character: '一',
        strokes: [
          [Offset(180, 120), Offset(60, 120)],
        ],
        passed: false,
      ),
      onConfirmed: (_) => confirmed++,
    );
    await _expectInkColors(tester, {const Offset(90, 120): scheme.onSurface});

    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    expect(confirmed, 0);
    expect(find.text('第 1 笔：方向不太对，请检查行笔方向。'), findsOneWidget);
    expect(find.byKey(const ValueKey('poem-stroke-number-1')), findsOneWidget);
    await _expectInkColors(tester, {const Offset(90, 120): scheme.error});

    await tester.tap(find.text('重写'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 笔：'), findsNothing);
    expect(find.byType(PoemStrokeNumbers), findsNothing);
    expect(
      tester.widget<WritingCanvas>(find.byType(WritingCanvas)).strokes,
      isEmpty,
    );
    await dragHeng(tester);
    await _expectInkColors(tester, {const Offset(90, 120): scheme.onSurface});
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
  });

  for (final theme in [PoemTheme.light(), PoemTheme.dark()]) {
    testWidgets('${theme.brightness} 多笔错误分别说明原因，忽略轻点仍定位正确', (tester) async {
      final scheme = theme.colorScheme;
      var confirmed = 0;
      await pumpPad(
        tester,
        theme: theme,
        strokeData: _threeStrokeData,
        initialInk: const PoemHandwrittenChar(
          character: '三',
          strokes: [
            [Offset(20, 20)], // 轻点不参与核对，错笔下标需映射回原笔迹。
            [Offset(180, 60), Offset(60, 60)],
            [Offset(60, 120), Offset(180, 120)],
            [Offset(108, 180), Offset(180, 180)],
          ],
          passed: false,
        ),
        onConfirmed: (_) => confirmed++,
      );
      await tester.tap(find.text('核对'));
      await tester.pumpAndSettle();

      expect(confirmed, 0);
      const message =
          '第 1 笔：方向不太对，请检查行笔方向。\n'
          '第 3 笔：起笔位置不太对，请调整下笔的位置。';
      expect(find.text(message), findsOneWidget);
      final numberOne = find.byKey(const ValueKey('poem-stroke-number-1'));
      final numberThree = find.byKey(const ValueKey('poem-stroke-number-3'));
      expect(find.byType(PoemStrokeNumbers), findsOneWidget);
      expect(numberOne, findsOneWidget);
      expect(numberThree, findsOneWidget);
      expect(find.byKey(const ValueKey('poem-stroke-number-2')), findsNothing);
      expect(find.byKey(const ValueKey('poem-stroke-number-4')), findsNothing);
      final canvasTop = tester.getTopLeft(find.byType(WritingCanvas)).dy;
      expect(tester.getCenter(numberOne).dy - canvasTop, closeTo(60, 40));
      expect(tester.getCenter(numberThree).dy - canvasTop, closeTo(180, 40));
      expectReadableText(
        tester,
        find.descendant(of: numberOne, matching: find.text('1')),
      );
      expectReadableText(
        tester,
        find.descendant(of: numberThree, matching: find.text('3')),
      );
      await _expectInkColors(tester, {
        const Offset(90, 60): scheme.error,
        const Offset(90, 120): scheme.onSurface,
        const Offset(150, 180): scheme.error,
      });
      expect(
        contrastRatio(scheme.error, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(3),
      );
      expectReadableText(tester, find.text(message));
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('writing-canvas')),
                  )
                  .painter!
              as TianziGridPainter;
      expect(painter.referenceStrokes, isNull, reason: '默写不能展示答案字形');
      expect(painter.showCharacter, isNull);

      // 继续落笔后旧核对结果失效，已写笔画全部恢复普通墨色。
      await dragHeng(tester);
      expect(find.text(message), findsNothing);
      expect(find.byType(PoemStrokeNumbers), findsNothing);
      await _expectInkColors(tester, {
        const Offset(90, 60): scheme.onSurface,
        const Offset(90, 120): scheme.onSurface,
        const Offset(150, 180): scheme.onSurface,
      });
      expect(confirmed, 0);
    });
  }

  testWidgets('窄屏双倍字号可滚动查看逐笔原因和重写操作', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const initialInk = PoemHandwrittenChar(
      character: '三',
      strokes: [
        [Offset(180, 60), Offset(60, 60)],
        [Offset(60, 120), Offset(180, 120)],
        [Offset(108, 180), Offset(180, 180)],
      ],
      passed: false,
    );
    await pumpPad(
      tester,
      strokeData: _threeStrokeData,
      initialInk: initialInk,
      onConfirmed: (_) {},
    );
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();

    // 已有反馈时调大系统字号，原因自然换行，底部操作仍可滚动触达。
    await pumpPad(
      tester,
      strokeData: _threeStrokeData,
      initialInk: initialInk,
      textScale: 2,
      onConfirmed: (_) {},
    );
    expect(
      find.text(
        '第 1 笔：方向不太对，请检查行笔方向。\n'
        '第 3 笔：起笔位置不太对，请调整下笔的位置。',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('重写'));
    await tester.pumpAndSettle();
    expect(find.text('重写').hitTestable(), findsOneWidget);
    expect(find.text('就这样').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('笔数不符显示教练提示，可重写后再核对', (tester) async {
    var calls = 0;
    await pumpPad(tester, strokeData: _hengData(), onConfirmed: (_) => calls++);

    // 写两笔：参考只有一笔 → 笔数不符提示。
    await dragHeng(tester);
    await dragHeng(tester);
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    expect(calls, 0, reason: '笔数不符不通过');
    expect(find.textContaining('有 1 笔'), findsOneWidget);
    expect(find.byType(PoemStrokeNumbers), findsNothing);
    final scheme = Theme.of(tester.element(find.byType(WritingCanvas)))
        .colorScheme;
    await _expectInkColors(tester, {const Offset(90, 120): scheme.onSurface});

    // 清空后写一笔正确的 → 核对通过。
    await tester.tap(find.text('重写'));
    await tester.pumpAndSettle();
    await dragHeng(tester);
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('核对不过可「就这样」带错推进（checked=false）', (tester) async {
    PoemHandwrittenChar? result;
    await pumpPad(
      tester,
      strokeData: _hengData(),
      onConfirmed: (r) => result = r,
    );

    // 两笔 → 笔数不符。
    await dragHeng(tester);
    await dragHeng(tester);
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    expect(find.textContaining('有 1 笔'), findsOneWidget);

    await tester.tap(find.text('就这样'));
    await tester.pumpAndSettle();
    expect(result?.passed, isFalse);
    expect(result?.checked, isFalse);
  });

  testWidgets('无笔顺数据：写一笔后「下一个」直通（checked=false）', (tester) async {
    PoemHandwrittenChar? result;
    await pumpPad(tester, strokeData: null, onConfirmed: (r) => result = r);

    expect(find.text('下一个'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '下一个'))
          .onPressed,
      isNull,
      reason: '空笔迹不可提交',
    );

    await dragHeng(tester);
    await tester.tap(find.text('下一个'));
    await tester.pumpAndSettle();
    expect(result?.passed, isTrue);
    expect(result?.checked, isFalse);
  });
}
