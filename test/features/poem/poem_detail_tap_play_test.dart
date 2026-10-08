// test/features/poem/poem_detail_tap_play_test.dart
//
// 诗词详情页区域点击播放回归测试（任务 10-06-poem-detail-tap-play）：
// - AppBar 播放按钮移除，点击正文整块区域朗读全文
// - 折叠区展开后点击内容播放该区域文本
// - 云端合成期间 loading 遮罩拦截重复点击，首段就绪后解除
// - 播放中点击语义：同区域停止 / 跨区域切换
// - 审查修复（任务 10-06-tap-play-review-fix）：stop 失败不切换（无双读）、
//   切换窗口期连点仅启动一次新朗读
// - 二轮审查修复（任务 10-07-tts-session-token）：stop 失败保留播放态、
//   同区停止重入守卫、`_isPreparing` 代码守卫真覆盖（绕过遮罩的等价时序）、
//   云端全跳句页面级联提示

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
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

/// 会话身份模拟器：复刻 TtsService 的会话代际令牌语义。
///
/// 真服务在朗读入口的**同步段**（任何 await 之前）递增令牌，回调携带
/// 该 id，`currentSessionId` 返回最新值。mock 必须同构，否则：
/// 恒返回常量时，过期会话的晚到回调会与新会话 id 相等而被误判为
/// 「当前会话」——正是 R3 要防的那个 bug，测试会假绿。
class _SessionIds {
  int _current = 0;

  int get current => _current;

  /// 新会话诞生：递增并返回本次会话 id（对应真服务入口同步段）。
  int next() => ++_current;
}

/// 可控朗读脚本：模拟 speakLines/speakSentences 的两阶段时序。
///
/// - 阶段一（合成期）：Future 挂起，对应页面遮罩期
/// - [signalReady]：触发 onReady 回调（首段音频开始播放），遮罩解除
/// - 阶段二（朗读期）：Future 继续挂起，对应页面朗读中状态
/// - [signalFinish]：朗读 Future 完成，页面回到空闲
class _SpeakScript {
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _finish = Completer<void>();

  /// 本次会话 id 与 onLineStart 回调，供 [signalLine] 手动投递行回调。
  int? _sessionId;
  void Function(int index, int sessionId)? _onLineStart;

  void signalReady() => _ready.complete();
  void signalFinish() => _finish.complete();

  /// 手动投递一次 onLineStart（模拟行推进；可在会话过期后投递，
  /// 用于验证页面的会话身份判定）。
  void signalLine(int index) => _onLineStart?.call(index, _sessionId!);

  /// [sessionId] 为本次会话 id，随回调回传（与真服务一致）。
  Future<void> run(
    void Function(int sessionId)? onReady,
    int sessionId, {
    void Function(int index, int sessionId)? onLineStart,
  }) async {
    _sessionId = sessionId;
    _onLineStart = onLineStart;
    await _ready.future;
    onReady?.call(sessionId);
    await _finish.future;
  }
}

/// mock speakLines 并返回可控脚本。
///
/// [autoComplete] 为 true 时立即走完两个阶段（瞬时朗读，页面直接回空闲）。
_SpeakScript _stubSpeakLines(
  _MockTtsService tts,
  _SessionIds sessions, {
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
    // thenAnswer 体的同步段等价于真服务入口同步段：在首个 await 之前
    // 递增令牌，页面随后读 currentSessionId 即得本次会话 id。
    final sessionId = sessions.next();
    final onReady =
        invocation.namedArguments[#onReady] as void Function(int)?;
    final onLineStart =
        invocation.namedArguments[#onLineStart] as void Function(int, int)?;
    await script.run(onReady, sessionId, onLineStart: onLineStart);
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
  _MockTtsService tts,
  _SessionIds sessions, {
  bool autoComplete = true,
}) {
  final script = _SpeakScript();
  when(
    () => tts.speakSentences(
      any<String>(),
      onReady: any(named: 'onReady'),
    ),
  ).thenAnswer((invocation) async {
    final sessionId = sessions.next();
    final onReady =
        invocation.namedArguments[#onReady] as void Function(int)?;
    await script.run(onReady, sessionId);
  });
  if (autoComplete) {
    script
      ..signalReady()
      ..signalFinish();
  }
  return script;
}

/// 当前被高亮的正文行文本（行高亮 = AnimatedContainer 背景非透明）。
///
/// 正文行高亮由 `_isSpeaking && i == _currentLineIndex` 决定，是「行回调
/// 归属判定」的可观测产物。
List<String> _highlightedLines(WidgetTester tester) {
  final highlighted = <String>[];
  for (final line in _contentLines) {
    final finder = find.ancestor(
      of: find.text(line),
      matching: find.byType(AnimatedContainer),
    );
    if (finder.evaluate().isEmpty) continue;
    final container = tester.widget<AnimatedContainer>(finder.first);
    final decoration = container.decoration as BoxDecoration?;
    if (decoration?.color != null && decoration!.color != Colors.transparent) {
      highlighted.add(line);
    }
  }
  return highlighted;
}

Future<void> _pumpPage(WidgetTester tester, TtsService tts) async {
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

/// 绕过遮罩的等价时序（AC5）：直接调用遮罩层下可点区域的 onTap 回调。
///
/// 遮罩 Container 在命中测试层拦截指针，tester 的手势永远送达遮罩——
/// 这里取得目标文本最近的 InkWell 祖先并直接调用其 onTap，等价于
/// 「遮罩不存在时用户再次点击」，用于验证 `_isPreparing` 代码守卫
/// （删守卫此路径必须红：会发起第二次 stop / 新朗读）。
Future<void> _tapUnderOverlay(WidgetTester tester, Finder textFinder) async {
  final inkWell = tester.widget<InkWell>(
    find.ancestor(of: textFinder, matching: find.byType(InkWell)).first,
  );
  // onTap 为 VoidCallback（内部异步），同步调用后 pump 推进时序。
  inkWell.onTap?.call();
  await tester.pump();
}

/// AC4 页面级联：恒返回音频字节的假 HTTP 客户端（云端合成恒成功）。
class _AlwaysAudioHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      http.ByteStream.fromBytes(Uint8List.fromList(List<int>.filled(8, 1))),
      200,
      headers: const {'content-type': 'audio/mpeg'},
    );
  }
}

/// AC4 页面级联：播放恒抛错的假云端播放器（audioplayers 损坏场景）。
class _ThrowingCloudPlayer implements CloudAudioPlayer {
  int playFailures = 0;

  @override
  Future<void> play(Uint8List bytes) async {
    playFailures++;
    throw Exception('audioplayers failure');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// AC4 页面级联：记录系统朗读的最小假引擎（验证不回退双读）。
class _RecordingFlutterTts extends Fake implements FlutterTts {
  final List<String> spokenTexts = <String>[];

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  void setCancelHandler(VoidCallback callback) {}

  @override
  void setErrorHandler(ErrorHandler handler) {}

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spokenTexts.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;
}

void main() {
  late _MockTtsService tts;
  late _SessionIds sessions;

  setUp(() {
    tts = _MockTtsService();
    sessions = _SessionIds();
    // 惰性求值：每次读取返回当前最新令牌（thenReturn 会固化为常量）。
    when(() => tts.currentSessionId).thenAnswer((_) => sessions.current);
    // 真服务 stop() 同步段即递增令牌；部分用例会覆盖本 stub 为抛错/挂起
    // 以制造失败与窗口期，那些覆盖不递增也不影响断言——会话 id 只需
    // 「每个新会话互不相同」，而递增由朗读入口保证。
    when(() => tts.stop()).thenAnswer((_) async {
      sessions.next();
    });
  });

  testWidgets('AppBar 无播放按钮，点击正文朗读全文', (tester) async {
    _stubSpeakLines(tts, sessions);

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
    final script = _stubSpeakLines(tts, sessions, autoComplete: false);

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
    final script = _stubSpeakLines(tts, sessions, autoComplete: false);

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
    final contentScript = _stubSpeakLines(tts, sessions, autoComplete: false);
    final translationScript =
        _stubSpeakSentences(tts, sessions, autoComplete: false);

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

  testWidgets('停止失败时点击其他区域：提示且不启动新朗读（无双读）', (tester) async {
    final contentScript = _stubSpeakLines(tts, sessions, autoComplete: false);
    _stubSpeakSentences(tts, sessions);

    await _pumpPage(tester, tts);

    // 展开译文折叠区。
    await tester.tap(find.text('译文'));
    await tester.pumpAndSettle();

    // 正文朗读中（首段就绪，朗读挂起）。
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    contentScript.signalReady();
    await tester.pump();

    // stop 抛异常：切换分支必须放弃，不允许新旧会话双读（R2）。
    when(() => tts.stop()).thenThrow(const TtsException('停止失败'));

    await tester.tap(find.text(_poem.translation));
    await tester.pump();

    expect(find.text('停止朗读失败，请稍后重试'), findsOneWidget);
    expect(find.text('语音合成中…'), findsNothing);
    // 新朗读未启动：speakSentences 零调用，speakLines 仍只有正文那一次。
    verifyNever(
      () => tts.speakSentences(any<String>(), onReady: any(named: 'onReady')),
    );
    verify(
      () => tts.speakLines(
        any<List<String>>(),
        onLineStart: any(named: 'onLineStart'),
        onReady: any(named: 'onReady'),
      ),
    ).called(1);

    // 收尾：恢复 stop stub 并放行挂起的朗读 Future。
    when(() => tts.stop()).thenAnswer((_) async {});
    contentScript.signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('切换窗口期连点两次仅启动一次新朗读', (tester) async {
    final contentScript = _stubSpeakLines(tts, sessions, autoComplete: false);
    final translationScript =
        _stubSpeakSentences(tts, sessions, autoComplete: false);
    // stop 挂起：制造「先置遮罩 → await stop」的切换窗口期（R3）。
    final stopGate = Completer<void>();
    when(() => tts.stop()).thenAnswer((_) => stopGate.future);

    await _pumpPage(tester, tts);

    // 展开译文折叠区。
    await tester.tap(find.text('译文'));
    await tester.pumpAndSettle();
    verifyNever(() => tts.speak(any<String>()));

    // 正文朗读中（首段就绪，朗读挂起）。
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    contentScript.signalReady();
    await tester.pump();

    // 第一次点击译文内容：进入切换窗口期，遮罩立即出现。
    // 停止窗口期遮罩文案为停止语义（缺陷 7）。
    await tester.tap(find.text(_poem.translation));
    await tester.pump();
    expect(find.text('正在停止…'), findsOneWidget);
    expect(find.text('语音合成中…'), findsNothing);

    // 窗口期第二次点击（遮罩吸收）：Container 命中测试拦截手势。
    await tester.tap(find.text(_poem.translation), warnIfMissed: false);
    await tester.pump();

    // 窗口期第三次点击（AC5 真覆盖）：绕过遮罩命中测试，直接调用遮罩
    // 层下译文 InkWell 的 onTap——等价于遮罩不存在时的再次点击，
    // 验证 `if (_isPreparing) return` 代码守卫。临时删除该守卫时
    // 此用例必须红（第二次 stop + 第二次 speakSentences）。
    await _tapUnderOverlay(tester, find.text(_poem.translation));

    // stop 放行 → 仅启动一次新朗读，stop 也只被调用一次。
    stopGate.complete();
    await tester.pump();

    verify(() => tts.stop()).called(1);
    verify(
      () => tts.speakSentences(any<String>(), onReady: any(named: 'onReady')),
    ).called(1);

    // 收尾：放行挂起的朗读 Future，避免残留 pending 状态。
    contentScript.signalFinish();
    translationScript
      ..signalReady()
      ..signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('stop 失败保留播放态：再点同区域再次走停止路由（AC1）', (tester) async {
    final script = _stubSpeakLines(tts, sessions, autoComplete: false);

    await _pumpPage(tester, tts);

    // 正文朗读中（首段就绪，朗读挂起）。
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    script.signalReady();
    await tester.pump();

    // stop 抛异常：音频确实还在播，页面不得显示空闲（缺陷 1：否则下次
    // 点击会绕过停止直达新朗读、复活旧会话双读）。
    when(() => tts.stop()).thenThrow(const TtsException('停止失败'));
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();

    expect(find.text('停止朗读失败，请稍后重试'), findsOneWidget);
    // 遮罩不挂死（R2：stop 失败也复位 _isPreparing）。
    expect(find.text('语音合成中…'), findsNothing);

    // 再点同区域：_isSpeaking 保留 → 再次走停止路由，不直达新朗读。
    when(() => tts.stop()).thenAnswer((_) async {});
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();

    verify(() => tts.stop()).called(2);
    verify(
      () => tts.speakLines(
        any<List<String>>(),
        onLineStart: any(named: 'onLineStart'),
        onReady: any(named: 'onReady'),
      ),
    ).called(1);

    // 收尾：放行挂起的朗读 Future（页面代际守卫已拦住旧会话回调）。
    script.signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('同区停止挂起期连点：stop 恰好一次且遮罩及时解除（AC3）', (tester) async {
    final script = _stubSpeakLines(tts, sessions, autoComplete: false);
    // stop 挂起：制造同区停止窗口期。
    final stopGate = Completer<void>();
    when(() => tts.stop()).thenAnswer((_) => stopGate.future);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    script.signalReady();
    await tester.pump();

    // 第一次点击同区域：进入停止窗口期，遮罩立即出现（R2：同区停止
    // 分支与切换分支一致的重入守卫）；文案为停止语义（缺陷 7 / AC5）。
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    expect(find.text('正在停止…'), findsOneWidget);
    expect(find.text('语音合成中…'), findsNothing);

    // 窗口期连点：遮罩吸收 + 绕过遮罩直接调用正文 InkWell onTap
    // 验证 `_isPreparing` 代码守卫（缺陷 5：删守卫此用例必须红）。
    await tester.tap(find.text('床前明月光，'), warnIfMissed: false);
    await _tapUnderOverlay(tester, find.text('床前明月光，'));

    // stop 放行（成功）→ 恰好一次 stop，遮罩解除，页面回空闲。
    stopGate.complete();
    await tester.pump();
    verify(() => tts.stop()).called(1);
    expect(find.text('语音合成中…'), findsNothing);
    expect(find.text('正在停止…'), findsNothing);

    // 收尾：放行挂起的朗读 Future。
    script.signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('同区停止连点后 stop 失败：仅一次提示不误报（AC3）', (tester) async {
    final script = _stubSpeakLines(tts, sessions, autoComplete: false);
    final stopGate = Completer<void>();
    when(() => tts.stop()).thenAnswer((_) => stopGate.future);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    script.signalReady();
    await tester.pump();

    // 第一次点击同区域进入停止窗口期，连点被守卫拦截。
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    await _tapUnderOverlay(tester, find.text('床前明月光，'));

    // stop 以失败放行：恰一次 stop、恰一次 SnackBar——若 `_isPreparing`
    // 守卫缺失，第二次 stop 也会触发提示（与事实相反的误报）。
    stopGate.completeError(const TtsException('停止失败'));
    await tester.pump();

    verify(() => tts.stop()).called(1);
    expect(find.text('停止朗读失败，请稍后重试'), findsOneWidget);
    // 遮罩不挂死（R2），播放态由 R1 语义保留（_isSpeaking 不复位）。
    expect(find.text('语音合成中…'), findsNothing);

    // 收尾：恢复 stop stub 并放行挂起的朗读 Future。
    when(() => tts.stop()).thenAnswer((_) async {});
    script.signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('云端播放全程失败：页面显示朗读失败提示而非静默（AC4 级联）', (tester) async {
    // 真实 TtsService 级联：HTTP 恒成功（合成成功）+ 播放器恒抛错
    // → 两行均 skippedCloudPlay → 全跳句上抛 → 页面现有 catch 走 SnackBar。
    final settings = _MockSettingsRepository();
    when(() => settings.pinyinVisible).thenReturn(false);
    when(() => settings.ttsCloudEnabled).thenReturn(true);
    when(() => settings.ttsCloudVoice).thenReturn(kDefaultWorkerVoice);
    when(() => settings.ttsCloudStyle).thenReturn('poetry-reading');
    when(() => settings.ttsSpeed).thenReturn(0.5);
    when(() => settings.ttsVoice).thenReturn(null);
    when(() => settings.isWorkerTtsVerified()).thenAnswer((_) async => true);
    when(() => settings.readWorkerTtsConfig()).thenAnswer(
      (_) async => WorkerTtsConfig(
        base: Uri.parse('https://tts.example.com'),
        apiKey: 'test-key',
      ),
    );
    final engine = _RecordingFlutterTts();
    final player = _ThrowingCloudPlayer();
    final service = TtsService(
      settings,
      flutterTts: engine,
      cloudClient: WorkerTtsClient(httpClient: _AlwaysAudioHttpClient()),
      cloudPlayer: player,
    );

    await _pumpPage(tester, service);

    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 两行均「合成成功但播放失败」→ 不再是遮罩闪一下的静默会话。
    expect(player.playFailures, 2);
    expect(engine.spokenTexts, isEmpty); // 不回退系统双读
    // R2：服务文案（云端音频播放失败）透传到 SnackBar，不再被硬编码
    // 「请检查系统语音服务」误导排查方向。
    expect(find.text('朗读失败：云端音频播放失败，请稍后重试'), findsOneWidget);
    expect(find.text('语音合成中…'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('折叠态点击译文标题仅展开不触发任何朗读', (tester) async {
    _stubSpeakLines(tts, sessions);
    _stubSpeakSentences(tts, sessions);

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
    _stubSpeakSentences(tts, sessions);

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

  testWidgets('过期会话的晚到 onLineStart 不移动新会话高亮（R3 身份判定）', (tester) async {
    // 旧会话（正文逐行）的行回调在新会话（译文）启动后才到达，模拟
    // 「stop 已发出但旧 Future 尚未终结，旧回调晚到」的真实时序。
    // 把 `_isCurrentSession` 改成恒真时此用例必须红：旧会话的行索引会
    // 把正文行高亮点亮，而当前播放的是译文区。
    final contentScript = _stubSpeakLines(tts, sessions, autoComplete: false);
    final translationScript =
        _stubSpeakSentences(tts, sessions, autoComplete: false);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('译文'));
    await tester.pumpAndSettle();

    // 旧会话：首段就绪并推进到第 0 行（正文首行高亮）。
    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    contentScript.signalReady();
    contentScript.signalLine(0);
    await tester.pump();
    expect(_highlightedLines(tester), const <String>['床前明月光，']);

    // 切到译文：stop 成功 → 正文高亮清空，新会话进入朗读中。
    await tester.tap(find.text(_poem.translation));
    await tester.pump();
    translationScript.signalReady();
    await tester.pump();
    expect(_highlightedLines(tester), isEmpty);

    // 旧会话的行回调此刻才到达（携带旧 sessionId）：必须被判定为过期，
    // 不得点亮正文行——当前播放的是译文区。
    contentScript.signalLine(1);
    await tester.pump();
    expect(_highlightedLines(tester), isEmpty);

    // 收尾：放行两个挂起的朗读 Future。
    contentScript.signalFinish();
    translationScript.signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('过期会话的晚到 finally 不复位新会话播放态（R3 身份判定）', (tester) async {
    final contentScript = _stubSpeakLines(tts, sessions, autoComplete: false);
    final translationScript =
        _stubSpeakSentences(tts, sessions, autoComplete: false);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('译文'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('床前明月光，'));
    await tester.pump();
    contentScript.signalReady();
    await tester.pump();

    // 切到译文并让新会话进入「朗读中」（遮罩已解除）。
    await tester.tap(find.text(_poem.translation));
    await tester.pump();
    translationScript.signalReady();
    await tester.pump();
    expect(find.text('语音合成中…'), findsNothing);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 旧会话的 Future 此刻才终结：其 finally 携带旧 sessionId，不得把
    // 新会话的播放态清成空闲（守卫恒真时播放指示会消失）。
    contentScript.signalFinish();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 新会话自然结束 → 播放态正常归零。
    translationScript.signalFinish();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('播放中折叠区标题显示播放指示图标', (tester) async {
    final script = _stubSpeakSentences(tts, sessions, autoComplete: false);

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
