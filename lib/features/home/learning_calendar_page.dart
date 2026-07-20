// lib/features/home/learning_calendar_page.dart
//
// 层级：features/home
// 职责：学习日历 — 月度热力图展示每日学习情况，直观呈现打卡记录。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/features/home/providers/home_providers.dart';

class LearningCalendarPage extends ConsumerStatefulWidget {
  const LearningCalendarPage({super.key});

  @override
  ConsumerState<LearningCalendarPage> createState() =>
      _LearningCalendarPageState();
}

class _LearningCalendarPageState extends ConsumerState<LearningCalendarPage> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(checkInRepoProvider);
    final records = repo.getByMonth(_currentMonth.year, _currentMonth.month);
    final streak = ref.watch(streakProvider);

    // 构建日期 → 打卡记录映射
    final checkInMap = <int, CheckIn>{};
    for (final r in records) {
      final parts = r.date.split('-');
      if (parts.length == 3) {
        checkInMap[int.parse(parts[2])] = r;
      }
    }

    final monthLabel = '${_currentMonth.year} 年 ${_currentMonth.month} 月';

    return Scaffold(
      appBar: AppBar(title: const Text('学习日历')),
      body: SafeArea(
        child: AnimatedPageBody(
          children: [
            // 月份导航
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _previousMonth,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  monthLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: _isCurrentMonth ? null : _nextMonth,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.sm),

            // 统计概览
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat(
                    theme,
                    Icons.local_fire_department_rounded,
                    '$streak',
                    '连续打卡',
                    theme.colorScheme.error,
                  ),
                  _buildStat(
                    theme,
                    Icons.event_available,
                    '${records.length}',
                    '本月学习',
                    theme.colorScheme.primary,
                  ),
                  _buildStat(
                    theme,
                    Icons.star_rounded,
                    '${records.fold<int>(0, (s, r) => s + r.starsEarned)}',
                    '本月星星',
                    theme.semantic.caution,
                  ),
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.md),

            // 日历网格
            _buildCalendarGrid(theme, checkInMap),
            const SizedBox(height: SpacingTokens.md),

            // 热力图图例
            _buildLegend(theme),
            const SizedBox(height: SpacingTokens.lg),
          ],
        ),
      ),
    );
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _currentMonth.year == now.year &&
        _currentMonth.month == now.month;
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(
        _currentMonth.year,
        _currentMonth.month - 1,
      );
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(
        _currentMonth.year,
        _currentMonth.month + 1,
      );
    });
  }

  Widget _buildCalendarGrid(ThemeData theme, Map<int, CheckIn> checkInMap) {
    final daysInMonth = DateUtils.getDaysInMonth(
      _currentMonth.year,
      _currentMonth.month,
    );
    // 月初是周几（1=周一, 7=周日）
    final firstWeekday = DateTime(
      _currentMonth.year,
      _currentMonth.month,
    ).weekday;
    final today = DateTime.now();
    final isThisMonth = _currentMonth.year == today.year &&
        _currentMonth.month == today.month;

    const weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

    return Column(
      children: [
        // 星期标题行
        Row(
          children: weekLabels.map((label) {
            return Expanded(
              child: Center(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: SpacingTokens.xs),

        // 日期格子
        ...List.generate(_rowCount(daysInMonth, firstWeekday), (week) {
          return Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
            child: Row(
              children: List.generate(7, (col) {
                final dayIndex = week * 7 + col - (firstWeekday - 1);
                if (dayIndex < 1 || dayIndex > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 44));
                }
                final checkIn = checkInMap[dayIndex];
                final isToday = isThisMonth && dayIndex == today.day;
                return Expanded(
                  child: _buildDayCell(theme, dayIndex, checkIn, isToday),
                );
              }),
            ),
          );
        }),
      ],
    );
  }

  int _rowCount(int daysInMonth, int firstWeekday) {
    return ((daysInMonth + firstWeekday - 1) / 7).ceil();
  }

  Widget _buildDayCell(
    ThemeData theme,
    int day,
    CheckIn? checkIn,
    bool isToday,
  ) {
    final level = _activityLevel(checkIn);
    final bgColor = _levelColor(theme, level);

    return GestureDetector(
      onTap: checkIn != null
          ? () => _showDayDetail(theme, day, checkIn)
          : null,
      child: Container(
        height: 44,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          border: isToday
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: isToday ? FontWeight.bold : null,
            color: level > 0
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 活跃等级：0=无，1=少量，2=中等，3=活跃，4=非常活跃
  int _activityLevel(CheckIn? checkIn) {
    if (checkIn == null) return 0;
    final total = checkIn.poemCount + checkIn.legacyCompatibleMathTotalCount;
    if (total == 0) return 0;
    if (total <= 3) return 1;
    if (total <= 10) return 2;
    if (total <= 20) return 3;
    return 4;
  }

  Color _levelColor(ThemeData theme, int level) {
    final primary = theme.colorScheme.primary;
    return switch (level) {
      0 => theme.colorScheme.surfaceContainerHighest,
      1 => primary.withValues(alpha: 0.2),
      2 => primary.withValues(alpha: 0.4),
      3 => primary.withValues(alpha: 0.7),
      _ => primary,
    };
  }

  Widget _buildLegend(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '少',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: SpacingTokens.xs),
        for (int i = 0; i <= 4; i++) ...[
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _levelColor(theme, i),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
        const SizedBox(width: SpacingTokens.xs),
        Text(
          '多',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _showDayDetail(ThemeData theme, int day, CheckIn checkIn) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final minutes = checkIn.durationSeconds ~/ 60;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_currentMonth.month} 月 $day 日学习记录',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
                _buildDetailRow(
                  theme,
                  Icons.menu_book_rounded,
                  '诗词学习',
                  '${checkIn.poemCount} 首',
                  theme.colorScheme.primary,
                ),
                const SizedBox(height: SpacingTokens.sm),
                _buildDetailRow(
                  theme,
                  Icons.calculate_rounded,
                  '口算答题',
                  '${checkIn.mathCorrectCount}/'
                      '${checkIn.legacyCompatibleMathTotalCount} 题',
                  theme.colorScheme.secondary,
                ),
                const SizedBox(height: SpacingTokens.sm),
                _buildDetailRow(
                  theme,
                  Icons.star_rounded,
                  '获得星星',
                  '${checkIn.starsEarned}',
                  theme.semantic.caution,
                ),
                const SizedBox(height: SpacingTokens.sm),
                _buildDetailRow(
                  theme,
                  Icons.timer_outlined,
                  '学习时长',
                  '$minutes 分钟',
                  theme.colorScheme.tertiary,
                ),
                const SizedBox(height: SpacingTokens.md),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: SpacingTokens.sm),
        Text(label, style: theme.textTheme.bodyMedium),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStat(
    ThemeData theme,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
