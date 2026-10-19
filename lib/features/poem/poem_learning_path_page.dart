import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/poem_curriculum.dart';

/// 册次由持久学习背景初始化，临时浏览其他册次不会改写背景。
class PoemLearningPathPage extends ConsumerStatefulWidget {
  const PoemLearningPathPage({super.key});
  @override
  ConsumerState<PoemLearningPathPage> createState() =>
      _PoemLearningPathPageState();
}

class _PoemLearningPathPageState extends ConsumerState<PoemLearningPathPage> {
  int? _grade;
  String? _semester;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsRepositoryProvider);
    final grade = _grade ?? settings.selectedGrade;
    final semester = _semester ?? settings.selectedSemester;
    final poems = ref.watch(poemRepositoryProvider).getAll();
    final progress = ref.watch(poemProgressRepositoryProvider);
    final required = requiredTextbookPoems(poems, grade, semester);
    final learned = required
        .where(
          (poem) =>
              (progress.get(poem.id)?.status ?? LearningStatus.notStarted) !=
              LearningStatus.notStarted,
        )
        .length;
    final mastered = required
        .where(
            (poem) => progress.get(poem.id)?.status == LearningStatus.mastered,)
        .length;
    final requiredIds = required.map((poem) => poem.id).toSet();
    final extended = poems
        .where(
          (poem) =>
              !requiredIds.contains(poem.id) &&
              poem.effectiveGrades.contains(grade) &&
              (poem.semester == null || poem.semester == semester),
        )
        .toList()
      ..sort(compareCurriculumPoems);
    final units = <String, List<Poem>>{};
    for (final poem in required) {
      units
          .putIfAbsent(poem.textbookUnit ?? '课标必背（未标教材单元）', () => [])
          .add(poem);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('教材学习路线')),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: [
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('选择册次，直接开始', style: theme.textTheme.titleMedium),
                  // 册次选择改为底部弹层：Dropdown 在移动端触控目标偏小，
                  // 且与全 App 其余选择器（学期 sheet、计划 sheet）的交互
                  // 不一致。选择仍只改页内局部 state，不写学习背景。
                  OutlinedButton.icon(
                    onPressed: () => _pickVolume(context, grade, semester),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text('$grade 年级 · $semester册'),
                  ),
                  Text('本册必背 $learned/${required.length} 首已学 · $mastered 首已掌握'),
                  const SizedBox(height: SpacingTokens.sm),
                  LinearProgressIndicator(
                      value: required.isEmpty ? 0 : learned / required.length,),
                  const SizedBox(height: SpacingTokens.sm),
                  const Text('按教材标注位置学习，无需先解锁低年级。浏览其他册次不改变学习背景。'),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            Text('本册必背', style: theme.textTheme.titleLarge),
            const SizedBox(height: SpacingTokens.sm),
            if (required.isEmpty) const Text('当前内容库未标注这一册的必背内容，可先阅读下方拓展诗词。'),
            for (final unit in units.entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
                child: Text(unit.key, style: theme.textTheme.titleSmall),
              ),
              for (final poem in unit.value) ...[
                _poemTile(poem, required: true),
                const SizedBox(height: SpacingTokens.sm),
              ],
            ],
            const SizedBox(height: SpacingTokens.md),
            Text('拓展阅读 · ${extended.length} 首',
                style: theme.textTheme.titleLarge,),
            const SizedBox(height: SpacingTokens.sm),
            const Text('拓展阅读不计入本册必背进度；未标册次的诗词按内容难度归入适读年级。'),
            const SizedBox(height: SpacingTokens.sm),
            for (final poem in extended) ...[
              _poemTile(poem, required: false),
              const SizedBox(height: SpacingTokens.sm),
            ],
          ],
        ),
      ),
    );
  }

  /// 底部弹层选择册次。
  ///
  /// 只改页内局部 state（`_grade` / `_semester`），**不写学习背景** ——
  /// 本页是"查看任意册次"的浏览工具，与"我这一学期在学哪册"是两回事。
  /// 页面顶部已明示这一点。
  Future<void> _pickVolume(
    BuildContext context,
    int currentGrade,
    String currentSemester,
  ) async {
    var grade = currentGrade;
    var semester = currentSemester;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择册次',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  '仅用于浏览，不改变学习背景',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: SpacingTokens.md),
                Text('年级', style: Theme.of(sheetContext).textTheme.titleSmall),
                const SizedBox(height: SpacingTokens.sm),
                Wrap(
                  spacing: SpacingTokens.sm,
                  runSpacing: SpacingTokens.xs,
                  children: [
                    for (var value = 1; value <= 6; value++)
                      ChoiceChip(
                        label: Text('$value 年级'),
                        selected: grade == value,
                        onSelected: (_) =>
                            setSheetState(() => grade = value),
                      ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.md),
                Text('册次', style: Theme.of(sheetContext).textTheme.titleSmall),
                const SizedBox(height: SpacingTokens.sm),
                Wrap(
                  spacing: SpacingTokens.sm,
                  children: [
                    for (final value in const ['上', '下'])
                      ChoiceChip(
                        label: Text('$value册'),
                        selected: semester == value,
                        onSelected: (_) =>
                            setSheetState(() => semester = value),
                      ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('查看这一册'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _grade = grade;
      _semester = semester;
    });
  }

  Widget _poemTile(Poem poem, {required bool required}) {
    final theme = Theme.of(context);
    final status =
        ref.read(poemProgressRepositoryProvider).get(poem.id)?.status;
    final label = switch (status) {
      LearningStatus.mastered => '已掌握',
      LearningStatus.learning || LearningStatus.reviewing => '已学习',
      _ => '未开始',
    };
    return AppTile(
      icon: status == LearningStatus.mastered
          ? Icons.verified_outlined
          : Icons.menu_book_outlined,
      iconColor:
          required ? theme.colorScheme.primary : theme.colorScheme.secondary,
      title: poem.title,
      subtitle: '${poem.author} · ${required ? '本册必背' : '拓展'} · $label',
      onTap: () async {
        await context.push<void>(AppRoutes.poemDetailOf(poem.id));
        if (mounted) setState(() {});
      },
    );
  }
}
