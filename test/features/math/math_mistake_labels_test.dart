// test/features/math/math_mistake_labels_test.dart
//
// 错因标签渲染专项测试：
// 两处页面（列表卡片 + 详情页）对 kErrorCauseLabels 的每个键
// 必须渲染中文标签而非英文原键。
// 标签键集单一来源为 lib/math_engine/diagnostics/error_cause_labels.dart，
// 其与诊断器规则 name 的一致性由
// test/math_engine/diagnostics/error_cause_labels_test.dart 守卫。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/math_mistake_detail_page.dart';
import 'package:poemath/features/math/math_mistake_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/math_engine/diagnostics/error_cause_labels.dart';

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
  test('标签表键名不带 _error 后缀（防历史键名漂移）', () {
    // 历史上两处页面 map 使用了带 _error 后缀的错误键名，这里显式排除
    for (final key in kErrorCauseLabels.keys) {
      expect(key.endsWith('_error'), isFalse, reason: '键 $key 不应带 _error 后缀');
    }
  });

  group('错题详情页标签渲染', () {
    for (final entry in kErrorCauseLabels.entries) {
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
    for (final entry in kErrorCauseLabels.entries) {
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
