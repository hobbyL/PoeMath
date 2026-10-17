// lib/features/math/math_tab_page.dart
//
// 层级：features/math
// 职责：口算 Tab 主页 — 练习类型卡片 + 最近练习 + 错题入口。
//
// 册次（年级/学期）不再在此就地选择：一律跟随「设置 → 学习与内容 →
// 学习背景」。此前这里有一套年级网格 + AppBar 学期按钮，但它们只改内存
// StateProvider、不写 Hive，与学习背景那份真源只在首次读取时对齐 ——
// 同一份信息存在三个互不同步的来源，故收拢到学习背景一处。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/math_entry_kind.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/widgets/practice_entry_card.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class MathTabPage extends ConsumerWidget {
  const MathTabPage({super.key});

  /// 册次简写：`2` + `上` → `二上`（用于 AppBar 标题后缀）。
  ///
  /// 用中文数字而非阿拉伯数字：与全局其它文案（"二年级上"、"四下"）的
  /// 表述一致，且短——标题空间有限，`数学练习 · 二上` 在窄屏也不会被截。
  static String _shortVolume(int grade, String semester) {
    const digits = ['', '一', '二', '三', '四', '五', '六'];
    final g = grade >= 1 && grade <= 6 ? digits[grade] : '$grade';
    return '$g$semester';
  }

  /// 练习类型卡片的外观。
  ///
  /// 只含图标/标题/描述 —— 颜色与点击行为不再随类型分叉：卡片统一用
  /// 主题主色（见 `PracticeEntryCard`），跳转统一走 `_open`。原先的
  /// `color` 回调已无消费方（网格布局下多色反而杂乱）。
  ({String title, String subtitle, IconData icon}) _appearance(
    MathEntryKind kind,
  ) =>
      switch (kind) {
        MathEntryKind.arithmetic => (
            title: '口算练习',
            subtitle: '综合练习，可选题型',
            icon: Icons.calculate_outlined,
          ),
        MathEntryKind.vertical => (
            title: '竖式计算',
            subtitle: '按列计算，练竖式写法',
            icon: Icons.view_stream_outlined,
          ),
        MathEntryKind.wordProblem => (
            title: '应用题',
            subtitle: '读懂题意，列式解决',
            icon: Icons.auto_awesome_outlined,
          ),
        MathEntryKind.challenge => (
            title: '挑战模式',
            subtitle: '限时作答，看能对多少',
            icon: Icons.timer_rounded,
          ),
      };

  /// 进入「口算练习」：直接用当前册次与设置中的偏好发起，不再弹方案
  /// 选择框。
  ///
  /// 竖式已是独立卡片，方案选择框里的"普通/竖式"二选一失去了意义 ——
  /// 用户点哪张卡片就已经选完了方案。普通方案内的题型细分（求未知/比
  /// 大小/连续运算/带括号）在「设置 → 练习设置」里配置，属于偏好而非
  /// 每次要选的东西。
  ///
  /// 偏好若指向竖式（旧数据、或用户曾在练习设置里选过），此处**不照办**
  /// 而是回落综合（null）：从口算卡片进来就是练普通。
  void _startArithmetic(BuildContext context, WidgetRef ref) {
    final grade = ref.read(mathGradeProvider);
    final semester = ref.read(mathSemesterProvider);
    final settings = ref.read(settingsRepositoryProvider);
    final difficulty = DifficultyLevel.values.byName(settings.mathDifficulty);
    final supported = MathEngine.supportedModes(
      grade: grade,
      semester: semester,
      difficulty: difficulty,
    );
    final preferred = ref.read(mathPracticeModeProvider);
    ref.read(nextMathPracticeRequestProvider.notifier).setNext(
          MathPracticeRequest(
            grade: grade,
            semester: semester,
            count: settings.mathBatchSize,
            difficulty: difficulty,
            mode: preferred != ProblemMode.vertical &&
                    supported.contains(preferred)
                ? preferred
                : null,
          ),
        );
    context.push(AppRoutes.mathPractice);
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
    // 按枚举声明顺序渲染卡片，与 MathEntryKind 的文档约定一致。
    final visible = MathEntryKind.values.where(kinds.contains).toList();

    return Scaffold(
      appBar: AppBar(
        // 标题带上当前册次简写（如「数学练习 · 二上」）：册次由学习背景
        // 决定且页面上不再有别的常驻展示位，附在标题后是最省空间的告知。
        // 不叫「口算练习」：页面已含四类入口，且「口算练习」是其中一张
        // 卡片的标题，同名会造成语义混淆（也影响按文案定位的测试）。
        title: Text('数学练习 · ${_shortVolume(grade, semester)}'),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 按 ~160px 每列计算列数，与旧版年级网格同款响应式策略
            // （`GradeSemesterCard` 的注释亦注明"适合 Grid 一行两个"）。
            final gridWidth = constraints.maxWidth - SpacingTokens.md * 2;
            final columns = (gridWidth / 160).floor().clamp(2, 4);

            return ListView(
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

                if (visible.isEmpty)
                  // 学习背景里把四类全关时会走到这里；仓储层已拦空集合，
                  // 此处是异常数据（如手工改 Hive）的兜底展示。
                  const Text('尚未开启任何练习类型，请在设置 → 学习背景中至少选择一类。')
                else
                  for (var row = 0;
                      row < (visible.length / columns).ceil();
                      row++) ...[
                    if (row > 0) const SizedBox(height: SpacingTokens.sm),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var col = 0; col < columns; col++) ...[
                            if (col > 0)
                              const SizedBox(width: SpacingTokens.sm),
                            Expanded(
                              child: row * columns + col < visible.length
                                  ? _entryCard(
                                      context,
                                      ref,
                                      visible[row * columns + col],
                                      theme,
                                    )
                                  // 末行不足时留空占位，保持已排卡片同宽。
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
              ],
            );
          },
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
    return PracticeEntryCard(
      icon: appearance.icon,
      title: appearance.title,
      description: appearance.subtitle,
      onTap: () => _open(context, ref, kind),
    );
  }
}
