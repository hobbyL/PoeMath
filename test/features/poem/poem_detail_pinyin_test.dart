// test/features/poem/poem_detail_pinyin_test.dart
//
// 诗词详情页拼音区：常驻折叠卡片 —— 默认收起、点击展开、展开后点击内容
// 可朗读。
//
// ── 契约变更说明（2026-10-19）────────────────────────────────────────
//
// 原先拼音由右上角开关控制**显隐**（状态写回 settings 的 `pinyin_visible`）
// 且不可折叠，与译文/注释/赏析等区块的处理方式不一致。现改为与它们同构的
// 折叠卡片，开关本身随之移除。
//
// 相关清理（同一批改动）：`pinyin_visible` settings key 与设置页的
// 「拼音显示」开关已一并移除 —— 详情页不再消费它，留着只会让用户以为
// 改了有效果。老备份若含该 key，恢复时因不在白名单而被跳过（不报错）。

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

const _poemId = 'pinyin-detail-poem';

final _poem = Poem(
  id: _poemId,
  title: '拼音测试诗',
  author: '测试作者',
  dynasty: '唐',
  content: '床前明月光',
  pinyin: 'chuáng qián míng yuè guāng',
  layer: 'core',
  grade: 1,
);

Future<_MockTtsService> _pumpPage(WidgetTester tester) async {
  final tts = _MockTtsService();
  when(() => tts.stop()).thenAnswer((_) async {});
  // 页面在发起朗读后同步读 `currentSessionId`；mock 默认返回 null 会在
  // `as int` 处抛 `type 'Null' is not a subtype of type 'int'`。
  when(() => tts.currentSessionId).thenReturn(1);
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
  return tts;
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

  testWidgets('拼音卡片常驻且默认收起', (tester) async {
    await _pumpPage(tester);

    // 卡片标题常驻。
    expect(find.text('拼音'), findsOneWidget);
    // 默认收起：拼音内容不可见。
    expect(find.text('chuáng qián míng yuè guāng'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('点击拼音卡片展开后可见内容', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.text('拼音'));
    await tester.pumpAndSettle();

    expect(find.text('chuáng qián míng yuè guāng'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('展开后点击内容触发拼音朗读', (tester) async {
    final tts = await _pumpPage(tester);
    // 非正文区走 `speakSentences`（正文才走 `speakLines`）。
    when(
      () => tts.speakSentences(any(), onReady: any(named: 'onReady')),
    ).thenAnswer((_) async {});

    await tester.tap(find.text('拼音'));
    await tester.pumpAndSettle();

    // 点击展开后的内容区（不是标题行）应触发朗读。
    await tester.tap(find.text('chuáng qián míng yuè guāng'));
    await tester.pump(const Duration(milliseconds: 100));

    verify(
      () => tts.speakSentences(
        'chuáng qián míng yuè guāng',
        onReady: any(named: 'onReady'),
      ),
    ).called(1);

    await _unmount(tester);
  });
}
