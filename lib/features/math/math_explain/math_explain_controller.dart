// lib/features/math/math_explain/math_explain_controller.dart
//
// 层级：features/math/math_explain
// 职责：算数题 AI 解析控制器 —— 读场景配置、发起单次解析请求、维护四态。
//
// 纪律与诗词侧同源：Loading 守卫先于第一个 await；会话代际令牌在每个
// await 之后校验（防换题/关弹层后晚到结果覆盖新状态）；失败不自动重试。
//
// 边界：只读题面与答案做讲解，绝不参与判分、错题记录与统计。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_explain_text.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/math/math_explain/math_explain_models.dart';
import 'package:poemath/features/math/math_explain/math_explain_prompts.dart';
import 'package:poemath/math_engine/diagnostics/error_cause_labels.dart';

/// 解析输出的 token 上限（3-5 小段中文）。
const int kMathExplainMaxTokens = 500;

class MathExplainNotifier extends Notifier<MathExplainState> {
  /// 会话代际令牌：reset / 新请求都会使旧请求的回调失效。
  int _sessionToken = 0;

  @override
  MathExplainState build() => const MathExplainState();

  /// 为一道题生成解析。重复调用在请求中被守卫拦截。
  ///
  /// [diagnosisCategory] 为 math_engine 诊断出的错因 category（可空）；
  /// 本地映射为中文标签后入 prompt，不传模板原文。
  Future<void> generate({
    required String problemText,
    required String correctAnswer,
    String? userAnswer,
    String? diagnosisCategory,
  }) async {
    // 守卫先于任何 await（含 Hive + 安全存储读取）。
    if (state.isLoading) return;
    final token = ++_sessionToken;
    state = MathExplainState(
      status: MathExplainStatus.loading,
      problemText: problemText,
    );

    LlmClient? client;
    try {
      final config = await ref
          .read(settingsRepositoryProvider)
          .readLlmConfigForScenario(LlmScenario.mathExplain);
      if (token != _sessionToken) return;
      if (config == null) {
        state = MathExplainState(
          status: MathExplainStatus.unconfigured,
          message: '还没有配置 AI 服务，配置后即可使用 AI 解析。',
          problemText: problemText,
        );
        return;
      }

      client = LlmClient(httpClient: ref.read(llmExplainHttpClientProvider));
      final result = await client.explain(
        config: config,
        systemPrompt: kMathExplainSystemPrompt,
        userPrompt: buildMathExplainUserPrompt(
          problemText: problemText,
          correctAnswer: correctAnswer,
          userAnswer: userAnswer,
          errorCauseLabel: diagnosisCategory == null
              ? null
              // 用 map 查找而非 errorCauseLabel()：未收录键不下发
              // 英文原键（llm 铁律），保持 prompt 省略该行的现状。
              : kErrorCauseLabels[diagnosisCategory],
        ),
        maxTokens: kMathExplainMaxTokens,
      );
      if (token != _sessionToken) return;

      final paragraphs = splitExplainParagraphs(result.text);
      if (paragraphs.isEmpty) {
        state = MathExplainState(
          status: MathExplainStatus.error,
          message: 'AI 没有返回有效内容，请重新生成。',
          problemText: problemText,
        );
        return;
      }
      state = MathExplainState(
        status: MathExplainStatus.ready,
        paragraphs: paragraphs,
        problemText: problemText,
      );
    } on LlmException catch (e) {
      if (token != _sessionToken) return;
      state = MathExplainState(
        status: MathExplainStatus.error,
        message: e.message,
        problemText: problemText,
      );
    } on FormatException catch (e) {
      if (token != _sessionToken) return;
      state = MathExplainState(
        status: MathExplainStatus.error,
        message: '服务地址无效：${e.message}',
        problemText: problemText,
      );
    } catch (error) {
      // 兜底：未预期异常不得让弹层卡在 loading。
      AppLogger.e('口算 AI 解析失败', tag: 'MathExplain', error: error);
      if (token != _sessionToken) return;
      state = MathExplainState(
        status: MathExplainStatus.error,
        message: 'AI 解析生成失败，请稍后重试。',
        problemText: problemText,
      );
    } finally {
      // 注入的 client 不被关闭（LlmClient 不持有所有权）。
      client?.close();
    }
  }

  /// 复位为初始态（换题等非 dispose 场景调用）；同时废弃在途请求。
  void reset() {
    _sessionToken++;
    state = const MathExplainState();
  }

  /// 弹层关闭（dispose）时调用：仅令牌失效（丢弃在途请求的晚到
  /// 回调），不写状态——弹层元素在 unmount 期间仍订阅本 provider，
  /// 同步状态写会通知 defunct element 触发 markNeedsBuild 断言。
  /// 残留状态由下次打开弹层时的 generate 覆盖（其首行同步切
  /// loading，不展示旧题内容）。
  void discardPending() {
    _sessionToken++;
  }
}

/// 算数题 AI 解析状态。
final mathExplainProvider =
    NotifierProvider<MathExplainNotifier, MathExplainState>(
  MathExplainNotifier.new,
);
