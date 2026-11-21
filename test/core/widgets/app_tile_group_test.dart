import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/app_tile.dart';
import 'package:poemath/core/widgets/app_tile_group.dart';
import 'package:poemath/core/widgets/colored_card.dart';

void main() {
  testWidgets('four themes share a single divided paper for navigation rows', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    var taps = 0;
    for (final subject in AppSubject.values) {
      for (final size in [const Size(320, 640), const Size(914, 411)]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.resolve(
              subject: subject,
              brightness: Brightness.light,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: AppTileGroup(
                  children: [
                    AppTile(
                      icon: Icons.palette_outlined,
                      iconColor: AppTheme.resolve(
                        subject: subject,
                        brightness: Brightness.light,
                      ).colorScheme.primary,
                      title: '外观与反馈',
                      subtitle: '主题、明暗模式、音效与触觉',
                      onTap: () => taps++,
                    ),
                    AppTile(
                      icon: Icons.menu_book_outlined,
                      iconColor: AppTheme.resolve(
                        subject: subject,
                        brightness: Brightness.light,
                      ).colorScheme.primary,
                      title: '学习与内容',
                      subtitle: '学习背景、练习参数、书籍与题库',
                      onTap: () => taps++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ColoredCard), findsOneWidget);
        expect(find.byType(AppTile), findsNWidgets(2));
        expect(find.byType(Divider), findsOneWidget);
        expect(
          tester
              .widgetList<AppTile>(find.byType(AppTile))
              .every((tile) => tile.flat),
          isTrue,
        );
        await tester.tap(find.text('外观与反馈'));
        expect(taps, greaterThan(0));
        expect(tester.takeException(), isNull);
      }
    }
  });
}
