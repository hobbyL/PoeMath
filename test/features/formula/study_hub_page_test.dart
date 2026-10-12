// test/features/formula/study_hub_page_test.dart
//
// 公式知识库「已收藏」筛选视图测试（任务 10-12-feature-batch-8 ①）：
// - 默认显示全部公式，星标按钮未激活；
// - 点击星标进入收藏视图，仅显示已收藏公式；
// - 收藏视图空态文案与「暂无公式」区分；
// - 取消收藏后列表即时反映（invalidate filteredFormulasProvider）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/models/formula_favorite.dart';
import 'package:poemath/features/formula/providers/formula_providers.dart';
import 'package:poemath/features/formula/study_hub_page.dart';

import '../../helpers/hive_test_helper.dart';

const _kFormulaA = 'hub-fav-a';
const _kFormulaB = 'hub-fav-b';

void _seedFormula(String id, String name) {
  HiveBoxes.formulas.put(
    id,
    Formula(
      id: id,
      category: '图形',
      name: name,
      formulaText: '$name=…',
      formulaLatex: '',
      grade: 3,
    ),
  );
}

Future<void> _addFavorite(String formulaId) async {
  await HiveBoxes.formulaFavorites.put(
    'default_$formulaId',
    FormulaFavorite(formulaId: formulaId, profileId: 'default'),
  );
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
    _seedFormula(_kFormulaA, '长方形周长');
    _seedFormula(_kFormulaB, '三角形面积');
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  Widget buildApp(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: StudyHubPage()),
    );
  }

  /// 有界 pump：固定推进 3 秒动画时钟（替代 pumpAndSettle，防持续帧
  /// 动画导致 settle 永不静止）。
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('默认显示全部公式，星标未激活', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildApp(container));
    await pumpFrames(tester);

    expect(container.read(formulaFavoritesOnlyProvider), isFalse);
    expect(find.text('长方形周长'), findsOneWidget);
    expect(find.text('三角形面积'), findsOneWidget);
    expect(find.byTooltip('仅显示已收藏'), findsOneWidget);
  });

  testWidgets('无收藏时进入收藏视图显示收藏专属空态', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildApp(container));
    await pumpFrames(tester);

    await tester.tap(find.byTooltip('仅显示已收藏'));
    await pumpFrames(tester);
    // 补一拍：触发列表重挂载时 flutter_animate 的零时长 Timer。
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(formulaFavoritesOnlyProvider), isTrue);
    expect(find.textContaining('还没有收藏的公式'), findsOneWidget);
    expect(find.text('暂无公式'), findsNothing);
  });

  testWidgets('收藏视图仅显示已收藏公式，与其他公式隔离', (tester) async {
    await tester.runAsync(() => _addFavorite(_kFormulaA));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildApp(container));
    await pumpFrames(tester);

    await tester.tap(find.byTooltip('仅显示已收藏'));
    await pumpFrames(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('长方形周长'), findsOneWidget);
    expect(find.text('三角形面积'), findsNothing);
  });

  testWidgets('退出收藏视图恢复全部公式', (tester) async {
    await tester.runAsync(() => _addFavorite(_kFormulaA));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildApp(container));
    await pumpFrames(tester);

    await tester.tap(find.byTooltip('仅显示已收藏'));
    await pumpFrames(tester);
    expect(find.text('三角形面积'), findsNothing);

    await tester.tap(find.byTooltip('显示全部公式'));
    await pumpFrames(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(formulaFavoritesOnlyProvider), isFalse);
    expect(find.text('长方形周长'), findsOneWidget);
    expect(find.text('三角形面积'), findsOneWidget);
  });

  testWidgets('详情页收藏切换路径（toggle + invalidate）使视图即时反映', (tester) async {
    await tester.runAsync(() => _addFavorite(_kFormulaA));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildApp(container));
    await pumpFrames(tester);

    await tester.tap(find.byTooltip('仅显示已收藏'));
    await pumpFrames(tester);
    expect(find.text('长方形周长'), findsOneWidget);

    // 模拟详情页取消收藏的完整路径（含 filteredFormulasProvider 失效）。
    // Hive 落盘 IO 必须经 runAsync 走真实事件循环（fake-async 内 await 会死锁）。
    await tester.runAsync(
      () => container.read(formulaFavoriteRepoProvider).toggle(_kFormulaA),
    );
    container
      ..invalidate(isFormulaFavoriteProvider(_kFormulaA))
      ..invalidate(filteredFormulasProvider);
    await pumpFrames(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('长方形周长'), findsNothing);
    expect(find.textContaining('还没有收藏的公式'), findsOneWidget);
  });

  test('filteredFormulasProvider 收藏分支与分类/搜索叠加（provider 单测）', () async {
    await _addFavorite(_kFormulaB);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 收藏视图 + 分类过滤：收藏的 B 属于「图形」分类 → 命中。
    container.read(formulaFavoritesOnlyProvider.notifier).state = true;
    container.read(selectedCategoryProvider.notifier).state = '图形';
    expect(
      container.read(filteredFormulasProvider).map((f) => f.id),
      [_kFormulaB],
    );

    // 叠加搜索关键词：命中 B 名称。
    container.read(formulaSearchQueryProvider.notifier).state = '三角形';
    expect(
      container.read(filteredFormulasProvider).map((f) => f.id),
      [_kFormulaB],
    );

    // 搜索不命中时收藏视图为空。
    container.read(formulaSearchQueryProvider.notifier).state = '不存在';
    expect(container.read(filteredFormulasProvider), isEmpty);
  });
}
