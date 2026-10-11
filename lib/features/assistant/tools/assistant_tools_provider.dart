// lib/features/assistant/tools/assistant_tools_provider.dart
//
// 层级：features/assistant/tools
// 职责：注册助手可用工具集。控制器据此构造 tools 入参与按 name 分发 execute。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/features/assistant/tools/assistant_tool.dart';
import 'package:poemath/features/assistant/tools/explain_mistake_tool.dart';
import 'package:poemath/features/assistant/tools/generate_word_problems_tool.dart';
import 'package:poemath/features/assistant/tools/open_practice_tool.dart';

/// 助手可调用的工具集（出题 / 打开练习 / 讲解错题）。
final assistantToolsProvider = Provider<List<AssistantTool>>((ref) {
  return <AssistantTool>[
    GenerateWordProblemsTool(),
    OpenPracticeTool(),
    ExplainMistakeTool(),
  ];
});
