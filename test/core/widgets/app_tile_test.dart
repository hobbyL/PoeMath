import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_tile.dart';

void main() {
  for (final flat in [false, true]) {
    for (final allowTap in [false, true]) {
      testWidgets('尾部开关独立交互，行点击遵循显式设置 flat=$flat allowTap=$allowTap',
          (tester) async {
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
    expect(
      tester.getCenter(find.byType(Switch)).dy,
      closeTo(rowCenter, 0.001),
    );
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
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
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
