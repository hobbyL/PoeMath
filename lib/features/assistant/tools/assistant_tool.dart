// lib/features/assistant/tools/assistant_tool.dart
//
// 层级：features/assistant/tools
// 职责：助手可调用的应用内工具抽象（OpenAI function calling）。
//       每个工具自描述 name/description/JSON Schema，并实现 execute；
//       toSchema() 产出 OpenAI tools 数组单项，交由 chatComplete 下发。
//
// 执行拿 [Ref]：repo 读写与 context-free 导航（ref.read(appRouterProvider)），
// 不依赖 BuildContext。
//
// 安全边界：工具参数 / 回灌文本均为明文会话数据，绝不承载 API Key。

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 工具执行结果。[content] 作为 `role:tool` 消息体回灌给模型；
/// [isError] 标记执行失败（仍以友好文本回灌，不抛异常、不中断循环）。
class ToolResult {
  const ToolResult(this.content) : isError = false;
  const ToolResult.error(this.content) : isError = true;

  final String content;
  final bool isError;
}

/// 助手可调用的应用内工具。
abstract class AssistantTool {
  /// 工具名（OpenAI `function.name`，须与模型回传的 tool_calls[].name 一致）。
  String get name;

  /// 工具用途描述（供模型判断何时调用）。
  String get description;

  /// 参数的 JSON Schema（OpenAI `function.parameters` 格式）。
  Map<String, Object?> get parametersSchema;

  /// 执行工具。[args] 为模型给出的参数（已解析）；返回回灌文本。
  /// 实现须自行兜底非法参数并返回 [ToolResult.error]，不得抛异常。
  Future<ToolResult> execute(Ref ref, Map<String, dynamic> args);

  /// 异步工具须在导航/写入等副作用前检查调用仍有效。
  Future<ToolResult> executeCancellable(
    Ref ref,
    Map<String, dynamic> args, {
    required bool Function() isActive,
  }) async {
    if (!isActive()) return const ToolResult.error('操作已取消');
    return execute(ref, args);
  }

  /// 序列化为 OpenAI tools 数组单项。
  Map<String, Object?> toSchema() => <String, Object?>{
        'type': 'function',
        'function': <String, Object?>{
          'name': name,
          'description': description,
          'parameters': parametersSchema,
        },
      };
}
