import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/textbook_learning_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_learning_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_cover.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/textbook_fixture.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForWidgetTesting);

  for (final subject in TextbookSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('星海课本封面铺满切角卡片且仍可打开：$subject/$brightness', (tester) async {
        tester.view.physicalSize = const Size(411, 914);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final book = textbookFixture().withSubject(subject);
        final theme = AppTheme.resolve(
          subject: AppSubject.space,
          brightness: brightness,
        );
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => TextbookLearningPage(subject: subject),
            ),
            GoRoute(
              path: AppRoutes.textbookDetailOf(book.pdfSha256),
              builder: (_, __) => const Scaffold(body: Text('课本已打开')),
            ),
          ],
        );
        addTearDown(router.dispose);
        final cover = (await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            // 封面比 3:4 网格窄，确保不会因等比例完整缩放留下两侧空隙。
            const Rect.fromLTWH(0, 0, 160, 240),
            Paint()..color = Colors.blue,
          );
          final picture = recorder.endRecording();
          try {
            return await picture.toImage(160, 240);
          } finally {
            picture.dispose();
          }
        }))!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentTextbooksProvider.overrideWithValue([book]),
              subjectTextbooksProvider(subject).overrideWithValue([book]),
              textbookPathProvider(book.pdfSha256)
                  .overrideWith((ref) async => '/shape-${subject.name}.pdf'),
              textbookCoverRendererProvider.overrideWithValue(
                (_, __) async => cover,
              ),
            ],
            child: RepaintBoundary(
              key: const ValueKey('capture'),
              child: MaterialApp.router(theme: theme, routerConfig: router),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final card = find.byKey(ValueKey('textbook-${book.pdfSha256}'));
        final bounds = tester.getRect(card);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        final pixels = (await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          } finally {
            image.dispose();
          }
        }))!;
        Color pixel(Offset point) {
          final offset = (point.dy.floor() * 411 + point.dx.floor()) * 4;
          return Color.fromARGB(
            pixels.getUint8(offset + 3),
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2),
          );
        }

        for (final point in [
          bounds.center,
          bounds.centerLeft + const Offset(2, 0),
          bounds.centerRight + const Offset(-2, 0),
          bounds.topCenter + const Offset(0, 2),
          bounds.bottomCenter + const Offset(0, -2),
        ]) {
          expect(
            pixel(point).toARGB32(),
            Colors.blue.toARGB32(),
            reason: '封面应铺满卡片，$point 不应露出底色',
          );
        }
        // 这些点位于旧 4dp 圆角内，但在 16dp 切角外。
        for (final point in [
          bounds.topLeft + const Offset(6, 4),
          bounds.topRight + const Offset(-6, 4),
          bounds.bottomLeft + const Offset(6, -4),
          bounds.bottomRight + const Offset(-6, -4),
        ]) {
          expect(
            pixel(point).toARGB32(),
            theme.scaffoldBackgroundColor.toARGB32(),
          );
        }
        await tester.tap(card);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('课本已打开'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
