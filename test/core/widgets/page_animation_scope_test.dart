import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/animated_page_body.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';

List<double> _bodyOpacities(WidgetTester tester) => tester
    .widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(AnimatedPageBody),
        matching: find.byType(FadeTransition),
      ),
    )
    .map((fade) => fade.opacity.value)
    .toList();

Future<void> _startEntrances(WidgetTester tester) async {
  // 先处理 Animate 的零延迟 Timer，再给 controller 一个起始帧。
  await tester.pump(Duration.zero);
  await tester.pump();
}

class _InputProbe extends StatefulWidget {
  const _InputProbe();

  @override
  State<_InputProbe> createState() => _InputProbeState();
}

class _InputProbeState extends State<_InputProbe> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        child: TextField(controller: controller),
      );
}

void main() {
  testWidgets('默认保留逐项淡入与滑入，间距不生成动画组件', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedPageBody(
          children: const [
            Text('第一项'),
            SizedBox(height: SpacingTokens.sm),
            Text('第二项'),
          ],
        ),
      ),
    );
    await _startEntrances(tester);
    expect(_bodyOpacities(tester), [0, 0]);
    await tester.pump(const Duration(milliseconds: 100));
    final values = _bodyOpacities(tester);
    expect(values.first, greaterThan(0));
    expect(values.last, 0);
    await tester.pumpAndSettle();
    expect(_bodyOpacities(tester), [1, 1]);
  });

  testWidgets('关闭时列表和单独实现的延迟入场内容立即完整显示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PageAnimationScope(
          enabled: false,
          child: Column(
            children: [
              Expanded(
                child: AnimatedPageBody(
                  children: const [
                    Text('第一项'),
                    SizedBox(height: SpacingTokens.sm),
                    Text('第二项'),
                  ],
                ),
              ),
              Builder(
                key: const ValueKey('standalone_entrance'),
                builder: (context) => const Text('单独入场')
                    .animatePage(context, delay: const Duration(seconds: 1))
                    .fadeIn(duration: const Duration(milliseconds: 400))
                    .slideY(begin: 0.1, end: 0),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(Duration.zero);
    expect(_bodyOpacities(tester), [1, 1]);
    final standaloneFades = find.descendant(
      of: find.byKey(const ValueKey('standalone_entrance')),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(standaloneFades).opacity.value, 1);
    final standaloneSlide = find.descendant(
      of: find.byKey(const ValueKey('standalone_entrance')),
      matching: find.byType(SlideTransition),
    );
    expect(
      tester.widget<SlideTransition>(standaloneSlide).position.value,
      Offset.zero,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('入场途中关闭立即完成，往返切换保留内容组件和输入', (tester) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          child: AnimatedPageBody(children: const [_InputProbe()]),
          builder: (context, value, child) => PageAnimationScope(
            enabled: value,
            child: child!,
          ),
        ),
      ),
    );
    await _startEntrances(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_bodyOpacities(tester).single, inExclusiveRange(0, 1));
    final state = tester.state<_InputProbeState>(find.byType(_InputProbe));
    state.controller.text = '保留输入';
    enabled.value = false;
    await tester.pump();
    expect(_bodyOpacities(tester), [1]);
    expect(tester.state(find.byType(_InputProbe)), same(state));
    expect(state.controller.text, '保留输入');
    enabled.value = true;
    await tester.pump();
    expect(_bodyOpacities(tester), [0]);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(_InputProbe)), same(state));
    expect(state.controller.text, '保留输入');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
