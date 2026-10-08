// lib/features/formula/formula_speak_text.dart
//
// 公式朗读文本构造：符号可读化替换 + 区域播放文本拼装（任务 10-07-formula-tts）。
//
// formula_text 是数学符号串（如 `C = (a + b) × 2`），TTS 逐字母读出小学生
// 无法理解——公式区朗读「名称 + 参数释义」而非符号原文（既定决策）；
// memory_tip / example 是中文口诀与例题，但含 `π ² ³ ° × ÷ →` 等读不准
// 的符号，朗读前统一过读音表替换。

import 'package:poemath/data/models/formula.dart';

/// 符号读音表：数据集（formulas.json，65 条）实测出现的不可读符号。
///
/// 只收录 TTS 读不好或读错语义的符号；字母（a/b/C/S/r/h/η 等）保持
/// 原样由 TTS 按字母读音；`…` `「」` TTS 可自行处理不收录。未收录
/// 符号原样保留（不报错、不吞字符）。
const Map<String, String> kFormulaSymbolReadings = {
  'π': '派',
  '²': '的平方',
  '³': '的立方',
  '°': '度',
  '×': '乘',
  '÷': '除以',
  '±': '正负',
  '≤': '小于等于',
  '≥': '大于等于',
  '≈': '约等于',
  '≠': '不等于',
  '∠': '角',
  '→': '到',
};

/// 文本符号可读化：按读音表逐符号替换，未收录符号原样保留。
String replaceFormulaSymbols(String text) {
  if (text.isEmpty) return text;
  return text.splitMapJoin(
    '',
    onNonMatch: (chunk) => kFormulaSymbolReadings[chunk] ?? chunk,
  );
}

/// 公式区朗读文本：`名称。` + 各参数的「`符号读音`，`释义`。」。
///
/// 无 params 的公式只读名称。参数符号同样过读音表（如 `π` → 「派」；
/// `d1` 等字母符号原样按字母读）。公式区**不**朗读 formulaText /
/// formulaLatex 原文（符号串不可读，既定决策）。
String formulaSpeakText(Formula formula) {
  final buffer = StringBuffer('${replaceFormulaSymbols(formula.name)}。');
  for (final param in formula.params) {
    final symbol = replaceFormulaSymbols(param.symbol);
    buffer.write('$symbol，${param.meaning}。');
  }
  return buffer.toString();
}
