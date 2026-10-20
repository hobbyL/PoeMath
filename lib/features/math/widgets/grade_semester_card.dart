// lib/features/math/widgets/grade_semester_card.dart
//
// 年级学期选择卡片：无边框、纯色背景、圆角，与首页卡片风格一致。
// 选中状态仅显示边框，不变背景色。适合 Grid 一行两个布局。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';

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

    return ColoredCard(
      color: primary,
      backgroundOpacity: 0.06,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md, vertical: SpacingTokens.sm,),
      border: isSelected ? Border.all(color: primary, width: 2) : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _gradeIcons[grade] ?? Icons.school,
            size: 28,
            color: isSelected ? primary : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isSelected ? primary : theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
