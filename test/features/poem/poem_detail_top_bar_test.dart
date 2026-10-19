// test/features/poem/poem_detail_top_bar_test.dart
//
// 诗词详情页顶部结构：无 AppBar，返回/诗题+作者/拼音+收藏 一条悬浮条，
// 滚动时固定不动。
//
// 背景：原为 `AppBar(title: 诗题, actions: [拼音, 收藏])`，占掉整条高度。
// 改为悬浮条后正文多出一屏空间；诗题与作者在这条里左右排布、基线对齐、
// 相对**屏幕**居中。
//
// 写法沿用 `poem_detail_pinyin_test`：`pump(Duration)` 推进页面入场动画，
// Hive 写入走 `runAsync`。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/poem/poem_detail_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

import '../../helpers/hive_test_helper.dart';

class _MockTtsService extends Mock implements TtsService {}

const _poemId = 'top-bar-poem';

final _poem = Poem(
  id: _poemId,
  title: '静夜思',
  author: '李白',
  dynasty: '唐',
  content: '床前明月光\n疑是地上霜',
  pinyin: 'chuáng qián míng yuè guāng',
  layer: 'core',
  grade: 1,
);

Future<void> _pumpPage(WidgetTester tester) async {
  final tts = _MockTtsService();
  when(() => tts.stop()).thenAnswer((_) async {});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        poemByIdProvider(_poemId).overrideWith((ref) => _poem),
        ttsServiceProvider.overrideWithValue(tts),
      ],
      child: const MaterialApp(home: PoemDetailPage(poemId: _poemId)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 卸载页面并放掉残余定时器（TTS/入场动画），否则框架会以
/// 「A Timer is still pending even after the widget tree was disposed」判失败。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('顶部无 AppBar，返回按钮与诗题+作者同屏', (tester) async {
    await _pumpPage(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('返回'), findsOneWidget);
    // 诗题只出现一次（原先 AppBar 标题 + 正文标题会重复两次）。
    expect(find.text('静夜思'), findsOneWidget);
    expect(find.text('〔唐〕李白'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('诗题与作者基线对齐，且整组相对屏幕水平居中', (tester) async {
    await _pumpPage(tester);

    final title = tester.getRect(find.text('静夜思'));
    final author = tester.getRect(find.text('〔唐〕李白'));

    // 左右排布：作者在诗题右侧。
    expect(author.left, greaterThan(title.left));
    // 基线对齐：两段文字的底边应基本齐平（同一 textBaseline）。
    expect((title.bottom - author.bottom).abs(), lessThan(6));

    // 整组居中：整组中点与屏幕中点对齐（容差 2px）。
    final groupCenter = (title.left + author.right) / 2;
    final screenCenter = tester.view.physicalSize.width /
        tester.view.devicePixelRatio /
        2;
    expect((groupCenter - screenCenter).abs(), lessThan(2));

    await _unmount(tester);
  });

  testWidgets('滚动后悬浮条位置不变', (tester) async {
    await _pumpPage(tester);

    final before = tester.getRect(find.byTooltip('返回'));

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byTooltip('返回'), findsOneWidget);
    expect(tester.getRect(find.byTooltip('返回')), before);

    await _unmount(tester);
    await drainHiveWritesForTesting(tester);
  });
}
