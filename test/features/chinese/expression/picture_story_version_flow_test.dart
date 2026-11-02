import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_history_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_practice_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';

import '../../../helpers/hive_test_helper.dart';
import '../../../helpers/parent_access_test_helper.dart';
import '../../../helpers/picture_story_fixture.dart';

/// 页面自动创建草稿时仍走真实仓储，I/O 固定在测试 setUp 的真实异步域。
class _Repository extends PictureStoryRepository {
  _Repository(this.ioZone);
  final Zone ioZone;
  Future<void>? lastRecordSave;
  @override
  Future<void> save(
    PictureStoryPracticeRecord record, {
    void Function()? check,
  }) =>
      lastRecordSave = ioZone.run<Future<void>>(
        () => super.save(record, check: check),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Repository repository;
  final channels = <String>{};
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockChannel(String name) {
    channels.add(name);
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }

  setUpAll(() {
    mockChannel('xyz.luan/audioplayers.global');
    mockChannel('xyz.luan/audioplayers.global/events');
    channels.add('xyz.luan/audioplayers');
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'), (call) async {
      if (call.method == 'create') {
        final id =
            (call.arguments as Map<dynamic, dynamic>)['playerId'] as String;
        mockChannel('xyz.luan/audioplayers/events/$id');
      }
      if (call.method == 'getCurrentPosition' || call.method == 'getDuration') {
        return 0;
      }
      return null;
    });
  });
  tearDownAll(() {
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
  });
  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    await unlockParentForTesting();
    repository = _Repository(Zone.current);
  });
  tearDown(() async {
    lockParentForTesting();
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  Future<ProviderContainer> pumpPage(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(420, 1000),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
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
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await drainHiveWritesForTesting(tester);
  }

  testWidgets('练习开始冻结题目，编辑后当前练习仍为 v1，下一次使用 v2', (tester) async {
    final first = (await tester.runAsync(
      () => repository.savePrompt(
        prompt: pictureStoryFixture(),
        profileId: 'default',
      ),
    ))!;
    await pumpPage(tester, PictureStoryPracticePage(promptId: first.id));
    await tester.runAsync(
      () => repository.lastRecordSave!.timeout(const Duration(seconds: 5)),
    );
    expect(find.text(first.title), findsOneWidget);
    expect(HiveBoxes.pictureStoryPractice.values.single.promptVersion, 1);
    final second = (await tester.runAsync(
      () => repository.savePrompt(
        prompt: first.copyWith(title: '第二版题目', reference: '第二版参考表达'),
        original: first,
        profileId: 'default',
      ),
    ))!;
    await tester.pumpAndSettle();
    expect(find.text(first.title), findsOneWidget);
    expect(find.text(second.title), findsNothing);
    expect(HiveBoxes.pictureStoryPractice.values.single.promptVersion, 1);
    expect(tester.takeException(), isNull);
    await unmount(tester);
    await pumpPage(tester, PictureStoryPracticePage(promptId: first.id));
    await tester.runAsync(
      () => repository.lastRecordSave!.timeout(const Duration(seconds: 5)),
    );
    expect(find.text(second.title), findsOneWidget);
    expect(
      HiveBoxes.pictureStoryPractice.values
          .map((record) => record.promptVersion)
          .toList()
        ..sort(),
      [1, 2],
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('历史按保存的题目版本显示完整题图和参考，不替换成当前版本', (tester) async {
    final first = (await tester.runAsync(
      () => repository.savePrompt(
        prompt: pictureStoryFixture(),
        profileId: 'default',
      ),
    ))!;
    await tester.runAsync(
      () => repository.save(
        PictureStoryPracticeRecord(
          id: 'history-v1',
          profileId: 'default',
          promptId: first.id,
          promptVersion: 1,
          startedAt: DateTime(2026),
          status: 'completed',
          segmentsJson: '[]',
          answerText: '小猫坐在窗前。',
        ),
      ),
    );
    await tester.runAsync(
      () => repository.savePrompt(
        prompt: first.copyWith(title: '第二版题目', reference: '新版参考内容'),
        original: first,
        profileId: 'default',
      ),
    );
    await pumpPage(tester, const PictureStoryHistoryPage());
    expect(find.text(first.title), findsOneWidget);
    expect(find.text(first.reference), findsOneWidget);
    expect(find.text('第二版题目'), findsNothing);
    expect(find.text('新版参考内容'), findsNothing);
    expect(find.text('小猫坐在窗前。'), findsOneWidget);
    final image = tester
        .widget<PictureStoryImageView>(find.byType(PictureStoryImageView));
    expect(image.image, first.image);
    expect(image.preview, isFalse);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('删除题目保留正在进行的练习，新入口不再创建草稿', (tester) async {
    final prompt = (await tester.runAsync(
      () => repository.savePrompt(
        prompt: pictureStoryFixture(),
        profileId: 'default',
      ),
    ))!;
    await pumpPage(tester, PictureStoryPracticePage(promptId: prompt.id));
    await tester.runAsync(
      () => repository.lastRecordSave!.timeout(const Duration(seconds: 5)),
    );
    await tester.runAsync(
      () => repository.deletePrompt(prompt: prompt, profileId: 'default'),
    );
    await tester.pumpAndSettle();
    expect(find.text(prompt.title), findsOneWidget);
    expect(HiveBoxes.pictureStoryPractice.values.single.promptVersion, 1);
    expect(tester.takeException(), isNull);
    await unmount(tester);
    await pumpPage(tester, PictureStoryPracticePage(promptId: prompt.id));
    expect(find.text('题目不存在，请返回选择其他题目。'), findsOneWidget);
    expect(HiveBoxes.pictureStoryPractice.length, 1);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('已删除题目的历史仍显示原题图、参考表达和已保存作答', (tester) async {
    final prompt = (await tester.runAsync(
      () => repository.savePrompt(
        prompt: pictureStoryFixture(),
        profileId: 'default',
      ),
    ))!;
    await tester.runAsync(
      () => repository.save(
        PictureStoryPracticeRecord(
          id: 'deleted-prompt-history',
          profileId: 'default',
          promptId: prompt.id,
          promptVersion: prompt.version,
          startedAt: DateTime(2026),
          status: 'completed',
          segmentsJson: '[]',
          answerText: '删除后仍保留的表达',
        ),
      ),
    );
    await tester.runAsync(
      () => repository.deletePrompt(prompt: prompt, profileId: 'default'),
    );
    await pumpPage(tester, const PictureStoryHistoryPage());
    expect(find.text(prompt.title), findsOneWidget);
    expect(find.text(prompt.reference), findsOneWidget);
    expect(find.text('删除后仍保留的表达'), findsOneWidget);
    expect(
      tester
          .widget<PictureStoryImageView>(find.byType(PictureStoryImageView))
          .image,
      prompt.image,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('历史原版本缺失时明确提示，仍展示已保存的表达文字', (tester) async {
    await tester.runAsync(
      () => repository.save(
        PictureStoryPracticeRecord(
          id: 'missing-version',
          profileId: 'default',
          promptId: 'missing-original',
          promptVersion: 9,
          startedAt: DateTime(2026),
          status: 'completed',
          segmentsJson: '[]',
          answerText: '孩子已保存的表达。',
        ),
      ),
    );
    await pumpPage(tester, const PictureStoryHistoryPage());
    expect(find.text('原题版本暂时无法读取，表达与录音记录仍保留。'), findsOneWidget);
    expect(find.text('孩子已保存的表达。'), findsOneWidget);
    expect(find.byType(PictureStoryImageView), findsNothing);
    expect(find.text('参考表达'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('旧内置题只用于历史，题库为空且旧练习入口不创建新草稿', (tester) async {
    final prompt = PictureStoryCatalog.prompts.first;
    await tester.runAsync(
      () => repository.save(
        PictureStoryPracticeRecord(
          id: 'legacy-builtin-history',
          profileId: 'default',
          promptId: prompt.id,
          promptVersion: prompt.version,
          startedAt: DateTime(2026),
          status: 'completed',
          segmentsJson: '[]',
          answerText: '风筝飞到了天空中。',
        ),
      ),
    );
    final container = await pumpPage(tester, const PictureStoryHistoryPage());
    expect(container.read(pictureStoryCatalogProvider), isEmpty);
    expect(container.read(pictureStoryPromptCountProvider), 0);
    expect(find.text(prompt.title), findsOneWidget);
    expect(find.text(prompt.reference), findsOneWidget);
    expect(find.text('风筝飞到了天空中。'), findsOneWidget);
    expect(
      tester
          .widget<PictureStoryImageView>(find.byType(PictureStoryImageView))
          .image,
      prompt.image,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
    await pumpPage(tester, PictureStoryPracticePage(promptId: prompt.id));
    expect(find.text('题目不存在，请返回选择其他题目。'), findsOneWidget);
    expect(HiveBoxes.pictureStoryPractice.length, 1);
    expect(repository.find('legacy-builtin-history')!.answerText, '风筝飞到了天空中。');
    expect(repository.storageSnapshot(), isEmpty);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('不存在的练习入口显示可返回提示，不能创建没有题目的草稿', (tester) async {
    await pumpPage(
      tester,
      const PictureStoryPracticePage(promptId: 'missing-original'),
    );
    expect(find.text('题目不存在，请返回选择其他题目。'), findsOneWidget);
    expect(HiveBoxes.pictureStoryPractice.isEmpty, isTrue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('孩子题库在窄屏大字号下自然展开，新增题立即可见', (tester) async {
    final title = List.filled(10, '窗前的小猫和小鸟').join();
    await tester.runAsync(
      () => repository.savePrompt(
        prompt: pictureStoryFixture(title: title),
        profileId: 'default',
      ),
    );
    final container = await pumpPage(
      tester,
      const PictureStoryPage(),
      size: const Size(320, 1000),
      textScale: 2,
    );
    expect(container.read(pictureStoryPromptCountProvider), 1);
    await tester.scrollUntilVisible(find.text(title), 300);
    expect(find.text(title), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
