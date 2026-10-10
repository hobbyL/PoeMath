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
  });

  final AssistantChatStatus status;

  /// 已完成的会话轮次（不含 system prompt）。
  final List<ChatMessage> messages;

  /// 当前流式 assistant 气泡的增量缓冲（[AssistantChatStatus.streaming] 期非空）。
  final String streamingText;

  /// 错误 / 引导文案（error / unconfigured 时非空）。
  final String? message;

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
  }) {
    return AssistantChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      streamingText: streamingText ?? this.streamingText,
      message: message ?? this.message,
    );
  }
}
