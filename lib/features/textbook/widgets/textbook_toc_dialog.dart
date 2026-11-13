import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:poemath/core/services/textbook_page_number_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_toc.dart';
import 'package:poemath/data/models/textbook_page_numbers.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_number_label.dart';

int? _entryIndexForPage(List<TextbookTocEntry> entries, int? currentPage) {
  if (currentPage == null) return null;
  int? selected;
  for (final (index, entry) in entries.indexed) {
    final page = entry.page;
    if (page == null || page > currentPage) continue;
    if (selected == null) {
      selected = index;
      continue;
    }
    final selectedEntry = entries[selected];
    if (page > selectedEntry.page! ||
        page == selectedEntry.page && entry.level >= selectedEntry.level) {
      selected = index;
    }
  }
  return selected;
}

Future<int?> showTextbookToc({
  required BuildContext context,
  required TextbookTocLoader load,
  int? currentPage,
  TextbookPageNumberService? pageNumbers,
}) => showGeneralDialog<int>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Durations.medium2,
  pageBuilder: (_, __, ___) => Align(
    alignment: Alignment.centerLeft,
    child: TextbookTocDrawer(
      load: load,
      currentPage: currentPage,
      pageNumbers: pageNumbers,
    ),
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
  const TextbookTocDrawer({
    super.key,
    required this.load,
    this.currentPage,
    this.pageNumbers,
  });

  final TextbookTocLoader load;
  final int? currentPage;
  final TextbookPageNumberService? pageNumbers;

  @override
  State<TextbookTocDrawer> createState() => _TextbookTocDrawerState();
}

class _TextbookTocDrawerState extends State<TextbookTocDrawer> {
  StreamSubscription<TextbookTocProgress>? _subscription;
  TextbookTocProgress? _progress;
  TextbookTocResult? _result;
  int _generation = 0;
  int _scrollGeneration = 0;
  int? _selectedIndex;
  bool _loading = true;
  bool _failed = false;
  final _collapsed = <int>{};
  final _scrollController = ScrollController();
  final _scrollViewportKey = GlobalKey();
  final _entryKeys = <int, GlobalKey>{};
  List<int> _visibleEntryIndices = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _cancel() {
    _generation++;
    _scrollGeneration++;
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
      _selectedIndex = null;
      _collapsed.clear();
      _entryKeys.clear();
    });
    void failed() {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }

    try {
      _subscription = widget
          .load(refresh)
          .listen(
            (progress) {
              if (!mounted || generation != _generation) return;
              final result = progress.result ?? _result;
              final selectCurrentPage =
                  _loading && progress.phase == TextbookTocPhase.ready;
              final selectedIndex = selectCurrentPage && result != null
                  ? _entryIndexForPage(result.entries, widget.currentPage)
                  : null;
              setState(() {
                _progress = progress;
                if (result != null) _result = result;
                if (selectCurrentPage) {
                  _selectedIndex = selectedIndex;
                  if (selectedIndex != null) {
                    _expandAncestors(result!.entries, selectedIndex);
                  }
                }
                _loading = progress.phase != TextbookTocPhase.ready;
              });
              if (selectedIndex != null) {
                unawaited(_scrollToEntry(selectedIndex));
              }
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
    _scrollController.dispose();
    super.dispose();
  }

  void _expandAncestors(List<TextbookTocEntry> entries, int index) {
    var level = entries[index].level;
    for (var ancestor = index - 1; ancestor >= 0 && level > 0; ancestor--) {
      if (entries[ancestor].level < level) {
        _collapsed.remove(ancestor);
        level = entries[ancestor].level;
      }
    }
  }

  Future<void> _scrollToEntry(int index) async {
    final generation = ++_scrollGeneration;
    // SliverList 只构建视口附近的条目；先按实际行高靠近，再精确居中。
    // 每次跳转后等待布局，避免用固定行高处理大字、换行和未定位提示。
    for (var attempt = 0; attempt <= 8; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _scrollGeneration) return;
      final targetContext = _entryKeys[index]?.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.5,
          duration: MediaQuery.disableAnimationsOf(targetContext)
              ? Duration.zero
              : Durations.short4,
          curve: Curves.easeOutCubic,
        );
        return;
      }
      if (attempt == 8 ||
          !_scrollController.hasClients ||
          _visibleEntryIndices.isEmpty) {
        return;
      }
      final position = _scrollController.position;
      final targetPosition = _visibleEntryIndices.indexOf(index);
      if (targetPosition < 0) return;
      final viewport = _scrollViewportKey.currentContext?.findRenderObject();
      final viewportTop = viewport is RenderBox && viewport.hasSize
          ? viewport.localToGlobal(Offset.zero).dy
          : 0.0;
      final samples = <(int, double, double)>[];
      for (final (listPosition, entryIndex) in _visibleEntryIndices.indexed) {
        final renderObject = _entryKeys[entryIndex]?.currentContext
            ?.findRenderObject();
        if (renderObject is RenderBox && renderObject.hasSize) {
          samples.add((
            listPosition,
            renderObject.localToGlobal(Offset.zero).dy,
            renderObject.size.height,
          ));
        }
      }
      double desiredOffset;
      if (samples.isEmpty) {
        final fraction = (targetPosition + 0.5) / _visibleEntryIndices.length;
        desiredOffset = position.maxScrollExtent * fraction;
      } else {
        final nearest = samples.reduce(
          (prior, sample) =>
              (sample.$1 - targetPosition).abs() <
                  (prior.$1 - targetPosition).abs()
              ? sample
              : prior,
        );
        final averageHeight =
            samples.map((sample) => sample.$3).reduce((a, b) => a + b) /
            samples.length;
        final estimatedTargetTop =
            position.pixels +
            nearest.$2 -
            viewportTop +
            (targetPosition - nearest.$1) * averageHeight;
        desiredOffset =
            estimatedTargetTop -
            (position.viewportDimension - averageHeight) / 2;
        if ((desiredOffset - position.pixels).abs() < 1) {
          desiredOffset +=
              (targetPosition - nearest.$1).sign *
              position.viewportDimension *
              0.75;
        }
      }
      final maxScrollExtent = position.maxScrollExtent;
      _scrollController.jumpTo(
        desiredOffset.clamp(0.0, maxScrollExtent).toDouble(),
      );
    }
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
    _visibleEntryIndices = visible;
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
          child: NotificationListener<ScrollStartNotification>(
            onNotification: (notification) {
              if (notification.dragDetails != null) _scrollGeneration++;
              return false;
            },
            child: CustomScrollView(
              key: _scrollViewportKey,
              controller: _scrollController,
              slivers: [
                if (status != null || _loading || _failed)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (status != null)
                          if (!_failed && !_loading && entries.isEmpty)
                            AppEmptyState(
                              icon: Icons.toc_outlined,
                              title: status,
                              description: '可返回原书直接翻页阅读。',
                              padding: const EdgeInsets.all(SpacingTokens.md),
                            )
                          else
                            Text(status),
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
                    void toggle() {
                      _scrollGeneration++;
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(_scrollController.offset);
                      }
                      setState(() {
                        if (!_collapsed.remove(index)) _collapsed.add(index);
                      });
                    }

                    final title = entry.lessonNumber == null
                        ? entry.title
                        : '${entry.lessonNumber}：${entry.title}';
                    final key = _entryKeys.putIfAbsent(
                      index,
                      () => GlobalKey(debugLabel: 'textbook-toc-entry-$index'),
                    );
                    return KeyedSubtree(
                      key: key,
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          start:
                              SpacingTokens.md *
                              entry.level.clamp(0, 3) /
                              math.max(
                                1,
                                MediaQuery.textScalerOf(context).scale(1),
                              ),
                        ),
                        child: TextbookPageNumberLabel(
                          service: entry.page == null
                              ? null
                              : widget.pageNumbers,
                          pages: entry.page == null ? const [] : [entry.page!],
                          fallbackLabel: textbookPrintedPageLabel(
                            entry.printedPage,
                          ),
                          builder: (context, pageLabel) => AppTile(
                            key: ValueKey('textbook-toc-entry-$index'),
                            flat: true,
                            selected: index == _selectedIndex,
                            iconColor: theme.colorScheme.primary,
                            title: title,
                            titleSuffix: entry.page == null ? null : pageLabel,
                            subtitle:
                                entry.page != null || branch || entry.isGroup
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
                            trailingTooltip: branch
                                ? '${collapsed ? '展开' : '收起'}$title'
                                : null,
                            trailing: !branch && entry.page == null
                                ? const Icon(Icons.bookmark_border)
                                : null,
                            onTap: entry.page == null
                                ? branch
                                      ? toggle
                                      : null
                                : () => Navigator.pop(context, entry.page),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
