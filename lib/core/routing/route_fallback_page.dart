// lib/core/routing/route_fallback_page.dart
//
// 层级：core/routing
// 职责：路由无法正常构建目标页时的兜底占位页（数据失效 / 路径不存在）。
//
// 背景：`/math/session`、`/math/mistake/detail`、`/word-problem/preview`、
//      `/word-problem/practice` 四条路由通过 `GoRouterState.extra` 传对象。
//      `extra` 不参与 URL 序列化：深链直达、或进程被系统回收后恢复路由栈时
//      必定为 null。旧实现 `state.extra! as X` 会抛 TypeError，用户只看到白屏
//      且无法返回。改为渲染本页并给出重新进入的入口。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 路由兜底页：说明原因 + 一个能重新拿到数据的入口。
class RouteFallbackPage extends StatelessWidget {
  /// `extra` 缺失或类型不符（进程恢复 / 深链直达）。
  const RouteFallbackPage.dataMissing({
    super.key,
    required this.title,
    required this.fallbackLocation,
    required this.fallbackLabel,
  })  : heading = '页面数据已失效',
        message = '应用被系统回收后恢复，或从外部链接直接打开时，'
            '这个页面需要的数据不会被保留。请从入口重新进入。';

  /// 路径本身不存在（旧版本链接 / 外部跳转拼错）。
  const RouteFallbackPage.notFound({super.key, required String path})
      : title = '页面不存在',
        heading = '无法打开这个页面',
        message = '“$path”不是有效的应用页面，可能来自旧版本或外部跳转。',
        fallbackLocation = AppRoutes.home,
        fallbackLabel = '返回首页';

  /// AppBar 标题，沿用目标页标题，避免用户以为进错了地方。
  final String title;

  /// 正文标题与说明。
  final String heading;
  final String message;

  /// 兜底按钮跳转的路由，应为「能重新产出这份数据」的入口页。
  final String fallbackLocation;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SpacingTokens.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 56,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  Text(
                    heading,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SpacingTokens.lg),
                  FilledButton.icon(
                    // 兜底页只在「没有上一页可回」的场景出现（深链 / 进程恢复），
                    // 故用 go 重置栈而非 pop。
                    onPressed: () => context.go(fallbackLocation),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(fallbackLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
