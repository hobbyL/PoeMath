// test/features/poem/poem_explain/poem_detail_ai_explain_test.dart
//
// 诗词详情页 AI 讲解区 widget 测试（任务 10-09-ai-explain-scenario-provider）：
// - 未配置：点「生成讲解」进入引导态（提示 + 去设置按钮）
// - 成功：讲解内容清洗 markdown 后分段渲染，附朗读/重新生成操作
// - 失败：错误文案展示（不含 API Key），点「重新生成」可恢复成功
// - 切诗防护：讲解状态带 poemId，非当前诗词的结果不得闪现
//
// 配置读取走 mock SettingsRepository（不触碰 Hive），HTTP 走 MockClient，
// 时序均为微任务级，无需 runAsync 真实异步区。

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

http.Response _chatResponse(String content) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': content},
          },
        ],
      }),),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

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
    // 等待 AnimatedPageBody 入场动画完成。
    await tester.pump(const Duration(milliseconds: 500));
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
        return _chatResponse('不该被调用');
      }),
    );

    // 初始 idle 态：提示文案 + 生成按钮 + AI 生成角标。
    expect(find.text('AI 讲解'), findsOneWidget);
    expect(find.text('AI 生成'), findsOneWidget);
    expect(find.text('让 AI 用小朋友能听懂的话讲讲这首诗。'), findsOneWidget);

    await tester.tap(find.text('生成讲解'));
    await tester.pump();

    expect(
      find.text('还没有配置 AI 服务，配置后即可使用 AI 讲解。'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, '去设置'), findsOneWidget);
    // 未配置不发任何网络请求。
    expect(requests, 0);
  });

  testWidgets('成功：讲解清洗 markdown 后分段渲染，附朗读/重新生成', (tester) async {
    late http.Request captured;
    await pumpPage(
      tester,
      settings: configuredRepo(),
      client: MockClient((request) async {
        captured = request;
        return _chatResponse(
          '## 这首诗在说什么\n'
          '诗人晚上睡不着，看到**明亮的月光**。\n'
          '\n'
          '- 举头望明月，低头思故乡。',
        );
      }),
    );

    await tester.tap(find.text('生成讲解'));
    await tester.pumpAndSettle();

    // markdown 残留（## / ** / - ）被清洗，分段渲染。
    expect(find.text('这首诗在说什么'), findsOneWidget);
    expect(find.text('诗人晚上睡不着，看到明亮的月光。'), findsOneWidget);
    expect(find.text('举头望明月，低头思故乡。'), findsOneWidget);
    expect(find.textContaining('##'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    // 操作按钮：朗读讲解 + 重新生成。
    expect(find.text('朗读讲解'), findsOneWidget);
    expect(find.text('重新生成'), findsOneWidget);
    // 请求走诗词讲解场景配置的厂商。
    expect(
      captured.url.toString(),
      'https://api.deepseek.com/v1/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer secret-key-poem');
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
        return _chatResponse('第二次成功的讲解内容。');
      }),
    );

    await tester.tap(find.text('生成讲解'));
    await tester.pumpAndSettle();

    // 鉴权失败文案展示，且不泄露 Key。
    expect(find.text('API Key 无效或未授权（HTTP 401）'), findsOneWidget);
    expect(find.textContaining('secret-key-poem'), findsNothing);

    // 点「重新生成」恢复成功。
    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();
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
                return _chatResponse('静夜思的讲解内容。');
              }),
            ),
          ],
          child: MaterialApp(home: PoemDetailPage(poemId: poemId)),
        );

    await tester.pumpWidget(scopeOf(_poemId));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('生成讲解'));
    await tester.pumpAndSettle();
    expect(find.text('静夜思的讲解内容。'), findsOneWidget);

    // 切到另一首诗：AI 区回到 idle 态，旧讲解不闪现。
    await tester.pumpWidget(scopeOf(_poemId2));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('静夜思的讲解内容。'), findsNothing);
    expect(find.text('让 AI 用小朋友能听懂的话讲讲这首诗。'), findsOneWidget);
    expect(find.text('生成讲解'), findsOneWidget);
    // 新页面未发起请求（idle 态不发）。
    expect(calls, 1);
  });
}
