import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_toc.dart';

Future<int?> showTextbookToc({
  required BuildContext context,
  required TextbookTocLoader load,
}) =>
    showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Durations.medium2,
      pageBuilder: (_, __, ___) => Align(
        alignment: Alignment.centerLeft,
        child: TextbookTocDrawer(load: load),
      ),
      transitionBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween(begin: const Offset(-1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
        child: child,
      ),
    );

class TextbookTocDrawer extends StatefulWidget {
  const TextbookTocDrawer({super.key, required this.load});

  final TextbookTocLoader load;

  @override
  State<TextbookTocDrawer> createState() => _TextbookTocDrawerState();
}

class _TextbookTocDrawerState extends State<TextbookTocDrawer> {
  StreamSubscription<TextbookTocProgress>? _subscription;
  TextbookTocProgress? _progress;
  TextbookTocResult? _result;
  int _generation = 0;
  bool _loading = true;
  bool _failed = false;
  final _collapsed = <int>{};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _cancel() {
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _scan({bool refresh = false}) {
    _cancel();
    final generation = _generation;
    setState(() {
      _loading = true;
      _failed = false;
      _result = null;
      _progress = null;
      _collapsed.clear();
    });
    void failed() {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }

    try {
      _subscription = widget.load(refresh).listen(
        (progress) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _progress = progress;
            if (progress.result != null) _result = progress.result;
            _loading = progress.phase != TextbookTocPhase.ready;
          });
        },
        onDone: () {
          if (mounted && generation == _generation && _result == null) {
            failed();
          }
        },
        onError: (Object error, StackTrace stack) => failed(),
        cancelOnError: true,
      );
    } on Object {
      failed();
    }
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _progress;
    final result = _result;
    final entries = result?.entries ?? const <TextbookTocEntry>[];
    bool hasChildren(int index) =>
        index + 1 < entries.length &&
        entries[index + 1].level > entries[index].level;
    final visible = <int>[];
    int? hiddenLevel;
    for (var index = 0; index < entries.length; index++) {
      if (hiddenLevel != null && entries[index].level > hiddenLevel) continue;
      hiddenLevel = null;
      visible.add(index);
      if (_collapsed.contains(index)) hiddenLevel = entries[index].level;
    }
    final status = _failed
        ? '目录识别未完成，请重试'
        : _loading
            ? progress == null
                ? '正在读取目录…'
                : '${progress.phase == TextbookTocPhase.resolving ? '正在校准页码' : '正在查找目录'} ${progress.scanned} / ${progress.total} 页'
            : entries.isEmpty
                ? result?.hasText == false
                    ? '这本书暂无可识别的文字目录'
                    : '未识别到可用目录'
                : entries.indexed.any(
                    (item) =>
                        item.$2.page == null &&
                        !item.$2.isGroup &&
                        !hasChildren(item.$1),
                  )
                    ? '部分条目暂未定位页码'
                    : null;
    return Drawer(
      width: math.min(
        ResponsiveLayout.mediumBreakpoint * 2 / 3,
        MediaQuery.sizeOf(context).width - SpacingTokens.xxl,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(SpacingTokens.radiusLarge),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: CustomScrollView(
            slivers: [
              if (status != null || _loading || _failed)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (status != null) Text(status),
                      if (_loading) ...[
                        const SizedBox(height: SpacingTokens.sm),
                        LinearProgressIndicator(
                          value: progress == null || progress.total == 0
                              ? null
                              : progress.scanned / progress.total,
                        ),
                      ],
                      if (_failed)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: () => _scan(refresh: true),
                            child: const Text('重试'),
                          ),
                        ),
                      const SizedBox(height: SpacingTokens.sm),
                    ],
                  ),
                ),
              SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, position) {
                  final index = visible[position];
                  final entry = entries[index];
                  final branch = hasChildren(index);
                  final collapsed = _collapsed.contains(index);
                  void toggle() => setState(() {
                        if (!_collapsed.remove(index)) _collapsed.add(index);
                      });
                  final title = entry.lessonNumber == null
                      ? entry.title
                      : '${entry.lessonNumber}：${entry.title}';
                  return Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: SpacingTokens.md *
                          entry.level.clamp(0, 3) /
                          math.max(
                            1,
                            MediaQuery.textScalerOf(context).scale(1),
                          ),
                    ),
                    child: AppTile(
                      key: ValueKey('textbook-toc-entry-$index'),
                      flat: true,
                      iconColor: theme.colorScheme.primary,
                      title: title,
                      titleSuffix:
                          entry.page == null ? null : '第 ${entry.page} 页',
                      subtitle: entry.page != null || branch || entry.isGroup
                          ? ''
                          : entry.printedPage != null
                              ? '书内第 ${entry.printedPage} 页 · 暂未定位页码'
                              : '暂无跳转页码',
                      subtitleMaxLines: 2,
                      trailingInTitle: true,
                      trailingIcon: branch && !collapsed
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      onTrailingTap: branch ? toggle : null,
                      trailingTooltip:
                          branch ? '${collapsed ? '展开' : '收起'}$title' : null,
                      trailing: !branch && entry.page == null
                          ? const Icon(Icons.bookmark_border)
                          : null,
                      onTap: entry.page == null
                          ? branch
                              ? toggle
                              : null
                          : () => Navigator.pop(context, entry.page),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
