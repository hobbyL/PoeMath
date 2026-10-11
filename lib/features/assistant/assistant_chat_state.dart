// lib/features/assistant/assistant_chat_state.dart
//
// 层级：features/assistant
// 职责：AI 助手对话的状态模型。纯 Dart，无 Flutter 依赖。
//
// messages 为已完成的会话轮次（user/assistant/tool，不含 system）；
// streamingText 为当前流式 assistant 气泡的增量缓冲，固化后并入 messages。

import 'package:poemath/core/services/llm/chat_message.dart';

/// 助手对话状态机（与讲解侧同构，复用六态）。
enum AssistantChatStatus { idle, loading, streaming, ready, error, unconfigured }

/// AI 助手对话状态。
class AssistantChatState {
  const AssistantChatState({
    this.status = AssistantChatStatus.idle,
    this.messages = const <ChatMessage>[],
    this.streamingText = '',
    this.message,
    this.contextBaseIndex = 0,
  });

  final AssistantChatStatus status;

  /// 已完成的会话轮次（不含 system prompt）。
  final List<ChatMessage> messages;

  /// 当前流式 assistant 气泡的增量缓冲（[AssistantChatStatus.streaming] 期非空）。
  final String streamingText;

  /// 错误 / 引导文案（error / unconfigured 时非空）。
  final String? message;

  /// 上下文起点下标：发给模型的历史从 `messages[contextBaseIndex]` 开始，
  /// 之前的消息仅用于展示/存档，不参与下一轮请求。点「清除上下文」会把它
  /// 置为当前 `messages.length`（记录保留，后续对话不再带入旧消息）。
  final int contextBaseIndex;

  bool get isIdle => status == AssistantChatStatus.idle;
  bool get isLoading => status == AssistantChatStatus.loading;
  bool get isStreaming => status == AssistantChatStatus.streaming;
  bool get isReady => status == AssistantChatStatus.ready;
  bool get isError => status == AssistantChatStatus.error;
  bool get isUnconfigured => status == AssistantChatStatus.unconfigured;

  /// 是否有在途请求（loading 或 streaming），用于防重入与 UI 禁用输入。
  bool get isBusy => isLoading || isStreaming;

  AssistantChatState copyWith({
    AssistantChatStatus? status,
    List<ChatMessage>? messages,
    String? streamingText,
    String? message,
    int? contextBaseIndex,
  }) {
    return AssistantChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      streamingText: streamingText ?? this.streamingText,
      message: message ?? this.message,
      contextBaseIndex: contextBaseIndex ?? this.contextBaseIndex,
    );
  }
}
