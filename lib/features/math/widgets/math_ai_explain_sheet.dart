// lib/features/math/widgets/math_ai_explain_sheet.dart
//
// 层级：features/math/widgets
// 职责：算数题 AI 解析底部弹层 —— 练习页讲解区与错题详情页共用入口。
//
// 四态（未生成 / 生成中 / 已就绪 / 失败 / 未配置）与诗词侧同构；
// 生成中用纯文案提示（不放无限动画）；关闭弹层即复位状态。
//
// 边界：只展示讲解，不参与判分与错题记录。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/math/math_explain/math_explain_controller.dart';
import 'package:poemath/features/math/math_explain/math_explain_models.dart';

/// 打开 AI 解析弹层并立即发起生成；关闭后复位状态。
Future<void> showMathAiExplainSheet(
  BuildContext context, {
  required String problemText,
  required String correctAnswer,
  String? userAnswer,
  String? diagnosisCategory,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => MathAiExplainSheet(
      problemText: problemText,
      correctAnswer: correctAnswer,
      userAnswer: userAnswer,
      diagnosisCategory: diagnosisCategory,
    ),
  );
}

/// AI 解析弹层内容。
class MathAiExplainSheet extends ConsumerStatefulWidget {
  const MathAiExplainSheet({
    super.key,
    required this.problemText,
    required this.correctAnswer,
    this.userAnswer,
    this.diagnosisCategory,
  });

  final String problemText;
  final String correctAnswer;
  final String? userAnswer;
  final String? diagnosisCategory;

  @override
  ConsumerState<MathAiExplainSheet> createState() =>
      _MathAiExplainSheetState();
}

class _MathAiExplainSheetState extends ConsumerState<MathAiExplainSheet> {
  /// dispose 阶段 ref 不可用，initState 先捕获 notifier。
  late final MathExplainNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(mathExplainProvider.notifier);
    // 打开即生成（入口按钮本身就是用户的生成意图）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 上一个弹层关闭时在途请求被 discardPending 废弃，state 可能残留
      // loading——先复位（idle + 废令牌）再生成，否则 generate 的
      // isLoading 守卫拦截且无任何自愈路径（loading 分支无按钮）。
      _notifier.reset();
      _generate();
    });
  }

  @override
  void dispose() {
    // 关闭弹层：仅令牌失效（丢弃在途请求晚到回调）。不在此写
    // provider 状态——弹层元素在 unmount 期间仍订阅该 provider，
    // 同步状态写会通知 defunct element 触发 markNeedsBuild 断言。
    _notifier.discardPending();
    super.dispose();
  }

  void _generate() {
    _notifier.generate(
      problemText: widget.problemText,
      correctAnswer: widget.correctAnswer,
      userAnswer: widget.userAnswer,
      diagnosisCategory: widget.diagnosisCategory,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(mathExplainProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  Text(
                    'AI 解析',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  _AiBadge(color: theme.colorScheme.tertiary),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: ColoredCard(
                    color: theme.colorScheme.tertiary,
                    backgroundOpacity: 0.06,
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildBody(context, theme, state),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    ThemeData theme,
    MathExplainState state,
  ) {
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    switch (state.status) {
      case MathExplainStatus.idle:
      case MathExplainStatus.loading:
        return [
          Text('AI 正在准备解析，请稍候…', style: hintStyle),
        ];
      case MathExplainStatus.ready:
        return [
          for (final paragraph in state.paragraphs) ...[
            Text(
              paragraph,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
            ),
            const SizedBox(height: SpacingTokens.sm),
          ],
          TextButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新生成'),
          ),
        ];
      case MathExplainStatus.error:
        return [
          Text(
            state.message ?? 'AI 解析生成失败，请稍后重试。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          OutlinedButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新生成'),
          ),
        ];
      case MathExplainStatus.unconfigured:
        return [
          Text(
            state.message ?? '还没有配置 AI 服务，配置后即可使用 AI 解析。',
            style: hintStyle,
          ),
          const SizedBox(height: SpacingTokens.sm),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(AppRoutes.llmSettings);
            },
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('去设置'),
          ),
        ];
    }
  }
}

/// 「AI 生成」角标。
///
/// 行内徽标（非信息卡片/容器），与 AppTile 内图标容器同类，沿用
/// BoxDecoration + 设计令牌，不套 ColoredCard。
class _AiBadge extends StatelessWidget {
  const _AiBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
      ),
      child: Text(
        'AI 生成',
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
