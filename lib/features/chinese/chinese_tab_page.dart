import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/swipe_navigation_region.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/poem/poem_tab_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_learning_providers.dart';
import 'package:poemath/features/textbook/textbook_learning_page.dart';
import 'package:poemath/features/chinese/expression/picture_story_page.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';

enum ChineseSection {
  textbook,
  poem,
  expression;

  // 枚举保留原有存储/页面索引，导航顺序与顶部标签从左到右一致。
  static const navigationOrder = [textbook, expression, poem];

  static ChineseSection? fromId(String? id) => switch (id) {
    'textbook' => textbook,
    'poem' => poem,
    'expression' => expression,
    _ => null,
  };
}

// 离开语文 Tab 后仍保留本档案的两个列表位置；不保存到学习数据中。
final _chinesePageStorageProvider = Provider.family<PageStorageBucket, String>(
  (ref, profileId) => PageStorageBucket(),
);

class ChineseTabPage extends ConsumerStatefulWidget {
  const ChineseTabPage({super.key, this.section, this.previewOnly = false});

  final ChineseSection? section;
  final bool previewOnly;

  @override
  ConsumerState<ChineseTabPage> createState() => _ChineseTabPageState();
}

class _ChineseTabPageState extends ConsumerState<ChineseTabPage> {
  late ChineseSection _section;
  final _visitedSections = <ChineseSection>{};
  late String _profileId;
  double _transitionDirection = 1;
  late final StreamSubscription<String> _profileSubscription;

  ChineseSection _savedSection() => ChineseSection.fromId(
    ref.read(settingsRepositoryProvider).chineseSection,
  )!;

  @override
  void initState() {
    super.initState();
    _profileId = ProfileScope.currentId;
    _section = widget.section ?? _savedSection();
    _visitedSections.add(_section);
    if (widget.section != null && !widget.previewOnly) {
      unawaited(_rememberSection());
    }
    _profileSubscription = ProfileScope.changes.listen((profileId) {
      if (!mounted) return;
      setState(() {
        _profileId = profileId;
        _section = _savedSection();
        _visitedSections
          ..clear()
          ..add(_section);
      });
    });
  }

  @override
  void didUpdateWidget(ChineseTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requested = widget.section;
    if (requested != null &&
        requested != oldWidget.section &&
        requested != _section) {
      _transitionDirection =
          ChineseSection.navigationOrder.indexOf(requested) >
              ChineseSection.navigationOrder.indexOf(_section)
          ? 1
          : -1;
      _section = requested;
      _visitedSections.add(requested);
      if (!widget.previewOnly) unawaited(_rememberSection());
    }
  }

  Future<void> _rememberSection() async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setChineseSection(_section.name);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '语文栏目偏好保存失败',
        tag: 'Chinese',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _select(ChineseSection section) {
    if (widget.previewOnly || _section == section) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _transitionDirection =
          ChineseSection.navigationOrder.indexOf(section) >
              ChineseSection.navigationOrder.indexOf(_section)
          ? 1
          : -1;
      _section = section;
      _visitedSections.add(section);
    });
    unawaited(_rememberSection());
    context.go(AppRoutes.chineseSectionOf(section.name));
  }

  @override
  void dispose() {
    unawaited(_profileSubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sectionIndex = ChineseSection.navigationOrder.indexOf(_section);
    final textbookCount = ref.watch(currentTextbooksProvider).length;
    final poemCount = ref.watch(availablePoemsProvider).length;
    final expressionCount = ref
        .watch(availablePictureStoryPromptsProvider)
        .length;
    final labelStyle = Theme.of(context).textTheme.labelLarge!;
    final labelHeight =
        MediaQuery.textScalerOf(context).scale(labelStyle.fontSize!) *
        (labelStyle.height ?? 1);
    final toolbarHeight = math.max(
      kToolbarHeight,
      labelHeight + SpacingTokens.sm * 4,
    );
    Widget switcherFor(ChineseSection selected) =>
        SwipeNavigationSegmentedButton<ChineseSection>(
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(0, SpacingTokens.xxl),
            padding: const EdgeInsets.all(SpacingTokens.sm),
          ),
          segments: [
            for (final section in ChineseSection.navigationOrder)
              ButtonSegment(
                value: section,
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(switch (section) {
                    ChineseSection.textbook => '课本($textbookCount)',
                    ChineseSection.expression => '表达($expressionCount)',
                    ChineseSection.poem => '诗词($poemCount)',
                  }, maxLines: 1),
                ),
              ),
          ],
          selected: selected,
          onSelectionChanged: (values) {
            _select(values.single);
          },
        );
    Widget sectionPage(ChineseSection section, {bool preview = false}) {
      final Widget Function(Widget)? bodySwipeWrapper = preview
          ? null
          : (child) =>
                SwipeNavigationBody(enabled: section == _section, child: child);
      final navigationTitle = preview ? null : switcherFor(section);
      final page = switch (section) {
        ChineseSection.textbook => TextbookLearningPage(
          navigationTitle: navigationTitle,
          navigationToolbarHeight: toolbarHeight,
          showAppBar: !preview,
          bodySwipeWrapper: bodySwipeWrapper,
        ),
        ChineseSection.poem => PoemTabPage(
          navigationTitle: navigationTitle,
          navigationToolbarHeight: toolbarHeight,
          showAppBar: !preview,
          bodySwipeWrapper: bodySwipeWrapper,
        ),
        ChineseSection.expression => PictureStoryPage(
          navigationTitle: navigationTitle,
          navigationToolbarHeight: toolbarHeight,
          showAppBar: !preview,
          bodySwipeWrapper: bodySwipeWrapper,
        ),
      };
      return TickerMode(
        enabled: preview || section == _section,
        child: preview || _visitedSections.contains(section)
            ? page
            : const SizedBox.shrink(),
      );
    }

    WidgetBuilder sectionPreview(ChineseSection section) =>
        (_) => KeyedSubtree(
          key: ValueKey('chinese-section-preview-${section.name}'),
          child: PageStorage(
            bucket: ref.read(_chinesePageStorageProvider(_profileId)),
            child: sectionPage(section, preview: true),
          ),
        );
    final pageStorage = ref.watch(_chinesePageStorageProvider(_profileId));
    return SwipeNavigationRegion(
      animateBodyOnly: true,
      transitionKey: _section,
      transitionDirection: _transitionDirection,
      onNext: sectionIndex < ChineseSection.navigationOrder.length - 1
          ? () => _select(ChineseSection.navigationOrder[sectionIndex + 1])
          : null,
      nextPageBuilder: sectionIndex < ChineseSection.navigationOrder.length - 1
          ? sectionPreview(ChineseSection.navigationOrder[sectionIndex + 1])
          : null,
      onPrevious: sectionIndex > 0
          ? () => _select(ChineseSection.navigationOrder[sectionIndex - 1])
          : null,
      previousPageBuilder: sectionIndex > 0
          ? sectionPreview(ChineseSection.navigationOrder[sectionIndex - 1])
          : null,
      child: PageStorage(
        bucket: pageStorage,
        child: IndexedStack(
          key: ValueKey(_profileId),
          index: _section.index,
          children: [
            for (final section in ChineseSection.values) sectionPage(section),
          ],
        ),
      ),
    );
  }
}
