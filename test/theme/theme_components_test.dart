import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/theme/poem_theme.dart';
import 'package:poemath/core/widgets/animated_favorite_button.dart';
import 'package:poemath/core/widgets/celebration_dialog.dart';
import 'package:poemath/core/widgets/colored_card.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/features/poem/widgets/poem_card.dart';

import '../helpers/theme_contrast.dart';

void main() {
  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      final theme = AppTheme.resolve(subject: subject, brightness: brightness);
      final scheme = theme.colorScheme;
      final label = '$subject/$brightness';

      test('$label 阅读正文与拼音使用阅读字号、可读前景，扩展可随主题插值', () {
        final reading = theme.extension<PoemThemeExt>()!;
        final background = Color.alphaBlend(
          scheme.primary.withValues(alpha: .08),
          theme.scaffoldBackgroundColor,
        );
        expect(reading.poemContent.fontSize, TypographyTokens.fsPoemContent);
        expect(reading.poemContent.height, 1.8);
        expect(
          contrastRatio(reading.poemContent.color!, background),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(reading.pinyin.color!, background),
          greaterThanOrEqualTo(4.5),
        );
        final other = AppTheme.resolve(
          subject: subject,
          brightness: brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light,
        );
        expect(
          theme.semantic.lerp(other.semantic, 1).secondaryForeground,
          other.semantic.secondaryForeground,
        );
        expect(
          theme.semantic.copyWith().secondaryForeground,
          theme.semantic.secondaryForeground,
        );
        expect(
          reading.lerp(other.extension<PoemThemeExt>(), 1).poemContent.color,
          other.extension<PoemThemeExt>()!.poemContent.color,
        );
        expect(reading.copyWith().pinyin.color, reading.pinyin.color);
      });

      testWidgets('$label 诗词标签、收藏与三类状态标签保持实际对比度', (tester) async {
        final poem = Poem(
          id: 'theme',
          title: '静夜思',
          author: '李白',
          dynasty: '唐',
          content: '床前明月光，\n疑是地上霜。',
          pinyin: '',
          layer: 'core',
          tags: ['写景'],
        );
        for (final (status, text, background, foreground) in [
          (LearningStatus.mastered, '已掌握', scheme.primary, scheme.onPrimary),
          (
            LearningStatus.reviewing,
            '复习中',
            scheme.secondary,
            scheme.onSecondary,
          ),
          (LearningStatus.learning, '学习中', scheme.tertiary, scheme.onTertiary),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: PoemCard(
                  poem: poem,
                  isFavorite: true,
                  learningStatus: status,
                ),
              ),
            ),
          );
          final card = tester.widget<ColoredCard>(find.byType(ColoredCard));
          final cardBackground = Color.alphaBlend(
            card.color!.withValues(alpha: card.backgroundOpacity),
            theme.scaffoldBackgroundColor,
          );
          final tag = find.text('必背');
          final tagBox = tester.widget<Container>(
            find.ancestor(of: tag, matching: find.byType(Container)).first,
          );
          final tagBackground = Color.alphaBlend(
            (tagBox.decoration! as BoxDecoration).color!,
            cardBackground,
          );
          expect(
            contrastRatio(
              tester.widget<Text>(tag).style!.color!,
              tagBackground,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(
              tester.widget<Icon>(find.byIcon(Icons.favorite)).color!,
              cardBackground,
            ),
            greaterThanOrEqualTo(3),
          );
          final ribbon = find.text(text);
          expect(tester.widget<Text>(ribbon).style!.color, foreground);
          expect(
            contrastRatio(
              tester.widget<Text>(ribbon).style!.color!,
              background,
            ),
            greaterThanOrEqualTo(4.5),
          );
          final statusChip = tester.widget<Chip>(
            find.ancestor(of: ribbon, matching: find.byType(Chip)).first,
          );
          expect(statusChip.backgroundColor, background);
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  AnimatedFavoriteButton(isFavorite: true, onToggle: () {}),
                ],
              ),
            ),
          ),
        );
        expect(
          contrastRatio(
            tester.widget<Icon>(find.byIcon(Icons.favorite)).color!,
            theme.appBarTheme.backgroundColor!,
          ),
          greaterThanOrEqualTo(3),
        );
      });

      testWidgets('$label 三种庆祝标题可读且按时自动关闭', (tester) async {
        for (final type in CelebrationType.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showCelebration(context, type: type),
                    child: const Text('庆祝'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('庆祝'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 800));
          final title = tester.widget<Text>(find.text(type.title));
          final background = tester
              .widget<ColoredCard>(
                find.ancestor(
                  of: find.text(type.title),
                  matching: find.byType(ColoredCard),
                ),
              )
              .color!;
          expect(
            contrastRatio(title.style!.color!, background),
            greaterThanOrEqualTo(4.5),
          );
          await tester.pump(kCelebrationAutoCloseDuration);
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text(type.title), findsNothing);
        }
      });
    }
  }

  test('未注册扩展的亮暗 ThemeData 也提供可读的次级信息前景', () {
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      expect(
        contrastRatio(
          theme.semantic.secondaryForeground,
          theme.colorScheme.surface,
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
