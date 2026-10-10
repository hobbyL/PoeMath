// test/features/poem/poem_explain/poem_detail_ai_explain_test.dart
//
// 诗词详情页 AI 讲解区 widget 测试（任务 10-09-ai-explain-scenario-provider）：
// - 未配置：点「生成讲解」tag 进入引导态（提示 + 去设置 tag）
// - 成功：讲解内容清洗 markdown 后分段渲染，附重新生成 tag 与点击朗读提示
// - 流式：生成中渐显已到达段落（无朗读入口），收尾转就绪可朗读
// - 失败：错误文案展示（不含 API Key），点「重新生成」可恢复成功
// - 切诗防护：讲解状态带 poemId，非当前诗词的结果不得闪现
//
// 配置读取走 mock SettingsRepository（不触碰 Hive），HTTP 走 MockClient，
// 时序均为微任务级，无需 runAsync 真实异步区。
// 注意：入场动画（AnimatedPageBody 交错 slideX）完成后才能点标题右侧的
// actionTag——AI 卡位于列表尾部（交错延迟 ~960ms），动画未完成时卡片整体
// 右偏 10%，tag 会落到 800px 测试视口外导致 tap hit test 落空、生成从未触发。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/widgets/ai_action_tag.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/poem/poem_detail_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class _MockTtsService extends Mock implements TtsService {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

const _poemId = 'explain-poem';
const _poemId2 = 'explain-poem-2';

Poem _poemOf(String id, String title) => Poem(
      id: id,
      title: title,
      author: '李白',
      dynasty: '唐',
      content: '床前明月光，\n疑是地上霜。',
      pinyin: '',
      layer: 'core',
      translation: '',
      annotations: const [],
      appreciation: '',
      background: '',
      famousLines: const [],
    );

final _poem = _poemOf(_poemId, '静夜思');
final _poem2 = _poemOf(_poemId2, '望庐山瀑布');

/// 单条 SSE data 行（含结尾空行），content 包进 choices[0].delta.content。
String _sseData(String content) {
  final json = jsonEncode({
    'choices': [
      {
        'delta': {'content': content},
      },
    ],
  });
  return 'data: $json\n\n';
}

/// 整段讲解包装成「单片 + [DONE]」的 OpenAI 兼容 SSE 响应。
///
/// 控制器已切流式（explainStream），mock 必须回 `text/event-stream`；
/// 经 MockClient.send 以单 chunk 字节流交付，收尾直达 ready 终态。
http.Response _sseResponse(String content) => http.Response.bytes(
      utf8.encode('${_sseData(content)}data: [DONE]\n\n'),
      200,
      headers: const {'content-type': 'text/event-stream; charset=utf-8'},
    );

/// 把 explainStream 的真实异步 SSE 流推进到终态并稳定界面。
///
/// explainStream 读 http 响应流；其「流读完/关闭」事件不在 fake-async 的微任务
/// 队列里，pumpAndSettle 单独驱动不了——控制器会一直卡在 streaming、标题右侧
/// busy 转圈（CircularProgressIndicator）永不 settle 直至超时。先用 runAsync 给
/// 真实事件循环一点时间把流读完、让控制器落到 ready/error 终态（busy 转圈卸下），
/// 再 pumpAndSettle 应用重建。生成须已在调用前触发（tap「生成讲解」同步进入
/// loading）。
Future<void> settleSse(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

void main() {
  late _MockTtsService tts;

  setUpAll(() {
    registerFallbackValue(LlmScenario.poemExplain);
  });

  setUp(() {
    tts = _MockTtsService();
    // 页面 dispose 会调用 stop（unawaited），须返回真实 Future。
    when(() => tts.stop()).thenAnswer((_) async {});
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required SettingsRepository settings,
    http.Client? client,
    String poemId = _poemId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          ttsServiceProvider.overrideWithValue(tts),
          poemByIdProvider(_poemId).overrideWith((ref) => _poem),
          poemByIdProvider(_poemId2).overrideWith((ref) => _poem2),
          isFavoriteProvider(_poemId).overrideWith((ref) => false),
          poemProgressProvider(_poemId).overrideWith((ref) => null),
          isFavoriteProvider(_poemId2).overrideWith((ref) => false),
          poemProgressProvider(_poemId2).overrideWith((ref) => null),
          if (client != null)
            llmExplainHttpClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          home: PoemDetailPage(poemId: poemId),
        ),
      ),
    );
    // 等待 AnimatedPageBody 入场动画完成：AI 卡位于列表尾部，交错
    // 延迟最长（80ms × 12 ≈ 960ms）+ slideX 300ms；动画中卡片右偏
    // 10%，右侧 tag 出 800px 视口，tap 会落空。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 900));
  }

  /// 已配置场景厂商的 repo mock（诗词讲解走 DeepSeek 配置）。
  SettingsRepository configuredRepo() {
    final settings = _MockSettingsRepository();
    when(() => settings.pinyinVisible).thenReturn(false);
    when(() => settings.readLlmConfigForScenario(LlmScenario.poemExplain))
        .thenAnswer(
      (_) async => const LlmConfig(
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'secret-key-poem',
        model: 'deepseek-chat',
      ),
    );
    return settings;
  }

  testWidgets('未配置：点「生成讲解」进入引导态（提示 + 去设置）', (tester) async {
    final settings = _MockSettingsRepository();
    when(() => settings.pinyinVisible).thenReturn(false);
    when(() => settings.readLlmConfigForScenario(any()))
        .thenAnswer((_) async => null);
    var requests = 0;
    await pumpPage(
      tester,
      settings: settings,
      client: MockClient((_) async {
        requests++;
        return _sseResponse('不该被调用');
      }),
    );

    // 初始 idle 态：标题 + 生成讲解 tag + 引导文案（无旧「AI 生成」角标）。
    expect(find.text('AI 讲解'), findsOneWidget);
    expect(find.text('AI 生成'), findsNothing);
    expect(
      find.text('点右上角「生成讲解」，让 AI 用小朋友能听懂的话讲讲这首诗。'),
      findsOneWidget,
    );
    expect(find.widgetWithText(AiActionTag, '生成讲解'), findsOneWidget);

    await tester.tap(find.text('生成讲解'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('还没有配置 AI 服务，配置后即可使用 AI 讲解。'),
      findsOneWidget,
    );
    // 未配置态主操作收敛为「去设置」tag（跳转 llmSettings 深链）。
    expect(find.widgetWithText(AiActionTag, '去设置'), findsOneWidget);
    // 未配置不发任何网络请求。
    expect(requests, 0);
  });

  testWidgets('成功：讲解清洗 markdown 后分段渲染，附重新生成与朗读提示',
      (tester) async {
    late http.Request captured;
    await pumpPage(
      tester,
      settings: configuredRepo(),
      client: MockClient((request) async {
        captured = request;
        return _sseResponse(
          '## 这首诗在说什么\n'
          '诗人晚上睡不着，看到**明亮的月光**。\n'
          '\n'
          '- 举头望明月，低头思故乡。',
        );
      }),
    );

    await tester.tap(find.text('生成讲解'));
    await settleSse(tester);

    // markdown 残留（## / ** / - ）被清洗，分段渲染。
    expect(find.text('这首诗在说什么'), findsOneWidget);
    expect(find.text('诗人晚上睡不着，看到明亮的月光。'), findsOneWidget);
    expect(find.text('举头望明月，低头思故乡。'), findsOneWidget);
    expect(find.textContaining('##'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    // 操作收敛为「重新生成」tag；朗读改为点击内容触发（不再有按钮）。
    expect(find.text('朗读讲解'), findsNothing);
    expect(find.widgetWithText(AiActionTag, '重新生成'), findsOneWidget);
    expect(find.text('点击内容可朗读，再次点击停止。'), findsOneWidget);
    // 请求走诗词讲解场景配置的厂商。
    expect(
      captured.url.toString(),
      'https://api.deepseek.com/v1/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer secret-key-poem');
  });

  testWidgets('streaming：渐显已到达段落、无朗读入口，收尾转可朗读', (tester) async {
    final sse = StreamController<List<int>>();
    await pumpPage(
      tester,
      settings: configuredRepo(),
      client: MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(sse.stream, 200),
      ),
    );

    await tester.tap(find.text('生成讲解'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 首片到达：streaming 态渐显首段 + 「逐句生成」提示，无朗读入口。
    sse.add(utf8.encode(_sseData('月光洒在床前。\n')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('月光洒在床前。'), findsOneWidget);
    expect(find.text('AI 正在逐句生成…'), findsOneWidget);
    expect(find.widgetWithText(AiActionTag, '生成中…'), findsOneWidget);
    expect(find.text('点击内容可朗读，再次点击停止。'), findsNothing);
    expect(find.widgetWithText(AiActionTag, '重新生成'), findsNothing);

    // 续片 + [DONE]：收尾转 ready，段落累积完整、朗读入口出现。
    sse.add(utf8.encode(_sseData('他抬头思念故乡。')));
    sse.add(utf8.encode('data: [DONE]\n\n'));
    await sse.close();
    await settleSse(tester);

    expect(find.text('月光洒在床前。'), findsOneWidget);
    expect(find.text('他抬头思念故乡。'), findsOneWidget);
    expect(find.text('点击内容可朗读，再次点击停止。'), findsOneWidget);
    expect(find.widgetWithText(AiActionTag, '重新生成'), findsOneWidget);
  });

  testWidgets('失败：错误文案不含 Key，点「重新生成」可恢复成功', (tester) async {
    var calls = 0;
    late http.Request captured;
    await pumpPage(
      tester,
      settings: configuredRepo(),
      client: MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response.bytes(const [], 401);
        captured = request;
        return _sseResponse('第二次成功的讲解内容。');
      }),
    );

    await tester.tap(find.text('生成讲解'));
    await tester.pumpAndSettle();

    // 鉴权失败文案展示，且不泄露 Key。
    expect(find.text('API Key 无效或未授权（HTTP 401）'), findsOneWidget);
    expect(find.textContaining('secret-key-poem'), findsNothing);

    // 点「重新生成」恢复成功。
    await tester.tap(find.widgetWithText(AiActionTag, '重新生成'));
    await settleSse(tester);
    expect(find.text('第二次成功的讲解内容。'), findsOneWidget);
    expect(calls, 2);
    expect(captured.headers['authorization'], 'Bearer secret-key-poem');
  });

  testWidgets('切诗防护：上一首的讲解结果不在新诗词页闪现', (tester) async {
    var calls = 0;
    // 两次 pump 复用同一组 overrides：ProviderScope 同位同型更新时
    // 容器保留，poemExplainProvider 中上一首的结果仍在——页面须靠
    // poemId 过滤，不得把旧结果渲染到新诗词页。
    ProviderScope scopeOf(String poemId) => ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(configuredRepo()),
            ttsServiceProvider.overrideWithValue(tts),
            poemByIdProvider(_poemId).overrideWith((ref) => _poem),
            poemByIdProvider(_poemId2).overrideWith((ref) => _poem2),
            isFavoriteProvider(_poemId).overrideWith((ref) => false),
            poemProgressProvider(_poemId).overrideWith((ref) => null),
            isFavoriteProvider(_poemId2).overrideWith((ref) => false),
            poemProgressProvider(_poemId2).overrideWith((ref) => null),
            llmExplainHttpClientProvider.overrideWithValue(
              MockClient((_) async {
                calls++;
                return _sseResponse('静夜思的讲解内容。');
              }),
            ),
          ],
          child: MaterialApp(home: PoemDetailPage(poemId: poemId)),
        );

    await tester.pumpWidget(scopeOf(_poemId));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.text('生成讲解'));
    await settleSse(tester);
    expect(find.text('静夜思的讲解内容。'), findsOneWidget);

    // 切到另一首诗：AI 区回到 idle 态，旧讲解不闪现。
    await tester.pumpWidget(scopeOf(_poemId2));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('静夜思的讲解内容。'), findsNothing);
    expect(
      find.text('点右上角「生成讲解」，让 AI 用小朋友能听懂的话讲讲这首诗。'),
      findsOneWidget,
    );
    expect(find.widgetWithText(AiActionTag, '生成讲解'), findsOneWidget);
    // 新页面未发起请求（idle 态不发）。
    expect(calls, 1);
  });
}
