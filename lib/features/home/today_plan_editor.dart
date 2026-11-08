import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/domain/today_plan.dart';

/// 只有保存成功或家长明确放弃修改时才关闭计划编辑。
class TodayPlanEditor extends StatefulWidget {
  const TodayPlanEditor({
    super.key,
    required this.initial,
    required this.onSave,
  });

  final TodayPlanConfig initial;
  final Future<void> Function(TodayPlanConfig config) onSave;

  @override
  State<TodayPlanEditor> createState() => _TodayPlanEditorState();
}

class _TodayPlanEditorState extends State<TodayPlanEditor> {
  late final _counts = {
    for (final kind in TodayTaskKind.values)
      kind: widget.initial.countFor(kind),
  };
  late final _order = List<TodayTaskKind>.of(widget.initial.order);
  bool _saving = false;
  bool _failed = false;
  bool _closing = false;

  Future<void> _saveAndClose() async {
    if (_saving || _closing) return;
    setState(() => _saving = true);
    try {
      assertParentAccess(context);
      await widget.onSave(
        TodayPlanConfig(
          reviewCount: _counts[TodayTaskKind.review]!,
          mistakeCount: _counts[TodayTaskKind.mistake]!,
          newPoemCount: _counts[TodayTaskKind.newPoem]!,
          order: List.of(_order),
        ),
      );
      if (!mounted) return;
      _closing = true;
      Navigator.of(context).pop();
    } on Object catch (error, stack) {
      AppLogger.e(
        '计划配置保存失败',
        tag: 'TodayPlan',
        error: error,
        stackTrace: stack,
      );
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndClose();
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('调整每日计划', style: theme.textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: '保存并关闭',
                      onPressed: _saving ? null : _saveAndClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.sm),
                const Text('每类 0–5 项，最多 15 项；数量及顺序从明天起生效。今天的清单保持固定。'),
                if (_failed) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    '计划保存失败，修改已保留，请重试。',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  Wrap(
                    spacing: SpacingTokens.sm,
                    children: [
                      FilledButton(
                        onPressed: _saving ? null : _saveAndClose,
                        child: Text(_saving ? '正在保存…' : '重试保存'),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () {
                                _closing = true;
                                Navigator.of(context).pop();
                              },
                        child: const Text('放弃修改'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: SpacingTokens.md),
                for (final (index, kind) in _order.indexed) ...[
                  AppTile(
                    icon: switch (kind) {
                      TodayTaskKind.review => Icons.history_edu,
                      TodayTaskKind.mistake => Icons.calculate_outlined,
                      TodayTaskKind.newPoem => Icons.menu_book_outlined,
                    },
                    iconColor: theme.colorScheme.primary,
                    title: kind.label,
                    subtitle: '每天最多 ${_counts[kind]} 项',
                    trailing: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          tooltip: '减少${kind.label}',
                          onPressed: !_saving && _counts[kind]! > 0
                              ? () => setState(
                                  () => _counts[kind] = _counts[kind]! - 1,
                                )
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        Text('${_counts[kind]}'),
                        IconButton(
                          tooltip: '增加${kind.label}',
                          onPressed: !_saving && _counts[kind]! < 5
                              ? () => setState(
                                  () => _counts[kind] = _counts[kind]! + 1,
                                )
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: !_saving && index > 0
                            ? () => setState(() {
                                _order[index] = _order[index - 1];
                                _order[index - 1] = kind;
                              })
                            : null,
                        child: const Text('上移'),
                      ),
                      TextButton(
                        onPressed: !_saving && index < _order.length - 1
                            ? () => setState(() {
                                _order[index] = _order[index + 1];
                                _order[index + 1] = kind;
                              })
                            : null,
                        child: const Text('下移'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
