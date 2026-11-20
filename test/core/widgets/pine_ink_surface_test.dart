import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/widgets/pine_ink_surface.dart';

import '../../helpers/theme_contrast.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scene in PineInkScene.values) {
      testWidgets('$scene/$brightness 淡墨实际可见且保留正文对比度', (tester) async {
        final theme = AppTheme.resolve(
          subject: AppSubject.poem,
          brightness: brightness,
        );
        const capture = ValueKey('paper');
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: RepaintBoundary(
                key: capture,
                child: ColoredBox(
                  color: theme.scaffoldBackgroundColor,
                  child: SizedBox(
                    width: 320,
                    height: 200,
                    child: PineInkSurface(
                      scene: scene,
                      page: true,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final art = tester.widget<Image>(find.byType(Image));
        await tester.runAsync(
          () => precacheImage(art.image, tester.element(find.byType(Image))),
        );
        await tester.pump();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final pixels = (await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          } finally {
            image.dispose();
          }
        }))!;
        var painted = 0;
        var minimumContrast = double.infinity;
        for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
          final background = Color.fromARGB(
            pixels.getUint8(offset + 3),
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2),
          );
          if (background != theme.scaffoldBackgroundColor) painted++;
          minimumContrast = math.min(
            minimumContrast,
            contrastRatio(theme.colorScheme.onSurfaceVariant, background),
          );
        }
        expect(painted, greaterThan(2000), reason: '不能只接入图片但实际未绘制');
        expect(minimumContrast, greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('淡墨不改变固有行高、内容位置或点击区域，切换主题不保留插画', (tester) async {
    addTearDown(tester.view.reset);
    var taps = 0;
    Widget content(String id) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          key: ValueKey(id),
          onPressed: () => taps++,
          child: const Text('打开学习内容'),
        ),
        const Text('内容较长时可以自然换行，也支持系统大字号。'),
      ],
    );
    for (final preset in AppSubject.values) {
      for (final (width, scale) in [(320.0, 2.0), (914.0, 1.0)]) {
        tester.view.physicalSize = Size(width, 914);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.resolve(
              subject: preset,
              brightness: Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SizedBox(
                        key: const ValueKey('plain'),
                        child: content('plain-action'),
                      ),
                    ),
                    Expanded(
                      child: PineInkSurface(
                        key: const ValueKey('ink'),
                        child: content('ink-action'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final plain = tester.getRect(find.byKey(const ValueKey('plain')));
        final ink = tester.getRect(find.byKey(const ValueKey('ink')));
        expect(ink.size, plain.size);
        expect(
          tester.getRect(find.byKey(const ValueKey('ink-action'))).top,
          tester.getRect(find.byKey(const ValueKey('plain-action'))).top,
        );
        expect(
          find.byType(Image),
          preset == AppSubject.poem ? findsOneWidget : findsNothing,
        );
        final before = taps;
        await tester.tap(find.byKey(const ValueKey('ink-action')));
        expect(taps, before + 1);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
