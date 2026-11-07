import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_tile.dart';

void main() {
  testWidgets('两行摘要与换行时间保持左右布局，未配置的列表行保留单行默认值', (tester) async {
    final theme = AppTheme.resolve(
      subject: AppSubject.poem,
      brightness: Brightness.light,
    );
    const answer = '公园里的孩子正在放风筝，小狗在旁边开心地跑来跑去，天空中飘着白云。';
    const date = '2026/01/01 14:30';
    var taps = 0;
    Future<void> pumpTile({required bool twoLines}) => tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: AppTile(
              iconColor: theme.colorScheme.primary,
              title: answer,
              titleMaxLines: twoLines ? 2 : null,
              subtitle: '',
              trailingText: date,
              trailingTextMaxLines: twoLines ? null : 1,
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    await pumpTile(twoLines: true);
    final answerRect = tester.getRect(find.text(answer));
    final dateRect = tester.getRect(find.text(date));
    final cardCenterY = tester.getCenter(find.byType(AppTile)).dy;
    expect(answerRect.center.dy, closeTo(cardCenterY, 0.01));
    expect(dateRect.center.dy, closeTo(cardCenterY, 0.01));
    expect(
      tester.getCenter(find.byIcon(Icons.chevron_right)).dy,
      closeTo(cardCenterY, 0.01),
    );
    expect(
      tester.renderObject<RenderParagraph>(find.text(answer)).didExceedMaxLines,
      isTrue,
    );
    expect(
      tester.renderObject<RenderParagraph>(find.text(date)).didExceedMaxLines,
      isFalse,
    );
    expect(answerRect.right, lessThan(dateRect.left));
    expect(
      dateRect.right,
      lessThanOrEqualTo(tester.getRect(find.byIcon(Icons.chevron_right)).left),
    );
    await tester.tap(find.text(date));
    expect(taps, 1);
    await pumpTile(twoLines: false);
    expect(
      tester.getSize(find.text(answer)).height,
      lessThan(answerRect.height),
    );
    expect(tester.getSize(find.text(date)).height, lessThan(dateRect.height));
    expect(
      tester.getCenter(find.text(answer)).dy,
      closeTo(tester.getCenter(find.byType(AppTile)).dy, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  for (final flat in [false, true]) {
    for (final allowTap in [false, true]) {
      testWidgets('尾部开关独立交互，行点击遵循显式设置 flat=$flat allowTap=$allowTap', (
        tester,
      ) async {
        var rowCalls = 0;
        var switchCalls = 0;
        var enabled = true;
        final theme = AppTheme.resolve(
          subject: AppSubject.poem,
          brightness: Brightness.light,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => AppTile(
                  flat: flat,
                  allowTapWithTrailing: allowTap,
                  iconColor: theme.colorScheme.primary,
                  title: '题目详情',
                  subtitle: '独立启用选择',
                  onTap: () => rowCalls++,
                  trailing: Switch(
                    value: enabled,
                    onChanged: (value) {
                      switchCalls++;
                      setState(() => enabled = value);
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('题目详情'));
        await tester.pump();
        expect(rowCalls, allowTap ? 1 : 0);
        expect(switchCalls, 0);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(enabled, isFalse);
        expect(switchCalls, 1);
        expect(rowCalls, allowTap ? 1 : 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('自定义前导内容应替换图标，并和尾部开关垂直居中', (tester) async {
    const previewKey = ValueKey('preview');
    final theme = AppTheme.resolve(
      subject: AppSubject.poem,
      brightness: Brightness.light,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AppTile(
            icon: Icons.image_outlined,
            leading: const SizedBox(
              key: previewKey,
              width: 64,
              height: 48,
              child: Icon(Icons.landscape_outlined),
            ),
            iconColor: theme.colorScheme.primary,
            title: '公园里的风筝',
            subtitle: '入门 · 人物与动作\n观察人物、地点和动作',
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(find.byKey(previewKey), findsOneWidget);
    expect(tester.getSize(find.byKey(previewKey)), const Size(64, 48));
    expect(
      tester.getTopLeft(find.text('公园里的风筝')).dx,
      tester.getTopRight(find.byKey(previewKey)).dx + SpacingTokens.md,
    );
    final rowCenter = tester.getCenter(find.byType(AppTile)).dy;
    expect(
      tester.getCenter(find.byKey(previewKey)).dy,
      closeTo(rowCenter, 0.001),
    );
    expect(tester.getCenter(find.byType(Switch)).dy, closeTo(rowCenter, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('贴边前导内容应铺满卡片高度，附注与大字号不影响开关居中', (tester) async {
    const previewKey = ValueKey('edge-preview');
    final theme = AppTheme.resolve(
      subject: AppSubject.poem,
      brightness: Brightness.light,
    );
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: AppTile(
            leading: ColoredBox(
              key: previewKey,
              color: theme.colorScheme.primary,
            ),
            leadingEdgeWidth: 64,
            iconColor: theme.colorScheme.primary,
            title: '公园里的风筝',
            titleSuffix: '3题',
            subtitle: '入门 · 人物与动作\n观察人物、地点和动作',
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
        ),
      ),
    );

    final cardRect = tester.getRect(find.byType(AppTile));
    final previewRect = tester.getRect(find.byKey(previewKey));
    expect(
      previewRect,
      Rect.fromLTWH(cardRect.left, cardRect.top, 64, cardRect.height),
    );
    expect(
      tester.getTopLeft(find.text('公园里的风筝')).dx,
      previewRect.right + SpacingTokens.md,
    );
    expect(
      tester.getCenter(find.byType(Switch)).dy,
      closeTo(cardRect.center.dy, 0.001),
    );
    expect(tester.takeException(), isNull);
  });
}
