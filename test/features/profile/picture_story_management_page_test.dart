import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_illustration.dart';
import 'package:poemath/features/profile/picture_story_management_page.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

final _prompts = [
  pictureStoryFixture(id: 'local-fixture-0'),
  pictureStoryFixture(
    id: 'local-fixture-1',
    title: '窗前的小鸟',
    image: const PictureStoryImage.builtin('umbrella'),
  ),
  pictureStoryFixture(
    id: 'local-fixture-2',
    title: '一起整理房间',
    image: const PictureStoryImage.builtin('toys'),
  ),
];

class _TrackingPictureStoryRepository extends PictureStoryRepository {
  late Future<void> lastWrite;

  @override
  Future<void> setEnabled(String promptId, bool enabled) {
    return lastWrite = super.setEnabled(promptId, enabled);
  }
}

Future<ProviderContainer> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(420, 800),
  double textScale = 1,
  PictureStoryRepository? repository,
  bool withPrompts = true,
}) async {
  if (withPrompts) {
    await tester.runAsync(() async {
      for (final prompt in _prompts) {
        await PictureStoryRepository().savePrompt(
          prompt: prompt,
          profileId: 'default',
        );
      }
    });
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      if (repository != null)
        pictureStoryRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.resolve(
          subject: AppSubject.poem,
          brightness: Brightness.light,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const PictureStoryManagementPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _switchOf(String title) => find.descendant(
      of: find.widgetWithText(AppTile, title),
      matching: find.byType(Switch),
    );

List<Rect> _promptRects(WidgetTester tester) => [
      for (final prompt in _prompts.reversed)
        tester.getRect(find.widgetWithText(AppTile, prompt.title)),
    ];

void _verifyPromptLayout(WidgetTester tester) {
  for (final prompt in _prompts) {
    final row = find.widgetWithText(AppTile, prompt.title);
    final illustration = find.descendant(
      of: row,
      matching: find.byType(PictureStoryIllustration),
    );
    expect(illustration, findsOneWidget);
    expect(
      tester.widget<PictureStoryIllustration>(illustration).kind,
      prompt.illustration,
    );
    final scene = find.descendant(
      of: illustration,
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(scene), const Size(64, 48));
    final preview = find.byWidget(tester.widget<AppTile>(row).leading!);
    final rowRect = tester.getRect(row);
    expect(
      tester.getRect(preview),
      Rect.fromLTWH(rowRect.left, rowRect.top, 64, rowRect.height),
    );
    expect(
      tester.getCenter(_switchOf(prompt.title)).dy,
      closeTo(rowRect.center.dy, 0.001),
    );
  }
  expect(find.byIcon(Icons.image_outlined), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
  });
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForWidgetTesting();
  });

  testWidgets('初始题库为空且可新增或AI出题，不展示内置题目', (tester) async {
    final container = await _pumpPage(tester, withPrompts: false);
    expect(find.byType(AppTile), findsNothing);
    expect(find.text('题库里还没有题目，点击右上角「新增题目」添加。'), findsOneWidget);
    expect(find.byTooltip('新增题目'), findsOneWidget);
    expect(find.byTooltip('AI 出题'), findsOneWidget);
    expect(container.read(pictureStoryCatalogProvider), isEmpty);
    expect(container.read(pictureStoryPromptCountProvider), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('题库最新入库的题目在前，插图贴住卡片左侧并铺满高度，开关居中', (tester) async {
    await _pumpPage(tester);

    _verifyPromptLayout(tester);
    final rects = _promptRects(tester);
    for (var index = 1; index < rects.length; index++) {
      expect(rects[index].left, rects.first.left);
      expect(rects[index].width, rects.first.width);
      expect(
        rects[index].top,
        closeTo(rects[index - 1].bottom + SpacingTokens.sm, 0.001),
      );
    }
  });

  testWidgets('窄屏和两倍字号下插图仍应贴边，开关居中且内容不溢出', (tester) async {
    await _pumpPage(tester, size: const Size(320, 900), textScale: 2);

    _verifyPromptLayout(tester);
  });

  testWidgets('平板宽度下题库应展示两列，末行卡片保持同宽', (tester) async {
    await _pumpPage(tester, size: const Size(800, 800));

    _verifyPromptLayout(tester);
    final rects = _promptRects(tester);
    final first = rects[0];
    final second = rects[1];
    final last = rects[2];
    expect(second.top, first.top);
    expect(second.height, first.height);
    expect(second.width, closeTo(first.width, 0.001));
    expect(second.left, closeTo(first.right + SpacingTokens.sm, 0.001));
    expect(last.left, first.left);
    expect(last.width, closeTo(first.width, 0.001));
    expect(last.top, closeTo(first.bottom + SpacingTokens.sm, 0.001));
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('宽屏题库应展示三列，同排等高且字号 $textScale 下不溢出', (tester) async {
      await _pumpPage(
        tester,
        size: const Size(900, 700),
        textScale: textScale,
      );

      _verifyPromptLayout(tester);
      final rects = _promptRects(tester);
      for (var index = 1; index < rects.length; index++) {
        expect(rects[index].top, rects.first.top);
        expect(rects[index].height, rects.first.height);
        expect(rects[index].width, closeTo(rects.first.width, 0.001));
        expect(
          rects[index].left,
          closeTo(rects[index - 1].right + SpacingTokens.sm, 0.001),
        );
      }
    });
  }

  testWidgets('切换启用状态应保存并刷新开关与表达题目数量', (tester) async {
    final repository = _TrackingPictureStoryRepository();
    final container = await _pumpPage(
      tester,
      size: const Size(900, 700),
      repository: repository,
    );
    const title = '窗前的小猫';
    const promptId = 'local-fixture-0';
    final control = _switchOf(title);

    expect(tester.widget<Switch>(control).value, isTrue);
    expect(container.read(pictureStoryPromptCountProvider), 3);

    await tester.runAsync(() async {
      await tester.tap(control);
      await repository.lastWrite;
    });
    await tester.pumpAndSettle();

    expect(repository.isEnabled(promptId), isFalse);
    expect(tester.widget<Switch>(control).value, isFalse);
    expect(container.read(pictureStoryPromptCountProvider), 2);

    await tester.runAsync(() async {
      await tester.tap(control);
      await repository.lastWrite;
    });
    await tester.pumpAndSettle();

    expect(repository.isEnabled(promptId), isTrue);
    expect(tester.widget<Switch>(control).value, isTrue);
    expect(container.read(pictureStoryPromptCountProvider), 3);
    expect(tester.takeException(), isNull);
    await drainHiveWritesForTesting(tester);
  });
}
