// lib/features/assistant/tools/open_practice_tool.dart
//
// 层级：features/assistant/tools
// 职责：打开练习工具。context-free 导航到口算练习或应用题题库。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/features/assistant/tools/assistant_tool.dart';

/// 打开练习工具：口算练习（arithmetic）或应用题题库（word_problem）。
class OpenPracticeTool extends AssistantTool {
  @override
  String get name => 'open_practice';

  @override
  String get description =>
      '为孩子打开练习页面。arithmetic 打开口算练习，word_problem 打开应用题题库。'
      '适用于孩子说想做练习 / 做题时。';

  @override
  Map<String, Object?> get parametersSchema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'kind': <String, Object?>{
            'type': 'string',
            'description': '练习类型：arithmetic（口算）或 word_problem（应用题题库）',
            'enum': <String>['arithmetic', 'word_problem'],
          },
        },
      };

  @override
  Future<ToolResult> execute(Ref ref, Map<String, dynamic> args) async {
    final kind = args['kind']?.toString() ?? 'arithmetic';
    final router = ref.read(appRouterProvider);
    switch (kind) {
      case 'word_problem':
        router.push(AppRoutes.wordProblemLibrary);
        return const ToolResult('已为你打开应用题题库，去挑一道题练练吧～');
      case 'arithmetic':
      default:
        router.push(AppRoutes.mathPractice);
        return const ToolResult('已为你打开口算练习，加油哦～');
    }
  }
}
