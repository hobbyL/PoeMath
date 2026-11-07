import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/data/models/picture_story_evaluation.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/picture_story_history_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_record_detail_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_practice_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_review_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';

import '../../../helpers/hive_test_helper.dart';
import '../../../helpers/parent_access_test_helper.dart';
import '../../../helpers/picture_story_fixture.dart';
import '../../../helpers/picture_story_feedback_fixture.dart';

/// 页面自动创建草稿时仍走真实仓储，I/O 固定在测试 setUp 的真实异步域。
class _Repository extends PictureStoryRepository {
  _Repository(this.ioZone);
  final Zone ioZone;
  Future<void>? lastRecordSave;
  @override
  Future<void> save(
    PictureStoryPracticeRecord record, {
    void Function()? check,
  }) => lastRecordSave = ioZone.run<Future<void>>(
    () => super.save(record, check: check),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Repository repository;
  final channels = <String>{};
  final audioCalls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockChannel(String name) {
    channels.add(name);
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }

  setUpAll(() async {
    mockChannel('xyz.luan/audioplayers.global');
    mockChannel('xyz.luan/audioplayers.global/events');
    channels.add('xyz.luan/audioplayers');
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        audioCalls.add(call.method);
        if (call.method == 'create') {
          final id =
              (call.arguments as Map<dynamic, dynamic>)['playerId'] as String;
          mockChannel('xyz.luan/audioplayers/events/$id');
        }
        if (call.method == 'setSourceUrl') {
          final id =
              (call.arguments as Map<dynamic, dynamic>)['playerId'] as String;
          ServicesBinding.instance.channelBuffers.push(
            'xyz.luan/audioplayers/events/$id',
            const StandardMethodCodec().encodeSuccessEnvelope({
              'event': 'audio.onPrepared',
              'value': true,
            }),
            (_) {},
          );
        }
        if (call.method == 'getCurrentPosition' ||
            call.method == 'getDuration') {
          return 0;
        }
        return null;
      },
    );
    // 全局初始化 Future 不能属于某个用例的 FakeAsync 域，否则后续 stop 会挂起。
    await AudioPlayer.global.ensureInitialized();
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
    audioCalls.clear();
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
      overrides: [pictureStoryRepositoryProvider.overrideWithValue(repository)],
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

  GoRouter historyRouter({String initialLocation = '/test-expression'}) {
    final production = createAppRouter();
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/test-expression',
          builder: (_, _) => const PictureStoryPage(),
        ),
        for (final route in production.configuration.routes)
          if (route is GoRoute &&
              {
                AppRoutes.pictureStoryHistory,
                AppRoutes.pictureStoryPromptHistory,
                AppRoutes.pictureStoryRecordDetail,
                AppRoutes.pictureStoryPractice,
              }.contains(route.path))
            route,
      ],
    );
    addTearDown(production.dispose);
    addTearDown(router.dispose);
    return router;
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
    final router = historyRouter(
      initialLocation: AppRoutes.pictureStoryHistory,
    );
    await pumpPage(tester, Router.withConfig(config: router));
    await tester.tap(find.text('小猫坐在窗前。'));
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryImageView), findsNothing);
    await tester.tap(find.byTooltip('查看题目'));
    await tester.pumpAndSettle();
    expect(find.text(first.title), findsOneWidget);
    expect(find.text(first.reference), findsOneWidget);
    expect(find.text('第二版题目'), findsNothing);
    expect(find.text('新版参考内容'), findsNothing);
    expect(find.text('小猫坐在窗前。'), findsOneWidget);
    final image = tester.widget<PictureStoryImageView>(
      find.byType(PictureStoryImageView),
    );
    expect(image.image, first.image);
    expect(image.preview, isFalse);
    final cardRect = tester.getRect(find.byType(ColoredCard).first);
    final imageRect = tester.getRect(find.byType(PictureStoryImageView));
    expect(imageRect.left, closeTo(cardRect.left, 0.01));
    expect(imageRect.top, closeTo(cardRect.top, 0.01));
    expect(imageRect.right, closeTo(cardRect.right, 0.01));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('题目卡片显示完成次数，进入后只展示这道题的多次练习', (tester) async {
    final prompt = (await tester.runAsync(
      () => repository.savePrompt(
        prompt: pictureStoryFixture(title: '同一道题'),
        profileId: 'default',
      ),
    ))!;
    final other = (await tester.runAsync(
      () => repository.savePrompt(
        prompt: pictureStoryFixture(id: 'local-other-prompt', title: '另一道题'),
        profileId: 'default',
      ),
    ))!;
    await tester.runAsync(() async {
      for (final entry in [
        ('practice-one', DateTime(2026, 1, 1, 10, 5), prompt.id),
        ('practice-two', DateTime(2026, 1, 1, 14, 30), prompt.id),
        ('practice-other', DateTime(2026, 1, 1, 17), other.id),
      ]) {
        await repository.save(
          PictureStoryPracticeRecord(
            id: entry.$1,
            profileId: 'default',
            promptId: entry.$3,
            promptVersion: 1,
            startedAt: entry.$2,
            status: 'completed',
            segmentsJson: '[]',
            answerText: entry.$1,
          ),
        );
      }
      await repository.save(
        PictureStoryPracticeRecord(
          id: 'unfinished',
          profileId: 'default',
          promptId: prompt.id,
          promptVersion: 1,
          startedAt: DateTime(2026, 1, 4),
          status: 'draft',
          segmentsJson: '[]',
          answerText: '未完成草稿',
        ),
      );
    });

    final router = historyRouter();
    final semantics = tester.ensureSemantics();
    final container = await pumpPage(tester, Router.withConfig(config: router));
    await tester.scrollUntilVisible(find.text('练习记录 · 2 次'), 250);
    await tester.pumpAndSettle();
    expect(find.text('练习记录 · 2 次'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.text('练习记录 · 2 次'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(find.text('练习记录 · 2 次'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PictureStoryHistoryPage>(find.byType(PictureStoryHistoryPage))
          .promptId,
      prompt.id,
    );
    expect(HiveBoxes.pictureStoryPractice.length, 4);
    expect(find.text('题目练习记录'), findsOneWidget);
    expect(find.text('已完成 2 次练习'), findsNothing);
    expect(find.text(prompt.reference), findsOneWidget);
    expect(find.text('题目与参考表达'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.byType(PictureStoryImageView), findsOneWidget);
    expect(find.textContaining('2026/01/01 14:30'), findsOneWidget);
    expect(find.text('第 2 次练习'), findsNothing);
    expect(find.text('practice-two'), findsOneWidget);
    expect(find.text('practice-other'), findsNothing);
    expect(find.text('未完成草稿'), findsNothing);
    final history = container.read(
      pictureStoryPromptHistoryProvider(prompt.id),
    );
    expect(history.map((r) => r.id), ['practice-two', 'practice-one']);
    await tester.scrollUntilVisible(
      find.text('practice-one'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(PictureStoryHistoryPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('第 1 次练习'), findsNothing);
    expect(find.textContaining('2026/01/01 10:05'), findsOneWidget);
    final older = find.byKey(
      const ValueKey('picture-story-record-practice-one'),
    );
    expect(find.text('修改表达并重新点评'), findsNothing);
    await tester.tap(
      find.descendant(of: older, matching: find.text('practice-one')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PictureStoryRecordDetailPage>(
            find.byType(PictureStoryRecordDetailPage),
          )
          .recordId,
      'practice-one',
    );
    final edit = find.text('修改表达并重新点评');
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(edit));
    for (
      var i = 0;
      i < 50 && find.byType(PictureStoryReviewPage).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PictureStoryReviewPage>(find.byType(PictureStoryReviewPage))
          .recordId,
      'practice-one',
    );
    router.pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();

    // 使用真实重评仓储写入后，卡片次数仍为 2。
    await tester.runAsync(() async {
      final draft = await repository.saveFeedbackDraft(
        repository.find('practice-two')!,
        '重评后的表达',
      );
      final feedback = PictureStoryEvaluation.parse(
        jsonEncode(pictureStoryFeedbackFixture(answer: '重评后的表达')),
        answer: '重评后的表达',
        questionCount: 2,
      );
      await repository.appendFeedback(
        draft,
        feedback.encode(answer: '重评后的表达', prompts: prompt.questions),
        check: () {},
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('练习记录 · 2 次'), findsOneWidget);
    expect(repository.find('practice-two')!.revisions.length, 2);
    await tester.tap(find.byTooltip('全部记录'));
    await tester.pumpAndSettle();
    expect(find.text('practice-other'), findsOneWidget);
    expect(find.text('第 1 次练习'), findsNothing);
    expect(find.text('第 3 次练习'), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('同一道题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同一道题'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => repository.lastRecordSave!);
    expect(
      tester
          .widget<PictureStoryPracticePage>(
            find.byType(PictureStoryPracticePage),
          )
          .promptId,
      prompt.id,
    );
    expect(HiveBoxes.pictureStoryPractice.length, 5);
    expect(tester.takeException(), isNull);
    semantics.dispose();
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

  testWidgets('同题多次练习保留各自题目版本，未练习的新版不替换历史题图', (tester) async {
    final versions = (await tester.runAsync(() async {
      final first = await repository.savePrompt(
        prompt: pictureStoryFixture(),
        profileId: 'default',
      );
      final second = await repository.savePrompt(
        prompt: first.copyWith(
          title: '雨天的孩子',
          image: const PictureStoryImage.builtin('umbrella'),
          questions: ['孩子拿着什么？'],
          reference: '孩子拿着一把伞。',
        ),
        original: first,
        profileId: 'default',
      );
      for (final prompt in [first, second]) {
        await repository.save(
          PictureStoryPracticeRecord(
            id: 'version-${prompt.version}',
            profileId: 'default',
            promptId: prompt.id,
            promptVersion: prompt.version,
            startedAt: DateTime(2026, 1, prompt.version),
            status: 'completed',
            segmentsJson: '[]',
            answerText: '第 ${prompt.version} 版的表达',
          ),
        );
      }
      await repository.savePrompt(
        prompt: second.copyWith(title: '尚未练习的新题名'),
        original: second,
        profileId: 'default',
      );
      return (first, second);
    }))!;
    final router = historyRouter(
      initialLocation: AppRoutes.pictureStoryPromptHistoryOf(versions.$1.id),
    );
    await pumpPage(tester, Router.withConfig(config: router));
    expect(find.text(versions.$2.title), findsOneWidget);
    expect(find.text(versions.$2.questions.single), findsOneWidget);
    expect(find.text(versions.$2.reference), findsOneWidget);
    expect(find.text('尚未练习的新题名'), findsNothing);
    expect(
      tester
          .widget<PictureStoryImageView>(
            find.byType(PictureStoryImageView).first,
          )
          .image,
      versions.$2.image,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('picture-story-record-version-2')),
        matching: find.byType(PictureStoryImageView),
      ),
      findsNothing,
    );
    final older = find.byKey(const ValueKey('picture-story-record-version-1'));
    await tester.scrollUntilVisible(find.text('第 1 版的表达'), 250);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: older, matching: find.text('第 1 版的表达')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryImageView), findsNothing);
    await tester.tap(find.byTooltip('查看题目'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(versions.$1.reference), 250);
    expect(find.text('练习详情'), findsOneWidget);
    expect(find.text('第 1 次练习'), findsNothing);
    expect(find.text(versions.$1.title), findsOneWidget);
    expect(find.text(versions.$1.questions.first), findsOneWidget);
    expect(find.text(versions.$2.title), findsNothing);
    expect(
      tester
          .widget<PictureStoryImageView>(find.byType(PictureStoryImageView))
          .image,
      versions.$1.image,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('次数与同题记录随完成写入刷新，切换孩子不串记录', (tester) async {
    final prompt = (await tester.runAsync(
      () => repository.savePrompt(
        prompt: pictureStoryFixture(),
        profileId: 'default',
      ),
    ))!;
    Future<void> saveCompleted(String id) => repository.save(
      PictureStoryPracticeRecord(
        id: id,
        profileId: ProfileScope.currentId,
        promptId: prompt.id,
        promptVersion: prompt.version,
        startedAt: DateTime(2026),
        status: 'completed',
        segmentsJson: '[]',
        answerText: id,
      ),
    );
    await tester.runAsync(() => saveCompleted('第一个孩子的表达'));
    final router = historyRouter();
    await pumpPage(tester, Router.withConfig(config: router));
    expect(find.text('练习记录 · 1 次'), findsOneWidget);
    ProfileScope.switchTo('another-child');
    await tester.runAsync(() => repository.setEnabled(prompt.id, true));
    await tester.pumpAndSettle();
    expect(find.text('尚未练习'), findsNothing);
    expect(find.text('练习记录'), findsNothing);
    expect(find.text('练习记录 · 1 次'), findsNothing);
    // 没有记录时卡片不显示入口，原来的记录路由仍能展示空态。
    unawaited(router.push(AppRoutes.pictureStoryPromptHistoryOf(prompt.id)));
    await tester.pumpAndSettle();
    expect(find.text('这道题还没有完成的练习'), findsOneWidget);
    expect(find.text('第一个孩子的表达'), findsNothing);
    await tester.runAsync(() => saveCompleted('第二个孩子的表达'));
    await tester.pumpAndSettle();
    expect(find.text('已完成 1 次练习'), findsNothing);
    expect(find.text('第 1 次练习'), findsNothing);
    expect(find.text('第二个孩子的表达'), findsOneWidget);
    expect(find.text('这道题还没有完成的练习'), findsNothing);
    ProfileScope.switchTo('default');
    await tester.pumpAndSettle();
    expect(find.text('第一个孩子的表达'), findsOneWidget);
    expect(find.text('第二个孩子的表达'), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    await tester.runAsync(() => saveCompleted('第一个孩子再次表达'));
    await tester.pumpAndSettle();
    expect(find.text('练习记录 · 2 次'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final (width, textScale) in [
    (320.0, 2.0),
    (700.0, 1.0),
    (1100.0, 1.0),
  ]) {
    testWidgets('有完成记录才在题图右上角显示可点击入口，宽度 $width，字号 $textScale', (tester) async {
      final prompt = (await tester.runAsync(
        () => repository.savePrompt(
          prompt: pictureStoryFixture(),
          profileId: 'default',
        ),
      ))!;
      final router = historyRouter();
      await pumpPage(
        tester,
        Router.withConfig(config: router),
        size: Size(width, 900),
        textScale: textScale,
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.text('尚未练习'), findsNothing);
      final draft = PictureStoryPracticeRecord(
        id: 'responsive-history',
        profileId: 'default',
        promptId: prompt.id,
        promptVersion: prompt.version,
        startedAt: DateTime(2026),
        status: 'draft',
        segmentsJson: '[]',
        answerText: '孩子放风筝。',
      );
      await tester.runAsync(() => repository.save(draft));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
      draft.status = 'completed';
      draft.feedbackJson = PictureStoryEvaluation.parse(
        jsonEncode(pictureStoryFeedbackFixture(answer: draft.answerText)),
        answer: draft.answerText,
        questionCount: prompt.questions.length,
      ).encode(answer: draft.answerText, prompts: prompt.questions);
      await tester.runAsync(() => repository.save(draft));
      await tester.pumpAndSettle();
      expect(find.text('练习记录 · 1 次').hitTestable(), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      final imageBefore = tester.getRect(find.byType(PictureStoryImageView));
      final entry = tester.getRect(find.byType(FilledButton));
      expect(imageBefore.contains(entry.topLeft), isTrue);
      expect(imageBefore.contains(entry.bottomRight), isTrue);
      expect(entry.top - imageBefore.top, lessThan(imageBefore.height / 4));
      expect(imageBefore.right - entry.right, lessThan(imageBefore.width / 4));
      await tester.tap(find.text('练习记录 · 1 次'));
      await tester.pumpAndSettle();
      expect(find.text(prompt.title), findsOneWidget);
      final image = tester.getRect(find.byType(PictureStoryImageView));
      final card = tester.getRect(find.byType(ColoredCard).first);
      expect(image.left, closeTo(card.left, 0.01));
      expect(image.top, closeTo(card.top, 0.01));
      expect(image.right, closeTo(card.right, 0.01));
      await tester.runAsync(() async {
        for (var index = 0; index < 3; index++) {
          await repository.save(
            PictureStoryPracticeRecord(
              id: 'responsive-older-$index',
              profileId: 'default',
              promptId: prompt.id,
              promptVersion: prompt.version,
              startedAt: DateTime(2025, 12, 31 - index),
              status: 'completed',
              segmentsJson: '[]',
              answerText: '以前的表达 $index：孩子在公园里放风筝，风筝飞得很高。',
            ),
          );
        }
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(draft.answerText),
        250,
        scrollable: find
            .descendant(
              of: find.byType(PictureStoryHistoryPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text(draft.answerText).hitTestable(), findsOneWidget);
      final firstCard = tester.getRect(
        find.byKey(const ValueKey('picture-story-record-responsive-history')),
      );
      final secondCard = tester.getRect(
        find.byKey(const ValueKey('picture-story-record-responsive-older-0')),
      );
      if (width >= 600) {
        expect(secondCard.top, closeTo(firstCard.top, 0.01));
        expect(secondCard.left, greaterThan(firstCard.right));
      } else {
        expect(secondCard.top, greaterThan(firstCard.bottom));
        expect(secondCard.left, firstCard.left);
      }
      if (width >= 900) {
        final thirdCard = tester.getRect(
          find.byKey(const ValueKey('picture-story-record-responsive-older-1')),
        );
        expect(thirdCard.top, closeTo(firstCard.top, 0.01));
        expect(thirdCard.left, greaterThan(secondCard.right));
      }
      final date = find.descendant(
        of: find.byKey(
          const ValueKey('picture-story-record-responsive-history'),
        ),
        matching: find.text('2026/01/01 00:00'),
      );
      final arrow = find.descendant(
        of: find.byKey(
          const ValueKey('picture-story-record-responsive-history'),
        ),
        matching: find.byIcon(Icons.chevron_right),
      );
      expect(
        tester.getRect(find.text(draft.answerText)).right,
        lessThanOrEqualTo(tester.getRect(date).left),
      );
      expect(
        tester.getRect(date).right,
        lessThanOrEqualTo(tester.getRect(arrow).left),
      );
      for (final content in [find.text(draft.answerText), date, arrow]) {
        expect(
          tester.getCenter(content).dy,
          closeTo(firstCard.center.dy, 0.01),
        );
      }
      expect(find.text('AI 表达点评'), findsNothing);
      expect(find.text('题目与参考表达'), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNothing);
      await tester.tap(find.text('孩子放风筝。'));
      await tester.pumpAndSettle();
      expect(find.text('我的表达'), findsOneWidget);
      expect(find.text('AI 表达点评'), findsOneWidget);
      expect(find.byType(PictureStoryImageView), findsNothing);
      expect(find.byType(ColoredCard), findsNothing);
      expect(find.text('第 1 次练习'), findsNothing);
      final editButton = find.widgetWithText(FilledButton, '修改表达并重新点评');
      expect(editButton.hitTestable(), findsOneWidget);
      final editRect = tester.getRect(editButton);
      expect(
        find.ancestor(of: editButton, matching: find.byType(Scrollable)),
        findsNothing,
      );
      final headingRect = tester.getRect(find.text('我的表达'));
      final timeRect = tester.getRect(find.text('2026/01/01 00:00'));
      expect(
        timeRect.right,
        closeTo(tester.getRect(find.text(draft.answerText)).right, 0.01),
      );
      if (textScale == 1) {
        expect(timeRect.center.dy, closeTo(headingRect.center.dy, 0.01));
      } else {
        expect(timeRect.top, greaterThanOrEqualTo(headingRect.bottom));
      }
      await tester.tap(find.byTooltip('查看题目'));
      await tester.pumpAndSettle();
      expect(find.byType(PictureStoryImageView), findsOneWidget);
      expect(find.text(prompt.title), findsOneWidget);
      expect(tester.getRect(editButton), editRect);
      await tester.tap(find.byTooltip('隐藏题目'));
      await tester.pumpAndSettle();
      expect(find.byType(PictureStoryImageView), findsNothing);
      final historyScroll = find
          .descendant(
            of: find.byType(PictureStoryRecordDetailPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('根据图片与文字提供建议，不评价发音和语调。'),
        250,
        scrollable: historyScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('修改表达并重新点评').hitTestable(), findsOneWidget);
      expect(tester.getRect(editButton), editRect);
      expect(
        tester.getRect(find.text('根据图片与文字提供建议，不评价发音和语调。')).bottom,
        lessThanOrEqualTo(editRect.top),
      );
      expect(find.text('原录音'), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('AI 表达点评'), findsNothing);
      expect(find.text('修改表达并重新点评'), findsNothing);
      expect(find.text(draft.answerText), findsOneWidget);
      expect(HiveBoxes.pictureStoryPractice.length, 4);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  testWidgets('退出练习详情停止播放，重进保留表达和独立录音入口', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('picture-story-playback-'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final prompt = (await tester.runAsync(() async {
      final file = await File('${directory.path}/original.wav')
          .writeAsBytes([0]);
      final prompt = await repository.savePrompt(
        prompt: pictureStoryFixture(),
        profileId: 'default',
      );
      final record =
          PictureStoryPracticeRecord(
            id: 'playback-history',
            profileId: 'default',
            promptId: prompt.id,
            promptVersion: prompt.version,
            startedAt: DateTime(2026),
            status: 'completed',
            segmentsJson: '[]',
          )..setSegments([
            PictureStorySegment(
              id: 'original',
              position: 0,
              audioPath: file.path,
              durationSeconds: 8,
              transcript: '孩子放风筝。',
            ),
          ]);
      record.feedbackJson = jsonEncode({'text': '已经记录下你的表达。'});
      await repository.save(record);
      return prompt;
    }))!;
    final router = historyRouter(
      initialLocation: AppRoutes.pictureStoryPromptHistoryOf(prompt.id),
    );
    await pumpPage(tester, Router.withConfig(config: router));
    expect(find.text('第 1 段录音'), findsNothing);
    await tester.tap(find.text('孩子放风筝。'));
    await tester.pumpAndSettle();
    expect(find.text('孩子放风筝。'), findsOneWidget);
    final audioRow = find.widgetWithText(AppTile, '第 1 段录音');
    final audioLeft = tester.getTopLeft(find.text('第 1 段录音')).dx;
    for (final text in ['我的表达', '孩子放风筝。', '点评']) {
      expect(audioLeft, closeTo(tester.getTopLeft(find.text(text)).dx, 0.01));
    }
    expect(
      tester.getRect(audioRow).top,
      greaterThan(tester.getRect(find.text('孩子放风筝。')).bottom),
    );
    expect(
      tester.getRect(find.text('点评')).top,
      greaterThan(tester.getRect(audioRow).bottom),
    );
    expect(find.text('修改表达并重新点评').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('第 1 段录音'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('第 1 段录音')));
    for (var i = 0; i < 50 && !audioCalls.contains('resume'); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(audioCalls, contains('resume'));
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    final stopCount = audioCalls.where((method) => method == 'stop').length;
    router.pop();
    await tester.pumpAndSettle();
    for (
      var i = 0;
      i < 50 &&
          audioCalls.where((method) => method == 'stop').length == stopCount;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(
      audioCalls.where((method) => method == 'stop').length,
      stopCount + 1,
    );
    expect(find.text('第 1 段录音'), findsNothing);
    expect(find.text('孩子放风筝。'), findsOneWidget);
    await tester.tap(find.text('孩子放风筝。'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    expect(repository.records().length, 1);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final isDraft in [false, true]) {
    testWidgets('详情直达入口拒绝不存在或未完成的记录（草稿：$isDraft）', (tester) async {
      final recordId = isDraft ? 'unfinished-detail' : 'missing /? #记录';
      if (isDraft) {
        await tester.runAsync(
          () => repository.save(
            PictureStoryPracticeRecord(
              id: recordId,
              profileId: 'default',
              promptId: 'missing-prompt',
              promptVersion: 1,
              startedAt: DateTime(2026),
              status: 'draft',
              segmentsJson: '[]',
              answerText: '不应在完成记录中展示的草稿',
            ),
          ),
        );
      }
      final router = historyRouter(
        initialLocation: AppRoutes.pictureStoryRecordDetailOf(recordId),
      );
      await pumpPage(tester, Router.withConfig(config: router));
      expect(
        tester
            .widget<PictureStoryRecordDetailPage>(
              find.byType(PictureStoryRecordDetailPage),
            )
            .recordId,
        recordId,
      );
      expect(find.text('暂时无法打开这次练习'), findsOneWidget);
      expect(find.text('不应在完成记录中展示的草稿'), findsNothing);
      expect(find.text('修改表达并重新点评'), findsNothing);
      expect(HiveBoxes.pictureStoryPractice.length, isDraft ? 1 : 0);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  testWidgets('详情绑定打开时的孩子，切换及切回档案后要求重新进入', (tester) async {
    await tester.runAsync(() async {
      for (final profileId in ['default', 'another-child']) {
        ProfileScope.switchTo(profileId);
        await repository.save(
          PictureStoryPracticeRecord(
            id: 'same-record-id',
            profileId: profileId,
            promptId: 'kite-in-the-park',
            promptVersion: 1,
            startedAt: DateTime(2026),
            status: 'completed',
            segmentsJson: '[]',
            answerText: '$profileId 的表达',
          ),
        );
      }
      ProfileScope.switchTo('default');
    });
    final router = historyRouter(
      initialLocation: AppRoutes.pictureStoryRecordDetailOf('same-record-id'),
    );
    await pumpPage(tester, Router.withConfig(config: router));
    expect(find.text('default 的表达'), findsOneWidget);
    ProfileScope.switchTo('another-child');
    await tester.pumpAndSettle();
    expect(find.text('孩子档案已切换，请返回重新打开记录。'), findsOneWidget);
    expect(find.text('default 的表达'), findsNothing);
    expect(find.text('another-child 的表达'), findsNothing);
    expect(find.text('修改表达并重新点评'), findsNothing);
    ProfileScope.switchTo('default');
    await tester.pumpAndSettle();
    expect(find.text('孩子档案已切换，请返回重新打开记录。'), findsOneWidget);
    expect(find.text('default 的表达'), findsNothing);
    expect(HiveBoxes.pictureStoryPractice.length, 2);
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
    await pumpPage(
      tester,
      const PictureStoryRecordDetailPage(recordId: 'deleted-prompt-history'),
    );
    expect(find.byType(PictureStoryImageView), findsNothing);
    await tester.tap(find.byTooltip('查看题目'));
    await tester.pumpAndSettle();
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
    await pumpPage(
      tester,
      const PictureStoryRecordDetailPage(recordId: 'missing-version'),
    );
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
    final container = await pumpPage(
      tester,
      const PictureStoryRecordDetailPage(recordId: 'legacy-builtin-history'),
    );
    expect(container.read(pictureStoryCatalogProvider), isEmpty);
    expect(container.read(pictureStoryPromptCountProvider), 0);
    expect(find.byType(PictureStoryImageView), findsNothing);
    await tester.tap(find.byTooltip('查看题目'));
    await tester.pumpAndSettle();
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

  for (final hasDisabledPrompt in [false, true]) {
    testWidgets('表达无可练习题目时统一引导家长，窄屏大字可读（停用题：$hasDisabledPrompt）', (
      tester,
    ) async {
      if (hasDisabledPrompt) {
        await tester.runAsync(() async {
          await repository.savePrompt(
            prompt: pictureStoryFixture(),
            profileId: 'default',
          );
          await repository.setEnabled('local-fixture', false);
        });
      }
      final container = await pumpPage(
        tester,
        const PictureStoryPage(),
        size: const Size(320, 360),
        textScale: 2,
      );

      expect(container.read(pictureStoryPromptCountProvider), 0);
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('暂时没有可练习的题目'), findsOneWidget);
      final guidance = find.text('请家长在设置中添加或启用看图说话题目。');
      await tester.ensureVisible(guidance);
      await tester.pumpAndSettle();
      expect(guidance.hitTestable(), findsOneWidget);
      expect(find.byType(ColoredCard), findsNothing);
      expect(find.byTooltip('全部记录'), findsOneWidget);
      expect(HiveBoxes.pictureStoryPractice.isEmpty, isTrue);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

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
    final prompt = repository.listPrompts().single;
    expect(find.text(prompt.levelLabel), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.button == true &&
            widget.properties.label == title,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
