import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/core/widgets/app_tile_group.dart';
import 'package:poemath/features/home/home_section.dart';

void main() {
  for (final flat in [false, true]) {
    testWidgets('卡片箭头使用首页右边距，左侧内容保留原留白 flat=$flat', (tester) async {
      final theme = AppTheme.resolve(
        subject: AppSubject.poem,
        brightness: Brightness.light,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(SpacingTokens.xl),
              child: SizedBox(
                width: 320,
                child: AppTile(
                  flat: flat,
                  icon: Icons.history_outlined,
                  iconColor: theme.colorScheme.primary,
                  title: '学习记录',
                  subtitle: '',
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final tile = tester.getRect(find.byType(AppTile));
      final icon = tester.getRect(find.byIcon(Icons.history_outlined));
      final arrow = tester.getRect(find.byIcon(Icons.chevron_right));
      final edgeInset = flat ? SpacingTokens.sm : SpacingTokens.md;
      expect(icon.left - tile.left, closeTo(edgeInset, .01));
      expect(tile.right - arrow.right, closeTo(8, .01));
      expect(tester.takeException(), isNull);
    });
  }

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('导航箭头对齐首页且独立操作可点击 $subject $brightness', (tester) async {
        addTearDown(tester.view.reset);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 1600);
        final theme = AppTheme.resolve(
          subject: subject,
          brightness: brightness,
        );
        var opened = 0, played = 0, toggled = 0, removed = 0;
        for (final width in [288.0, 800.0]) {
          for (final scale in [1.0, 2.0]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: SizedBox(
                        width: width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            HomeEntryGroup(
                              children: [
                                AppTile(
                                  key: const ValueKey('home-reference'),
                                  flat: theme.appearance.ink,
                                  icon: Icons.history_outlined,
                                  iconColor: theme.colorScheme.primary,
                                  title: '继续学习',
                                  subtitle: '首页卡片',
                                  onTap: () {},
                                ),
                              ],
                            ),
                            AppTile(
                              key: const ValueKey('word'),
                              layout: AppTileLayout.stacked,
                              iconColor: theme.colorScheme.primary,
                              title: 'grandmother',
                              subtitle: '（外）祖母',
                              trailingPrefix: IconButton(
                                tooltip: '朗读单词',
                                onPressed: () => played++,
                                icon: const Icon(Icons.volume_up_outlined),
                              ),
                              onTap: () => opened++,
                            ),
                            AppTileGroup(
                              children: [
                                AppTile(
                                  key: const ValueKey('settings'),
                                  icon: Icons.settings_outlined,
                                  iconColor: theme.colorScheme.primary,
                                  title: '设置',
                                  subtitle: '',
                                  onTap: () {},
                                ),
                              ],
                            ),
                            AppTile(
                              key: const ValueKey('flat'),
                              flat: true,
                              iconColor: theme.colorScheme.primary,
                              title: '目录条目',
                              subtitle: '',
                              onTap: () {},
                            ),
                            AppTile(
                              key: const ValueKey('branch'),
                              flat: true,
                              iconColor: theme.colorScheme.primary,
                              title: '可展开的目录',
                              subtitle: '',
                              onTrailingTap: () => toggled++,
                              trailingTooltip: '展开目录',
                              onTap: () {},
                            ),
                            AppTile(
                              key: const ValueKey('history'),
                              iconColor: theme.colorScheme.primary,
                              title: '完整的学习记录说明',
                              titleWrap: true,
                              subtitle: '',
                              trailingText: '2026/11/25',
                              trailingTextMaxLines: null,
                              onTap: () {},
                            ),
                            AppTile(
                              key: const ValueKey('thumbnail'),
                              leading: const SizedBox.expand(),
                              leadingEdgeWidth: SpacingTokens.xxl,
                              iconColor: theme.colorScheme.primary,
                              title: '带题图的内容',
                              subtitle: '内容说明',
                              onTap: () {},
                            ),
                            AppTile(
                              key: const ValueKey('delete'),
                              iconColor: theme.colorScheme.primary,
                              title: '编辑作答项',
                              subtitle: '',
                              trailingAction: IconButton(
                                tooltip: '移除作答项',
                                onPressed: () => removed++,
                                icon: const Icon(Icons.delete_outline),
                              ),
                              onTap: () {},
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            Rect arrowRect(String key) => tester.getRect(
              find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byIcon(Icons.chevron_right),
              ),
            );
            final reference = arrowRect('home-reference');
            expect(
              tester
                      .getRect(find.byKey(const ValueKey('home-reference')))
                      .right -
                  reference.right,
              closeTo(8, .01),
            );
            for (final key in [
              'word',
              'settings',
              'flat',
              'branch',
              'history',
              'thumbnail',
              'delete',
            ]) {
              final arrow = arrowRect(key);
              expect(
                arrow.right,
                closeTo(reference.right, .01),
                reason: '$key $width $scale',
              );
              expect(arrow.size, const Size(24, 24));
            }
            expect(
              tester
                  .getSize(
                    find.widgetWithIcon(IconButton, Icons.volume_up_outlined),
                  )
                  .width,
              greaterThanOrEqualTo(44),
            );
            expect(
              tester
                  .getSize(
                    find.ancestor(
                      of: find.byTooltip('展开目录'),
                      matching: find.byType(IconButton),
                    ),
                  )
                  .width,
              greaterThanOrEqualTo(44),
            );
            final before = (opened, played, toggled, removed);
            await tester.ensureVisible(find.text('grandmother'));
            expect(
              tester.getRect(find.text('（外）祖母')).bottom,
              lessThan(tester.getRect(find.byTooltip('朗读单词')).top),
            );
            await tester.tap(find.text('grandmother'));
            await tester.tap(find.byTooltip('朗读单词'));
            await tester.tapAt(arrowRect('word').center);
            await tester.ensureVisible(find.byTooltip('展开目录'));
            await tester.tap(find.byTooltip('展开目录'));
            await tester.ensureVisible(find.byTooltip('移除作答项'));
            await tester.tap(find.byTooltip('移除作答项'));
            expect(
              (opened, played, toggled, removed),
              (before.$1 + 2, before.$2 + 1, before.$3 + 1, before.$4 + 1),
            );
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  }

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
