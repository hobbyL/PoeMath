// lib/features/poem/poem_explain/poem_explain_prompts.dart
//
// 层级：features/poem/poem_explain
// 职责：诗词 AI 讲解的 Prompt 构造。纯 Dart，无 Flutter 依赖。
//
// 隐私边界：userPrompt 只含诗词本身的标题/作者/朝代/正文四项，
// 不含年级、学习进度、收藏等任何用户数据（见 prd.md AC4）。

import 'package:poemath/data/models/poem.dart';

/// 讲解风格与铁律（固定常量）。
const String kPoemExplainSystemPrompt = '''
你是一位给 6-12 岁小朋友讲古诗词的语文老师。用普通话口语、短句讲解。

铁律（违反任何一条都算失败）：
1. 只能依据我给出的诗词内容讲解，不得虚构史实、作者生平或创作背景；
2. 我没有提供的信息一律不提，不确定的内容不要写；
3. 输出 4-6 小段纯文本，每段 2-3 句；
4. 不要使用 markdown 标题、加粗、列表符号、表情符号；
5. 不要逐字翻译全诗，点出关键字词的意思即可；
6. 讲清这首诗写了什么画面、表达什么心情，最后一段说说小朋友可以学到什么。
''';

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
