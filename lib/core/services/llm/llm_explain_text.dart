// lib/core/services/llm/llm_explain_text.dart
//
// 层级：core/services/llm
// 职责：AI 讲解输出的文本规范化（诗词讲解 / 口算解析共用）。纯 Dart。

/// 规范化模型输出为段落列表。
///
/// 模型偶尔无视「纯文本」约束输出 markdown，这里做最小清洗：
/// 去掉 code fence、按行切分、剥离行首列表/标题符号与加粗标记、丢弃空行。
List<String> splitExplainParagraphs(String raw) {
  final paragraphs = <String>[];
  for (final line in raw.split('\n')) {
    var text = line.trim();
    if (text.isEmpty) continue;
    // code fence 整行丢弃。
    if (text.startsWith('```')) continue;
    // 行首列表符号 / 标题井号。
    text = text.replaceFirst(RegExp(r'^(#{1,6}\s*|[-*+•]\s+|\d+[.、)]\s+)'), '');
    // 残留的加粗标记。
    text = text.replaceAll('**', '').trim();
    if (text.isEmpty) continue;
    paragraphs.add(text);
  }
  return paragraphs;
}
