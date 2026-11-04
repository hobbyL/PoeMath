import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/widgets/app_widgets.dart';

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

const _empty = AppEmptyState(
  icon: Icons.image_outlined,
  title: '暂时没有可练习的题目',
  description: '请家长在设置中添加或启用看图说话题目。',
);

void main() {
  testWidgets('普通页面在可用区域居中，标题可被辅助技术识别', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(_empty));

    final content = find.descendant(
      of: find.byType(AppEmptyState),
      matching: find.byType(Column),
    );
    expect(tester.getCenter(content).dy, closeTo(300, 1));
    expect(
      tester.getSemantics(find.text('暂时没有可练习的题目')),
      matchesSemantics(label: '暂时没有可练习的题目', isHeader: true),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('窄屏大字号和矮窗口可滚动到操作，按钮换行后仍可点击', (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var tapped = false;
    await tester.pumpWidget(
      _app(
        AppEmptyState(
          icon: Icons.image_outlined,
          title: _empty.title,
          description: _empty.description,
          actions: [
            FilledButton(onPressed: () {}, child: const Text('AI 出题')),
            OutlinedButton(
              onPressed: () => tapped = true,
              child: const Text('新增题目'),
            ),
          ],
        ),
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byType(OutlinedButton)).dy,
      greaterThan(tester.getTopLeft(find.byType(FilledButton)).dy),
    );
    await tester.ensureVisible(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('可置于列表中，内容自然撑高且保持外层可滚动', (tester) async {
    await tester.pumpWidget(
      _app(ListView(children: const [SizedBox(height: 500), _empty])),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text(_empty.description!).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('SliverFillRemaining 支持固有高度与大字号（$scale）', (tester) async {
      tester.view.physicalSize = const Size(320, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          const CustomScrollView(
            slivers: [
              SliverAppBar(title: Text('表达')),
              SliverFillRemaining(hasScrollBody: false, child: _empty),
            ],
          ),
          textScale: scale,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(_empty.description!));
      await tester.pumpAndSettle();
      expect(find.text(_empty.description!).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
