// 批量错题重练：保存失败后的重试、部分完成汇总、防重入与离页回调。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/math_mistake_page.dart';
import 'package:poemath/features/math/widgets/mistake_repractice_dialog.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

class _FakeMistakeRepo extends MathMistakeRepository {
  _FakeMistakeRepo(this._mistakes);

  final List<MathMistake> _mistakes;

  @override
  List<MathMistake> getAll() => List.of(_mistakes);

  @override
  List<MathMistake> getUnresolved() =>
      _mistakes.where((m) => !m.isResolved).toList();

  @override
  int get totalCount => _mistakes.length;
}

MathMistake _mistake({
  required String id,
  required String problemText,
  bool isResolved = false,
  int consolidationRound = 0,
  DateTime? nextConsolidationDate,
}) {
  return MathMistake(
    id: id,
    profileId: 'default',
    problemText: problemText,
    // 答案取两位数：卡片会渲染答案文本，避免与统计卡的个位数计数撞车。
    correctAnswer: '63',
    userAnswer: '61',
    problemType: 'addition',
    grade: 2,
    isResolved: isResolved,
    consolidationRound: consolidationRound,
    nextConsolidationDate: nextConsolidationDate,
  );
}

class _FailingRepo extends _FakeMistakeRepo {
  _FailingRepo(super.mistakes);
  int attempts = 0;
  final saved = <String>[];
  final answers = <bool>[];
  int failures = 1;
  Completer<void>? pending;
  @override
  Future<RepracticeOutcome?> recordRepracticeResult(
    String id, {
    required bool isCorrect,
  }) async {
    attempts++;
    answers.add(isCorrect);
    await pending?.future;
    if (failures > 0) {
      failures--;
      throw StateError('synthetic disk full');
    }
    saved.add(id);
    return RepracticeOutcome.reset;
  }
}

void main() {
  Future<void> mount(WidgetTester tester, _FailingRepo repo) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mathMistakeRepoProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: MathMistakePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> answer(WidgetTester tester, bool result) async {
    Navigator.of(tester.element(find.byType(MistakeRepracticeDialog)))
        .pop(result);
    await tester.pumpAndSettle();
  }

  testWidgets('批量保存失败提示重试，原答案重试成功才计数且阻止重复启动', (tester) async {
    final repo = _FailingRepo([_mistake(id: 'm1', problemText: '30 + 33 = ?')]);
    await mount(tester, repo);
    final start = find.widgetWithText(FilledButton, '开始重练（1 题）');
    final callback = tester.widget<FilledButton>(start).onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(find.byType(MistakeRepracticeDialog), findsOneWidget);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    await answer(tester, true);
    expect(repo.saved, isEmpty);
    expect(find.text('重练结果未保存'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(repo.attempts, 2);
    expect(repo.answers, [true, true]);
    expect(repo.saved, ['m1']);
    expect(find.byType(MistakeRepracticeDialog), findsNothing);
    expect(find.text('重练完成：1 题中答对 1 题（正确率 100%）'), findsOneWidget);
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('中途保存失败退出，只汇总已保存题目且可以重新开始', (tester) async {
    final repo = _FailingRepo([
      _mistake(id: 'm1', problemText: '30 + 33 = ?'),
      _mistake(id: 'm2', problemText: '31 + 32 = ?'),
    ])..failures = 0;
    await mount(tester, repo);
    await tester.tap(find.text('开始重练（2 题）'));
    await tester.pumpAndSettle();
    await answer(tester, false);
    repo.failures = 1;
    await answer(tester, true);
    expect(find.text('重练结果未保存'), findsOneWidget);
    await tester.tap(find.text('退出重练'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    expect(find.text('本次已保存：1 题中答对 0 题（正确率 0%）'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '开始重练（2 题）'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('等待批量保存时离页，失败只记录日志不弹过期对话框', (tester) async {
    final repo = _FailingRepo([_mistake(id: 'm1', problemText: '30 + 33 = ?')]);
    final pending = repo.pending = Completer<void>();
    await mount(tester, repo);
    await tester.tap(find.text('开始重练（1 题）'));
    await tester.pumpAndSettle();
    await answer(tester, true);
    expect(repo.attempts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
