import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/features/chinese/expression/widgets/picture_story_guidance.dart';

import '../../../helpers/picture_story_fixture.dart';

void main() {
  testWidgets('逐问观察与自由讲述可切换，帮手仅在主动展开时显示原题提示', (tester) async {
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
                    onStartSpeaking: () {},
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
    expect(find.text(prompt.questions.first), findsOneWidget);
    expect(find.text(prompt.questions.last), findsNothing);
    final questionSemantics = tester.getSemantics(
      find.text(prompt.questions.first),
    );
    expect(questionSemantics.label, prompt.questions.first);
    expect(questionSemantics.flagsCollection.isLiveRegion, isTrue);
    final nextButton = find.ancestor(
      of: find.text('下一问'),
      matching: find.byType(TextButton),
    );
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
    await tester.tap(find.text('自己完整讲'));
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
              child: Column(
                children: [
                  PictureStoryGuidance(
                    prompt: prompt,
                    guided: true,
                    questionIndex: 0,
                    busy: true,
                    onQuestionChanged: (_) => fail('忙碌时不能换问题'),
                    onModeChanged: (_) => fail('忙碌时不能换练法'),
                    onStartSpeaking: () {},
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
      await tester.ensureVisible(find.text('看看另一种说法'));
      await tester.tap(find.text('看看另一种说法'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(prompt.reference));
      expect(find.text(prompt.reference).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
