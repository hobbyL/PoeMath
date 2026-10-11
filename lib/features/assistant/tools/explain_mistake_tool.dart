// lib/features/assistant/tools/explain_mistake_tool.dart
//
// 层级：features/assistant/tools
// 职责：讲解错题工具。从错题本取一道错题的信息作为 payload 回灌，
//       由模型在对话内行内讲解（不弹独立讲解页，保持对话内）。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/assistant/tools/assistant_tool.dart';

/// 讲解错题工具：返回一道错题的题面 / 答案 / 错因，供模型行内讲解。
class ExplainMistakeTool extends AssistantTool {
  @override
  String get name => 'explain_mistake';

  @override
  String get description =>
      '获取一道口算错题的信息（题目、孩子的答案、正确答案、错误类型），'
      '以便你在对话里一步步给孩子讲解。'
      '不传 mistakeId 时默认取最近一道还没订正的错题。';

  @override
  Map<String, Object?> get parametersSchema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'mistakeId': <String, Object?>{
            'type': 'string',
            'description': '错题 ID（可选）；缺省取最近一道未订正的错题。',
          },
        },
      };

  @override
  Future<ToolResult> execute(Ref ref, Map<String, dynamic> args) async {
    final repo = ref.read(mathMistakeRepositoryProvider);
    final id = args['mistakeId']?.toString();

    final mistake = (id != null && id.isNotEmpty)
        ? repo.getById(id)
        : _firstUnresolved(repo.getUnresolved());
    if (mistake == null) {
      return const ToolResult('没有找到可讲解的错题，错题本是空的或都已订正啦。');
    }

    final buffer = StringBuffer()
      ..writeln('题目：${mistake.problemText}')
      ..writeln('孩子的答案：${mistake.userAnswer}')
      ..writeln('正确答案：${mistake.correctAnswer}');
    final errorType = mistake.errorType;
    if (errorType != null && errorType.isNotEmpty) {
      buffer.writeln('错误类型：$errorType');
    }
    buffer.write('请用鼓励的语气，一步步给孩子讲清楚这道题怎么做对。');
    return ToolResult(buffer.toString());
  }

  static T? _firstUnresolved<T>(List<T> list) =>
      list.isNotEmpty ? list.first : null;
}
