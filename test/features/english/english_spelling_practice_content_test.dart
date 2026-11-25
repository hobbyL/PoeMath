import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/domain/english_practice.dart';
import 'package:poemath/features/english/widgets/english_spelling_practice_content.dart';

import '../../helpers/english_fixture.dart';

void main() {
  final question = EnglishQuestion(
    id: 'spelling-layout',
    lessonId: 'unit-1-p2',
    target: englishWord(text: 'red balloon', meaning: '一个漂亮的红色气球'),
    kind: EnglishPracticeKind.spelling,
    prompt: '一个漂亮的红色气球',
    options: 'red balloon'.split(''),
    answers: const ['red balloon'],
  );

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('拼写卡与固定操作 $subject $brightness 适配竖横屏和大字号', (tester) async {
        addTearDown(tester.view.reset);
        for (final layout in [
          (size: const Size(360, 780), scale: 1.0),
          (size: const Size(390, 844), scale: 1.0),
          (size: const Size(320, 740), scale: 1.0),
          (size: const Size(844, 390), scale: 1.0),
          (size: const Size(320, 740), scale: 2.0),
          (size: const Size(844, 390), scale: 2.0),
        ]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = layout.size;
          var tokens = <int>[];
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
                    builder: (context, update) =>
                        EnglishSpellingPracticeContent(
                          question: question,
                          tokens: tokens,
                          busy: false,
                          complete: true,
                          feedback: feedback,
                          onChange: (next) => update(() => tokens = next),
                          onPrevious: () {},
                          onNext: () {},
                          onSkip: () {},
                          onSubmit: () => update(() {
                            final answer = tokens
                                .map((i) => question.options[i])
                                .join();
                            feedback = EnglishAnswer(
                              question: question,
                              answer: answer,
                              correct: question.accepts(answer),
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
          final submit = find.byKey(const ValueKey('english-spelling-submit'));
          final input = find.byKey(const ValueKey('english-spelling-input'));
          final footer = tester.getRect(submit);
          expect(find.text(question.prompt), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(question.prompt),
            ),
            findsOneWidget,
          );
          expect(find.text('red balloon'), findsNothing);
          expect(find.text('看提示'), findsNothing);
          expect(tester.widget<FilledButton>(submit).onPressed, isNull);
          for (final control in [
            find.byTooltip('上一题'),
            find.byTooltip('下一题'),
            find.widgetWithText(TextButton, '跳过'),
          ]) {
            expect(
              tester.getCenter(control).dy,
              closeTo(footer.center.dy, .01),
            );
            expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
            expect(control.hitTestable(), findsOneWidget);
          }
          final answerCard = tester.getRect(
            find.byKey(const ValueKey('english-spelling-answer')),
          );
          final letters = tester.getRect(
            find.byKey(const ValueKey('english-spelling-letters')),
          );
          if (layout.size.width == 844 && layout.scale == 1) {
            expect(letters.left, greaterThan(answerCard.right));
            expect(letters.top, answerCard.top);
          } else {
            expect(letters.top, greaterThan(answerCard.bottom));
          }
          Future<void> tapToken(int index) async {
            final token = find.byKey(ValueKey('english-token-$index'));
            await tester.ensureVisible(token);
            await tester.pumpAndSettle();
            expect(tester.getSize(token).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(token).height, greaterThanOrEqualTo(44));
            await tester.tap(token);
            await tester.pumpAndSettle();
          }

          await tapToken(0);
          await tapToken(0);
          expect(tokens, [0], reason: '同一个字母块只能使用一次');
          expect(tester.widget<Text>(input).data, 'r');
          expect(tester.widget<FilledButton>(submit).onPressed, isNull);
          final undo = find.byTooltip('撤回一个字母');
          await tester.ensureVisible(undo);
          await tester.pumpAndSettle();
          await tester.tap(undo);
          await tester.pumpAndSettle();
          expect(tokens, isEmpty);
          // 完整拼写包含独立的两个 l、两个 o 和一个空格。
          for (var i = 0; i < question.options.length; i++) {
            await tapToken(i);
          }
          expect(tester.widget<Text>(input).data, 'red balloon');
          expect(tester.getRect(submit), footer);
          expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(feedback!.correct, isTrue);
          expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
          expect(find.text('答对了'), findsNothing);
          expect(find.text('完成练习'), findsOneWidget);
          await tapToken(0);
          expect(tokens.length, question.options.length);
          await tester.tap(submit);
          expect(continued, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
