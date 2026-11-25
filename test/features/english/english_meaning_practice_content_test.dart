import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/domain/english_practice.dart';
import 'package:poemath/features/english/widgets/english_meaning_practice_content.dart';

import '../../helpers/english_fixture.dart';

void main() {
  final question = EnglishQuestion(
    id: 'meaning-layout',
    lessonId: 'unit-1-p2',
    target: englishWord(text: 'a beautiful red kite'),
    kind: EnglishPracticeKind.meaning,
    prompt: 'a beautiful red kite',
    options: const ['红风筝', '一只在花园里飞来飞去的蓝色小鸟', '绿色的小船', '漂亮的红风筝'],
    answers: const ['漂亮的红风筝'],
  );

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('词义选择 $subject $brightness 选项、反馈与固定操作适应宽度和字号', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        for (final layout in [
          (size: const Size(360, 780), scale: 1.0, columns: 2),
          (size: const Size(390, 844), scale: 1.0, columns: 2),
          (size: const Size(320, 740), scale: 1.0, columns: 1),
          (size: const Size(844, 390), scale: 1.0, columns: 2),
          (size: const Size(320, 740), scale: 2.0, columns: 1),
          (size: const Size(844, 390), scale: 2.0, columns: 1),
        ]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = layout.size;
          var selected = '';
          EnglishAnswer? feedback;
          var continued = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.resolve(subject: subject, brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(layout.scale)),
                child: child!,
              ),
              home: AppScaffold(
                appBar: AppBar(
                  centerTitle: true,
                  title: Text(
                    question.prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                body: SafeArea(
                  top: false,
                  child: StatefulBuilder(
                    builder: (context, setState) =>
                        EnglishMeaningPracticeContent(
                          question: question,
                          selected: selected,
                          busy: false,
                          lastQuestion: true,
                          feedback: feedback,
                          onSelect: (value) => setState(() => selected = value),
                          onPrevious: () {},
                          onNext: () {},
                          onSkip: () {},
                          onSubmit: () => setState(() {
                            feedback = EnglishAnswer(
                              question: question,
                              answer: selected,
                              correct: question.accepts(selected),
                            );
                          }),
                          onContinue: () => continued++,
                        ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final submit = find.byKey(const ValueKey('english-meaning-submit'));
          final first = find.byKey(const ValueKey('english-meaning-option-0'));
          final second = find.byKey(const ValueKey('english-meaning-option-1'));
          final scrollable = find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          );
          final footerBounds = tester.getRect(submit);
          expect(submit.hitTestable(), findsOneWidget);
          expect(tester.widget<FilledButton>(submit).onPressed, isNull);
          expect(find.byIcon(Icons.radio_button_checked), findsNothing);
          expect(find.byIcon(Icons.check_circle_outline), findsNothing);
          expect(find.text(question.prompt), findsOneWidget);
          expect(
            find.byKey(const ValueKey('english-meaning-prompt')),
            findsNothing,
          );
          expect(find.text('看提示'), findsNothing);
          for (final control in [
            find.byTooltip('上一题'),
            find.byTooltip('下一题'),
            find.widgetWithText(TextButton, '跳过'),
          ]) {
            final bounds = tester.getRect(control);
            expect(bounds.center.dy, closeTo(footerBounds.center.dy, .01));
            expect(bounds.height, greaterThanOrEqualTo(44));
            expect(control.hitTestable(), findsOneWidget);
          }
          await tester.scrollUntilVisible(first, 100, scrollable: scrollable);
          await tester.pumpAndSettle();
          expect(tester.getRect(first).height, greaterThanOrEqualTo(44));
          final firstBounds = tester.getRect(first);
          final secondBounds = tester.getRect(second);
          if (layout.columns == 2) {
            expect(firstBounds.top, secondBounds.top);
            expect(firstBounds.height, secondBounds.height);
            expect(secondBounds.left - firstBounds.right, closeTo(8, .01));
          } else {
            expect(secondBounds.top, greaterThan(firstBounds.bottom));
            expect(secondBounds.left, firstBounds.left);
          }

          await tester.ensureVisible(first);
          await tester.pumpAndSettle();
          await tester.tap(first);
          await tester.pumpAndSettle();
          expect(selected, question.options.first);
          expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
          expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
          expect(tester.getRect(submit), footerBounds);
          await tester.drag(scrollable, const Offset(0, -800));
          await tester.pumpAndSettle();
          expect(tester.getRect(submit), footerBounds);
          expect(submit.hitTestable(), findsOneWidget);
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(find.text('再记一遍'), findsNothing);
          expect(find.text('答对了'), findsNothing);
          expect(find.text('完成练习'), findsOneWidget);
          expect(find.text('提交答案'), findsNothing);
          expect(tester.getRect(submit).bottom, footerBounds.bottom);

          // 核对后仍可回看原题及两个状态，不允许再改答案。
          await tester.scrollUntilVisible(first, -100, scrollable: scrollable);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: first,
              matching: find.byIcon(Icons.cancel_outlined),
            ),
            findsOneWidget,
          );
          final correct = find.byKey(
            const ValueKey('english-meaning-option-3'),
          );
          await tester.scrollUntilVisible(correct, 100, scrollable: scrollable);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: correct,
              matching: find.byIcon(Icons.check_circle_outline),
            ),
            findsOneWidget,
          );
          await tester.tap(correct);
          expect(selected, question.options.first);
          await tester.tap(submit);
          expect(continued, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }

  testWidgets('词义选项可通过无障碍操作选择，忙碌时禁止重复选择和提交', (tester) async {
    final handle = tester.ensureSemantics();
    var selected = '';
    var busy = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return EnglishMeaningPracticeContent(
                question: question,
                selected: selected,
                busy: busy,
                lastQuestion: false,
                onSelect: (value) => setState(() => selected = value),
                onPrevious: () {},
                onNext: () {},
                onSkip: () {},
                onSubmit: () {},
                onContinue: () {},
              );
            },
          ),
        ),
      ),
    );
    final option = find.bySemanticsLabel('选项 A，红风筝');
    expect(
      tester.getSemantics(option),
      matchesSemantics(
        label: '选项 A，红风筝',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        viewId: tester.view.viewId,
        nodeId: tester.getSemantics(option).id,
        type: SemanticsAction.tap,
      ),
    );
    await tester.pump();
    expect(selected, '红风筝');
    update(() => busy = true);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('english-meaning-submit')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text(question.options[1]));
    expect(selected, '红风筝');
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
