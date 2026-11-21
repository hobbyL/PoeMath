import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/core/widgets/theme_page_panel.dart';

void main() {
  testWidgets('奶糖装订纸保持平整，前景练习入口可点击', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = AppTheme.resolve(
      subject: AppSubject.candy,
      brightness: Brightness.light,
    );
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: ThemePagePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ColoredCard(
                  color: theme.colorScheme.primary,
                  onTap: () => opened = true,
                  child: const Text('口算练习'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final background =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(ColoredCard).first,
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(
      background.borderRadius,
      BorderRadius.circular(SpacingTokens.radiusLarge),
    );
    expect(background.border, isNull);
    expect(background.boxShadow, isNull);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('口算练习'), findsOneWidget);
    await tester.tap(find.text('口算练习'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
