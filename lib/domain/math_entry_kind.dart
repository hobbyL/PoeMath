// lib/domain/math_entry_kind.dart
//
// 层级：domain
// 职责：口算页可显示的一级练习类型。顺序即卡片显示顺序。
//
// 与 ProblemMode 的区别：ProblemMode 描述「这道题长什么样」（求未知、
// 比大小、竖式…），本枚举描述「口算页上有哪几张入口卡片」。一个入口
// 可能对应多个 ProblemMode（如「口算」入口可再选题型），两者不是同一
// 维度，不要合并。
//
// 持久化：以逗号分隔的 name 串存进 `HiveBoxes.settings`（见
// `SettingsRepository.mathEntryKinds`）。用 name 而非 index：新增枚举
// 值时不会让旧数据的语义错位。

/// 口算页一级练习入口。
///
/// **顺序即显示顺序**。新增值请追加在末尾，且同步
/// `settings_constraints.dart` 与 `backup_service.dart` 的登记。
enum MathEntryKind {
  /// 普通口算练习（进入后可再选普通方案内的题型）。
  arithmetic,

  /// 竖式计算。是否可用受当前册次与难度的引擎能力限制。
  vertical,

  /// 应用题（AI 出题 + 题库）。
  wordProblem,

  /// 限时挑战。
  challenge,
}

/// 默认开启的全部入口（新装与旧数据缺省均为全开，等价改造前行为）。
const Set<MathEntryKind> kDefaultMathEntryKinds = {
  MathEntryKind.arithmetic,
  MathEntryKind.vertical,
  MathEntryKind.wordProblem,
  MathEntryKind.challenge,
};

/// 解析逗号分隔的入口串；忽略无法识别的 name（前向兼容）。
///
/// 返回空集表示「无有效项」——调用方负责回落默认，不在此处兜底，
/// 以便校验层能区分「用户显式清空」与「数据缺失」。
Set<MathEntryKind> parseMathEntryKinds(String raw) {
  if (raw.trim().isEmpty) return const {};
  final byName = {for (final kind in MathEntryKind.values) kind.name: kind};
  return raw
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .map((part) => byName[part])
      .whereType<MathEntryKind>()
      .toSet();
}

/// 序列化为逗号分隔串。
///
/// 按 [MathEntryKind.values] 顺序输出（而非集合迭代顺序），让同一集合
/// 恒定得到同一字符串 —— 便于测试断言，也避免无意义的写盘差异。
String encodeMathEntryKinds(Set<MathEntryKind> kinds) {
  return MathEntryKind.values
      .where(kinds.contains)
      .map((kind) => kind.name)
      .join(',');
}
