// lib/features/assistant/assistant_chat_controller.dart
//
// 层级：features/assistant
// 职责：AI 助手多轮流式对话控制器 —— 读场景配置、按需走工具循环
//       （chatComplete 判定 → 执行工具 → 回灌 role:tool，≤4 轮），再以
//       chatStream 流式产出最终回答，维护六态状态机，用会话代际令牌护栏
//       防止换会话/中途停止后晚到的流片覆盖新状态。
//
// 纪律与讲解侧同源（math_explain_controller）：防重入守卫先于首个 await；
// _sessionToken 在每个 await / 每片 chunk 之后校验，过期直接 return 且
// 绝不写 state（避免对已卸载 element markNeedsBuild）；finally 关闭 client。
//
// 安全边界：API Key 仅经 LlmConfig 下沉到 Authorization 头，绝不写入
// 日志 / 异常 message / state。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/prompts/assistant_prompt_defaults.dart';
import 'package:poemath/core/services/llm/chat_completion.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/assistant/assistant_chat_state.dart';
import 'package:poemath/features/assistant/tools/assistant_tool.dart';
import 'package:poemath/features/assistant/tools/assistant_tools_provider.dart';

/// 助手单轮回答的 token 上限（多段中文，略高于讲解档）。
const int kAssistantMaxTokens = 1024;

/// 工具循环硬上限（≤4 轮）：防止模型反复要工具导致死循环；到顶后强制
/// 走最终流式回答（见 design §5）。
const int kAssistantMaxToolRounds = 4;

class AssistantChatController extends Notifier<AssistantChatState> {
  /// 会话代际令牌：send / stop / regenerate / 切换会话都会使旧请求失效。
  int _sessionToken = 0;

  /// provider 是否已销毁（微任务收敛前的写入防抖）。
  bool _disposed = false;

  @override
  AssistantChatState build() {
    _disposed = false;
    _sessionToken++;
    ref.onDispose(() => _disposed = true);
    return const AssistantChatState();
  }

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
      contextBaseIndex: state.contextBaseIndex,
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
      contextBaseIndex: state.contextBaseIndex.clamp(0, lastUserIndex + 1),
    );
    await _complete(token);
  }

  /// 重新发送 [index] 处的用户提问：截掉它之后的全部消息（该提问保留为
  /// 末条）再重跑。用于回答失败 / 被中断 / 想换个答案时从任意历史提问重来
  /// ——与 [regenerate] 的差别仅在起点可指定（regenerate 恒为最后一条）。
  ///
  /// [index] 非法（越界 / 不是 user 轮次）或在途时忽略。截断为「从尾部截断」，
  /// 会话层按长度 diff 连带删除已落库的后续消息（见 assistant_session_provider）。
  Future<void> resendFrom(int index) async {
    if (state.isBusy) return;
    final messages = state.messages;
    if (index < 0 || index >= messages.length) return;
    if (messages[index].role != ChatRole.user) return;
    final token = ++_sessionToken;
    state = AssistantChatState(
      status: AssistantChatStatus.loading,
      messages: messages.sublist(0, index + 1),
      contextBaseIndex: state.contextBaseIndex.clamp(0, index + 1),
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
      contextBaseIndex: state.contextBaseIndex,
    );
  }

  /// 载入历史会话（子任务 3 切换会话时调用）；废弃在途请求。
  void loadConversation(
    List<ChatMessage> messages, {
    int contextBaseIndex = 0,
  }) {
    _sessionToken++;
    state = AssistantChatState(
      status: messages.isEmpty
          ? AssistantChatStatus.idle
          : AssistantChatStatus.ready,
      messages: List<ChatMessage>.unmodifiable(messages),
      contextBaseIndex: contextBaseIndex.clamp(0, messages.length),
    );
  }

  /// 开启新会话：清空历史、废弃在途请求。
  void startNewConversation() {
    _sessionToken++;
    state = const AssistantChatState();
  }

  /// 清除当前对话上下文：**保留全部消息记录**（展示/存档不变），仅把上下文
  /// 起点移到末尾——后续对话不再把此前的消息发给模型。返回是否实际清除
  /// （已在末尾 / 空会话 / 在途时为 false，不动状态）。
  bool clearContext() {
    if (state.isBusy) return false;
    if (state.contextBaseIndex >= state.messages.length) return false;
    state = state.copyWith(contextBaseIndex: state.messages.length);
    return true;
  }

  /// 页面销毁时调用：令牌失效（丢弃在途流的晚到回调）并收敛在途状态。
  ///
  /// 本 provider 为 App 生命周期常驻（非 autoDispose）：若只令牌失效而不
  /// 收敛，状态会永远停在 loading/streaming —— 重进页面（当前会话仍存在，
  /// ensureOpen 不重置聊天状态）后 isBusy 恒真，清除上下文按钮恒灰、输入栏
  /// 恒禁用。收敛语义与 [stop] 一致：streaming 已累积增量固化为一条
  /// assistant 消息（记录保留、经会话监听自动落库），无增量则回 ready。
  ///
  /// 收敛须延后到微任务：页面 unmount 期间同步写 state 会触发 defunct
  /// element markNeedsBuild 断言；微任务时点 unmount 已完成。
  void discardPending() {
    _sessionToken++;
    if (!state.isBusy) return;
    final snapshot = state;
    scheduleMicrotask(() {
      // 期间已被 stop / 切换会话收敛，或 provider 已销毁：不再写。
      if (_disposed || !state.isBusy) return;
      final partial = snapshot.streamingText.trim();
      if (partial.isEmpty) {
        state = snapshot.copyWith(
          status: AssistantChatStatus.ready,
          streamingText: '',
        );
        return;
      }
      state = AssistantChatState(
        status: AssistantChatStatus.ready,
        messages: [
          ...snapshot.messages,
          ChatMessage(role: ChatRole.assistant, content: partial),
        ],
        contextBaseIndex: snapshot.contextBaseIndex,
      );
    });
  }

  /// 读配置 →（按需）工具循环 → 流式接收 → 固化回答。假定 `state.messages`
  /// 末尾已是待回答的 user 轮次。全程以 [token] 守护代际一致性：每次 await
  /// 后校验，mismatch 只 return 不写 state。
  Future<void> _complete(int token) async {
    LlmClient? client;
    try {
      final repo = ref.read(settingsRepositoryProvider);
      final config = await repo.readLlmConfigForScenario(LlmScenario.assistant);
      if (token != _sessionToken) return;
      if (config == null) {
        state = state.copyWith(
          status: AssistantChatStatus.unconfigured,
          message: '还没有配置 AI 服务，配置后即可使用 AI 助手。',
        );
        return;
      }

      // 家长 override 优先，否则内置儿童安全默认。
      final systemPrompt =
          repo.assistantPromptOverride ?? kAssistantSystemPrompt;
      final tools = ref.read(assistantToolsProvider);
      final toolSchemas = <Map<String, Object?>>[
        for (final tool in tools) tool.toSchema(),
      ];
      final toolsByName = <String, AssistantTool>{
        for (final tool in tools) tool.name: tool,
      };

      client = LlmClient(httpClient: ref.read(llmExplainHttpClientProvider));

      // 工具循环：非流式 chatComplete 判定是否调工具；有则执行并回灌
      // role:tool，循环（≤4 轮）；无 tool_calls 或到顶即跳出走流式收尾。
      // 从 contextBaseIndex 起取历史：清除上下文后旧消息仅存档、不入请求。
      final base = state.contextBaseIndex.clamp(0, state.messages.length);
      final prefix = state.messages.sublist(0, base);
      final working = <ChatMessage>[...state.messages.sublist(base)];
      for (var round = 0; round < kAssistantMaxToolRounds; round++) {
        final completion = await client.chatComplete(
          config: config,
          systemPrompt: systemPrompt,
          messages: working,
          tools: toolSchemas,
          maxTokens: kAssistantMaxTokens,
        );
        if (token != _sessionToken) return;
        if (completion.toolCalls.isEmpty) break;

        // assistant 发起工具调用的轮次（content 可空）并入历史与 UI。
        working.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: completion.content ?? '',
            toolCalls: completion.toolCalls,
          ),
        );
        for (final call in completion.toolCalls) {
          final result = await _runTool(toolsByName, call, token);
          if (token != _sessionToken) return;
          working.add(
            ChatMessage(
              role: ChatRole.tool,
              content: result.content,
              toolCallId: call.id,
              name: call.name,
            ),
          );
        }
        // 工具轮次并入 state → UI 渲染工具卡；仍 loading，等流式收尾。
        state = state.copyWith(
          status: AssistantChatStatus.loading,
          messages: List<ChatMessage>.unmodifiable([...prefix, ...working]),
          streamingText: '',
        );
      }

      // 收尾：流式产出最终自然语言回答（保留逐段渐显 UX）。
      final buffer = StringBuffer();
      await for (final chunk in client.chatStream(
        config: config,
        systemPrompt: systemPrompt,
        messages: working,
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

  /// 执行单个工具调用：未知工具名 / 参数 JSON 非法一律回 [ToolResult.error]
  /// 友好文本（回灌给模型让其纠正），不抛异常、不中断循环。
  Future<ToolResult> _runTool(
    Map<String, AssistantTool> toolsByName,
    ToolCall call,
    int token,
  ) async {
    final tool = toolsByName[call.name];
    if (tool == null) {
      return ToolResult.error('未知工具「${call.name}」，请改用可用的工具。');
    }
    Map<String, dynamic> args;
    try {
      final decoded = jsonDecode(call.argumentsJson);
      args = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      args = const <String, dynamic>{};
    }
    try {
      return await tool.executeCancellable(
        ref,
        args,
        isActive: () => !_disposed && token == _sessionToken,
      );
    } catch (error) {
      // 工具自身兜底之上的最后防线：任何未预期异常都转错误文本回灌。
      AppLogger.e('助手工具执行失败：${call.name}', tag: 'Assistant', error: error);
      return const ToolResult.error('工具执行出错，请换个方式再试试。');
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
      contextBaseIndex: state.contextBaseIndex,
    );
  }
}

/// AI 助手对话状态 provider。
final assistantChatControllerProvider =
    NotifierProvider<AssistantChatController, AssistantChatState>(
  AssistantChatController.new,
);
