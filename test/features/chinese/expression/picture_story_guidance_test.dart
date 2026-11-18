import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_guidance.dart';

import '../../../helpers/picture_story_fixture.dart';

void main() {
  testWidgets('逐问观察与自由讲述可切换，帮手仅在主动展开时显示原题提示', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    var guided = true;
    var question = 0;
    var used = 0;
    final prompt = pictureStoryFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Column(
                children: [
                  PictureStoryGuidance(
                    prompt: prompt,
                    guided: guided,
                    questionIndex: question,
                    busy: false,
                    onQuestionChanged: (value) =>
                        setState(() => question = value),
                    onModeChanged: (value) => setState(() => guided = value),
                  ),
                  PictureStoryLanguageHelp(
                    prompt: prompt,
                    canViewReference: false,
                    onUsed: () => used++,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final titleRect = tester.getRect(find.text(prompt.title));
    final modesRect = tester.getRect(find.byType(SegmentedButton<bool>));
    final questionModeRect = tester.getRect(find.text('问答模式'));
    final fullModeRect = tester.getRect(find.text('完整模式'));
    expect(titleRect.center.dy, closeTo(modesRect.center.dy, 1));
    expect(titleRect.right, lessThan(modesRect.left));
    expect(
      questionModeRect.left - modesRect.left,
      greaterThanOrEqualTo(SpacingTokens.sm),
    );
    expect(
      modesRect.right - fullModeRect.right,
      greaterThanOrEqualTo(SpacingTokens.sm),
    );
    expect(find.text(prompt.levelLabel), findsNothing);
    expect(find.text(prompt.theme), findsNothing);
    expect(find.text(prompt.questions.first), findsOneWidget);
    expect(find.text(prompt.questions.last), findsNothing);
    final questionSemantics = tester.getSemantics(
      find.text(prompt.questions.first),
    );
    expect(questionSemantics.label, prompt.questions.first);
    expect(questionSemantics.flagsCollection.isLiveRegion, isTrue);
    final progressRect = tester.getRect(
      find.text('观察问题 1/${prompt.questions.length}'),
    );
    final previousButton = find.ancestor(
      of: find.text('上一问'),
      matching: find.byType(TextButton),
    );
    final nextButton = find.ancestor(
      of: find.text('下一问'),
      matching: find.byType(TextButton),
    );
    final previousButtonRect = tester.getRect(previousButton);
    final nextButtonRect = tester.getRect(nextButton);
    expect(previousButtonRect.center.dy, closeTo(progressRect.center.dy, 1));
    expect(nextButtonRect.center.dy, closeTo(progressRect.center.dy, 1));
    expect(progressRect.right, lessThan(previousButtonRect.left));
    expect(nextButtonRect.left, closeTo(previousButtonRect.right, .01));
    expect(nextButtonRect.right, closeTo(modesRect.right, .01));
    expect(
      previousButtonRect.height,
      greaterThanOrEqualTo(SpacingTokens.minTapTarget),
    );
    expect(
      nextButtonRect.height,
      greaterThanOrEqualTo(SpacingTokens.minTapTarget),
    );
    expect(
      tester.getRect(find.text(prompt.questions.first)).top,
      greaterThan(nextButtonRect.bottom),
    );
    final nextLabelRect = tester.getRect(find.text('下一问'));
    final nextIconRect = tester.getRect(find.byIcon(Icons.chevron_right));
    final previousLabelRect = tester.getRect(find.text('上一问'));
    expect(
      nextLabelRect.left - previousLabelRect.right,
      lessThanOrEqualTo(SpacingTokens.sm),
    );
    expect(nextIconRect.center.dy, closeTo(nextLabelRect.center.dy, 1));
    expect(nextIconRect.left, greaterThan(nextLabelRect.right));
    expect(nextIconRect.right, closeTo(modesRect.right, .01));
    expect(
      tester
          .getSemantics(nextButton)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(find.text('下一问'));
    await tester.pump();
    expect(find.text(prompt.questions.last), findsOneWidget);
    expect(find.text(prompt.questions.first), findsNothing);
    await tester.tap(find.text('完整模式'));
    await tester.pump();
    expect(find.text(prompt.questions.first), findsOneWidget);
    expect(find.text(prompt.questions.last), findsOneWidget);
    expect(find.text(prompt.reference), findsNothing);
    expect(find.text(prompt.sceneFacts.single).hitTestable(), findsNothing);
    await tester.ensureVisible(find.text('观察线索'));
    await tester.tap(find.text('观察线索'));
    await tester.pumpAndSettle();
    expect(find.text(prompt.sceneFacts.single).hitTestable(), findsOneWidget);
    expect(used, 1);
    expect(find.byType(TextField), findsNothing);
    semantics.dispose();
  });

  for (final size in [const Size(320, 900), const Size(900, 320)]) {
    testWidgets('窄屏和横屏双倍字号下提示可读且按钮自然换行 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prompt = pictureStoryFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Column(
                children: [
                  PictureStoryGuidance(
                    prompt: prompt,
                    guided: true,
                    questionIndex: 0,
                    busy: true,
                    onQuestionChanged: (_) => fail('忙碌时不能换问题'),
                    onModeChanged: (_) => fail('忙碌时不能换练法'),
                  ),
                  PictureStoryLanguageHelp(
                    prompt: prompt,
                    canViewReference: true,
                    onUsed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final modesRect = tester.getRect(find.byType(SegmentedButton<bool>));
      final nextButtonRect = tester.getRect(
        find.ancestor(of: find.text('下一问'), matching: find.byType(TextButton)),
      );
      expect(nextButtonRect.right, closeTo(modesRect.right, .01));
      await tester.ensureVisible(find.text('看看另一种说法'));
      await tester.tap(find.text('看看另一种说法'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(prompt.reference));
      expect(find.text(prompt.reference).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
