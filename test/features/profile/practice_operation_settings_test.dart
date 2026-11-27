import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/math/math_practice_page.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/widgets/math_text.dart';
import 'package:poemath/features/profile/practice_settings_page.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  testWidgets('次数至少保留一项，题型切换给出明确调整，简单难度仍保留三步', (tester) async {
    tester.view.physicalSize = const Size(440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => SettingsRepository().setLearningBackground(3, '下'),
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PageAnimationScope(
            enabled: false,
            child: PracticeSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '1 次'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, '1 次'));
    await tester.pump();
    expect(find.text('至少保留一种运算次数'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '1 次'))
          .selected,
      isTrue,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '带括号'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilterChip, '1 次'),
      -200,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '1 次'))
          .onSelected,
      isNull,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '2 次'))
          .selected,
      isTrue,
    );
    expect(find.text('当前题型至少计算 2 次，已调整为2 次运算'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, '3 次'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, '2 次'));
    await tester.pump();
    await tester.scrollUntilVisible(find.widgetWithText(ChoiceChip, '简单'), 200);
    await tester.tap(find.widgetWithText(ChoiceChip, '简单'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilterChip, '3 次'),
      -200,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '3 次'))
          .selected,
      isTrue,
    );
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '综合')).selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      for (final size in [const Size(320, 800), const Size(914, 411)]) {
        testWidgets('${subject.name}/${brightness.name}/$size 设置和三步题支持两倍字号', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final problem = MathProblem(
            operands: [96, 3, 9, 100].map(NumberValue.fromInt).toList(),
            operators: [Operator.add, Operator.multiply, Operator.subtract],
            result: NumberValue.fromInt(791),
            mode: ProblemMode.withBrackets,
            bracketRange: (0, 2),
            grade: 3,
            semester: '下',
          );
          await tester.runAsync(() async {
            final settings = SettingsRepository();
            await settings.setLearningBackground(3, '下');
            await settings.setMathOperationCounts(OperationCounts([2, 3]));
            await settings.setSoundEnabled(false);
            await settings.setHapticEnabled(false);
            await PracticeDraftRepository().save('math', {
              'sessionId': 'operation-layout',
              'startedAt': DateTime.now().toIso8601String(),
              'elapsedMilliseconds': 0,
              'index': 0,
              'input': '',
              'request': MathPracticeRequest(
                grade: 3,
                semester: '下',
                count: 1,
                difficulty: DifficultyLevel.medium,
                mode: ProblemMode.withBrackets,
                operationCounts: OperationCounts([3]),
              ).toJson(),
              'problems': [problem.toJson()],
              'records': <Object>[],
            });
          });
          Widget app(Widget child) => ProviderScope(
            key: UniqueKey(),
            child: MaterialApp(
              theme: AppTheme.resolve(subject: subject, brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: PageAnimationScope(enabled: false, child: child),
            ),
          );
          try {
            await tester.pumpWidget(app(const PracticeSettingsPage()));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.widgetWithText(FilterChip, '3 次'));
            await tester.pump();
            expect(
              tester
                  .widget<FilterChip>(find.widgetWithText(FilterChip, '3 次'))
                  .selected,
              isTrue,
            );
            await tester.scrollUntilVisible(
              find.widgetWithText(FilledButton, '保存'),
              300,
            );
            await tester.pump();
            expect(
              find.widgetWithText(FilledButton, '保存').hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(app(const MathPracticePage(resume: true)));
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            expect(
              tester
                  .widgetList<MathText>(find.byType(MathText))
                  .any((w) => w.text == problem.problemText),
              isTrue,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(seconds: 1));
            await drainHiveWritesForTesting(tester);
          }
        });
      }
    }
  }
}
