import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
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
  const ChineseTabPage({super.key, this.section});

  final ChineseSection? section;

  @override
  ConsumerState<ChineseTabPage> createState() => _ChineseTabPageState();
}

class _ChineseTabPageState extends ConsumerState<ChineseTabPage> {
  late ChineseSection _section;
  late String _profileId;
  late final StreamSubscription<String> _profileSubscription;

  ChineseSection _savedSection() => ChineseSection.fromId(
        ref.read(settingsRepositoryProvider).chineseSection,
      )!;

  @override
  void initState() {
    super.initState();
    _profileId = ProfileScope.currentId;
    _section = widget.section ?? _savedSection();
    if (widget.section != null) unawaited(_rememberSection());
    _profileSubscription = ProfileScope.changes.listen((profileId) {
      if (!mounted) return;
      setState(() {
        _profileId = profileId;
        _section = _savedSection();
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
      _section = requested;
      unawaited(_rememberSection());
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
    if (_section == section) return;
    FocusScope.of(context).unfocus();
    setState(() => _section = section);
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
    final textbookCount = ref.watch(currentTextbooksProvider).length;
    final poemCount = ref.watch(filteredPoemsProvider).length;
    final expressionCount = ref.watch(pictureStoryPromptCountProvider);
    final labelStyle = Theme.of(context).textTheme.labelLarge!;
    final labelHeight =
        MediaQuery.textScalerOf(context).scale(labelStyle.fontSize!) *
            (labelStyle.height ?? 1);
    final toolbarHeight = math.max(
      kToolbarHeight,
      labelHeight + SpacingTokens.sm * 4,
    );
    final switcher = SegmentedButton<ChineseSection>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, SpacingTokens.xxl),
        padding: const EdgeInsets.all(SpacingTokens.sm),
      ),
      segments: [
        ButtonSegment(
          value: ChineseSection.textbook,
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('课本($textbookCount)', maxLines: 1),
          ),
        ),
        ButtonSegment(
          value: ChineseSection.expression,
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('表达($expressionCount)', maxLines: 1),
          ),
        ),
        ButtonSegment(
          value: ChineseSection.poem,
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('诗词($poemCount)', maxLines: 1),
          ),
        ),
      ],
      selected: {_section},
      onSelectionChanged: (selected) => _select(selected.single),
    );
    return PageStorage(
      bucket: ref.watch(_chinesePageStorageProvider(_profileId)),
      child: IndexedStack(
        key: ValueKey(_profileId),
        index: _section.index,
        children: [
          TickerMode(
            enabled: _section == ChineseSection.textbook,
            child: TextbookLearningPage(
              navigationTitle: switcher,
              navigationToolbarHeight: toolbarHeight,
            ),
          ),
          TickerMode(
            enabled: _section == ChineseSection.poem,
            child: PoemTabPage(
              navigationTitle: switcher,
              navigationToolbarHeight: toolbarHeight,
            ),
          ),
          TickerMode(
            enabled: _section == ChineseSection.expression,
            child: PictureStoryPage(
              navigationTitle: switcher,
              navigationToolbarHeight: toolbarHeight,
            ),
          ),
        ],
      ),
    );
  }
}
