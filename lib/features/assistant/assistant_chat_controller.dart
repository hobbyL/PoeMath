// lib/features/assistant/assistant_chat_controller.dart
//
// 层级：features/assistant
// 职责：AI 助手多轮流式对话控制器 —— 读场景配置、发起 chatStream、维护
//       六态状态机，用会话代际令牌护栏防止换会话/中途停止后晚到的流片
//       覆盖新状态。
//
// 纪律与讲解侧同源（math_explain_controller）：防重入守卫先于首个 await；
// _sessionToken 在每个 await / 每片 chunk 之后校验，过期直接 return 且
// 绝不写 state（避免对已卸载 element markNeedsBuild）；finally 关闭 client。
//
// 安全边界：API Key 仅经 LlmConfig 下沉到 Authorization 头，绝不写入
// 日志 / 异常 message / state。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/prompts/assistant_prompt_defaults.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/assistant/assistant_chat_state.dart';

/// 助手单轮回答的 token 上限（多段中文，略高于讲解档）。
const int kAssistantMaxTokens = 1024;

class AssistantChatController extends Notifier<AssistantChatState> {
  /// 会话代际令牌：send / stop / regenerate / 切换会话都会使旧请求失效。
  int _sessionToken = 0;

  @override
  AssistantChatState build() => const AssistantChatState();

  /// 发送一条用户消息并流式接收助手回答。在途（loading/streaming）时忽略。
  Future<void> send(String userInput) async {
    final text = userInput.trim();
    if (text.isEmpty) return;
    if (state.isBusy) return;
    final token = ++_sessionToken;

    // 立即把用户消息并入历史并切 loading（同步、先于任何 await），
    // 用户气泡即时上屏；新建 state 顺带清掉上一轮的错误/引导文案。
    state = AssistantChatState(
      status: AssistantChatStatus.loading,
      messages: [
        ...state.messages,
        ChatMessage(role: ChatRole.user, content: text),
      ],
    );
    await _complete(token);
  }

  /// 重新生成最后一次回答：截掉末尾 assistant 回答，以最后一条 user
  /// 消息重跑。无可重跑的用户消息 / 在途时忽略。
  Future<void> regenerate() async {
    if (state.isBusy) return;
    final messages = state.messages;
    final lastUserIndex =
        messages.lastIndexWhere((m) => m.role == ChatRole.user);
    if (lastUserIndex < 0) return;
    final token = ++_sessionToken;
    state = AssistantChatState(
      status: AssistantChatStatus.loading,
      messages: messages.sublist(0, lastUserIndex + 1),
    );
    await _complete(token);
  }

  /// 中止在途请求：令牌失配使在途流自然失效；已累积的增量固化为一条
  /// assistant 消息（允许部分回答），无增量则回 ready。
  void stop() {
    if (!state.isBusy) return;
    _sessionToken++;
    final partial = state.streamingText.trim();
    if (partial.isEmpty) {
      state = state.copyWith(
        status: AssistantChatStatus.ready,
        streamingText: '',
      );
      return;
    }
    state = AssistantChatState(
      status: AssistantChatStatus.ready,
      messages: [
        ...state.messages,
        ChatMessage(role: ChatRole.assistant, content: partial),
      ],
    );
  }

  /// 载入历史会话（子任务 3 切换会话时调用）；废弃在途请求。
  void loadConversation(List<ChatMessage> messages) {
    _sessionToken++;
    state = AssistantChatState(
      status: messages.isEmpty
          ? AssistantChatStatus.idle
          : AssistantChatStatus.ready,
      messages: List<ChatMessage>.unmodifiable(messages),
    );
  }

  /// 开启新会话：清空历史、废弃在途请求。
  void startNewConversation() {
    _sessionToken++;
    state = const AssistantChatState();
  }

  /// 页面销毁时调用：仅令牌失效（丢弃在途流的晚到回调），不写状态
  /// ——订阅本 provider 的 element 在 unmount 期间同步写会触发
  /// defunct element markNeedsBuild 断言。
  void discardPending() {
    _sessionToken++;
  }

  /// 读配置 → 流式接收 → 固化回答。假定 `state.messages` 末尾已是待回答
  /// 的 user 轮次。全程以 [token] 守护代际一致性。
  Future<void> _complete(int token) async {
    LlmClient? client;
    try {
      final repo = ref.read(settingsRepositoryProvider);
      final config =
          await repo.readLlmConfigForScenario(LlmScenario.assistant);
      if (token != _sessionToken) return;
      if (config == null) {
        state = state.copyWith(
          status: AssistantChatStatus.unconfigured,
          message: '还没有配置 AI 服务，配置后即可使用 AI 助手。',
        );
        return;
      }

      client = LlmClient(httpClient: ref.read(llmExplainHttpClientProvider));
      final buffer = StringBuffer();
      await for (final chunk in client.chatStream(
        config: config,
        // 家长 override 优先，否则内置儿童安全默认。
        systemPrompt: repo.assistantPromptOverride ?? kAssistantSystemPrompt,
        messages: state.messages,
        maxTokens: kAssistantMaxTokens,
      )) {
        // 每片校验令牌：切会话 / stop 后立即丢弃在途流，不写 state。
        if (token != _sessionToken) return;
        buffer.write(chunk);
        state = state.copyWith(
          status: AssistantChatStatus.streaming,
          streamingText: buffer.toString(),
        );
      }
      if (token != _sessionToken) return;
      _finalize(buffer.toString());
    } on LlmException catch (e) {
      if (token != _sessionToken) return;
      state = state.copyWith(
        status: AssistantChatStatus.error,
        message: e.message,
      );
    } on FormatException catch (e) {
      if (token != _sessionToken) return;
      state = state.copyWith(
        status: AssistantChatStatus.error,
        message: '服务地址无效：${e.message}',
      );
    } catch (error) {
      // 兜底：未预期异常不得让对话卡在 loading（日志不含 key）。
      AppLogger.e('AI 助手对话失败', tag: 'Assistant', error: error);
      if (token != _sessionToken) return;
      state = state.copyWith(
        status: AssistantChatStatus.error,
        message: 'AI 助手回复失败，请稍后重试。',
      );
    } finally {
      // 注入的 client 不被关闭（LlmClient 不持有所有权）。
      client?.close();
    }
  }

  /// 把流式增量固化为一条 assistant 消息并切 ready。
  void _finalize(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      // chatStream 对空内容已抛 LlmResponseFormatError，此处为兜底。
      state = state.copyWith(
        status: AssistantChatStatus.error,
        message: 'AI 没有返回有效内容，请重新生成。',
        streamingText: '',
      );
      return;
    }
    state = AssistantChatState(
      status: AssistantChatStatus.ready,
      messages: [
        ...state.messages,
        ChatMessage(role: ChatRole.assistant, content: trimmed),
      ],
    );
  }
}

/// AI 助手对话状态 provider。
final assistantChatControllerProvider =
    NotifierProvider<AssistantChatController, AssistantChatState>(
  AssistantChatController.new,
);
