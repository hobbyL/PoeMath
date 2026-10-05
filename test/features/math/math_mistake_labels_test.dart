// test/features/math/math_mistake_labels_test.dart
//
// R5（错题标签键名对齐）专项测试：
// 两处 _errorTypeLabels（列表卡片 + 详情页）的键必须覆盖诊断器
// mistake_rule.dart 的全部 6 个权威分类键，渲染中文标签而非英文原键。
// 权威键清单：carry_omission / borrow_omission / multiplication_table /
// operation_order / remainder_mistake / decimal_alignment。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/math_mistake_detail_page.dart';
import 'package:poemath/features/math/math_mistake_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

/// 诊断器（mistake_rule.dart）6 类规则的 name 权威键。
const authoritativeKeys = <String, String>{
  'carry_omission': '进位遗漏',
  'borrow_omission': '退位遗漏',
  'multiplication_table': '口诀错误',
  'operation_order': '运算顺序错误',
  'remainder_mistake': '余数错误',
  'decimal_alignment': '小数对位错误',
};

/// 不触碰 Hive 的内存仓储（仅为标签渲染测试服务，
/// 真实仓储行为由 math_mistake_repository_test 覆盖）。
class _FakeMistakeRepo extends MathMistakeRepository {
  _FakeMistakeRepo(this._mistakes);

  final List<MathMistake> _mistakes;

  @override
  MathMistake? getById(String id) {
    for (final m in _mistakes) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  List<MathMistake> getAll() => List.of(_mistakes);

  @override
  List<MathMistake> getUnresolved() =>
      _mistakes.where((m) => !m.isResolved).toList();

  @override
  int get totalCount => _mistakes.length;
}

MathMistake _mistakeOf(String id, String errorType) {
  return MathMistake(
    id: id,
    profileId: 'default',
    problemText: '3 × 5 = ?',
    correctAnswer: '15',
    userAnswer: '14',
    problemType: 'multiplication',
    grade: 2,
    errorType: errorType,
  );
}

void main() {
  test('权威键清单与诊断器 6 类规则一一对应（防测试数据漂移）', () {
    expect(authoritativeKeys.length, 6);
    // 历史上两处页面 map 使用了带 _error 后缀的错误键名，这里显式排除
    for (final key in authoritativeKeys.keys) {
      expect(key.endsWith('_error'), isFalse, reason: '键 $key 不应带 _error 后缀');
    }
  });

  group('错题详情页标签渲染', () {
    for (final entry in authoritativeKeys.entries) {
      testWidgets('详情页对 ${entry.key} 显示「${entry.value}」', (tester) async {
        final repo = _FakeMistakeRepo([_mistakeOf('m1', entry.key)]);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [mathMistakeRepoProvider.overrideWithValue(repo)],
            child: const MaterialApp(
              home: MathMistakeDetailPage(mistakeId: 'm1'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('错因：${entry.value}'), findsOneWidget);
        // 英文原键不得回退显示
        expect(find.textContaining(entry.key), findsNothing);
      });
    }
  });

  group('错题列表页标签渲染', () {
    // CustomScrollView 懒加载，逐条 pump 确保卡片 build 并可见
    for (final entry in authoritativeKeys.entries) {
      testWidgets('列表卡片对 ${entry.key} 显示「${entry.value}」', (tester) async {
        final repo = _FakeMistakeRepo([_mistakeOf('m1', entry.key)]);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [mathMistakeRepoProvider.overrideWithValue(repo)],
            child: const MaterialApp(home: MathMistakePage()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(entry.value), findsOneWidget);
        // 英文原键不得回退显示在卡片标签上
        expect(find.text(entry.key), findsNothing);
      });
    }
  });
}
