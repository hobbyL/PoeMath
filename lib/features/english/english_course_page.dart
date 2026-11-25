import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/english/english_audio.dart';
import 'package:poemath/domain/english_course_parser.dart';
import 'package:poemath/features/english/english_providers.dart';
import 'package:poemath/features/english/english_widgets.dart';

class EnglishCoursePage extends ConsumerStatefulWidget {
  const EnglishCoursePage({
    super.key,
    required this.bookId,
    this.review = false,
  });
  final String bookId;
  final bool review;
  @override
  ConsumerState<EnglishCoursePage> createState() => _EnglishCoursePageState();
}

class _EnglishCoursePageState extends ConsumerState<EnglishCoursePage>
    with WidgetsBindingObserver {
  late final EnglishGenerationController _generation;
  final _profileRevision = ProfileScope.revision;
  @override
  void initState() {
    super.initState();
    _generation = ref.read(englishGenerationProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _generation.pause(widget.bookId);
  }

  @override
  void dispose() {
    _generation.pause(widget.bookId);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _generate(Textbook book, {bool refresh = false}) async {
    try {
      assertParentAccess(context);
      final authorized = ParentAccessService.instance.captureAuthorization();
      void check() {
        if (!mounted || ProfileScope.revision != _profileRevision) {
          throw StateError('学习档案已变化');
        }
        assertParentAccess(context);
        authorized();
        if (ref.read(englishBookProvider(widget.bookId)) == null) {
          throw StateError('课本已移除');
        }
      }

      await _generation.start(book, check, refresh: refresh);
    } on Object catch (e) {
      if (mounted) englishMessage(context, e);
    }
  }

  Future<void> _open(EnglishLesson lesson) async {
    _generation.pause(widget.bookId);
    await _generation.drain();
    if (!mounted) return;
    await context.push(
      AppRoutes.englishBookOf(
        widget.bookId,
        lesson: lesson.id,
        review: widget.review,
      ),
    );
    if (mounted) ref.invalidate(englishCourseProvider(widget.bookId));
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(englishBookProvider(widget.bookId));
    final progress = ref.watch(englishGenerationProvider)[widget.bookId];
    final course = ref.watch(englishCourseProvider(widget.bookId));
    final theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(title: Text(widget.review ? '英语整理与审核' : '全书课程')),
      body: SafeArea(
        top: false,
        child:
            widget.review &&
                book != null &&
                course.valueOrNull == null &&
                !course.hasError
            ? course.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox.expand()
            : EnglishCourseBody(
                bookId: widget.bookId,
                builder: (book, course) {
                  final groups = <String, List<EnglishLesson>>{};
                  for (final lesson in course.lessons) {
                    groups.putIfAbsent(lesson.unitId, () => []).add(lesson);
                  }
                  final last = ref
                      .watch(englishProgressProvider(widget.bookId))
                      ?.lastLessonId;
                  return ListView(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    children: [
                      if (!widget.review &&
                          last != null &&
                          course.lesson(last) != null)
                        AppTile(
                          icon: Icons.play_circle_outline,
                          iconColor: theme.colorScheme.primary,
                          title: '继续上次学习',
                          subtitle:
                              '${course.lesson(last)!.unitTitle} · ${course.lesson(last)!.title}',
                          onTap: () => _open(course.lesson(last)!),
                        ),
                      for (final group in groups.values) ...[
                        englishHeading(context, group.first.unitTitle),
                        AppTileGroup(
                          children: [
                            for (final lesson in group)
                              AppTile(
                                icon: widget.review
                                    ? Icons.fact_check_outlined
                                    : Icons.auto_stories_outlined,
                                iconColor: theme.colorScheme.primary,
                                title: lesson.title,
                                titleMaxLines: 2,
                                subtitle: widget.review
                                    ? 'PDF ${lesson.startPage}–${lesson.endPage} · 已核对 ${lesson.approvedCount}/${lesson.targets.length}${lesson.prepared ? '' : ' · 待整理'}${course.pending.any((l) => l.id == lesson.id) ? ' · 有新稿' : ''}'
                                    : 'PDF ${lesson.startPage}–${lesson.endPage} · ${lesson.availableCount} 项可学',
                                onTap: () => _open(lesson),
                              ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
      ),
      bottomNavigationBar: widget.review && book != null
          ? _actions(book, progress, theme)
          : null,
    );
  }

  Widget _actions(
    Textbook book,
    EnglishGenerationState? state,
    ThemeData theme,
  ) {
    final showMessage =
        state != null &&
        state.message.isNotEmpty &&
        !state.message.startsWith('已整理 ');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showMessage) ...[
              Text(
                state.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SpacingTokens.xs),
            ],
            if (state?.running == true) ...[
              LinearProgressIndicator(
                value: state!.total == 0 ? null : state.done / state.total,
              ),
              const SizedBox(height: SpacingTokens.sm),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, SpacingTokens.minTapTarget),
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.xs,
                      ),
                    ),
                    onPressed: state?.running == true
                        ? () => _generation.pause(widget.bookId)
                        : () => _generate(book),
                    icon: Icon(
                      state?.running == true ? Icons.pause : Icons.play_arrow,
                    ),
                    label: AutoFitLine(
                      child: Text(
                        state?.running == true ? '暂停整理' : '整理 / 继续',
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, SpacingTokens.minTapTarget),
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.xs,
                      ),
                    ),
                    onPressed: state?.running == true
                        ? null
                        : () => _generate(book, refresh: true),
                    icon: const Icon(Icons.refresh),
                    label: const AutoFitLine(
                      child: Text('重新提取候选稿', maxLines: 1),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const double _englishReviewPageCardMaxWidth = 560;
const double _englishReviewGridMaxWidth = 1200;
const double _englishReviewTargetMinColumnWidth = 280;

class EnglishLessonPage extends ConsumerStatefulWidget {
  const EnglishLessonPage({
    super.key,
    required this.bookId,
    required this.lessonId,
    this.review = false,
    this.sourceContent = false,
  });
  final String bookId, lessonId;
  final bool review, sourceContent;

  @override
  ConsumerState<EnglishLessonPage> createState() => _EnglishLessonPageState();
}

class _EnglishLessonPageState extends ConsumerState<EnglishLessonPage>
    with WidgetsBindingObserver {
  EnglishAudio? _audio;

  @override
  void initState() {
    super.initState();
    if (widget.sourceContent) {
      _audio = ref.read(englishAudioProvider(englishAudioKey(widget.bookId)));
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_audio?.stop());
  }

  @override
  void dispose() {
    if (_audio != null) {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(_audio!.stop());
    }
    super.dispose();
  }

  Future<void> _adopt(
    BuildContext context,
    WidgetRef ref,
    Textbook book,
    EnglishCourse course,
    EnglishLesson candidate,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('采用这个候选稿？'),
        content: const Text('本课当前内容会被候选稿替换，需重新核对。孩子过去的学习记录仍保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留当前稿'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('采用候选稿'),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    try {
      assertParentAccess(context);
      final authorized = ParentAccessService.instance.captureAuthorization();
      await ref
          .read(englishCourseRepositoryProvider)
          .saveLesson(
            book,
            candidate,
            expectedRevision: course.revision,
            adopt: true,
            check: () {
              assertParentAccess(context);
              authorized();
            },
          );
      ref.invalidate(englishCourseProvider(widget.bookId));
    } on Object catch (e) {
      if (context.mounted) englishMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookId = widget.bookId,
        lessonId = widget.lessonId,
        review = widget.review,
        sourceContent = widget.sourceContent;
    final theme = Theme.of(context);
    final currentLesson = ref
        .watch(englishCourseProvider(bookId))
        .valueOrNull
        ?.lesson(lessonId);
    return AppScaffold(
      appBar: AppBar(
        title: Text(
          (review || sourceContent) && currentLesson != null
              ? '${currentLesson.unitTitle} · ${currentLesson.title}'
              : sourceContent
              ? '学一学'
              : review
              ? '课时内容审核'
              : '课时学习',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (review)
            IconButton(
              tooltip: '补充内容',
              icon: const Icon(Icons.add),
              onPressed: currentLesson == null
                  ? null
                  : () => context.push(
                      AppRoutes.englishBookOf(
                        bookId,
                        lesson: lessonId,
                        target: 'new-${newEnglishId()}',
                        review: true,
                      ),
                    ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: EnglishCourseBody(
          bookId: bookId,
          builder: (book, course) {
            final lesson = course.lesson(lessonId);
            if (lesson == null) {
              return const AppEmptyState(
                icon: Icons.menu_book_outlined,
                title: '找不到这个课时',
              );
            }
            final candidate = course.pending
                .where((l) => l.id == lessonId)
                .firstOrNull;
            if (review || sourceContent) {
              return _reviewContent(
                context,
                ref,
                book,
                course,
                lesson,
                candidate,
                theme,
                readOnlyContent: sourceContent,
              );
            }
            return ListView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                Text(
                  '${lesson.unitTitle} · ${lesson.title}',
                  style: theme.textTheme.headlineSmall,
                ),
                Text(
                  'PDF ${lesson.startPage}–${lesson.endPage} · ${lesson.availableCount} 项可学',
                ),
                const SizedBox(height: SpacingTokens.md),
                Wrap(
                  spacing: SpacingTokens.sm,
                  runSpacing: SpacingTokens.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => context.push(
                        AppRoutes.englishBookOf(bookId, page: lesson.startPage),
                      ),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('看原书'),
                    ),
                    FilledButton(
                      onPressed: () => context.push(
                        AppRoutes.englishBookOf(
                          bookId,
                          action: 'practice',
                          lesson: lessonId,
                        ),
                      ),
                      child: const Text('练一练'),
                    ),
                  ],
                ),
                AppTileGroup(
                  children: [
                    for (final kind in EnglishTargetKind.values)
                      if (lesson.targets.any(
                        (t) => t.kind == kind && t.isAvailableForChild,
                      ))
                        AppTile(
                          icon: kind == EnglishTargetKind.letter
                              ? Icons.abc
                              : Icons.auto_stories_outlined,
                          iconColor: theme.colorScheme.primary,
                          title: kind.label,
                          subtitle:
                              '${lesson.targets.where((t) => t.kind == kind && t.isAvailableForChild).length} 项可学',
                          onTap: () => context.push(
                            AppRoutes.englishBookOf(
                              bookId,
                              lesson: lessonId,
                              action: 'study',
                              kind: kind.name,
                            ),
                          ),
                        ),
                    if (lesson.targets.any((t) => t.approved && t.hasSpeech))
                      AppTile(
                        icon: Icons.mic_none,
                        iconColor: theme.colorScheme.primary,
                        title: '跟读与回听',
                        subtitle: '逐句跟读并保存录音',
                        onTap: () => context.push(
                          AppRoutes.englishBookOf(
                            bookId,
                            lesson: lessonId,
                            action: 'speaking',
                          ),
                        ),
                      ),
                  ],
                ),
                if (lesson.availableCount == 0)
                  const AppEmptyState(
                    icon: Icons.pending_actions,
                    title: '本课还没有可学习的内容',
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _reviewContent(
    BuildContext context,
    WidgetRef ref,
    Textbook book,
    EnglishCourse course,
    EnglishLesson lesson,
    EnglishLesson? candidate,
    ThemeData theme, {
    bool readOnlyContent = false,
  }) {
    final bookId = widget.bookId, lessonId = widget.lessonId;
    final pageImage = ref.watch(englishReviewPageImageBuilderProvider);
    final audio = readOnlyContent
        ? ref.watch(englishAudioProvider(englishAudioKey(widget.bookId)))
        : null;
    final voice = readOnlyContent ? ref.watch(englishVoiceProvider) : null;
    final cardNumbers =
        ref
            .watch(englishTargetCardNumberProvider((bookId, lessonId)))
            .valueOrNull ??
        const <String, int>{};
    final pageNumbers = <int>{
      for (var page = lesson.startPage; page <= lesson.endPage; page++) page,
    };
    final learnableVocabulary = readOnlyContent
        ? lesson.targets
              .where((target) => target.isLearnableVocabulary)
              .toList()
        : const <EnglishTarget>[];
    final targetsByPage = <int, List<EnglishTarget>>{};
    final sourceByTarget = <String, EnglishSource>{};
    final originalOrder = {
      for (final (index, target) in lesson.targets.indexed) target.id: index,
    };
    for (final target in lesson.targets) {
      if (readOnlyContent &&
          !target.isAvailableForChild &&
          target.kind != EnglishTargetKind.sentence) {
        continue;
      }
      final lessonSources = target.sources
          .where((value) => lesson.containsPage(value.page))
          .toList();
      final sourcePage =
          lessonSources.firstOrNull?.page ?? target.sources.first.page;
      final pageSources = target.sources
          .where((value) => value.page == sourcePage)
          .toList();
      final source = EnglishSource(
        sourcePage,
        printedPage: pageSources.first.printedPage,
        left: pageSources.map((value) => value.left).reduce(math.min),
        top: pageSources.map((value) => value.top).reduce(math.min),
        right: pageSources.map((value) => value.right).reduce(math.max),
        bottom: pageSources.map((value) => value.bottom).reduce(math.max),
      );
      sourceByTarget[target.id] = source;
      pageNumbers.add(source.page);
      targetsByPage.putIfAbsent(source.page, () => []).add(target);
    }
    for (final targets in targetsByPage.values) {
      final cardGroups = <int, List<EnglishTarget>>{};
      final unnumbered = <EnglishTarget>[];
      for (final target in targets) {
        final cardNumber = cardNumbers[target.id];
        if (cardNumber == null) {
          unnumbered.add(target);
        } else {
          cardGroups.putIfAbsent(cardNumber, () => []).add(target);
        }
      }

      final ordered = <EnglishTarget>[
        ...englishTargetsInSourceRowOrder(
          unnumbered,
          sourceByTarget,
          originalOrder: originalOrder,
        ),
        for (final card in cardGroups.keys.toList()..sort())
          ...englishTargetsInSourceRowOrder(
            cardGroups[card]!,
            sourceByTarget,
            originalOrder: originalOrder,
          ),
      ];
      targets
        ..clear()
        ..addAll(ordered);
    }
    final pages = pageNumbers.toList()..sort();
    return SingleChildScrollView(
      key: PageStorageKey(
        '${readOnlyContent ? 'english-study-source' : 'english-review'}-$bookId-$lessonId',
      ),
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (learnableVocabulary.isNotEmpty) ...[
            AppTileGroup(
              children: [
                AppTile(
                  key: const ValueKey('english-vocabulary-entry'),
                  icon: Icons.abc,
                  iconColor: theme.colorScheme.primary,
                  title: '单词与短语',
                  subtitle: '${learnableVocabulary.length} 项可学',
                  onTap: () => context.push(
                    AppRoutes.englishBookOf(
                      bookId,
                      lesson: lessonId,
                      action: 'study',
                      kind: EnglishTargetKind.vocabulary.name,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.md),
          ],
          LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: math.min(
                  constraints.maxWidth,
                  _englishReviewGridMaxWidth,
                ),
                child: ResponsiveCardGrid(
                  preferredTileWidth: 360,
                  children: [
                    for (final page in pages)
                      LayoutBuilder(
                        builder: (context, constraints) => Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: math.min(
                              constraints.maxWidth,
                              _englishReviewPageCardMaxWidth,
                            ),
                            child: ColoredCard(
                              key: ValueKey(
                                '${readOnlyContent ? 'english-study' : 'english-review'}-source-$page',
                              ),
                              color: theme.colorScheme.primary,
                              padding: EdgeInsets.zero,
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  pageImage(book, page),
                                  if (targetsByPage[page]
                                      case final pageTargets?)
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final textScale =
                                            MediaQuery.textScalerOf(context)
                                                .scale(16) /
                                            16;
                                        final columns = math.min(
                                          (constraints.maxWidth /
                                                  (_englishReviewTargetMinColumnWidth *
                                                      textScale))
                                              .floor()
                                              .clamp(1, 3),
                                          pageTargets.length,
                                        );
                                        return Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (
                                              var row = 0;
                                              row < pageTargets.length;
                                              row += columns
                                            ) ...[
                                              if (row > 0)
                                                const Divider(height: 0),
                                              IntrinsicHeight(
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    for (
                                                      var column = 0;
                                                      column < columns;
                                                      column++
                                                    ) ...[
                                                      if (column > 0)
                                                        const VerticalDivider(
                                                          width: 0,
                                                        ),
                                                      Expanded(
                                                        child:
                                                            row + column >=
                                                                pageTargets
                                                                    .length
                                                            ? const SizedBox.shrink()
                                                            : _reviewTargetTile(
                                                                context,
                                                                pageTargets[row +
                                                                    column],
                                                                row + column,
                                                                theme,
                                                                readOnlyContent:
                                                                    readOnlyContent,
                                                                audio: audio,
                                                                voice: voice,
                                                              ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (readOnlyContent &&
              !lesson.targets.any(
                (target) =>
                    target.isAvailableForChild ||
                    target.kind == EnglishTargetKind.sentence,
              ))
            const AppEmptyState(
              icon: Icons.pending_actions,
              title: '本课还没有开放学习的内容',
              description: '待家长核对后，这里会显示原书图文。',
            ),
          if (!readOnlyContent)
            if (candidate case final candidateLesson?) ...[
              const SizedBox(height: SpacingTokens.md),
              ColoredCard(
                color: theme.colorScheme.secondary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前 ${lesson.targets.length} 项 / 候选 ${candidateLesson.targets.length} 项',
                    ),
                    ExpansionTile(
                      title: const Text('对照候选内容'),
                      children: [
                        for (final target in candidateLesson.targets)
                          Padding(
                            padding: const EdgeInsets.all(SpacingTokens.sm),
                            child: Text(
                              '${target.kind.label} · ${target.text}\n${target.meaning}',
                            ),
                          ),
                      ],
                    ),
                    TextButton(
                      onPressed: () =>
                          _adopt(context, ref, book, course, candidateLesson),
                      child: const Text('采用此候选稿'),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _reviewTargetTile(
    BuildContext context,
    EnglishTarget target,
    int index,
    ThemeData theme, {
    bool readOnlyContent = false,
    EnglishAudio? audio,
    Map<String, String>? voice,
  }) => AppTile(
    flat: true,
    icon: readOnlyContent && target.kind == EnglishTargetKind.sentence
        ? Icons.volume_up_outlined
        : readOnlyContent
        ? Icons.auto_stories_outlined
        : target.approved
        ? Icons.check_circle_outline
        : Icons.edit_note,
    iconColor: theme.colorScheme.primary,
    title: '${index + 1}. ${target.text}',
    titleWrap: true,
    subtitle: [
      target.kind.label,
      if (target.meaning.isNotEmpty) target.meaning,
      if (!readOnlyContent) target.approved ? '已核对' : '待核对',
    ].join(' · '),
    subtitleMaxLines: 3,
    onTap: readOnlyContent
        ? target.kind == EnglishTargetKind.sentence &&
                  target.hasSpeech &&
                  audio != null
              ? () => unawaited(
                  _speakSentence(context, audio, voice, target.text),
                )
              : null
        : () => context.push(
            AppRoutes.englishBookOf(
              widget.bookId,
              lesson: widget.lessonId,
              target: target.id,
              review: true,
            ),
          ),
  );

  Future<void> _speakSentence(
    BuildContext context,
    EnglishAudio audio,
    Map<String, String>? voice,
    String text,
  ) async {
    final played = await audio.speak(text, voice);
    if (!played && !audio.busy && context.mounted && audio.message.isNotEmpty) {
      englishMessage(context, StateError(audio.message));
    }
  }
}
