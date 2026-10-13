// test/features/math/mistake_status_filter_test.dart
//
// ⑤ 错题三态筛选测试：filteredMistakesProvider 的
// 未掌握 / 待巩固 / 已掌握三组推导，以及重练队列
// （未掌握 + 今日到期待巩固）的构成。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/repositories/math_mistake_repository.dart';
import 'package:poemath/features/math/providers/math_providers.dart';

class _FakeMistakeRepo extends MathMistakeRepository {
  _FakeMistakeRepo(this._mistakes);

  final List<MathMistake> _mistakes;

  @override
  List<MathMistake> getAll() => List.of(_mistakes);

  @override
  List<MathMistake> getUnresolved() =>
      _mistakes.where((m) => !m.isResolved).toList();
}

/// 当天零点。口径同 math_mistake_page_consolidation_test：日期字段构造，
/// DST 安全；调用方不要再自行取 `DateTime.now()` 对比。
DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

MathMistake _mistake({
  required String id,
  int grade = 2,
  bool isResolved = false,
  int consolidationRound = 0,
  DateTime? nextConsolidationDate,
}) {
  return MathMistake(
    id: id,
    profileId: 'default',
    problemText: '1 + 1 = ?',
    correctAnswer: '2',
    userAnswer: '3',
    problemType: 'addition',
    grade: grade,
    isResolved: isResolved,
    consolidationRound: consolidationRound,
    nextConsolidationDate: nextConsolidationDate,
  );
}

void main() {
  late MathMistake unmastered;
  late MathMistake dueConsolidating;
  late MathMistake pendingConsolidating;
  late MathMistake mastered;
  late ProviderContainer container;

  setUp(() {
    unmastered = _mistake(id: 'm_unmastered');
    dueConsolidating = _mistake(
      id: 'm_due',
      consolidationRound: 1,
      nextConsolidationDate: _today().subtract(const Duration(days: 1)),
    );
    pendingConsolidating = _mistake(
      id: 'm_pending',
      grade: 3,
      consolidationRound: 2,
      nextConsolidationDate: _today().add(const Duration(days: 3)),
    );
    mastered = _mistake(id: 'm_mastered', isResolved: true);

    container = ProviderContainer(
      overrides: [
        mathMistakeRepoProvider.overrideWithValue(
          _FakeMistakeRepo([
            unmastered,
            dueConsolidating,
            pendingConsolidating,
            mastered,
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  List<String> idsOf(List<MathMistake> list) =>
      list.map((m) => m.id).toList();

  test('默认不筛选返回全部', () {
    expect(idsOf(container.read(filteredMistakesProvider)), [
      'm_unmastered',
      'm_due',
      'm_pending',
      'm_mastered',
    ]);
  });

  test('未掌握组只含轮次为 0 且未掌握的题', () {
    container.read(mistakeStatusFilterProvider.notifier).state =
        MistakeStatusFilter.unmastered;
    expect(idsOf(container.read(filteredMistakesProvider)), ['m_unmastered']);
  });

  test('待巩固组含到期与未到期的巩固题', () {
    container.read(mistakeStatusFilterProvider.notifier).state =
        MistakeStatusFilter.consolidating;
    expect(
      idsOf(container.read(filteredMistakesProvider)),
      ['m_due', 'm_pending'],
    );
  });

  test('已掌握组只含 isResolved', () {
    container.read(mistakeStatusFilterProvider.notifier).state =
        MistakeStatusFilter.mastered;
    expect(idsOf(container.read(filteredMistakesProvider)), ['m_mastered']);
  });

  test('状态筛选与年级筛选叠加', () {
    container.read(mistakeStatusFilterProvider.notifier).state =
        MistakeStatusFilter.consolidating;
    container.read(mistakeGradeFilterProvider.notifier).state = 3;
    expect(idsOf(container.read(filteredMistakesProvider)), ['m_pending']);
  });

  test('重练队列 = 未掌握 + 今日到期待巩固（排除未到期与已掌握）', () {
    expect(
      idsOf(container.read(repracticeQueueProvider)),
      ['m_unmastered', 'm_due'],
    );
  });
}
