// test/features/math/math_explain/math_ai_explain_sheet_test.dart
//
// 口算 AI 解析弹层 widget 测试（任务 10-09-ai-explain-scenario-provider）：
// - loading：打开即生成，纯文案提示；关闭弹层丢弃在途请求（不崩溃）
// - ready：markdown 清洗分段渲染 + 重新生成；请求走 mathExplain 场景配置
// - error：错误文案不含 API Key，点「重新生成」可恢复成功
// - unconfigured：引导文案 + 「去设置」跳转 llmSettings 路由
// - 错题详情页入口：「AI 帮我讲」点击弹出弹层并携带题面/答案
//
// 配置读取走 mock SettingsRepository（不触碰 Hive），HTTP 走 MockClient，
// 时序均为微任务级，无需 runAsync 真实异步区。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/math/math_mistake_detail_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/math_ai_explain_sheet.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

/// 不触碰 Hive 的内存错题仓储（仅为入口挂载测试服务，真实仓储行为
/// 由 math_mistake_repository_test 覆盖；同 math_mistake_labels_test 模式）。
class _FakeMistakeRepo extends MathMistakeRepository {
  _FakeMistakeRepo(this._mistakes);

  final List<MathMistake> _mistakes;

  @override
  MathMistake? getById(String id) {
    for (final m in _mistakes) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  List<MathMistake> getAll() => List.of(_mistakes);

  @override
  List<MathMistake> getUnresolved() =>
      _mistakes.where((m) => !m.isResolved).toList();

  @override
  int get totalCount => _mistakes.length;
}

/// 弹层宿主页：点按钮经真实入口函数打开弹层。
class _SheetHost extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showMathAiExplainSheet(
            context,
            problemText: '12 + 34 = ?',
            correctAnswer: '46',
            userAnswer: '47',
          ),
          child: const Text('打开 AI 解析'),
        ),
      ),
    );
  }
}

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
  setUpAll(() {
    registerFallbackValue(LlmScenario.mathExplain);
  });

  /// 已配置 mathExplain 场景厂商的 repo mock。
  SettingsRepository configuredRepo() {
    final settings = _MockSettingsRepository();
    when(() => settings.readLlmConfigForScenario(LlmScenario.mathExplain))
        .thenAnswer(
      (_) async => const LlmConfig(
        baseUrl: 'https://llm-math.example.com',
        apiKey: 'secret-key-math',
        model: 'qwen-plus',
      ),
    );
    return settings;
  }

  Future<void> pumpSheet(
    WidgetTester tester, {
    required SettingsRepository settings,
    http.Client? client,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => _SheetHost()),
        GoRoute(
          path: AppRoutes.llmSettings,
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('llm-settings-stub')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          if (client != null)
            llmExplainHttpClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('打开 AI 解析'));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('loading：纯文案提示；关闭弹层丢弃在途请求不崩溃', (tester) async {
    // 用未完成的 completer 卡住配置读取，捕获 loading 中间态。
    final completer = Completer<LlmConfig?>();
    final settings = _MockSettingsRepository();
    when(() => settings.readLlmConfigForScenario(LlmScenario.mathExplain))
        .thenAnswer((_) => completer.future);
    var requests = 0;
    await pumpSheet(
      tester,
      settings: settings,
      client: MockClient((_) async {
        requests++;
        return _chatResponse('不该被请求');
      }),
    );

    expect(find.text('AI 解析'), findsOneWidget);
    expect(find.text('AI 正在准备解析，请稍候…'), findsOneWidget);

    // loading 中关闭：discardPending 使晚到回调失效，dispose 不写状态。
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    completer.complete(
      const LlmConfig(
        baseUrl: 'https://llm-math.example.com',
        apiKey: 'secret-key-math',
        model: 'qwen-plus',
      ),
    );
    await tester.pumpAndSettle();

    // 弹层已关、令牌已废弃：请求不发出、无 defunct 断言崩溃。
    expect(find.text('AI 解析'), findsNothing);
    expect(requests, 0);
  });

  testWidgets('ready：清洗 markdown 分段渲染 + 重新生成；请求走场景配置', (tester) async {
    late http.Request captured;
    await pumpSheet(
      tester,
      settings: configuredRepo(),
      client: MockClient((request) async {
        captured = request;
        return _chatResponse(
          '## 竖式计算\n'
          '先算 **12 + 34**。\n'
          '\n'
          '- 12 加 34 等于 46。',
        );
      }),
    );

    // markdown 残留（## / ** / - ）被清洗，分段渲染。
    expect(find.text('竖式计算'), findsOneWidget);
    expect(find.text('先算 12 + 34。'), findsOneWidget);
    expect(find.text('12 加 34 等于 46。'), findsOneWidget);
    expect(find.textContaining('##'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    // 操作按钮：重新生成。
    expect(find.text('重新生成'), findsOneWidget);
    // 请求走口算解析场景配置的厂商。
    expect(
      captured.url.toString(),
      'https://llm-math.example.com/v1/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer secret-key-math');

    // 关闭弹层：不写 provider 状态，无 defunct 断言崩溃。
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('AI 解析'), findsNothing);
  });

  testWidgets('error：错误文案不含 Key，点「重新生成」可恢复成功', (tester) async {
    var calls = 0;
    await pumpSheet(
      tester,
      settings: configuredRepo(),
      client: MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response.bytes(const [], 401);
        return _chatResponse('第二次成功的解析内容。');
      }),
    );

    // 鉴权失败文案展示，且不泄露 Key。
    expect(find.text('API Key 无效或未授权（HTTP 401）'), findsOneWidget);
    expect(find.textContaining('secret-key-math'), findsNothing);

    // 点「重新生成」恢复成功。
    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();
    expect(find.text('第二次成功的解析内容。'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('unconfigured：引导文案 + 「去设置」跳转设置页', (tester) async {
    final settings = _MockSettingsRepository();
    when(() => settings.readLlmConfigForScenario(any()))
        .thenAnswer((_) async => null);
    var requests = 0;
    await pumpSheet(
      tester,
      settings: settings,
      client: MockClient((_) async {
        requests++;
        return _chatResponse('不该被请求');
      }),
    );

    expect(find.text('还没有配置 AI 服务，配置后即可使用 AI 解析。'),
        findsOneWidget,);
    expect(find.widgetWithText(OutlinedButton, '去设置'), findsOneWidget);
    // 未配置不发任何网络请求。
    expect(requests, 0);

    // 点「去设置」：关弹层并跳转 llmSettings 路由。
    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();
    expect(find.text('llm-settings-stub'), findsOneWidget);
    expect(find.text('AI 解析'), findsNothing);
  });

  group('错题详情页入口', () {
    testWidgets('「AI 帮我讲」存在且点击弹出解析弹层（题面/答案入 prompt）',
        (tester) async {
      final repo = _FakeMistakeRepo([
        MathMistake(
          id: 'm1',
          profileId: 'default',
          problemText: '3 × 5 = ?',
          correctAnswer: '15',
          userAnswer: '14',
          problemType: 'multiplication',
          grade: 2,
          errorType: 'multiplication_table',
        ),
      ]);
      late http.Request captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mathMistakeRepoProvider.overrideWithValue(repo),
            settingsRepositoryProvider.overrideWithValue(configuredRepo()),
            llmExplainHttpClientProvider.overrideWithValue(
              MockClient((request) async {
                captured = request;
                return _chatResponse('这道题考查乘法口诀。三五十五，得 15。');
              }),
            ),
          ],
          child: const MaterialApp(
            home: MathMistakeDetailPage(mistakeId: 'm1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('AI 帮我讲'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('AI 帮我讲'));
      await tester.pump();
      await tester.pumpAndSettle();

      // 弹层打开并完成生成，讲解内容渲染。
      expect(find.text('AI 解析'), findsOneWidget);
      expect(find.text('这道题考查乘法口诀。三五十五，得 15。'), findsOneWidget);
      // prompt 载荷携带题面答案与用户作答（14 / 15）。
      expect(utf8.decode(captured.bodyBytes), contains('14'));
      expect(utf8.decode(captured.bodyBytes), contains('15'));
    });
  });
}
