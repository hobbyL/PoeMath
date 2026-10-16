// lib/features/math/math_tab_page.dart
//
// 层级：features/math
// 职责：口算 Tab 主页 — 练习类型卡片 + 最近练习 + 错题入口。
//
// 册次（年级/学期）不再在此就地选择：一律跟随「设置 → 学习与提醒 →
// 学习背景」。此前这里有一套年级网格 + AppBar 学期按钮，但它们只改内存
// StateProvider、不写 Hive，与学习背景那份真源只在首次读取时对齐 ——
// 同一份信息存在三个互不同步的来源，故收拢到学习背景一处。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/routing/page_transitions.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/math_entry_kind.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/practice_scheme_selector.dart';
import 'package:poemath/features/profile/learning_background_page.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class MathTabPage extends ConsumerWidget {
  const MathTabPage({super.key});

  /// 练习类型卡片的外观与路由。
  ({String title, String subtitle, IconData icon, Color Function(ThemeData) color})
      _appearance(MathEntryKind kind) => switch (kind) {
            MathEntryKind.arithmetic => (
                title: '口算',
                subtitle: '综合练习，可选普通方案内的题型',
                icon: Icons.calculate_outlined,
                color: (theme) => theme.colorScheme.primary,
              ),
            MathEntryKind.vertical => (
                title: '竖式',
                subtitle: '按列计算，练加减乘的竖式写法',
                icon: Icons.view_stream_outlined,
                color: (theme) => theme.colorScheme.secondary,
              ),
            MathEntryKind.wordProblem => (
                title: '应用题',
                subtitle: '读懂题意，列式解决实际问题',
                icon: Icons.auto_awesome_outlined,
                color: (theme) => theme.colorScheme.tertiary,
              ),
            MathEntryKind.challenge => (
                title: '挑战',
                subtitle: '限时作答，看看能答对多少',
                icon: Icons.timer_rounded,
                color: (theme) => theme.colorScheme.primary,
              ),
          };

  /// 进入「口算」：先让用户选普通方案内的题型，再发起练习。
  Future<void> _startArithmetic(BuildContext context, WidgetRef ref) async {
    final grade = ref.read(mathGradeProvider);
    final semester = ref.read(mathSemesterProvider);
    final settings = ref.read(settingsRepositoryProvider);
    final count = settings.mathBatchSize;
    final difficulty = DifficultyLevel.values.byName(settings.mathDifficulty);
    final supported = MathEngine.supportedModes(
      grade: grade,
      semester: semester,
      difficulty: difficulty,
    );
    final preferred = ref.read(mathPracticeModeProvider);
    var vertical = preferred == ProblemMode.vertical &&
        supported.contains(ProblemMode.vertical);
    final selected = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('练习方案'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${GradePresets.get(grade, semester).label} · $count 题 · ${difficulty.label}',
                ),
                const SizedBox(height: SpacingTokens.md),
                PracticeSchemeSelector(
                  grade: grade,
                  semester: semester,
                  difficulty: difficulty,
                  vertical: vertical,
                  onChanged: (value) => setDialogState(() => vertical = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, vertical),
              child: const Text('开始练习'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    ref.read(nextMathPracticeRequestProvider.notifier).setNext(
          MathPracticeRequest(
            grade: grade,
            semester: semester,
            count: count,
            difficulty: difficulty,
            mode: selected
                ? ProblemMode.vertical
                : preferred != ProblemMode.vertical &&
                        supported.contains(preferred)
                    ? preferred
                    : null,
          ),
        );
    await context.push(AppRoutes.mathPractice);
  }

  /// 进入「竖式」：直接用当前册次发起竖式练习，不再二次选择方案。
  ///
  /// 用户点竖式卡片即已表达"我要练竖式"，再弹一次方案选择属于重复询问。
  /// 但竖式是否可用**受册次与难度的引擎能力限制**（一上、一下、五下未
  /// 开放；简单难度仅普通），不可用时必须明确说明原因，不静默改成普通。
  Future<void> _startVertical(BuildContext context, WidgetRef ref) async {
    final grade = ref.read(mathGradeProvider);
    final semester = ref.read(mathSemesterProvider);
    final settings = ref.read(settingsRepositoryProvider);
    final difficulty = DifficultyLevel.values.byName(settings.mathDifficulty);
    final supported = MathEngine.supportedModes(
      grade: grade,
      semester: semester,
      difficulty: difficulty,
    );
    if (!supported.contains(ProblemMode.vertical)) {
      // 区分两种不可用原因：册次本身没开放 vs 当前难度收窄掉了。
      final atOtherDifficulty = DifficultyLevel.values.any(
        (level) => level != difficulty &&
            MathEngine.supportedModes(
              grade: grade,
              semester: semester,
              difficulty: level,
            ).contains(ProblemMode.vertical),
      );
      final reason = atOtherDifficulty
          ? '当前「${difficulty.label}」难度不包含竖式，可在设置中调高难度后重试。'
          : '${GradePresets.get(grade, semester).label}暂未开放竖式练习。';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
      return;
    }
    ref.read(nextMathPracticeRequestProvider.notifier).setNext(
          MathPracticeRequest(
            grade: grade,
            semester: semester,
            count: settings.mathBatchSize,
            difficulty: difficulty,
            mode: ProblemMode.vertical,
          ),
        );
    await context.push(AppRoutes.mathPractice);
  }

  void _open(BuildContext context, WidgetRef ref, MathEntryKind kind) {
    switch (kind) {
      case MathEntryKind.arithmetic:
        _startArithmetic(context, ref);
      case MathEntryKind.vertical:
        _startVertical(context, ref);
      case MathEntryKind.wordProblem:
        context.push(AppRoutes.wordProblemLibrary);
      case MathEntryKind.challenge:
        context.push(AppRoutes.mathChallenge);
    }
  }

  /// 前往学习背景设置。
  ///
  /// 与设置页的入口同构：受家长保护包裹（改册次是家长决策），返回后失效
  /// `settingsRepositoryProvider` 让口算页立即反映新册次 —— 口算页的
  /// 年级/学期由该 provider 派生。
  Future<void> _openLearningBackground(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await Navigator.push<void>(
      context,
      fadeSlideRoute(
        builder: (_) =>
            const ParentAccessBoundary(child: LearningBackgroundPage()),
      ),
    );
    if (context.mounted) {
      ref.invalidate(settingsRepositoryProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grade = ref.watch(mathGradeProvider);
    final semester = ref.watch(mathSemesterProvider);
    final kinds = ref.watch(mathEntryKindsProvider);
    final totalProblems = ref.watch(totalProblemsCountProvider);
    final accuracy = ref.watch(overallAccuracyProvider);
    final mistakeCount = ref.watch(mistakeCountProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 420;
    final gradeLabel = GradePresets.get(grade, semester).label;
    // 按枚举声明顺序渲染卡片，与 MathEntryKind 的文档约定一致。
    final visible = MathEntryKind.values.where(kinds.contains).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('口算练习'),
        automaticallyImplyLeading: false,
        leadingWidth: mistakeCount > 0 ? (isWide ? 160.0 : 96.0) : null,
        leading: mistakeCount > 0
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isWide)
                    TextButton.icon(
                      onPressed: () => context.push(AppRoutes.mathMistake),
                      icon: const Icon(Icons.error_outline, size: 18),
                      label: Text('错题 $mistakeCount'),
                    )
                  else
                    IconButton(
                      onPressed: () => context.push(AppRoutes.mathMistake),
                      icon: Badge(
                        label: Text('$mistakeCount'),
                        child: const Icon(Icons.error_outline),
                      ),
                      tooltip: '错题 $mistakeCount',
                    ),
                  IconButton(
                    onPressed: () => context.push(AppRoutes.studyHub),
                    icon: const Icon(Icons.auto_stories_outlined),
                    tooltip: '公式知识库',
                  ),
                ],
              )
            : IconButton(
                onPressed: () => context.push(AppRoutes.studyHub),
                icon: const Icon(Icons.auto_stories_outlined),
                tooltip: '公式知识库',
              ),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.mathHistory),
            icon: const Icon(Icons.history_outlined),
            tooltip: '练习记录',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            // 统计概览
            if (totalProblems > 0)
              StatOverviewCard(
                items: [
                  StatOverviewItem(value: '$totalProblems', label: '已做题'),
                  StatOverviewItem(
                    value: '${(accuracy * 100).toStringAsFixed(0)}%',
                    label: '正确率',
                  ),
                  StatOverviewItem(value: '$mistakeCount', label: '错题'),
                ],
              ),

            // 当前册次（只读）：册次统一由学习背景决定，此处仅展示并给出
            // 修改入口，不提供就地切换。
            const SizedBox(height: SpacingTokens.md),
            AppTile(
              icon: Icons.school_outlined,
              iconColor: theme.colorScheme.primary,
              title: '当前学习 $gradeLabel',
              subtitle: '册次与练习类型在「学习背景」中调整',
              onTap: () => _openLearningBackground(context, ref),
            ),

            const SizedBox(height: SpacingTokens.md),
            Text('选择练习', style: theme.textTheme.titleMedium),
            const SizedBox(height: SpacingTokens.sm),

            if (visible.isEmpty)
              // 学习背景里把四类全关时会走到这里；仓储层已拦空集合，
              // 此处是异常数据（如手工改 Hive）的兜底展示。
              const Text('尚未开启任何练习类型，请到「学习背景」中至少选择一类。')
            else
              for (final kind in visible) ...[
                _entryCard(context, ref, kind, theme),
                const SizedBox(height: SpacingTokens.sm),
              ],
          ],
        ),
      ),
    );
  }

  Widget _entryCard(
    BuildContext context,
    WidgetRef ref,
    MathEntryKind kind,
    ThemeData theme,
  ) {
    final appearance = _appearance(kind);
    return AppTile(
      icon: appearance.icon,
      iconColor: appearance.color(theme),
      title: appearance.title,
      subtitle: appearance.subtitle,
      onTap: () => _open(context, ref, kind),
    );
  }
}
