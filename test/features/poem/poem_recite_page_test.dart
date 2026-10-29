// test/features/poem/poem_recite_page_test.dart
//
// 背诵页基础契约：
// - ReciteLevel 与掌握等级映射；
// - 默写模式「提交默写」按钮随输入启用/禁用（原先无输入监听，按钮永不启用）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/models/poem.dart';
import 'package:poemath/features/poem/poem_recite_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';

import '../../helpers/hive_test_helper.dart';

const _poemId = 'recite-submit-poem';

final _poem = Poem(
  id: _poemId,
  title: '提交态测试诗',
  author: '测试作者',
  dynasty: '唐',
  content: '床',
  pinyin: '',
  layer: 'core',
  grade: 1,
);

void main() {
  test('ReciteLevel 与背诵掌握等级 1-4 一一对应', () {
    expect(ReciteLevel.easy.masteryLevel, 1);
    expect(ReciteLevel.medium.masteryLevel, 2);
    expect(ReciteLevel.hard.masteryLevel, 3);
    expect(ReciteLevel.dictation.masteryLevel, 4);
  });

  group('默写提交按钮启用态', () {
    setUp(() async {
      await setUpHiveForTesting();
    });

    tearDown(() async {
      await tearDownHiveForTesting();
    });

    /// 进入默写模式（手写为默认输入，先切到键盘）；结束时提交按钮处于禁用态。
    Future<void> enterDictation(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            poemByIdProvider(_poemId).overrideWith((ref) => _poem),
            writingStrokeDataProvider.overrideWith(
              (ref) => const WritingStrokeAsset({}),
            ),
          ],
          child: const MaterialApp(home: PoemRecitePage(poemId: _poemId)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('默写'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 默写默认手写，本组回归的是键盘输入路径：切到键盘。
      await tester.tap(find.byTooltip('切换键盘输入'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    bool submitEnabled(WidgetTester tester) {
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '提交默写'),
      );
      return button.onPressed != null;
    }

    testWidgets('输入后按钮启用，清空后重新禁用', (tester) async {
      await enterDictation(tester);

      expect(find.widgetWithText(FilledButton, '提交默写'), findsOneWidget);
      expect(submitEnabled(tester), isFalse, reason: '空输入时应禁用');

      // 回归点：原先既无 addListener 也无 onChanged，输入不触发重建，
      // 按钮永远停在禁用态，默写模式整条链路无法走通。
      await tester.enterText(find.byType(TextField), '床');
      await tester.pump();
      expect(submitEnabled(tester), isTrue);

      // 纯空白输入等同于空。
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(submitEnabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), '床');
      await tester.pump();
      expect(submitEnabled(tester), isTrue);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(submitEnabled(tester), isFalse);

      expect(tester.takeException(), isNull);
    });

    testWidgets('切换关卡会清空输入并重新禁用按钮', (tester) async {
      await enterDictation(tester);

      await tester.enterText(find.byType(TextField), '床');
      await tester.pump();
      expect(submitEnabled(tester), isTrue);

      // _changeLevel 内部 clear() 也必须让按钮回到禁用态
      // （监听器覆盖键入与程序化清空两条路径）。
      await tester.tap(find.text('简单'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('默写'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
      expect(submitEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
