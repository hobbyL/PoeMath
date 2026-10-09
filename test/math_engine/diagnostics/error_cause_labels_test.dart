// test/math_engine/diagnostics/error_cause_labels_test.dart
//
// 错因标签表与诊断器规则键集一致性守卫：
// kErrorCauseLabels 的键集必须与 MistakeDiagnoser 全部规则实例的 name
// 完全一致。引擎新增错因规则而标签表漏更新时，本测试必须红——
// 否则页面与 AI 讲解 prompt 会回退显示英文原键。

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/math_engine/diagnostics/error_cause_labels.dart';
import 'package:poemath/math_engine/diagnostics/mistake_rule.dart';

void main() {
  group('键集一致性（单一来源闭环）', () {
    test('kErrorCauseLabels 键集 == 诊断器规则 name 集合', () {
      expect(
        kErrorCauseLabels.keys.toSet(),
        equals(MistakeDiagnoser.categoryNames.toSet()),
      );
    });

    test('规则 name 无重复（防 toSet 比较掩盖重名规则）', () {
      // toSet 比较对重名规则不敏感（去重后仍可相等）；重名意味着
      // 诊断器中后注册的规则永远不可达，需在引擎层直接暴露。
      final names = MistakeDiagnoser.categoryNames.toList();
      expect(
        names.toSet().length,
        names.length,
        reason: '引擎存在重名规则 name，诊断器后注册的规则不可达',
      );
    });

    test('标签表非空且每个值非空中文', () {
      expect(kErrorCauseLabels, isNotEmpty);
      for (final entry in kErrorCauseLabels.entries) {
        expect(entry.key, isNotEmpty);
        expect(entry.value, isNotEmpty);
      }
    });
  });

  group('errorCauseLabel 回退语义', () {
    test('命中返回中文标签', () {
      expect(errorCauseLabel('carry_omission'), '进位遗漏');
      expect(errorCauseLabel('borrow_omission'), '退位遗漏');
      expect(errorCauseLabel('multiplication_table'), '口诀错误');
      expect(errorCauseLabel('operation_order'), '运算顺序错误');
      expect(errorCauseLabel('remainder_mistake'), '余数错误');
      expect(errorCauseLabel('decimal_alignment'), '小数对位错误');
    });

    test('未命中回退英文原键（与页面现状一致）', () {
      expect(errorCauseLabel('unknown_cause'), 'unknown_cause');
    });

    test('null 传入返回 null（调用方守卫后才渲染）', () {
      expect(errorCauseLabel(null), isNull);
    });
  });
}
