import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/core/widgets/page_animation_scope.dart';
import 'package:poemath/features/home/learning_calendar_page.dart';

import '../../helpers/day_key_override.dart';
import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForWidgetTesting);

  for (final subject in AppSubject.values) {
    testWidgets('$subject 小屏两倍字号统计留在卡片内，两位日期完整显示', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [staticDayKeyOverride()],
          child: MaterialApp(
            theme: AppTheme.resolve(
              subject: subject,
              brightness: Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const PageAnimationScope(
              enabled: false,
              child: LearningCalendarPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      final card = tester.getRect(find.byType(ColoredCard).first);
      for (final label in ['连续打卡', '本月学习', '本月星星']) {
        final bounds = tester.getRect(find.text(label));
        expect(bounds.left, greaterThanOrEqualTo(card.left));
        expect(bounds.right, lessThanOrEqualTo(card.right));
      }
      for (final day in {'20', '28', '${DateTime.now().day}'}) {
        final date = find.text(day).last;
        final cell = find
            .ancestor(of: date, matching: find.byType(GestureDetector))
            .first;
        final bounds = tester.getRect(date);
        final cellBounds = tester.getRect(cell);
        expect(bounds.left, greaterThanOrEqualTo(cellBounds.left));
        expect(bounds.right, lessThanOrEqualTo(cellBounds.right));
        expect(bounds.height, lessThanOrEqualTo(cellBounds.height));
        expect(tester.widget<Text>(date).maxLines, 1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
