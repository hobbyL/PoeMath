import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_illustration.dart';
import 'package:poemath/features/profile/picture_story_management_page.dart';

import '../../helpers/hive_test_helper.dart';

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
}) async {
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

void _verifyPromptLayout(WidgetTester tester) {
  for (final prompt in PictureStoryCatalog.prompts) {
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
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForWidgetTesting);

  testWidgets('题库插图应贴住卡片左侧并铺满高度，开关居中', (tester) async {
    await _pumpPage(tester);

    _verifyPromptLayout(tester);
  });

  testWidgets('窄屏和两倍字号下插图仍应贴边，开关居中且内容不溢出', (tester) async {
    await _pumpPage(tester, size: const Size(320, 900), textScale: 2);

    _verifyPromptLayout(tester);
  });

  testWidgets('切换启用状态应保存并刷新开关与表达题目数量', (tester) async {
    final repository = _TrackingPictureStoryRepository();
    final container = await _pumpPage(tester, repository: repository);
    const title = '公园里的风筝';
    const promptId = 'kite-in-the-park';
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
