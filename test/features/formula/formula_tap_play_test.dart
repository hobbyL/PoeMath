// test/features/formula/formula_tap_play_test.dart
//
// 公式详情页区域点击播放回归测试（任务 10-07-formula-tts AC2）：
// - 点击公式区朗读「名称 + 参数释义」（formulaSpeakText 输出）
// - 点击记忆技巧 / 例题朗读符号可读化替换后的原文
// - 播放中该区标题旁显示 graphic_eq 指示图标
// - 同区再点停止 / 跨区先 stop 再播且仅一次 speakSentences
// - 合成期遮罩可见且点击不触发第二次朗读；onReady 后遮罩解除
// - TtsException → SnackBar 含 message
// - 关联公式导航三段语义：朗读中先停止且成功才导航（AC1）、stop 失败
//   留在本页（AC2）、空闲直接导航不调 stop（AC3）
// - 公式区播放中显示 graphic_eq 角标指示，切走后消失（AC4）
//
// mock 时序与诗词页同一模式（_SessionIds / _SpeakScript）：
// mock 必须同构复刻真服务的会话代际令牌语义，否则过期会话的晚到回调
// 会误匹配新会话 id，测试假绿（见 poem_detail_tap_play_test.dart）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/models/formula_param.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/formula/formula_detail_page.dart';
import 'package:poemath/features/formula/providers/formula_providers.dart';

class _MockTtsService extends Mock implements TtsService {}

const _formulaId = 'tap-play-formula';
const _relatedFormulaId = 'related-id';

/// 关联公式导航目标（镜像用例 9 的 related 构造）。
final _relatedFormula = Formula(
  id: _relatedFormulaId,
  category: '图形',
  name: '长方形面积',
  formulaText: 'S = a × b',
  formulaLatex: '',
  grade: 3,
  relatedFormulas: const [],
);

final _formula = Formula(
  id: _formulaId,
  category: '图形',
  name: '长方形周长',
  formulaText: 'C = (a + b) × 2',
  formulaLatex: '',
  grade: 3,
  params: [
    FormulaParam(symbol: 'C', meaning: '周长'),
    FormulaParam(symbol: 'a', meaning: '长'),
    FormulaParam(symbol: 'b', meaning: '宽'),
  ],
  memoryTip: '长加宽的和再乘 2。S = 36 cm²。',
  example: '长 5 cm、宽 3 cm，周长 = (5+3)×2 = 16 cm。',
  relatedFormulas: const [],
);

/// 记忆技巧朗读文本：朗读原文过符号读音替换。
const _memoryTipSpeakText = '长加宽的和再乘 2。S = 36 cm的平方。';

/// 会话身份模拟器：复刻 TtsService 的会话代际令牌语义（同诗词页）。
class _SessionIds {
  int _current = 0;

  int get current => _current;

  /// 新会话诞生：递增并返回本次会话 id（对应真服务入口同步段）。
  int next() => ++_current;
}

/// 可控朗读脚本：模拟 speakSentences 的两阶段时序（同诗词页）。
class _SpeakScript {
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _finish = Completer<void>();

  void signalReady() => _ready.complete();
  void signalFinish() => _finish.complete();

  Future<void> run(
    void Function(int sessionId)? onReady,
    int sessionId,
  ) async {
    await _ready.future;
    onReady?.call(sessionId);
    await _finish.future;
  }
}

/// 按调用次序分发脚本的朗读脚本记录器。
///
/// 公式页三区域都走 speakSentences（诗词页是 speakLines / speakSentences
/// 两个方法，可用两个独立 stub）；同一方法上后注册的 mock 会整体覆盖
/// 先前的——两次 `_stubSpeakSentences` 会共享最后一个脚本，旧会话的
/// signalFinish 实际不投递任何事件（变异测试假绿的根因）。这里每次
/// 调用新建脚本并按调用次序记录，测试用 `scripts[i]` 精确操控第 i 个
/// 会话的两阶段时序。
class _SpeakScriptRecorder {
  final List<_SpeakScript> scripts = [];

  _SpeakScriptRecorder(_MockTtsService tts, _SessionIds sessions) {
    when(
      () => tts.speakSentences(
        any<String>(),
        onReady: any(named: 'onReady'),
      ),
    ).thenAnswer((invocation) async {
      final sessionId = sessions.next();
      final onReady =
          invocation.namedArguments[#onReady] as void Function(int)?;
      final script = _SpeakScript();
      scripts.add(script);
      await script.run(onReady, sessionId);
    });
  }
}

/// mock speakSentences 并返回可控脚本。
///
/// [autoComplete] 为 true 时立即走完两个阶段（瞬时朗读，页面直接回空闲）。
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
    // thenAnswer 体的同步段等价于真服务入口同步段：在首个 await 之前
    // 递增令牌，页面随后读 currentSessionId 即得本次会话 id。
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

Future<void> _pumpPage(WidgetTester tester, TtsService tts) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ttsServiceProvider.overrideWithValue(tts),
        formulaByIdProvider(_formulaId).overrideWith((ref) => _formula),
        isFormulaFavoriteProvider(_formulaId).overrideWith((ref) => false),
      ],
      child: const MaterialApp(
        home: FormulaDetailPage(formulaId: _formulaId),
      ),
    ),
  );
  // 等待 AnimatedPageBody 入场动画完成。
  await tester.pump(const Duration(milliseconds: 500));
}

/// 带关联公式的测试公式：[relatedFormulas] 指向 [relatedFormula]。
Formula _formulaWithRelated() => Formula(
      id: _formulaId,
      category: _formula.category,
      name: _formula.name,
      formulaText: _formula.formulaText,
      formulaLatex: '',
      grade: _formula.grade,
      params: _formula.params,
      memoryTip: _formula.memoryTip,
      example: _formula.example,
      relatedFormulas: const [_relatedFormulaId],
    );

/// 关联公式导航目标的 pump 结构（用例 9 同一组 provider 覆写）。
///
/// 关联公式区在视口外（AnimatedPageBody 是 ListView 懒构建），
/// 须先滚动到可见。返回后需 `await tester.pumpAndSettle()` 收尾入场动画。
Future<void> _pumpPageWithRelated(WidgetTester tester, TtsService tts) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ttsServiceProvider.overrideWithValue(tts),
        formulaByIdProvider(_formulaId).overrideWith((ref) {
          return _formulaWithRelated();
        }),
        formulaByIdProvider(_relatedFormulaId).overrideWith(
          (ref) => _relatedFormula,
        ),
        // 点击关联公式标签会导航到新 FormulaDetailPage(_relatedFormulaId)，
        // 其收藏 provider 也需覆写（否则真 provider 触 Hive 未初始化）。
        isFormulaFavoriteProvider(_relatedFormulaId).overrideWith((ref) => false),
        isFormulaFavoriteProvider(_formulaId).overrideWith((ref) => false),
      ],
      child: const MaterialApp(
        home: FormulaDetailPage(formulaId: _formulaId),
      ),
    ),
  );
  // 等待 AnimatedPageBody 入场动画完成。
  await tester.pump(const Duration(milliseconds: 500));
}

/// 滚动到关联公式标签并点击，并 pump 一帧让点击处理器 setState 生效。
///
/// 注意不在此处 pumpAndSettle：朗读中点击的遮罩 / SnackBar 需要在
/// stop 结果揭晓前被断言，调用方自行控制后续时序。
Future<void> _tapRelatedChip(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text(_relatedFormula.name),
    100.0,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(_relatedFormula.name));
  await tester.pump();
}

void main() {
  late _MockTtsService tts;
  late _SessionIds sessions;

  setUp(() {
    tts = _MockTtsService();
    sessions = _SessionIds();
    // 惰性求值：每次读取返回当前最新令牌（thenReturn 会固化为常量）。
    when(() => tts.currentSessionId).thenAnswer((_) => sessions.current);
    when(() => tts.stop()).thenAnswer((_) async {
      sessions.next();
    });
  });

  testWidgets('点击记忆技巧区：朗读替换后文本并显示指示图标', (tester) async {
    final script = _stubSpeakSentences(tts, sessions, autoComplete: false);

    await _pumpPage(tester, tts);

    // 播放前无指示图标。
    expect(find.byIcon(Icons.graphic_eq), findsNothing);

    await tester.tap(find.text('记忆技巧'));
    await tester.pump();

    final captured = verify(
      () => tts.speakSentences(
        captureAny(),
        onReady: any(named: 'onReady'),
      ),
    ).captured;
    // AC2：朗读原文过符号读音替换（cm² → cm的平方），不是原文。
    expect(captured.first, _memoryTipSpeakText);
    expect(captured.first, isNot(_formula.memoryTip));

    // 首段就绪 → 遮罩解除，朗读中标题旁出现指示图标。
    script.signalReady();
    await tester.pump();
    expect(find.text('语音合成中…'), findsNothing);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 朗读结束 → 指示消失。
    script.signalFinish();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('点击公式区：朗读名称 + 参数释义而非符号串', (tester) async {
    _stubSpeakSentences(tts, sessions);

    await _pumpPage(tester, tts);

    // 公式区渲染的是 formulaText（formulaLatex 为空走纯文本降级）。
    await tester.tap(find.text(_formula.formulaText));
    await tester.pump();

    final captured = verify(
      () => tts.speakSentences(
        captureAny(),
        onReady: any(named: 'onReady'),
      ),
    ).captured;
    // AC2：读「名称 + 参数释义」，不读公式符号串。
    expect(captured.first, '长方形周长。C，周长。a，长。b，宽。');
    expect(captured.first, isNot(contains(_formula.formulaText)));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('点击例题区：朗读替换后例题文本', (tester) async {
    _stubSpeakSentences(tts, sessions);

    await _pumpPage(tester, tts);

    await tester.tap(find.text(_formula.example));
    await tester.pump();

    final captured = verify(
      () => tts.speakSentences(
        captureAny(),
        onReady: any(named: 'onReady'),
      ),
    ).captured;
    // × 读作「乘」：朗读文本 ≠ 界面原文。
    expect(captured.first, '长 5 cm、宽 3 cm，周长 = (5+3)乘2 = 16 cm。');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('合成挂起期间遮罩可见且重复点击不二次请求', (tester) async {
    final script = _stubSpeakSentences(tts, sessions, autoComplete: false);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('记忆技巧'));
    await tester.pump();

    // 遮罩期：loading 可见。
    expect(find.text('语音合成中…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 遮罩层吸收点击（Container 命中测试拦截），内容不再收到手势。
    await tester.tap(find.text('记忆技巧'), warnIfMissed: false);
    await tester.pump();

    verify(
      () => tts.speakSentences(any<String>(), onReady: any(named: 'onReady')),
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

  testWidgets('播放中同区再点：停止朗读', (tester) async {
    final script = _stubSpeakSentences(tts, sessions, autoComplete: false);

    await _pumpPage(tester, tts);

    await tester.tap(find.text('记忆技巧'));
    await tester.pump();
    script.signalReady();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 播放中再点同区 → stop 被调用，指示图标消失。
    await tester.tap(find.text('记忆技巧'));
    await tester.pump();

    verify(() => tts.stop()).called(1);
    expect(find.byIcon(Icons.graphic_eq), findsNothing);

    script.signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('播放中跨区点击：先 stop 再播放新区域，仅一次新朗读', (tester) async {
    final scripts = _SpeakScriptRecorder(tts, sessions);

    await _pumpPage(tester, tts);

    // 记忆技巧朗读中（首段就绪，朗读挂起）。
    await tester.tap(find.text('记忆技巧'));
    await tester.pump();
    scripts.scripts[0].signalReady();
    await tester.pump();

    // 点击例题 → stop + 一次新 speakSentences。
    await tester.tap(find.text(_formula.example));
    await tester.pump();

    verify(() => tts.stop()).called(1);
    final captured = verify(
      () => tts.speakSentences(
        captureAny(),
        onReady: any(named: 'onReady'),
      ),
    ).captured;
    // 共两次调用：第一次记忆技巧，第二次例题（替换后文本）。
    expect(captured, [
      _memoryTipSpeakText,
      '长 5 cm、宽 3 cm，周长 = (5+3)乘2 = 16 cm。',
    ]);

    // 收尾：放行两个挂起的朗读 Future。
    scripts.scripts[0].signalFinish();
    scripts.scripts[1]
      ..signalReady()
      ..signalFinish();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('朗读失败 TtsException：SnackBar 展示服务 message', (tester) async {
    // 朗读抛错（在 onReady 触发前），遮罩走 finally 兜底解除。
    when(
      () => tts.speakSentences(
        any<String>(),
        onReady: any(named: 'onReady'),
      ),
    ).thenThrow(const TtsException('云端音频播放失败，请稍后重试'));

    await _pumpPage(tester, tts);

    await tester.tap(find.text('记忆技巧'));
    await tester.pump();
    await tester.pump();

    // AC2：SnackBar 文案含服务 message，而非硬编码引擎提示。
    expect(
      find.text('朗读失败：云端音频播放失败，请稍后重试'),
      findsOneWidget,
    );
    // 遮罩不挂死（finally 兜底），播放态归零。
    expect(find.text('语音合成中…'), findsNothing);
    expect(find.byIcon(Icons.graphic_eq), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('过期会话的晚到 finally 不复位新会话播放态（R3 身份判定）', (tester) async {
    // 三区域同走 speakSentences，须按调用次序分发脚本（否则后注册的
    // mock 覆盖先前，旧会话的 signalFinish 不投递任何事件，守卫恒真
    // 的变异体存活——见 _SpeakScriptRecorder 注释）。
    final scripts = _SpeakScriptRecorder(tts, sessions);

    await _pumpPage(tester, tts);

    // 记忆技巧朗读中（首段就绪，朗读挂起）。
    await tester.tap(find.text('记忆技巧'));
    await tester.pump();
    scripts.scripts[0].signalReady();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 切到例题并让新会话进入「朗读中」（遮罩已解除）。
    await tester.tap(find.text(_formula.example));
    await tester.pump();
    scripts.scripts[1].signalReady();
    await tester.pump();
    expect(find.text('语音合成中…'), findsNothing);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 旧会话（记忆技巧）的 Future 此刻才终结：其 finally 携带旧 sessionId，
    // 不得把新会话的播放态清成空闲（守卫恒真时例题区指示会消失）。
    scripts.scripts[0].signalFinish();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 新会话自然结束 → 播放态正常归零。
    scripts.scripts[1].signalFinish();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('参数说明与关联公式区不可点击（纯展示区）', (tester) async {
    _stubSpeakSentences(tts, sessions);

    // 带关联公式构造，验证关联公式区同样不触发朗读。
    final related = Formula(
      id: 'related-id',
      category: '图形',
      name: '长方形面积',
      formulaText: 'S = a × b',
      formulaLatex: '',
      grade: 3,
      relatedFormulas: const [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWithValue(tts),
          formulaByIdProvider(_formulaId).overrideWith(
            (ref) => Formula(
              id: _formulaId,
              category: _formula.category,
              name: _formula.name,
              formulaText: _formula.formulaText,
              formulaLatex: '',
              grade: _formula.grade,
              params: _formula.params,
              memoryTip: _formula.memoryTip,
              example: _formula.example,
              relatedFormulas: const ['related-id'],
            ),
          ),
          formulaByIdProvider('related-id').overrideWith((ref) => related),
          // 点击关联公式标签会导航到新 FormulaDetailPage('related-id')，
          // 其收藏 provider 也需覆写（否则真 provider 触 Hive 未初始化）。
          isFormulaFavoriteProvider('related-id').overrideWith((ref) => false),
          isFormulaFavoriteProvider(_formulaId).overrideWith((ref) => false),
        ],
        child: const MaterialApp(
          home: FormulaDetailPage(formulaId: _formulaId),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 点击参数说明行：不触发任何朗读（参数说明是纯展示区）。
    await tester.tap(find.text('周长'));
    await tester.pump();

    // 关联公式区在视口外（AnimatedPageBody 是 ListView 懒构建），
    // 滚动到可见后点击标签：其语义是导航到关联公式，不是朗读入口。
    final listFinder = find.byType(Scrollable);
    await tester.scrollUntilVisible(
      find.text('长方形面积'),
      100.0,
      scrollable: listFinder.first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('长方形面积'));
    await tester.pump();

    verifyNever(
      () => tts.speakSentences(any<String>(), onReady: any(named: 'onReady')),
    );
    verifyNever(() => tts.stop());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('AC1：朗读中点关联公式 → stop 成功后导航到新详情页', (tester) async {
    final scripts = _SpeakScriptRecorder(tts, sessions);
    // stop 挂起（真服务的 stop 耗时数百毫秒）：让「正在停止…」遮罩
    // 窗口可观察，并控制导航发生在 stop 完成之后。
    final stopDone = Completer<void>();
    when(() => tts.stop()).thenAnswer((_) async {
      sessions.next();
      await stopDone.future;
    });

    await _pumpPageWithRelated(tester, tts);

    // 记忆技巧朗读挂起中（首段就绪，朗读未结束）。
    await tester.tap(find.text('记忆技巧'));
    await tester.pump();
    scripts.scripts[0].signalReady();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 朗读中点击关联公式标签：先停止（「正在停止…」遮罩），stop 尚未
    // 完成前不导航（新页 AppBar 标题缺席）。
    await _tapRelatedChip(tester);
    expect(find.text('正在停止…'), findsOneWidget);
    verify(() => tts.stop()).called(1);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(_relatedFormula.name),
      ),
      findsNothing,
    );

    // stop 完成 → 遮罩清除、导航发生。新页以 400ms 转场滑入，
    // pumpAndSettle 等转场走完；「长方形面积」的查找限定 AppBar 内，
    // 排除旧页 body 里的同名 ActionChip 标签。
    stopDone.complete();
    await tester.pumpAndSettle();
    expect(find.text('正在停止…'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(_relatedFormula.name),
      ),
      findsOneWidget,
    );

    // 收尾：放行挂起的朗读 Future，销毁页面。
    scripts.scripts[0].signalFinish();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('AC2：朗读中点关联公式 stop 抛错 → SnackBar、不导航、播放态保留',
      (tester) async {
    final scripts = _SpeakScriptRecorder(tts, sessions);
    // setUp 已注册 stop 的 thenAnswer；同 matcher 后注册整体覆盖前者
    // （spec recorder 模式条款的反向应用：需要差异行为时重新注册）。
    when(() => tts.stop()).thenThrow(const TtsException('引擎停止失败'));

    await _pumpPageWithRelated(tester, tts);

    // 记忆技巧朗读挂起中。
    await tester.tap(find.text('记忆技巧'));
    await tester.pump();
    scripts.scripts[0].signalReady();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 朗读中点击关联公式标签：stop 抛错 → SnackBar、留在本页。
    await _tapRelatedChip(tester);

    expect(find.text('停止朗读失败，请稍后重试'), findsOneWidget);
    // 断言「不导航」前先 settle：导航（若发生）在 stop Future 失败后
    // 的异步续段里执行，tap 后单帧 pump 不保证续段已被调度——恒导航
    // 变异体曾在单帧断言下存活（10-08 变异验证实证，测试假绿）。
    // settle 排空微任务与转场动效，对「晚一拍的导航」同样有咬合力。
    await tester.pumpAndSettle();

    // 新页未出现（AppBar 标题缺席）。
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(_relatedFormula.name),
      ),
      findsNothing,
    );
    // 播放态保留：指示图标仍在（音频可能仍在播）。
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    expect(find.text('正在停止…'), findsNothing);

    // 收尾：放行挂起的朗读 Future，销毁页面。
    scripts.scripts[0].signalFinish();
    await tester.pump();
    // stop 抛错的覆盖仅限本用例主流程；收尾销毁页面前恢复成功
    // stop：mock 的 thenThrow 在方法调用点同步抛出，而 dispose 的
    // unawaited(_tts.stop().onError(...)) 只能吞 Future 异步失败，
    // 同步抛会击穿到 tree finalize 阶段炸测试。生产无此隐患——真
    // TtsService.stop 是 async 函数（语言语义保证同步段抛错也会包装
    // 进 Future 失败），失败只会走 onError 被吞并记日志。
    when(() => tts.stop()).thenAnswer((_) async {
      sessions.next();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('AC3：空闲时点关联公式 → 直接导航且不调 stop', (tester) async {
    _stubSpeakSentences(tts, sessions);

    await _pumpPageWithRelated(tester, tts);

    await _tapRelatedChip(tester);
    await tester.pumpAndSettle();

    verifyNever(() => tts.stop());
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(_relatedFormula.name),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('AC4：公式区朗读中显示角标指示，切走后消失', (tester) async {
    final scripts = _SpeakScriptRecorder(tts, sessions);

    await _pumpPage(tester, tts);

    // 播放前无指示图标。
    expect(find.byIcon(Icons.graphic_eq), findsNothing);

    // 公式区朗读挂起中：首段就绪后出现指示（F2 修复——公式区此前
    // 无任何播放反馈）。
    await tester.tap(find.text(_formula.formulaText));
    await tester.pump();
    scripts.scripts[0].signalReady();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 切到记忆技巧：公式区指示消失，由记忆技巧区的指示取而代之
    // （同图标的另一种位置，数量不变）。
    await tester.tap(find.text('记忆技巧'));
    await tester.pump();
    scripts.scripts[1].signalReady();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    // 公式区指示判定：切走后「公式区播放中」不再成立 → 其卡片内
    // 不应渲染任何指示图标（记忆技巧区标题行持有那一个）。
    final formulaCard = find
        .ancestor(
          of: find.text(_formula.formulaText),
          matching: find.byType(ColoredCard),
        )
        .first;
    expect(
      find.descendant(
        of: formulaCard,
        matching: find.byIcon(Icons.graphic_eq),
      ),
      findsNothing,
    );

    // 收尾：放行两个挂起的朗读 Future，销毁页面。
    scripts.scripts[0].signalFinish();
    scripts.scripts[1].signalFinish();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
