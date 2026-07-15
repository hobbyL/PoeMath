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

class PracticeSettingsPage extends ConsumerStatefulWidget {
  const PracticeSettingsPage({super.key});

  @override
  ConsumerState<PracticeSettingsPage> createState() =>
      _PracticeSettingsPageState();
}

class _PracticeSettingsPageState extends ConsumerState<PracticeSettingsPage> {
  late int _poemGoal;
  late int _mathGoal;
  late int _batchSize;
  late DifficultyLevel _difficulty;
  bool _initialized = false;

  static const int _poemMin = 1;
  static const int _poemMax = 10;
  static const int _mathMin = 5;
  static const int _mathMax = 100;
  static const int _mathStep = 5;
  static const _batchOptions = [5, 10, 15, 20, 30];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final settings = ref.read(settingsRepositoryProvider);
      _poemGoal = ref.read(dailyPoemGoalProvider);
      _mathGoal = ref.read(dailyMathGoalProvider);
      _batchSize = settings.mathBatchSize;
      _difficulty = _parseDifficulty(settings.mathDifficulty);
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
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setDailyPoemGoal(_poemGoal);
    await settings.setDailyMathGoal(_mathGoal);
    await settings.setMathBatchSize(_batchSize);
    await settings.setMathDifficulty(_difficulty.name);

    // 同步 in-memory provider
    ref.read(mathDifficultyProvider.notifier).state = _difficulty;

    ref.invalidate(settingsRepositoryProvider);
    ref.invalidate(dailyPoemGoalProvider);
    ref.invalidate(dailyMathGoalProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('练习设置')),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: [
            // ============ 每组题数 ============
            ColoredCard(
              color: theme.colorScheme.tertiary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.format_list_numbered_rounded,
                        color: theme.colorScheme.tertiary,
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
                        onSelected: (_) =>
                            setState(() => _batchSize = n),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            // ============ 练习难度 ============
            ColoredCard(
              color: theme.colorScheme.secondary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.speed_rounded,
                        color: theme.colorScheme.secondary,
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
                        onSelected: (_) =>
                            setState(() => _difficulty = d),
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
              color: theme.colorScheme.secondary,
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calculate_rounded,
                        color: theme.colorScheme.secondary,
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
                    color: theme.colorScheme.secondary,
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
                onPressed: _save,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('保存'),
              ),
            ),
          ],
        ),
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
            disabledBackgroundColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.05),
          ),
        ),
        const SizedBox(width: SpacingTokens.lg),
        Text(
          '$value',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: SpacingTokens.xs),
        Text(unit, style: theme.textTheme.titleMedium),
        const SizedBox(width: SpacingTokens.lg),
        IconButton.filled(
          onPressed: value < max
              ? () => onChanged((value + step).clamp(min, max))
              : null,
          icon: const Icon(Icons.add),
          style: IconButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            disabledBackgroundColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.05),
          ),
        ),
      ],
    );
  }
}
