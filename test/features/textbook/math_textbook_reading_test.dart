import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_study_content.dart';

import '../../helpers/math_textbook_fixture.dart';
import '../../helpers/math_textbook_image_test_helper.dart';

class _ReadingFiles extends TextbookFileService {
  _ReadingFiles(Directory root) : super(directoryProvider: () async => root);
  @override
  Future<String?> installedPath(Textbook book) async => '/self-owned.pdf';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  defineMathTextbookReadingTests();
}

void defineMathTextbookReadingTests() {
  for (final knowledgePoint in [false, true]) {
    for (final large in [false, true]) {
      testWidgets('原书排版、知识点导航及完整阅读交互（知识点：$knowledgePoint，大字：$large）', (
        tester,
      ) async {
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('math-reading-images-'),
        ))!;
        addTearDown(() => root.delete(recursive: true));
        final book = mathTextbookFixture();
        const source = MathTextbookRegion(
          page: 1,
          left: .1,
          top: .2,
          right: .9,
          bottom: .6,
          printedPage: '7',
        );
        final rendered = <MathTextbookRegion>[];
        final block = MathTextbookBlock(
          id: 'example',
          kind: MathTextbookBlockKind.example,
          exerciseNumber: '1',
          sourceLayout: true,
          spans: const [MathTextbookSpan.text('观察图形并说明你的比较方法。')],
          sources: const [source],
        );
        final reading = MathTextbookSourceContentPage(
          book: book,
          title: '自有例题',
          knowledgePoint: knowledgePoint,
          blocks: [
            block,
            for (final page in [1, 2])
              MathTextbookBlock(
                id: 'source-$page',
                kind: MathTextbookBlockKind.sourcePage,
                spans: const [],
                sources: [
                  MathTextbookRegion(
                    page: page,
                    left: 0,
                    top: 0,
                    right: 1,
                    bottom: 1,
                  ),
                ],
              ),
          ],
        );
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, __) => reading),
            GoRoute(
              path: AppRoutes.textbookReadOf(book.pdfSha256),
              builder: (_, state) => Scaffold(
                appBar: AppBar(title: const Text('完整原书')),
                body: Text('原书 PDF 第 ${state.extra} 页'),
              ),
            ),
          ],
        );
        tester.view.physicalSize = Size(large ? 320 : 420, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              textbookFileServiceProvider.overrideWithValue(
                _ReadingFiles(root),
              ),
              mathTextbookRegionRendererProvider.overrideWithValue((
                path,
                source,
                token,
              ) async {
                token.check();
                rendered.add(source);
                final recorder = ui.PictureRecorder();
                ui.Canvas(recorder).drawRect(
                  const ui.Rect.fromLTWH(0, 0, 240, 120),
                  ui.Paint()..color = Colors.white,
                );
                final picture = recorder.endRecording();
                try {
                  return picture.toImageSync(240, 120);
                } finally {
                  picture.dispose();
                }
              }),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.resolve(
                subject: AppSubject.math,
                brightness: large ? Brightness.dark : Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: child!,
              ),
            ),
          ),
        );
        await settleMathTextbookImages(tester);
        expect(find.text('观察图形并说明你的比较方法。', findRichText: true), findsNothing);
        expect(
          rendered.any(
            (r) => r.toJson().toString() == source.toJson().toString(),
          ),
          isTrue,
        );
        expect(
          rendered.any((r) => r.page == 1 && r.top == 0 && r.bottom == 1),
          isFalse,
        );
        final appBar = find.byType(AppBar);
        final navTitle = find.descendant(
          of: appBar,
          matching: find.text('自有例题'),
        );
        final bookButton = find.descendant(
          of: appBar,
          matching: find.byTooltip('打开原书'),
        );
        expect(navTitle, findsOneWidget);
        expect(bookButton, findsOneWidget);
        if (knowledgePoint) {
          expect(find.byType(ColoredCard), findsNothing);
          expect(find.text('书本第 7 页'), findsNothing);
          expect(find.textContaining(RegExp(r'^例\s*1$')), findsNothing);
          expect(find.text('查看文字'), findsNothing);
          expect(find.text('收起文字'), findsNothing);
          final button = find.ancestor(
            of: bookButton,
            matching: find.byType(IconButton),
          );
          expect(button, findsOneWidget);
          expect(
            tester.getSize(button).height,
            greaterThanOrEqualTo(SpacingTokens.minTapTarget),
          );
          expect(
            tester.getSize(button).width,
            greaterThanOrEqualTo(SpacingTokens.minTapTarget),
          );
          expect(
            tester.getRect(button).left,
            greaterThanOrEqualTo(tester.getRect(navTitle).right),
          );
          expect(
            tester.getRect(button).bottom,
            lessThanOrEqualTo(tester.getRect(appBar).bottom),
          );
        } else {
          await tester.ensureVisible(find.text('查看文字'));
          await tester.tap(find.text('查看文字'));
          await tester.pumpAndSettle();
          expect(
            find.text('观察图形并说明你的比较方法。', findRichText: true),
            findsOneWidget,
          );
        }
        await tester.tap(bookButton);
        await tester.pumpAndSettle();
        expect(find.text('原书 PDF 第 1 页'), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();
        expect(navTitle, findsOneWidget);
        expect(find.text('查看文字'), findsNothing);
        expect(
          find.text('收起文字'),
          knowledgePoint ? findsNothing : findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('math-reading-source-2')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await settleMathTextbookImages(tester);
        expect(
          rendered.any((r) => r.page == 2 && r.top == 0 && r.bottom == 1),
          isTrue,
        );
        expect(
          find.byKey(const ValueKey('math-reading-source-1')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
