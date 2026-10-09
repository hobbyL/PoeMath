// lib/features/poem/poem_explain/poem_explain_controller.dart
//
// 层级：features/poem/poem_explain
// 职责：诗词 AI 讲解控制器 —— 读场景配置、发起单次讲解请求、维护四态。
//
// 纪律：
// - Loading 守卫先于第一个 await（防连点重复请求）；
// - 会话代际令牌：每次 await 之后校验，防晚到结果覆盖新状态
//   （切诗 / 退页 / 重新生成）；
// - 失败不自动重试，由用户点「重新生成」。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_explain_text.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/poem/poem_explain/poem_explain_models.dart';
import 'package:poemath/features/poem/poem_explain/poem_explain_prompts.dart';

/// 讲解输出的 token 上限（4-6 小段中文，800 足够）。
const int kPoemExplainMaxTokens = 800;

class PoemExplainNotifier extends Notifier<PoemExplainState> {
  /// 会话代际令牌：reset / 新请求都会使旧请求的回调失效。
  int _sessionToken = 0;

  @override
  PoemExplainState build() => const PoemExplainState();

  /// 为 [poem] 生成讲解。重复调用在请求中被守卫拦截。
  Future<void> generate(Poem poem) async {
    // 守卫先于任何 await（含 Hive + 安全存储读取）。
    if (state.isLoading) return;
    final token = ++_sessionToken;
    state = PoemExplainState(
      status: PoemExplainStatus.loading,
      poemId: poem.id,
    );

    LlmClient? client;
    try {
      final config = await ref
          .read(settingsRepositoryProvider)
          .readLlmConfigForScenario(LlmScenario.poemExplain);
      if (token != _sessionToken) return;
      if (config == null) {
        state = PoemExplainState(
          status: PoemExplainStatus.unconfigured,
          message: '还没有配置 AI 服务，配置后即可使用 AI 讲解。',
          poemId: poem.id,
        );
        return;
      }

      client = LlmClient(httpClient: ref.read(llmExplainHttpClientProvider));
      final result = await client.explain(
        config: config,
        systemPrompt: kPoemExplainSystemPrompt,
        userPrompt: buildPoemExplainUserPrompt(poem),
        maxTokens: kPoemExplainMaxTokens,
      );
      if (token != _sessionToken) return;

      final paragraphs = splitExplainParagraphs(result.text);
      if (paragraphs.isEmpty) {
        state = PoemExplainState(
          status: PoemExplainStatus.error,
          message: 'AI 没有返回有效内容，请重新生成。',
          poemId: poem.id,
        );
        return;
      }
      state = PoemExplainState(
        status: PoemExplainStatus.ready,
        paragraphs: paragraphs,
        poemId: poem.id,
      );
    } on LlmException catch (e) {
      if (token != _sessionToken) return;
      state = PoemExplainState(
        status: PoemExplainStatus.error,
        message: e.message,
        poemId: poem.id,
      );
    } on FormatException catch (e) {
      if (token != _sessionToken) return;
      state = PoemExplainState(
        status: PoemExplainStatus.error,
        message: '服务地址无效：${e.message}',
        poemId: poem.id,
      );
    } catch (error) {
      // 兜底：未预期异常不得让卡片卡在 loading。
      AppLogger.e('诗词 AI 讲解失败', tag: 'PoemExplain', error: error);
      if (token != _sessionToken) return;
      state = PoemExplainState(
        status: PoemExplainStatus.error,
        message: 'AI 讲解生成失败，请稍后重试。',
        poemId: poem.id,
      );
    } finally {
      // 注入的 client 不被关闭（LlmClient 不持有所有权）。
      client?.close();
    }
  }

  /// 复位为初始态（进入页面调用）；同时废弃在途请求的回调。
  void reset() {
    _sessionToken++;
    state = const PoemExplainState();
  }

  /// 页面退出时调用：仅令牌失效（丢弃在途请求的晚到回调），不写状态。
  ///
  /// 不在 dispose 中写 `state`：退页元素在 unmount 期间仍订阅本
  /// provider，同步状态写会通知 defunct element 触发 markNeedsBuild
  /// 断言（widget 测试抓到的真实缺陷）。残留内容由页面的 poemId
  /// 过滤兜底，下次进入页面时 [reset]。
  void discardPending() {
    _sessionToken++;
  }
}

/// 诗词 AI 讲解状态。
final poemExplainProvider =
    NotifierProvider<PoemExplainNotifier, PoemExplainState>(
  PoemExplainNotifier.new,
);
