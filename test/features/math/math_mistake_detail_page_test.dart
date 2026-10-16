// test/features/math/math_mistake_detail_page_test.dart
//
// 错题详情页展示测试：③ 聚合计数「累计答错 N 次」与
// 既有「重练 N 次」徽章并存（两者语义不同：答错次数 ≠ 重练次数）。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/math_mistake_detail_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/models/vertical_attempt.dart';

/// 不触碰 Hive 的内存仓储（真实仓储行为由 math_mistake_repository_test 覆盖）。
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
}

MathMistake _mistakeOf({
  int wrongCount = 1,
  int retryCount = 0,
  bool isResolved = false,
}) {
  return MathMistake(
    id: 'm1',
    profileId: 'default',
    problemText: '25 + 38 = ?',
    correctAnswer: '63',
    userAnswer: '61',
    problemType: 'addition',
    grade: 2,
    isResolved: isResolved,
    retryCount: retryCount,
    wrongCount: wrongCount,
  );
}

Future<void> _pumpDetail(WidgetTester tester, MathMistake mistake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mathMistakeRepoProvider.overrideWithValue(_FakeMistakeRepo([mistake])),
      ],
      child: const MaterialApp(
        home: MathMistakeDetailPage(mistakeId: 'm1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('结果正确但进位错误时展示真实过程与中文错因', (tester) async {
    final problem = MathProblem(
      operands: [NumberValue.fromInt(38), NumberValue.fromInt(45)],
      operators: const [Operator.add],
      result: NumberValue.fromInt(83),
      mode: ProblemMode.vertical,
      grade: 2,
    );
    final mistake = MathMistake(
      id: 'm1',
      profileId: 'default',
      problemText: problem.problemText,
      correctAnswer: '83',
      userAnswer: '83',
      problemType: 'vertical',
      grade: 2,
      errorType: VerticalAttempt.errorCategory,
      problemJson: jsonEncode(problem.toJson()),
      attemptJson: jsonEncode(
          const VerticalAttempt(ones: '3', tens: '8', regroup: '0').toJson(),),
    );
    await _pumpDetail(tester, mistake);
    expect(find.text('错因：竖式过程错误'), findsOneWidget);
    expect(find.text('本题同时检查结果与进退位，结果相同也可能出现过程错误。'), findsOneWidget);
    expect(find.textContaining('个位进位：0'), findsOneWidget);
  });

  testWidgets('首次答错显示累计答错 1 次', (tester) async {
    await _pumpDetail(tester, _mistakeOf());
    expect(find.text('累计答错 1 次'), findsOneWidget);
  });

  testWidgets('同题多次答错显示累计次数', (tester) async {
    await _pumpDetail(tester, _mistakeOf(wrongCount: 4));
    expect(find.text('累计答错 4 次'), findsOneWidget);
  });

  testWidgets('已掌握时累计答错与重练次数并存', (tester) async {
    await _pumpDetail(
      tester,
      _mistakeOf(wrongCount: 3, retryCount: 2, isResolved: true),
    );
    expect(find.text('累计答错 3 次'), findsOneWidget);
    expect(find.text('重练 2 次'), findsOneWidget);
    expect(find.text('已掌握'), findsOneWidget);
  });
}
