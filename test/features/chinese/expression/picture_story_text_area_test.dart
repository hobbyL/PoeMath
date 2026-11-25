import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_text_area.dart';

void main() {
  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('多行表达自然增高，字数随识别和编辑更新：$subject $brightness', (tester) async {
        final controller = TextEditingController(text: '小猫在窗前。');
        addTearDown(controller.dispose);
        tester.view.physicalSize = brightness == Brightness.light
            ? const Size(320, 640)
            : const Size(740, 320);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var edited = '';
        final theme = AppTheme.resolve(
          subject: subject,
          brightness: brightness,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: AppScaffold(
              appBar: AppBar(title: const Text('我的表达')),
              body: ListView(
                padding: const EdgeInsets.all(SpacingTokens.md),
                children: [
                  ColoredCard(
                    color: theme.colorScheme.primary,
                    child: PictureStoryTextArea(
                      controller: controller,
                      onChanged: (value) => edited = value,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('6 字'), findsOneWidget);
        final initialHeight = tester.getSize(find.byType(TextField)).height;
        controller.text = '小猫\n看🐱，𠀀 e\u0301';
        await tester.pump();
        expect(find.text('7 字'), findsOneWidget, reason: '空白不计数，组合字符不会被拆成多个字');
        final longText = List.filled(12, '小猫在窗前。').join('\n');
        await tester.enterText(find.byType(TextField), longText);
        await tester.pump();
        expect(edited, longText);
        expect(find.text('72 字'), findsOneWidget);
        expect(
          tester.getSize(find.byType(TextField)).height,
          greaterThan(initialHeight),
        );
        await tester.ensureVisible(find.text('72 字'));
        await tester.pumpAndSettle();
        expect(find.text('72 字').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(find.text('0 字'), findsOneWidget);
        expect(edited, isEmpty);
      });
    }
  }
}
