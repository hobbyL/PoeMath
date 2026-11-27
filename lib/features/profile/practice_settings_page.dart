// lib/features/profile/practice_settings_page.dart
//
// 层级：features/profile
// 职责：练习设置子页面 — 每组题数、练习难度、每日目标。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/domain/daily_goal_activity.dart';
import 'package:poemath/core/utils/logger.dart';

class PracticeSettingsPage extends ConsumerStatefulWidget {
  const PracticeSettingsPage({super.key});

  @override
  ConsumerState<PracticeSettingsPage> createState() =>
      _PracticeSettingsPageState();
}

class _PracticeSettingsPageState extends ConsumerState<PracticeSettingsPage> {
  late int _poemGoal;
  late int _mathGoal;
  late Set<DailyGoalActivity> _dailyGoalTypes;
  late int _batchSize;
  late DifficultyLevel _difficulty;
  late ProblemMode? _practiceMode;
  OperationCounts? _operationCounts;
  String? _selectionNotice;
  bool _saving = false;
  bool _initialized = false;

  static const int _poemMin = 1;
  static const int _poemMax = 10;
  static const int _mathMin = 5;
  static const int _mathMax = 100;
  static const int _mathStep = 5;
  static const _batchOptions = [5, 10, 15, 20, 30, 50, 100];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final settings = ref.read(settingsRepositoryProvider);
      _poemGoal = ref.read(dailyPoemGoalProvider);
      _mathGoal = ref.read(dailyMathGoalProvider);
      _dailyGoalTypes = Set.of(ref.read(dailyGoalTypesProvider));
      _batchSize = settings.mathBatchSize;
      _difficulty = _parseDifficulty(settings.mathDifficulty);
      _practiceMode = ref.read(mathPracticeModeProvider);
      _operationCounts = settings.mathOperationCounts;
      if (_practiceMode == ProblemMode.vertical) _practiceMode = null;
      _reconcileSelection();
      _initialized = true;
    }
  }

  DifficultyLevel _parseDifficulty(String name) {
    return DifficultyLevel.values.firstWhere(
      (d) => d.name == name,
      orElse: () => DifficultyLevel.medium,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    _reconcileSelection();
    setState(() => _saving = true);
    final settings = ref.read(settingsRepositoryProvider);
    try {
      await settings.setDailyPoemGoal(_poemGoal);
      await settings.setDailyMathGoal(_mathGoal);
      await settings.setDailyGoalTypes(_dailyGoalTypes);
      await settings.setMathBatchSize(_batchSize);
      await settings.setMathDifficulty(_difficulty.name);
      await settings.setMathPracticeMode(_practiceMode?.name);
      await settings.setMathOperationCounts(_operationCounts);
      if (!mounted) return;

      ref.read(mathDifficultyProvider.notifier).state = _difficulty;
      ref.read(mathPracticeModeProvider.notifier).state = _practiceMode;
      ref.invalidate(settingsRepositoryProvider);
      ref.invalidate(dailyPoemGoalProvider);
      ref.invalidate(dailyMathGoalProvider);
      ref.invalidate(dailyGoalTypesProvider);
      Navigator.pop(context);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '练习设置保存失败',
        tag: 'PracticeSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      appBar: AppBar(title: const Text('练习设置')),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _saving,
          child: AnimatedPageBody(
            padding: const EdgeInsets.all(SpacingTokens.lg),
            children: [
              // ============ 每组题数 ============
              ColoredCard(
                color: theme.colorScheme.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.format_list_numbered_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: SpacingTokens.sm),
                        Text(
                          '每组题数',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    Wrap(
                      spacing: SpacingTokens.sm,
                      children: _batchOptions.map((n) {
                        return ChoiceChip(
                          label: Text('$n 题'),
                          selected: _batchSize == n,
                          onSelected: (_) => setState(() => _batchSize = n),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SpacingTokens.md),

              // ============ 练习模式 ============
              _buildOperationCountCard(theme),
              const SizedBox(height: SpacingTokens.md),
              _buildModeCard(theme),
              const SizedBox(height: SpacingTokens.md),

              // ============ 练习难度 ============
              ColoredCard(
                color: theme.colorScheme.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.speed_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: SpacingTokens.sm),
                        Text(
                          '练习难度',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    Wrap(
                      spacing: SpacingTokens.sm,
                      children: DifficultyLevel.values.map((d) {
                        return ChoiceChip(
                          avatar: Icon(_difficultyIcon(d), size: 16),
                          label: Text(d.label),
                          selected: _difficulty == d,
                          onSelected: (_) => setState(() {
                            _difficulty = d;
                            _reconcileSelection();
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      _difficulty.desc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SpacingTokens.md),

              ColoredCard(
                color: theme.colorScheme.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '每日参与目标',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    Wrap(
                      spacing: SpacingTokens.sm,
                      runSpacing: SpacingTokens.xs,
                      children: [
                        for (final activity in DailyGoalActivity.values)
                          FilterChip(
                            label: Text(activity.label),
                            selected: _dailyGoalTypes.contains(activity),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _dailyGoalTypes.add(activity);
                                } else if (_dailyGoalTypes.length > 1) {
                                  _dailyGoalTypes.remove(activity);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SpacingTokens.md),

              // ============ 每日诗词目标 ============
              ColoredCard(
                color: theme.colorScheme.primary,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: SpacingTokens.sm),
                        Text(
                          '每日诗词背诵',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    _buildCounter(
                      theme: theme,
                      value: _poemGoal,
                      min: _poemMin,
                      max: _poemMax,
                      step: 1,
                      unit: '首',
                      color: theme.colorScheme.primary,
                      onChanged: (v) => setState(() => _poemGoal = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SpacingTokens.md),

              // ============ 每日口算目标 ============
              ColoredCard(
                color: theme.colorScheme.primary,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calculate_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: SpacingTokens.sm),
                        Text(
                          '每日口算做题',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    _buildCounter(
                      theme: theme,
                      value: _mathGoal,
                      min: _mathMin,
                      max: _mathMax,
                      step: _mathStep,
                      unit: '题',
                      color: theme.colorScheme.primary,
                      onChanged: (v) => setState(() => _mathGoal = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: SpacingTokens.xl),

              // 保存按钮
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(_saving ? '保存中…' : '保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard(ThemeData theme) {
    const modes = <(ProblemMode?, String, IconData)>[
      (null, '综合', Icons.shuffle_rounded),
      (ProblemMode.findMissing, '求未知', Icons.help_outline_rounded),
      (ProblemMode.compare, '比大小', Icons.compare_arrows_rounded),
      (ProblemMode.chain, '连续运算', Icons.link_rounded),
      (ProblemMode.withBrackets, '带括号', Icons.data_array_rounded),
    ];

    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.gamepad_outlined,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: SpacingTokens.sm),
              Text(
                '普通方案题型',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.xs,
            children: modes.map((m) {
              final (mode, label, icon) = m;
              return ChoiceChip(
                avatar: Icon(icon, size: 16),
                label: Text(label),
                selected: _practiceMode == mode,
                onSelected: mode == null || _supportedModes.contains(mode)
                    ? (_) => setState(() {
                        _practiceMode = mode;
                        _reconcileSelection();
                      })
                    : null,
              );
            }).toList(),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            '题型随年级学期和难度调整；竖式通过独立入口练习',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Set<ProblemMode> get _supportedModes => MathEngine.supportedModes(
    grade: ref.read(mathGradeProvider),
    semester: ref.read(mathSemesterProvider),
    difficulty: _difficulty,
    explicitOperationCounts: _operationCounts != null,
  );

  void _reconcileSelection() {
    _selectionNotice = null;
    if (_practiceMode != null && !_supportedModes.contains(_practiceMode)) {
      _practiceMode = null;
      _selectionNotice = '当前年级或难度不支持原题型，已调整为综合练习';
    }
    final adjusted = _operationCounts?.forMode(_practiceMode);
    if (adjusted != _operationCounts) {
      _operationCounts = adjusted;
      _selectionNotice = '当前题型至少计算 2 次，已调整为${adjusted!.label}';
    }
  }

  Widget _buildOperationCountCard(ThemeData theme) {
    final supported = OperationCounts.supportedForMode(_practiceMode);
    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '每题运算次数',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.xs,
            children: [
              ChoiceChip(
                label: const Text('自动'),
                selected: _operationCounts == null,
                onSelected: (_) => setState(() {
                  _operationCounts = null;
                  _reconcileSelection();
                }),
              ),
              for (final count in [1, 2, 3])
                FilterChip(
                  label: Text('$count 次'),
                  selected: _operationCounts?.contains(count) ?? false,
                  onSelected: !supported.contains(count)
                      ? null
                      : (selected) {
                          final values =
                              _operationCounts?.values.toSet() ?? <int>{};
                          if (selected) {
                            values.add(count);
                          } else if (values.length > 1) {
                            values.remove(count);
                          } else {
                            setState(() => _selectionNotice = '至少保留一种运算次数');
                            return;
                          }
                          setState(() {
                            _operationCounts = OperationCounts(values);
                            _reconcileSelection();
                          });
                        },
                ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            _operationCounts == null
                ? '自动沿用原出题规则；选中次数可混合练习'
                : '${_operationCounts!.values.length == 1 ? '每题计算 ${_operationCounts!.values.single} 次' : '本组按${_operationCounts!.label}均匀混合'}'
                      '${_operationCounts!.values.any((n) => n > 1) ? '；组合题使用整数' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            '2 次：8 + 5 − 3\n3 次：8 + 5 − 3 + 2',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!supported.contains(1)) ...[
            const SizedBox(height: SpacingTokens.xs),
            Text('连续运算和带括号题至少计算 2 次', style: theme.textTheme.bodySmall),
          ],
          if (_selectionNotice != null) ...[
            const SizedBox(height: SpacingTokens.sm),
            Text(_selectionNotice!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  IconData _difficultyIcon(DifficultyLevel d) {
    return switch (d) {
      DifficultyLevel.easy => Icons.sentiment_satisfied_outlined,
      DifficultyLevel.medium => Icons.sentiment_neutral_outlined,
      DifficultyLevel.hard => Icons.local_fire_department_outlined,
    };
  }

  Widget _buildCounter({
    required ThemeData theme,
    required int value,
    required int min,
    required int max,
    required int step,
    required String unit,
    required Color color,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filled(
          onPressed: value > min
              ? () => onChanged((value - step).clamp(min, max))
              : null,
          icon: const Icon(Icons.remove),
          style: IconButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            disabledBackgroundColor: theme.colorScheme.onSurface.withValues(
              alpha: 0.05,
            ),
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: SpacingTokens.xs,
            children: [
              Text(
                '$value',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(unit, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        IconButton.filled(
          onPressed: value < max
              ? () => onChanged((value + step).clamp(min, max))
              : null,
          icon: const Icon(Icons.add),
          style: IconButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            disabledBackgroundColor: theme.colorScheme.onSurface.withValues(
              alpha: 0.05,
            ),
          ),
        ),
      ],
    );
  }
}
