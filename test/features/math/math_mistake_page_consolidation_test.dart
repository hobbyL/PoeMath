// test/features/math/math_mistake_page_consolidation_test.dart
//
// ⑤ 错题本页面三组 UI 测试：四态筛选 chip、统计卡四口径、
// 卡片状态 pill 三态与「今日可练」角标、批量重练按钮的数据源口径。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/math_mistake_page.dart';
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

/// 当天零点。取一次「现在」后归一化到日期字段构造，
/// 相比 `DateTime.now().subtract(Duration(days: n))` 在 DST 切换日仍能拿到
/// 正确的日历日期（一天不总是 24 小时）。调用方须只用其结果，不要再单独
/// 调 `DateTime.now()` 做对比——那会引入跨午夜漂移。
DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
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

Future<void> _pumpPage(
  WidgetTester tester,
  List<MathMistake> mistakes,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mathMistakeRepoProvider.overrideWithValue(_FakeMistakeRepo(mistakes)),
      ],
      child: const MaterialApp(home: MathMistakePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('状态筛选提供未掌握 / 待巩固 / 已掌握四态 chip', (tester) async {
    await _pumpPage(tester, [
      _mistake(id: 'm1', problemText: '1 + 1 = ?'),
    ]);

    expect(find.widgetWithText(ChoiceChip, '全部'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '未掌握'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '待巩固'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '已掌握'), findsOneWidget);
  });

  testWidgets('统计卡按未掌握 / 待巩固 / 已掌握三组计数', (tester) async {
    await _pumpPage(tester, [
      _mistake(id: 'm1', problemText: '1 + 1 = ?'),
      _mistake(id: 'm2', problemText: '2 + 2 = ?'),
      _mistake(
        id: 'm3',
        problemText: '3 + 3 = ?',
        consolidationRound: 1,
        nextConsolidationDate: _today().add(const Duration(days: 1)),
      ),
      _mistake(id: 'm4', problemText: '4 + 4 = ?', isResolved: true),
    ]);

    expect(find.text('总错题'), findsOneWidget);
    // 同名文案出现在三处（统计卡标签 / 筛选 chip / 卡片 pill），
    // 这里只核数字口径：总 4、未掌握 2、待巩固 1、已掌握 1。
    // 题面是完整串（'1 + 1 = ?'），不会与纯数字文本冲突。
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('待巩固卡片显示关卡 pill，到期时追加今日可练角标', (tester) async {
    await _pumpPage(tester, [
      _mistake(
        id: 'm_due',
        problemText: '1 + 1 = ?',
        consolidationRound: 2,
        nextConsolidationDate: _today().subtract(const Duration(days: 1)),
      ),
      _mistake(
        id: 'm_pending',
        problemText: '2 + 2 = ?',
        consolidationRound: 1,
        nextConsolidationDate: _today().add(const Duration(days: 3)),
      ),
    ]);

    expect(find.text('待巩固 第 2 关'), findsOneWidget);
    expect(find.text('待巩固 第 1 关'), findsOneWidget);
    // 只有到期的那张卡带角标
    expect(find.text('今日可练'), findsOneWidget);
  });

  testWidgets('未掌握与已掌握卡片显示对应 pill', (tester) async {
    await _pumpPage(tester, [
      _mistake(id: 'm1', problemText: '1 + 1 = ?'),
      _mistake(id: 'm2', problemText: '2 + 2 = ?', isResolved: true),
    ]);

    // 同名文案三处：统计卡标签 + 筛选 chip + 卡片 pill
    expect(find.text('未掌握'), findsNWidgets(3));
    expect(find.text('已掌握'), findsNWidgets(3));
    expect(find.text('今日可练'), findsNothing);
  });

  testWidgets('重练按钮只计未掌握与今日到期的抽查题', (tester) async {
    await _pumpPage(tester, [
      _mistake(id: 'm_unmastered', problemText: '1 + 1 = ?'),
      _mistake(
        id: 'm_due',
        problemText: '2 + 2 = ?',
        consolidationRound: 1,
        nextConsolidationDate: _today(),
      ),
      _mistake(
        id: 'm_pending',
        problemText: '3 + 3 = ?',
        consolidationRound: 1,
        nextConsolidationDate: _today().add(const Duration(days: 3)),
      ),
      _mistake(id: 'm_mastered', problemText: '4 + 4 = ?', isResolved: true),
    ]);

    expect(find.text('开始重练（2 题）'), findsOneWidget);
  });

  testWidgets('全部掌握时不显示重练按钮', (tester) async {
    await _pumpPage(tester, [
      _mistake(id: 'm1', problemText: '1 + 1 = ?', isResolved: true),
    ]);

    expect(find.textContaining('开始重练'), findsNothing);
  });

  testWidgets('点选待巩固 chip 只留巩固中的题', (tester) async {
    await _pumpPage(tester, [
      _mistake(id: 'm1', problemText: '1 + 1 = ?'),
      _mistake(
        id: 'm2',
        problemText: '2 + 2 = ?',
        consolidationRound: 1,
        nextConsolidationDate: _today().add(const Duration(days: 1)),
      ),
    ]);

    await tester.tap(find.widgetWithText(ChoiceChip, '待巩固'));
    await tester.pumpAndSettle();

    expect(find.text('2 + 2 = ?'), findsOneWidget);
    expect(find.text('1 + 1 = ?'), findsNothing);
  });
}
