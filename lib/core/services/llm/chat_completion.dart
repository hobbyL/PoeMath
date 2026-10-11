// lib/core/services/llm/chat_completion.dart
//
// 层级：core/services/llm
// 职责：非流式工具调用（function calling）的响应 DTO（纯 Dart，无 Hive/Flutter）。
//       chatComplete 一次性取回 choices[0].message 的 content 与 tool_calls，
//       交由控制器判定是否进入工具循环（见 design §2/§5）。
//
// 安全边界：content / argumentsJson 均为明文协议数据，绝不承载 API Key。

import 'dart:convert';

/// 模型发起的一次工具调用（OpenAI `tool_calls[i]`）。
///
/// [argumentsJson] 为 `function.arguments` 的原样 JSON 字符串（模型可能
/// 产出瑕疵 JSON，解析交由调用方 try/catch，解析失败回 `ToolResult.isError`）。
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;

  /// 从响应体的单个 `tool_calls[i]` 解析。结构不符返回 null（调用方跳过）。
  static ToolCall? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString();
    final function = raw['function'];
    if (id == null || function is! Map) return null;
    final name = function['name']?.toString();
    if (name == null || name.isEmpty) return null;
    final args = function['arguments'];
    // 标准实现返回字符串；个别实现直接返回对象，统一归一为 JSON 串。
    return ToolCall(
      id: id,
      name: name,
      argumentsJson:
          args is String ? args : jsonEncode(args ?? <String, Object?>{}),
    );
  }

  /// 序列化回请求体（assistant 消息回灌 tool_calls 时携带）。
  Map<String, Object?> toWire() => <String, Object?>{
        'id': id,
        'type': 'function',
        'function': <String, Object?>{
          'name': name,
          'arguments': argumentsJson,
        },
      };

  // argumentsJson 可能含会话数据，toString 刻意只暴露 id/name。
  @override
  String toString() => 'ToolCall(id: $id, name: $name)';
}

/// 非流式对话补全结果：模型的一次性回复。
///
/// [content] 可空（模型只发起工具调用时常为 null/空）；
/// [toolCalls] 为空表示模型未请求任何工具，上层退化为纯聊天。
class ChatCompletion {
  const ChatCompletion({
    this.content,
    this.toolCalls = const <ToolCall>[],
  });

  final String? content;
  final List<ToolCall> toolCalls;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}
