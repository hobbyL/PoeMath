// lib/core/services/tts/markdown_speech_text.dart
//
// 层级：core/services/tts
// 职责：把 Markdown + LaTeX 文本转成适合朗读引擎的纯文本（纯 Dart）。
//       AI 助手的回答经 gpt_markdown 渲染，直接送 TTS 会把 **、#、$…$
//       与 LaTeX 命令原样读出；本函数做朗读前的最小清洗，并把常见数学
//       符号转成中文口语（\frac{1}{2} → 2分之1、\times → 乘以 等）。
//
// 与 llm_explain_text.splitExplainParagraphs 的分工：那边面向「纯文本
// 讲解 + 偶发 markdown」的段落切分；这边面向富 Markdown 回答的整段朗读
// 文本，输出单个字符串——分句由 TtsService.speakSentences 按标点完成。

/// LaTeX 命令 → 中文口语映射。
///
/// 应用时按 key 长度降序替换，防止 `\le` 先吃掉 `\leq` 的前缀。
const Map<String, String> _latexCommandSpeech = <String, String>{
  '\\leq': '小于等于',
  '\\le': '小于等于',
  '\\geq': '大于等于',
  '\\ge': '大于等于',
  '\\neq': '不等于',
  '\\ne': '不等于',
  '\\approx': '约等于',
  '\\times': '乘以',
  '\\cdot': '乘',
  '\\div': '除以',
  '\\pm': '加减',
  '\\mp': '减加',
  '\\pi': '圆周率',
  '\\infty': '无穷',
  '\\angle': '角',
  '\\perp': '垂直于',
  '\\parallel': '平行于',
  '\\cdots': '等等',
  '\\ldots': '等等',
  '\\dots': '等等',
  '\\degree': '度',
  '\\quad': '，',
  '\\ ': ' ',
};

/// Markdown + LaTeX → 朗读用纯文本。
///
/// 清洗规则（顺序敏感）：
/// 1. 代码块（```…```）整块移除——代码朗读无意义；
/// 2. 行内代码去反引号，内容保留；
/// 3. 图片整体移除，链接保留文字、丢弃地址；
/// 4. LaTeX（`$$…$$` / `$…$` / `\[…\]` / `\(…\)`）→ [_latexToSpeech]；
/// 5. 行首标题 / 列表 / 引用符号剥离，表格分隔行丢弃、`|` 换空格，
///    强调标记（`**` `__` `*` `_`）去除（此步在 LaTeX 转换之后，
///    剩余的 `*` `_` 才是 markdown 残留）。
String markdownToSpeechText(String markdown) {
  var text = markdown;

  // 1) 代码块整块移除（含围栏语言标注行）。
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  // 2) 行内代码去反引号（Dart replaceAll 不解释 $1，须 replaceAllMapped）。
  text = text.replaceAllMapped(
    RegExp(r'`([^`\n]*)`'),
    (m) => m.group(1) ?? '',
  );

  // 3) 图片整体移除；链接保留文字。
  text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ');
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );

  // 4) LaTeX → 中文口语。$$…$$ 先于 $…$ 处理（成对消费后剩余的才是单 $）。
  text = text
      .replaceAllMapped(
        RegExp(r'\$\$([\s\S]*?)\$\$'),
        (m) => _latexToSpeech(m.group(1)!),
      )
      .replaceAllMapped(
        RegExp(r'\$([^$\n]+)\$'),
        (m) => _latexToSpeech(m.group(1)!),
      )
      .replaceAllMapped(
        RegExp(r'\\\[([\s\S]*?)\\\]'),
        (m) => _latexToSpeech(m.group(1)!),
      )
      .replaceAllMapped(
        RegExp(r'\\\(([\s\S]*?)\\\)'),
        (m) => _latexToSpeech(m.group(1)!),
      );

  // 5) 行级 markdown 符号清洗 + 空行折叠。
  final lines = <String>[];
  for (final rawLine in text.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty) continue;
    // 未闭合围栏的残留行。
    if (line.startsWith('```')) continue;
    // 行首标题 / 有序与无序列表 / 引用 / 水平分割线。有序列表区分分隔符：
    // `1. ` 需后随空白（避开小数 3.14），中文 `2、` 常无空格故不要求。
    line = line.replaceFirst(
      RegExp(
        r'^(#{1,6}\s*|[-*+•]\s+|\d+[.]\s+|\d+[、)]\s*|>\s?|-{3,}|\*{3,})',
      ),
      '',
    );
    // 表格分隔行（| --- | :---: |）丢弃。
    if (line.contains('|') &&
        RegExp(
          r'^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$',
        ).hasMatch(line)) {
      continue;
    }
    line = line.replaceAll('|', ' ');
    // 强调标记（LaTeX 已转换，剩余 * / _ 为 markdown 残留）。
    line = line.replaceAll('**', '').replaceAll('__', '');
    line = line.replaceAll('*', '').replaceAll('_', '');
    // 表格竖线换空格等产生的连续空白折叠。
    line = line.replaceAll(RegExp(r'\s{2,}'), ' ');
    line = line.trim();
    if (line.isEmpty) continue;
    lines.add(line);
  }
  return lines.join('\n');
}

/// LaTeX 片段 → 中文口语。未识别的命令去命令名、保留参数文本。
String _latexToSpeech(String tex) {
  var t = tex.trim();
  if (t.isEmpty) return '';
  t = t.replaceAll('\\dfrac', '\\frac');

  // 分数：\frac{a}{b} → 「b分之a」（中文读法分母在前）；嵌套最多展开 3 层。
  for (var i = 0; i < 3; i++) {
    final next = t.replaceAllMapped(
      RegExp(r'\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}'),
      (m) => '${m.group(2)}分之${m.group(1)}',
    );
    if (next == t) break;
    t = next;
  }

  // 根号：\sqrt{x} → 根号x；\sqrt[n]{x} 的 n 无法口语化，取被开方数。
  t = t.replaceAllMapped(
    RegExp(r'\\sqrt\s*(?:\[[^\]]*\])?\s*\{([^{}]*)\}'),
    (m) => '根号${m.group(1)}',
  );

  // 百分号前置：50\% → 百分之50（须在通用命令清理前完成重排）。
  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*\\%'),
    (m) => '百分之${m.group(1)}',
  );

  // 角度：90^\circ → 90度（须在上标数字规则前）。
  t = t.replaceAll(RegExp(r'\^?\s*\\circ'), '度');

  // 上标：^2 → 的平方、^3 → 的立方、^{n} → 的n次方。
  t = t.replaceAllMapped(
    RegExp(r'\^\{?(\d+)\}?'),
    (m) {
      final n = m.group(1)!;
      if (n == '2') return '的平方';
      if (n == '3') return '的立方';
      return '的$n次方';
    },
  );

  // 已知命令 → 中文口语（长 key 优先，防 \le 吃掉 \leq）。
  final commands = _latexCommandSpeech.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final cmd in commands) {
    t = t.replaceAll(cmd, _latexCommandSpeech[cmd]!);
  }

  // 未识别命令（\text、\begin 等）：去命令名，参数文本经去花括号后保留。
  t = t.replaceAll(RegExp(r'\\[a-zA-Z]+\s*'), ' ');
  // 残留的孤立百分号（无前置数字的 \%）。
  t = t.replaceAll('\\%', '%');
  // 花括号与 latex 手动换行残留。
  t = t.replaceAll('{', '').replaceAll('}', '');
  t = t.replaceAll('\\\\', ' ');
  // 空白折叠。
  t = t.replaceAll(RegExp(r'\s{2,}'), ' ');
  return t.trim();
}
