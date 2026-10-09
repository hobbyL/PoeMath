// lib/features/poem/poem_explain/poem_explain_prompts.dart
//
// 层级：features/poem/poem_explain
// 职责：诗词 AI 讲解的 Prompt 构造。纯 Dart，无 Flutter 依赖。
//
// 隐私边界：userPrompt 只含诗词本身的标题/作者/朝代/正文四项，
// 不含年级、学习进度、收藏等任何用户数据（见 prd.md AC4）。
//
// 默认 system prompt 常量迁至 core/prompts/explain_prompt_defaults.dart
// （设置页与 controller 共享的出厂默认）；此处 re-export 保持既有
// import 路径兼容。

import 'package:poemath/data/models/poem.dart';

export 'package:poemath/core/prompts/explain_prompt_defaults.dart';

/// 构造用户侧 Prompt：仅标题、作者、朝代、正文。
String buildPoemExplainUserPrompt(Poem poem) {
  final buffer = StringBuffer()
    ..writeln('《${poem.title}》')
    ..writeln('作者：${poem.author}（${poem.dynasty}）')
    ..writeln('正文：')
    ..writeln(poem.content)
    ..writeln()
    ..write('请按上面的要求讲解这首诗。');
  return buffer.toString();
}
