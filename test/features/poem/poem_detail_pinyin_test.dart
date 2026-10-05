// test/features/poem/poem_detail_pinyin_test.dart
//
// R5 拼音单一事实源回归测试：详情页拼音开关须同步写回 settings
// （Hive `pinyin_visible`），与设置页/备份白名单的值保持一致。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
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

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('详情页拼音开关写回 settings 的 pinyin_visible', (tester) async {
    final tts = _MockTtsService();
    when(() => tts.stop()).thenAnswer((_) async {});

    // 预置关闭态（默认 getter 为 true，需要从关闭开始才能观察写回）。
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('pinyin_visible', false);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          poemByIdProvider(_poemId).overrideWith((ref) => _poem),
          ttsServiceProvider.overrideWithValue(tts),
        ],
        child: const MaterialApp(
          home: PoemDetailPage(poemId: _poemId),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('显示拼音'), findsOneWidget);
    expect(HiveBoxes.settings.get('pinyin_visible'), isFalse);

    // Hive 写在 FakeAsync 中不会完成，走 runAsync 真实时序（模式 2）。
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('显示拼音'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();

    // UI 反映新状态，且持久化值同步写回（与设置页/备份白名单同源）。
    expect(find.byTooltip('隐藏拼音'), findsOneWidget);
    expect(HiveBoxes.settings.get('pinyin_visible'), isTrue);

    // 卸载页面并放掉残余定时器（TTS/动画），避免 timersPending 断言。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
