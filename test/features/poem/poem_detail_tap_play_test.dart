// test/features/poem/poem_detail_tap_play_test.dart
//
// 诗词详情页区域点击播放回归测试（任务 10-06-poem-detail-tap-play）：
// - AppBar 播放按钮移除，点击正文整块区域朗读全文
// - 折叠区展开后点击内容播放该区域文本
// - 云端合成期间 loading 遮罩拦截重复点击，首段就绪后解除
// - 播放中点击语义：同区域停止 / 跨区域切换

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/poem/poem_detail_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class _MockTtsService extends Mock implements TtsService {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

const _poemId = 'tap-play-poem';

final _poem = Poem(
  id: _poemId,
  title: '静夜思',
  author: '李白',
  dynasty: '唐',
  content: '床前明月光，\n疑是地上霜。',
  pinyin: '',
  layer: 'core',
  translation: '明亮的月光洒在窗前。',
  annotations: const [],
  appreciation: '',
  background: '',
  famousLines: const [],
);

const _contentLines = <String>['床前明月光，', '疑是地上霜。'];

/// 可控朗读脚本：模拟 speakLines/speakSentences 的两阶段时序。
///
/// - 阶段一（合成期）：Future 挂起，对应页面遮罩期
/// - [signalReady]：触发 onReady 回调（首段音频开始播放），遮罩解除
/// - 阶段二（朗读期）：Future 继续挂起，对应页面朗读中状态
/// - [signalFinish]：朗读 Future 完成，页面回到空闲
class _SpeakScript {
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _finish = Completer<void>();

  void signalReady() => _ready.complete();
  void signalFinish() => _finish.complete();

  Future<void> run(void Function()? onReady) async {
    await _ready.future;
    onReady?.call();
    await _finish.future;
  }
}

/// mock speakLines 并返回可控脚本。
///
/// [autoComplete] 为 true 时立即走完两个阶段（瞬时朗读，页面直接回空闲）。
_SpeakScript _stubSpeakLines(
  _MockTtsService tts, {
  bool autoComplete = true,
}) {
  final script = _SpeakScript();
  when(
    () => tts.speakLines(
      any<List<String>>(),
      onLineStart: any(named: 'onLineStart'),
      onReady: any(named: 'onReady'),
    ),
  ).thenAnswer((invocation) async {
    final onReady =
        invocation.namedArguments[#onReady] as void Function()?;
    await script.run(onReady);
  });
  if (autoComplete) {
    script
      ..signalReady()
      ..signalFinish();
  }
  return script;
}

/// mock speakSentences 并返回可控脚本（时序语义同上）。
_SpeakScript _stubSpeakSentences(
  _MockTtsService tts, {
  bool autoComplete = true,
}) {
  final script = _SpeakScript();
  when(
    () => tts.speakSentences(
      any<String>(),
      onReady: any(named: 'onReady'),
    ),
  ).thenAnswer((invocation) async {
    final onReady =
        invocation.namedArguments[#onReady] as void Function()?;
    await script.run(onReady);
  });
  if (autoComplete) {
    script
      ..signalReady()
      ..signalFinish();
  }
  return script;
}

Future<void> _pumpPage(WidgetTester tester, _MockTtsService tts) async {
  final settings = _MockSettingsRepository();
  when(() => settings.pinyinVisible).thenReturn(false);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        ttsServiceProvider.overrideWithValue(tts),
        poemByIdProvider(_poemId).overrideWith((ref) => _poem),
        isFavoriteProvider(_poemId).overrideWith((ref) => false),
        poemProgressProvider(_poemId).overrideWith((ref) => null),
      ],
      child: const MaterialApp(
        home: PoemDetailPage(poemId: _poemId),
      ),
    ),
  );
  // 等待 AnimatedPageBody 入场动画完成。
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late _MockTtsService tts;

  setUp(() {
    tts = _MockTtsService();
    when(() => tts.stop()).thenAnswer((_) async {});
  });

  testWidgets('AppBar 无播放按钮，点击正文朗读全文', (tester) async {
    _stubSpeakLines(tts);

    await _pumpPage(tester, tts);

    expect(find.byTooltip('朗读全文'), findsNothing);
    expect(find.byTooltip('停止朗读'), findsNothing);

    await tester.tap(find.text('床前明月光，'));
    await tester.pump();

    final captured = verify(
      () => tts.speakLines(
        captureAny(),
        onLineStart: any(named: 'onLineStart'),
        onReady: any(named: 'onReady'),
      ),
    ).captured;
    expect(captured.first, _contentLines);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('合成挂起期间遮罩可见且重复点击不二次请求', (tester) async {
    final script = _stubSpeakLines(tts, autoComplete: false);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('床前明月光，'));
    await tester.pump();

    // 遮罩期：loading 可见。
    expect(find.text('语音合成中…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 遮罩层吸收点击（Container 命中测试拦截），正文不再收到手势。
    await tester.tap(find.text('床前明月光，'), warnIfMissed: false);
    await tester.pump();

    verify(
      () => tts.speakLines(
        any<List<String>>(),
        onLineStart: any(named: 'onLineStart'),
        onReady: any(named: 'onReady'),
      ),
    ).called(1);
    verifyNever(() => tts.stop());

    // 首段就绪 → 遮罩解除，但朗读仍在进行（_isSpeaking 保持）。
    script.signalReady();
    await tester.pump();
    expect(find.text('语音合成中…'), findsNothing);

    script.signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('播放中点击正文停止朗读', (tester) async {
    final script = _stubSpeakLines(tts, autoComplete: false);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('床前明月光，'));
    await tester.pump();

    // 首段就绪：遮罩解除，speakLines 的 Future 仍挂起（朗读进行中）。
    script.signalReady();
    await tester.pump();
    expect(find.text('语音合成中…'), findsNothing);

    // 朗读中点击正文 → stop 被调用。
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();

    verify(() => tts.stop()).called(1);

    script.signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('播放中点击展开的译文内容：停止当前并播放译文', (tester) async {
    final contentScript = _stubSpeakLines(tts, autoComplete: false);
    final translationScript = _stubSpeakSentences(tts, autoComplete: false);

    await _pumpPage(tester, tts);

    // 展开译文折叠区（点击标题只展开，不触发播放）。
    await tester.tap(find.text('译文'));
    await tester.pumpAndSettle();
    verifyNever(() => tts.speak(any<String>()));
    verifyNever(
      () => tts.speakSentences(any<String>(), onReady: any(named: 'onReady')),
    );

    // 正文朗读中（首段就绪，朗读挂起）。
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    contentScript.signalReady();
    await tester.pump();

    // 点击展开后的译文内容 → stop + speakSentences(translation)。
    await tester.tap(find.text(_poem.translation));
    await tester.pump();

    verify(() => tts.stop()).called(1);
    final captured = verify(
      () => tts.speakSentences(
        captureAny(),
        onReady: any(named: 'onReady'),
      ),
    ).captured;
    expect(captured.first, _poem.translation);

    // 收尾：放行挂起的朗读 Future，避免残留 pending 状态。
    contentScript.signalFinish();
    translationScript
      ..signalReady()
      ..signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('折叠态点击译文标题仅展开不触发任何朗读', (tester) async {
    _stubSpeakLines(tts);
    _stubSpeakSentences(tts);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('译文'));
    await tester.pumpAndSettle();

    verifyNever(() => tts.speak(any<String>()));
    verifyNever(
      () => tts.speakSentences(any<String>(), onReady: any(named: 'onReady')),
    );
    verifyNever(() => tts.stop());

    // 展开后内容可见。
    expect(find.text(_poem.translation), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('空闲点击展开的译文内容播放该区域文本', (tester) async {
    _stubSpeakSentences(tts);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('译文'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_poem.translation));
    await tester.pump();

    final captured = verify(
      () => tts.speakSentences(
        captureAny(),
        onReady: any(named: 'onReady'),
      ),
    ).captured;
    expect(captured.first, _poem.translation);
    verifyNever(() => tts.stop());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('播放中折叠区标题显示播放指示图标', (tester) async {
    final script = _stubSpeakSentences(tts, autoComplete: false);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('译文'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_poem.translation));
    await tester.pump();
    script.signalReady();
    await tester.pump();

    // 播放中：译文标题旁出现 graphic_eq 指示（译文区唯一该图标）。
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 朗读结束 → 指示消失。
    script.signalFinish();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
