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
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/math/math_tab_page.dart';
import 'package:poemath/features/textbook/providers/textbook_learning_providers.dart';
import 'package:poemath/features/textbook/textbook_learning_page.dart';

enum MathSection {
  practice,
  textbook;

  static MathSection? fromId(String? id) =>
      values.where((s) => s.name == id).firstOrNull;
}

final _mathPageStorageProvider = Provider.family<PageStorageBucket, String>(
  (ref, profileId) => PageStorageBucket(),
);

class MathHomePage extends ConsumerStatefulWidget {
  const MathHomePage({super.key, this.section, this.previewOnly = false});
  final MathSection? section;
  final bool previewOnly;
  @override
  ConsumerState<MathHomePage> createState() => _MathHomePageState();
}

class _MathHomePageState extends ConsumerState<MathHomePage> {
  late String _profileId;
  late MathSection _section;
  double _transitionDirection = 1;
  late final StreamSubscription<String> _profileSubscription;
  final _visited = <MathSection>{};
  static String _key(String profile) =>
      'math_section_v1:${Uri.encodeComponent(profile)}';
  MathSection _saved() =>
      MathSection.fromId(HiveBoxes.settings.get(_key(_profileId)) as String?) ??
      MathSection.practice;

  @override
  void initState() {
    super.initState();
    _profileId = ProfileScope.currentId;
    _section = widget.section ?? _saved();
    _visited.add(_section);
    if (widget.section != null && !widget.previewOnly) {
      unawaited(_rememberSection());
    }
    _profileSubscription = ProfileScope.changes.listen((id) {
      if (!mounted) return;
      setState(() {
        _profileId = id;
        _section = _saved();
        _visited
          ..clear()
          ..add(_section);
      });
    });
  }

  @override
  void didUpdateWidget(MathHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.section != null &&
        widget.section != oldWidget.section &&
        widget.section != _section) {
      _transitionDirection = widget.section!.index > _section.index ? 1 : -1;
      _section = widget.section!;
      _visited.add(_section);
      if (!widget.previewOnly) unawaited(_rememberSection());
    }
  }

  Future<void> _select(MathSection section) async {
    if (widget.previewOnly || _section == section) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _transitionDirection = section.index > _section.index ? 1 : -1;
      _section = section;
      _visited.add(section);
    });
    context.go(AppRoutes.mathSectionOf(section.name));
    await _rememberSection();
  }

  Future<void> _rememberSection() async {
    try {
      await HiveBoxes.settings.put(_key(_profileId), _section.name);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '数学栏目偏好保存失败',
        tag: 'MathTextbook',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void dispose() {
    unawaited(_profileSubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!;
    final height =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) *
        (style.height ?? 1);
    final count = ref
        .watch(subjectTextbooksProvider(TextbookSubject.math))
        .length;
    final toolbarHeight = math.max(
      kToolbarHeight,
      height + SpacingTokens.sm * 4,
    );
    Widget switcherFor(MathSection selected) =>
        SwipeNavigationSegmentedButton<MathSection>(
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(0, SpacingTokens.xxl),
            padding: const EdgeInsets.all(SpacingTokens.sm),
          ),
          segments: [
            const ButtonSegment(
              value: MathSection.practice,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('练习', maxLines: 1),
              ),
            ),
            ButtonSegment(
              value: MathSection.textbook,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('课本($count)', maxLines: 1),
              ),
            ),
          ],
          selected: selected,
          onSelectionChanged: (values) {
            unawaited(_select(values.single));
          },
        );
    Widget sectionPage(MathSection section, {bool preview = false}) {
      final Widget Function(Widget)? bodySwipeWrapper = preview
          ? null
          : (child) =>
                SwipeNavigationBody(enabled: section == _section, child: child);
      final page = switch (section) {
        MathSection.practice => MathTabPage(
          navigationTitle: preview ? null : switcherFor(section),
          navigationToolbarHeight: toolbarHeight,
          showAppBar: !preview,
          bodySwipeWrapper: bodySwipeWrapper,
        ),
        MathSection.textbook => TextbookLearningPage(
          subject: TextbookSubject.math,
          navigationTitle: preview ? null : switcherFor(section),
          navigationToolbarHeight: toolbarHeight,
          showAppBar: !preview,
          bodySwipeWrapper: bodySwipeWrapper,
        ),
      };
      return TickerMode(
        enabled: preview || section == _section,
        child: preview || _visited.contains(section)
            ? page
            : const SizedBox.shrink(),
      );
    }

    final pageStorage = ref.watch(_mathPageStorageProvider(_profileId));
    WidgetBuilder sectionPreview(MathSection section) =>
        (_) => KeyedSubtree(
          key: ValueKey('math-section-preview-${section.name}'),
          child: PageStorage(
            bucket: pageStorage,
            child: sectionPage(section, preview: true),
          ),
        );
    return SwipeNavigationRegion(
      animateBodyOnly: true,
      transitionKey: _section,
      transitionDirection: _transitionDirection,
      onNext: _section == MathSection.practice
          ? () => unawaited(_select(MathSection.textbook))
          : null,
      nextPageBuilder: _section == MathSection.practice
          ? sectionPreview(MathSection.textbook)
          : null,
      onPrevious: _section == MathSection.textbook
          ? () => unawaited(_select(MathSection.practice))
          : null,
      previousPageBuilder: _section == MathSection.textbook
          ? sectionPreview(MathSection.practice)
          : null,
      child: PageStorage(
        bucket: pageStorage,
        child: IndexedStack(
          key: ValueKey(_profileId),
          index: _section.index,
          children: [
            for (final section in MathSection.values) sectionPage(section),
          ],
        ),
      ),
    );
  }
}
