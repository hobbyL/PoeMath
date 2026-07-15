// lib/features/profile/daily_goal_page.dart
//
// 层级：features/profile
// 职责：每日目标设置子页面 — 同时设置诗词和口算的每日目标数量。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

class DailyGoalPage extends ConsumerStatefulWidget {
  const DailyGoalPage({super.key});

  @override
  ConsumerState<DailyGoalPage> createState() => _DailyGoalPageState();
}

class _DailyGoalPageState extends ConsumerState<DailyGoalPage> {
  late int _poemGoal;
  late int _mathGoal;
  bool _initialized = false;

  static const int _poemMin = 1;
  static const int _poemMax = 10;
  static const int _mathMin = 5;
  static const int _mathMax = 100;
  static const int _mathStep = 5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _poemGoal = ref.read(dailyPoemGoalProvider);
      _mathGoal = ref.read(dailyMathGoalProvider);
      _initialized = true;
    }
  }

  Future<void> _save() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.setDailyPoemGoal(_poemGoal);
    await settingsRepo.setDailyMathGoal(_mathGoal);
    ref.invalidate(settingsRepositoryProvider);
    ref.invalidate(dailyPoemGoalProvider);
    ref.invalidate(dailyMathGoalProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('每日目标')),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: [
              // 诗词目标
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

              // 口算目标
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
