// test/core/widgets/auto_fit_line_test.dart
//
// AutoFitLine 组件契约：宽度不足整行等比缩小（不换行），宽度充足不缩不放。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/widgets/auto_fit_line.dart';

const _style = TextStyle(fontSize: 24, height: 1.8);

Widget _harness({required double maxWidth, required Widget child}) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('宽度不足时整行等比缩小且保持单行', (tester) async {
    await tester.pumpWidget(
      _harness(
        maxWidth: 120,
        child: const AutoFitLine(
          child: Text('春江潮水连海平海上明月共潮生',
              maxLines: 1, style: _style,),
        ),
      ),
    );

    final textBox = tester.renderObject<RenderBox>(find.byType(Text));
    final fittedBox = tester.renderObject<RenderBox>(find.byType(FittedBox));

    // 子内容保持固有单行尺寸（16 字 × 24px 远超 120，未换行压缩）。
    expect(textBox.size.height, closeTo(24 * 1.8, 0.5));
    expect(textBox.size.width, greaterThan(120));
    // 外框缩到约束内，且高度同比例缩小（等比，非裁剪）。
    expect(fittedBox.size.width, closeTo(120, 0.1));
    expect(fittedBox.size.height, lessThan(textBox.size.height));
  });

  testWidgets('宽度充足时保持原尺寸不放大', (tester) async {
    await tester.pumpWidget(
      _harness(
        maxWidth: 800,
        child: const AutoFitLine(
          child: Text('春江潮水连海平海上明月共潮生',
              maxLines: 1, style: _style,),
        ),
      ),
    );

    final textBox = tester.renderObject<RenderBox>(find.byType(Text));
    final fittedBox = tester.renderObject<RenderBox>(find.byType(FittedBox));

    // 缩放比例为 1：外框 == 子内容固有尺寸（不放大到 800，也不缩小）。
    expect(fittedBox.size.width, closeTo(textBox.size.width, 0.1));
    expect(fittedBox.size.height, closeTo(textBox.size.height, 0.1));
    expect(fittedBox.size.width, lessThan(800));
  });

  testWidgets('短内容在宽容器中不被拉伸放大', (tester) async {
    await tester.pumpWidget(
      _harness(
        maxWidth: 600,
        child: const AutoFitLine(child: Text('床', style: _style)),
      ),
    );

    final textBox = tester.renderObject<RenderBox>(find.byType(Text));
    final fittedBox = tester.renderObject<RenderBox>(find.byType(FittedBox));

    expect(fittedBox.size.width, closeTo(textBox.size.width, 0.1));
    expect(fittedBox.size.width, lessThan(600));
  });
}
