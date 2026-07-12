// lib/features/math/widgets/grade_semester_card.dart
//
// 年级学期选择卡片。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

class GradeSemesterCard extends StatelessWidget {
  const GradeSemesterCard({
    super.key,
    required this.grade,
    required this.semester,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  final int grade;
  final String semester;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  static const _gradeIcons = <int, IconData>{
    1: Icons.looks_one_rounded,
    2: Icons.looks_two_rounded,
    3: Icons.looks_3_rounded,
    4: Icons.looks_4_rounded,
    5: Icons.looks_5_rounded,
    6: Icons.looks_6_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Card(
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        side: isSelected
            ? BorderSide(color: primary, width: 2)
            : BorderSide.none,
      ),
      color: isSelected
          ? primary.withValues(alpha: 0.08)
          : theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Row(
            children: [
              Icon(
                _gradeIcons[grade] ?? Icons.school,
                size: 32,
                color: isSelected
                    ? primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: SpacingTokens.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isSelected
                    ? primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
