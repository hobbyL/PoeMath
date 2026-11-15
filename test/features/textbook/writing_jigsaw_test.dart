import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';
import 'package:poemath/features/textbook/writing/writing_jigsaw.dart';

import '../../helpers/theme_contrast.dart';
import '../../helpers/writing_jigsaw_test_helper.dart';

void main() {
  late WritingStrokeAsset asset;
  setUpAll(() async => asset = await loadJigsawTestAsset());

  Future<void> pump(
    WidgetTester tester, {
    String character = '星',
    Future<bool> Function(String, DateTime)? save,
    VoidCallback? write,
    Size size = const Size(400, 760),
    double scale = 1,
    ThemeData? theme,
    bool enabled = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(title: Text('拼一拼 · $character')),
          body: Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: WritingJigsaw(
              character: character,
              strokeData: asset[character],
              onCompleted: save ?? (_, _) async => true,
              onWrite: write ?? () {},
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认浅色整字提示可开关，已经吸附的碎片与布局不重置', (tester) async {
    await pump(tester);
    expect(find.text('拖动碎片，拼回整字。'), findsNothing);
    expect(jigsawPainter(tester).showHint, isTrue);
    final layout = jigsawPainter(tester).layout;
    final id = layout.trayOrder.first;
    await dragJigsawPiece(tester, id, grip: const Offset(0.72, 0.31));
    expect(jigsawPainter(tester).placed, {id});
    expect(find.byKey(ValueKey('jigsaw-piece-$id')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('jigsaw-hint-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('开启提示'), findsOneWidget);
    expect(jigsawPainter(tester).showHint, isFalse);
    expect(jigsawPainter(tester).placed, {id});
    expect(jigsawPainter(tester).layout, same(layout));
    await tester.tap(find.text('开启提示'));
    await tester.pumpAndSettle();
    expect(jigsawPainter(tester).showHint, isTrue);
    expect(jigsawPainter(tester).placed, {id});
    expect(jigsawPainter(tester).layout, same(layout));
  });

  testWidgets('放错位置不算完成；能重新拖动后吸附，每片都有真实字形', (tester) async {
    final saves = <String>[];
    await pump(
      tester,
      save: (id, _) async {
        saves.add(id);
        return true;
      },
    );
    final painter = jigsawPainter(tester);
    for (final piece in painter.layout.pieces) {
      expect(
        painter.glyph.contains(Offset(piece.inkPoint.x, piece.inkPoint.y)),
        isTrue,
      );
    }
    final id = painter.layout.trayOrder.first;
    await dragJigsawPiece(tester, id, correct: false);
    expect(jigsawPainter(tester).placed, isEmpty);
    expect(find.byKey(ValueKey('jigsaw-piece-$id')), findsOneWidget);
    expect(find.text('再挪一挪，让笔画接起来。'), findsOneWidget);
    expect(saves, isEmpty);
    await dragJigsawPiece(tester, id);
    expect(jigsawPainter(tester).placed, {id});
    expect(saves, isEmpty);
  });

  testWidgets('先选碎片再点位置，也能拼装；错误点击保留碎片', (tester) async {
    await pump(tester);
    final piece = jigsawPainter(tester).layout.pieces.first;
    await tester.ensureVisible(
      find.byKey(ValueKey('jigsaw-piece-${piece.id}')),
    );
    await tester.tap(find.byKey(ValueKey('jigsaw-piece-${piece.id}')));
    await tester.pumpAndSettle();
    final board = tester.getRect(find.byKey(const ValueKey('jigsaw-board')));
    final other = jigsawPainter(tester).layout.pieces.last.inkPoint;
    await tester.tapAt(
      board.topLeft + Offset(other.x * board.width, other.y * board.height),
    );
    await tester.pumpAndSettle();
    expect(jigsawPainter(tester).placed, isEmpty);
    await tester.tapAt(
      board.topLeft +
          Offset(
            piece.inkPoint.x * board.width,
            piece.inkPoint.y * board.height,
          ),
    );
    await tester.pumpAndSettle();
    expect(jigsawPainter(tester).placed, {piece.id});
  });

  testWidgets('完整拼装保存一次；重新开始使用新 round ID 并保留提示选择', (tester) async {
    final rounds = <String>[];
    await pump(
      tester,
      save: (round, _) async {
        rounds.add(round);
        return true;
      },
    );
    await tester.tap(find.text('关闭提示'));
    await tester.pumpAndSettle();
    for (final id in jigsawPainter(tester).layout.trayOrder) {
      await dragJigsawPiece(tester, id);
    }
    expect(find.text('拼好了！'), findsOneWidget);
    expect(jigsawPainter(tester).placed, hasLength(6));
    expect(rounds, hasLength(1));
    await tester.pumpAndSettle();
    expect(rounds, hasLength(1));
    await tester.tap(find.text('再拼一次'));
    await tester.pumpAndSettle();
    expect(jigsawPainter(tester).placed, isEmpty);
    expect(jigsawPainter(tester).showHint, isFalse);
    for (final id in jigsawPainter(tester).layout.trayOrder) {
      await dragJigsawPiece(tester, id);
    }
    expect(rounds, hasLength(2));
    expect(rounds.last, isNot(rounds.first));
  });

  testWidgets('失败重试沿用同一 round ID；保存中和未保存时不能清空本轮', (tester) async {
    final rounds = <String>[];
    final firstSave = Completer<bool>();
    await pump(
      tester,
      save: (round, _) {
        rounds.add(round);
        return rounds.length == 1 ? firstSave.future : Future.value(true);
      },
    );
    for (final id in jigsawPainter(tester).layout.trayOrder) {
      await dragJigsawPiece(tester, id);
    }
    expect(find.text('正在保存拼装记录…'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('jigsaw-restart')))
          .onPressed,
      isNull,
    );
    firstSave.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('拼装记录还没保存，请重试。'), findsOneWidget);
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(rounds, hasLength(2));
    expect(rounds.first, rounds.last);
    expect(find.text('完整的字拼出来啦。'), findsNothing);
    expect(find.text('去写一写'), findsOneWidget);
  });

  for (final subject in AppSubject.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$subject/$brightness 窄屏大字号与横屏能拖取全部碎片，控件清晰', (tester) async {
        for (final size in [const Size(320, 568), const Size(760, 360)]) {
          await pump(
            tester,
            size: size,
            scale: 2,
            theme: AppTheme.resolve(subject: subject, brightness: brightness),
          );
          expectReadableText(tester, find.text('关闭提示'));
          final board = tester.getRect(
            find.byKey(const ValueKey('jigsaw-board')),
          );
          final tray = tester.getRect(
            find.byKey(const ValueKey('jigsaw-tray')),
          );
          expect(tray.top, greaterThanOrEqualTo(board.bottom));
          expect(tray.center.dx, closeTo(board.center.dx, 0.01));
          expect(tester.takeException(), isNull);
          for (final id in jigsawPainter(tester).layout.trayOrder) {
            final finder = find.byKey(ValueKey('jigsaw-piece-$id'));
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            final hitSize = tester.getSize(finder);
            expect(
              hitSize.width,
              greaterThanOrEqualTo(SpacingTokens.minTapTarget),
            );
            expect(
              hitSize.height,
              greaterThanOrEqualTo(SpacingTokens.minTapTarget),
            );
            await dragJigsawPiece(tester, id);
            expect(jigsawPainter(tester).placed, contains(id));
          }
          expect(find.text('拼好了！'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('无字形数据的字保留自己写入口', (tester) async {
    var writes = 0;
    await pump(tester, character: '𠮷', write: () => writes++);
    expect(find.byKey(const ValueKey('jigsaw-unavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('jigsaw-board')), findsNothing);
    await tester.tap(find.text('自己写'));
    expect(writes, 1);
  });
}
