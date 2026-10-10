// lib/core/services/llm/chat_message.dart
//
// 层级：core/services/llm
// 职责：面向 OpenAI 兼容协议的对话消息 DTO（纯 Dart，无 Hive/Flutter 依赖）。
//
// 关键解耦：这是 API 层的协议模型，与子任务 2 的持久化 `Message`（Hive）
// 解耦——持久化模型向本模型做单向映射，client 层不感知持久化。
//
// 安全边界：content/toolCallId/name 均为明文会话数据，绝不承载 API Key。

/// 对话消息角色（OpenAI chat completions 协议）。
enum ChatRole {
  system('system'),
  user('user'),
  assistant('assistant'),
  tool('tool');

  const ChatRole(this.wire);

  /// 序列化到请求体 `role` 字段的线格式字符串。
  final String wire;
}

/// 单条对话消息。
///
/// [toolCallId] / [name] 为子任务 5（工具调用）预留：`role=tool` 的结果
/// 消息用 `toolCallId` 关联发起调用、`name` 标记工具名。内核阶段仅
/// user/assistant/system 轮次使用，这两个字段保持 null。
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.name,
  });

  final ChatRole role;
  final String content;

  /// 预留给子任务 5：role=tool 时关联的 tool_call id。
  final String? toolCallId;

  /// 预留给子任务 5：role=tool 时的工具名。
  final String? name;

  /// 序列化为 OpenAI 兼容请求体中的单条消息。
  ///
  /// 仅在对应字段非空时才写出 `tool_call_id` / `name`，避免给普通
  /// 会话轮次附加无意义的 null 字段。
  Map<String, Object?> toJson() => <String, Object?>{
        'role': role.wire,
        'content': content,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (name != null) 'name': name,
      };

  @override
  String toString() =>
      'ChatMessage(role: ${role.wire}, content: ${content.length} chars)';
}
