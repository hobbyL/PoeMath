// lib/math_engine/diagnostics/error_cause_labels.dart
//
// 错因 category → 中文标签的唯一映射表（单一来源）。
// 消费方：错题列表卡片、错题详情页、口算 AI 解析 prompt、标签守卫测试；
// 引擎新增错因规则而本表漏更新时，键集一致性测试
// （test/math_engine/diagnostics/error_cause_labels_test.dart）必须红。

/// 错因 category → 中文标签。
///
/// key 对齐 MistakeDiagnoser 规则实例的 name（权威键，见 mistake_rule.dart）。
const Map<String, String> kErrorCauseLabels = {
  'carry_omission': '进位遗漏',
  'borrow_omission': '退位遗漏',
  'multiplication_table': '口诀错误',
  'operation_order': '运算顺序错误',
  'remainder_mistake': '余数错误',
  'decimal_alignment': '小数对位错误',
};

/// 查表返回错因中文标签。
///
/// 命中返回中文；未命中返回原 category（回退显示英文原键，与页面既有
/// `?? mistake.errorType!` 行为一致）；null 返回 null（调用方在
/// `errorType != null` 守卫内渲染）。
String? errorCauseLabel(String? category) {
  if (category == null) return null;
  return kErrorCauseLabels[category] ?? category;
}
