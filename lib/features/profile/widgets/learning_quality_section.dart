import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/domain/learning_quality.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/profile/providers/learning_quality_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

class LearningQualitySection extends ConsumerStatefulWidget {
  const LearningQualitySection({super.key, required this.days});
  final int days;
  @override
  ConsumerState<LearningQualitySection> createState() =>
      _LearningQualitySectionState();
}

class _LearningQualitySectionState
    extends ConsumerState<LearningQualitySection> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = ref.watch(learningQualityProvider(widget.days));
    final total = report.classifiedMathTotal + report.unknownMathTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ColoredCard(
          color: theme.colorScheme.primary,
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('学习质量', style: theme.textTheme.titleMedium),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                  '新学 ${report.newPoems} 首 · 练习 ${report.poemPracticeCount} 次 · 完成复习 ${report.completedReviews} 次',),
              Text('新增掌握 ${report.newlyMasteredPoems} 首'),
              const SizedBox(height: SpacingTokens.xs),
              const Text(
                  '新学按首次学习的诗词计数；练习含背诵、测试、默写及跟读，可与新学、复习重叠。复习仅计有记录的完成事件，旧历史未知。',),
              if (report.poemHistoryUnknown) ...[
                const SizedBox(height: SpacingTokens.xs),
                const Text('部分诗词历史只有最后学习时间，无法还原每次练习。'),
              ],
              if (report.masteryHistoryUnknown) ...[
                const SizedBox(height: SpacingTokens.xs),
                const Text('部分已掌握诗词没有首次掌握日期，不计入本期新增。'),
              ],
              for (final mode in report.poemModes) ...[
                const SizedBox(height: SpacingTokens.xs),
                Text(_poemModeLabel(mode)),
              ],
              const SizedBox(height: SpacingTokens.xs),
              const Text('测试按题、默写与跟读按句分别统计，不合并为诗词总正确率；背诵不同提示级别仅计完成次数。'),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                  '数学知识点已分类 ${report.classifiedMathTotal}/$total 题 · 历史或挑战未分类 ${report.unknownMathTotal} 题',),
              const SizedBox(height: SpacingTokens.xs),
              const Text('正确率来自逐题作答；不从错题数推算。变化对比前一个同长度周期。'),
            ],
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        if (report.skills.isEmpty) const Text('还没有可分类的知识点作答，完成练习后可查看。'),
        for (final quality in report.skills) ...[
          AppTile(
            icon: Icons.analytics_outlined,
            iconColor: theme.colorScheme.secondary,
            title:
                '${quality.skill.label} · ${quality.grade}年级${quality.semester ?? '学期未知'}',
            subtitle:
                '${quality.correct}/${quality.total} 题正确 · ${(quality.accuracy * 100).round()}%\n${_changeLabel(quality)}',
            trailing: const SizedBox.shrink(),
          ),
          const SizedBox(height: SpacingTokens.sm),
        ],
        if (report.recommendations.isNotEmpty) ...[
          Text('接下来练什么', style: theme.textTheme.titleMedium),
          const SizedBox(height: SpacingTokens.sm),
          for (final quality in report.recommendations) ...[
            AppTile(
              icon: Icons.play_circle_outline,
              iconColor: theme.colorScheme.primary,
              title: '${quality.skill.label} · 再练 5 题',
              subtitle: quality.isSmallSample
                  ? '样本不足，补充练习后再判断掌握情况'
                  : '本期正确率低于 80%，试试同知识点专项',
              onTap: _opening ? null : () => _practice(quality),
            ),
            const SizedBox(height: SpacingTokens.sm),
          ],
        ],
      ],
    );
  }

  String _changeLabel(SkillQuality quality) {
    if (quality.isSmallSample) {
      return '小样本（少于 ${SkillQuality.minimumSample} 题），暂不判断掌握或变化';
    }
    if (quality.previousTotal < SkillQuality.minimumSample) {
      return '上期样本不足，暂无可靠变化';
    }
    final change = (quality.change! * 100).round();
    return '较上期 ${change >= 0 ? '+' : ''}$change 个百分点（上期 ${quality.previousCorrect}/${quality.previousTotal}）';
  }

  String _poemModeLabel(PoemModeQuality quality) {
    final label = switch (quality.mode) {
      LearningActivityType.poemQuiz => '测试',
      LearningActivityType.poemDictation => '听写',
      LearningActivityType.readAlong => '跟读',
      _ => '背诵',
    };
    if (quality.mode == LearningActivityType.poemRecitation) {
      return '$label完成 ${quality.practices} 次（提示级别不混算）';
    }
    if (quality.total == 0) return '$label完成 ${quality.practices} 次，暂无可计量题句';
    final ratio = '${(quality.successful / quality.total * 100).round()}%';
    return switch (quality.mode) {
      LearningActivityType.poemQuiz =>
        '$label ${quality.successful}/${quality.total} 题正确 · $ratio',
      LearningActivityType.poemDictation =>
        '$label ${quality.successful}/${quality.total} 句通过 · $ratio（含错句专项）',
      LearningActivityType.readAlong =>
        '$label ${quality.successful}/${quality.total} 句内容匹配达标 · $ratio（参考阈值 60%，不评价音准）',
      _ => label,
    };
  }

  Future<void> _practice(SkillQuality quality) async {
    if (_opening || !quality.canPractice) return;
    setState(() => _opening = true);
    try {
      // 先验证这一册、难度与知识点确实兼容，失败不发布一次性请求。
      MathEngine.generate(
        grade: quality.grade,
        semester: quality.semester!,
        difficulty: quality.difficulty,
        skillId: quality.skill.id,
        random: Random(0),
      );
      ref.read(nextMathPracticeRequestProvider.notifier).setNext(
            MathPracticeRequest(
              grade: quality.grade,
              semester: quality.semester!,
              count: 5,
              difficulty: quality.difficulty,
              skillId: quality.skill.id,
            ),
          );
      await context.push<void>(AppRoutes.mathPractice);
    } on Object catch (error, stack) {
      AppLogger.e('质量报告专项打开失败',
          tag: 'LearningQuality', error: error, stackTrace: stack,);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这一册或难度暂不支持该专项，请从练习页选择其他内容')),
        );
      }
    } finally {
      if (mounted) {
        ref.invalidate(learningQualityProvider(widget.days));
        setState(() => _opening = false);
      }
    }
  }
}
