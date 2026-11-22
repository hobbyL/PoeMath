import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/math_textbook_progress.dart';
import 'package:poemath/domain/math_textbook_practice.dart';
import 'package:poemath/domain/math_textbook_course_plan.dart';
import 'package:poemath/domain/math_textbook_content_organizer.dart';
import 'package:poemath/domain/math_textbook_study.dart';
import 'package:poemath/domain/math_textbook_knowledge_illustrations.dart';
import 'package:poemath/features/textbook/math_textbook_labels.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_reader_page.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_study_content.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_knowledge_images.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_view.dart';

class MathTextbookBookPage extends ConsumerWidget {
  const MathTextbookBookPage({
    super.key,
    required this.bookId,
    this.mode,
    this.currentPages,
  });
  final String bookId;
  final String? mode;
  final List<int>? currentPages;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(mathTextbookProfileProvider);
    final catalog = ref.watch(textbookCatalogProvider);
    final book = ref
        .watch(textbookLocalListProvider)
        .where(
          (b) => b.pdfSha256 == bookId && b.subject == TextbookSubject.math,
        )
        .firstOrNull;
    return AppScaffold(
      backgroundScene: PineInkScene.study,
      appBar: AppBar(
        title: Text(_modeLabel(mode) ?? '数学课本'),
        actions: [
          IconButton(
            tooltip: '本书学习记录',
            icon: const Icon(Icons.history_outlined),
            onPressed: book == null
                ? null
                : () => context.push(AppRoutes.mathTextbookHistoryOf(bookId)),
          ),
        ],
      ),
      body: SafeArea(
        child: book == null
            ? const AppEmptyState(
                icon: Icons.menu_book_outlined,
                title: '本书已移除',
                description: '请返回数学课本重新选择。',
              )
            : ref
                  .watch(mathTextbookCourseProvider(bookId))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => AppEmptyState(
                      icon: Icons.error_outline,
                      title: '课时暂时无法读取',
                      description: mathTextbookDisplayError(error, '请稍后重试。'),
                      actions: [
                        TextButton(
                          onPressed: () => ref.invalidate(
                            mathTextbookCourseProvider(bookId),
                          ),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                    data: (course) {
                      final entry = catalog.valueOrNull
                          ?.where((value) => value.book.pdfSha256 == bookId)
                          .firstOrNull;
                      if (course == null && catalog.isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (course == null &&
                          entry?.supportsMathCourseGeneration == false) {
                        return AppEmptyState(
                          icon: Icons.menu_book_outlined,
                          title: '课时学习暂未开放',
                          description: '当前版本暂时只支持原书阅读，课时内容尚未开放。',
                          actions: [
                            TextButton.icon(
                              onPressed: () => context.push(
                                AppRoutes.textbookReadOf(bookId),
                              ),
                              icon: const Icon(Icons.menu_book_outlined),
                              label: const Text('阅读原书'),
                            ),
                          ],
                        );
                      }
                      return ref
                          .watch(mathTextbookBookLearningProvider(bookId))
                          .when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (error, _) => AppEmptyState(
                              icon: Icons.error_outline,
                              title: '学习记录暂时无法读取',
                              description: mathTextbookDisplayError(
                                error,
                                '请稍后重试。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => ref.invalidate(
                                    mathTextbookProgressProvider(bookId),
                                  ),
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                            data: (snapshot) => _content(
                              context,
                              snapshot.course,
                              snapshot.lessons,
                              mode: mode,
                              currentPages: currentPages,
                            ),
                          );
                    },
                  ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    MathTextbookCourse? course,
    Map<String, MathTextbookLessonProgress> summaries, {
    String? mode,
    List<int>? currentPages,
  }) {
    final selectedMode = _validMode(mode);
    final color = Theme.of(context).colorScheme.primary;
    final unconfirmedPurposeLessonIds = {
      for (final range
          in course?.outline?.ranges ?? const <MathTextbookCourseRange>[])
        if (range.needsAlignment && range.title.endsWith('（待确认用途）'))
          range.lessonId,
    };
    final lessons = [...?course?.currentLessons]
      ..removeWhere((lesson) => unconfirmedPurposeLessonIds.contains(lesson.id))
      ..sort((a, b) => a.startPage.compareTo(b.startPage));
    // 页码只用于定位课时；同一课时的任意页共享完整的知识点和练习。
    final pageLessons = currentPages == null
        ? lessons
        : lessons
              .where(
                (lesson) => currentPages.any(
                  (page) => page >= lesson.startPage && page <= lesson.endPage,
                ),
              )
              .toList();
    final needsCourseUpdate =
        course?.outline != null &&
        course!.outline!.organizationVersion < mathTextbookOrganizationVersion;
    final lessonGroups = <({String unit, List<MathTextbookLesson> lessons})>[];
    var previousUnit = '';
    for (var index = 0; index < lessons.length; index++) {
      final lesson = lessons[index];
      final unit = lesson.learning?.unitTitle ?? '';
      final unitChanged = index == 0 || unit != previousUnit;
      final heading = unitChanged && unit.isNotEmpty && unit != lesson.title
          ? unit
          : '';
      if (lessonGroups.isEmpty ||
          heading.isNotEmpty ||
          unitChanged && lessonGroups.last.unit.isNotEmpty) {
        lessonGroups.add((unit: heading, lessons: <MathTextbookLesson>[]));
      }
      lessonGroups.last.lessons.add(lesson);
      previousUnit = unit;
    }
    final knowledgeEntries = [
      for (final lesson in pageLessons)
        for (final point in mathTextbookStudyNotes(lesson))
          (lesson: lesson, point: point),
    ];
    final exampleEntries = [
      for (final lesson in pageLessons)
        for (final example in mathTextbookWorkedExamples(lesson))
          (lesson: lesson, example: example),
    ];
    final practiceEntries =
        <
          ({
            MathTextbookLesson lesson,
            String title,
            String subtitle,
            IconData icon,
            String? planId,
            bool original,
            bool enabled,
          })
        >[];
    for (final lesson in pageLessons) {
      final learning = lesson.learning;
      if (learning == null) continue;
      final availability = mathTextbookPracticeAvailability(lesson, bookId);
      final summary = summaries[lesson.id]!;
      if (!learning.noExercises && learning.exercises.isNotEmpty) {
        final subtitle = availability.exerciseIds.isEmpty
            ? '${lesson.title} · 原书题目，可按纸上练习完成'
            : availability.exerciseIds.length < learning.exercises.length
            ? '${lesson.title} · ${availability.exerciseIds.length}/${learning.exercises.length} 组可练'
            : '${lesson.title} · 已通过 ${summary.originalPassed}/${summary.originalTotal} 组';
        practiceEntries.add((
          lesson: lesson,
          title: '教材原题',
          subtitle: subtitle,
          icon: Icons.edit_note_outlined,
          planId: null,
          original: true,
          enabled: true,
        ));
      }
      for (final plan in learning.practicePlans) {
        final enabled = availability.planIds.contains(plan.id);
        final detail = !enabled
            ? '答案与练习范围待核对'
            : plan.kind == MathTextbookPracticeKind.parentTask
            ? mathTextbookPaperTaskInstruction(plan.task, previewVisible: false)
            : '${mathTextbookPracticeLabel(plan.kind)} · ${plan.count} 题';
        practiceEntries.add((
          lesson: lesson,
          title: plan.title,
          subtitle: '${lesson.title} · $detail',
          icon: Icons.fitness_center_outlined,
          planId: plan.id,
          original: false,
          enabled: enabled,
        ));
      }
    }
    final hasModeContent = switch (selectedMode) {
      AppRoutes.mathTextbookLearnMode =>
        knowledgeEntries.isNotEmpty || exampleEntries.isNotEmpty,
      AppRoutes.mathTextbookPracticeMode => practiceEntries.isNotEmpty,
      _ => lessons.isNotEmpty,
    };
    final showIntro = !hasModeContent || needsCourseUpdate;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ResponsiveLayout.columns(constraints.maxWidth);
        final modeSlivers = <Widget>[];
        if (selectedMode == AppRoutes.mathTextbookLearnMode && hasModeContent) {
          modeSlivers.add(
            SliverPadding(
              padding: const EdgeInsets.only(
                top: SpacingTokens.md,
                bottom: SpacingTokens.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: MasonryLayout(
                  key: const ValueKey('math-textbook-knowledge-masonry'),
                  columnCount: columns,
                  gap: SpacingTokens.sm,
                  children: [
                    for (final entry in knowledgeEntries)
                      AppTile(
                        icon: Icons.lightbulb_outline,
                        iconColor: color,
                        title: entry.point.title,
                        titleMaxLines: 2,
                        subtitle:
                            '${entry.lesson.title} · ${entry.point.summary}',
                        subtitleMaxLines: 3,
                        onTap: () => context.push(
                          AppRoutes.mathTextbookStudyOf(
                            bookId,
                            entry.lesson.id,
                            mode: AppRoutes.mathTextbookLearnMode,
                            knowledgePointId: entry.point.id,
                          ),
                        ),
                      ),
                    for (final entry in exampleEntries)
                      AppTile(
                        icon: Icons.menu_book_outlined,
                        iconColor: color,
                        title: entry.example.title,
                        titleMaxLines: 2,
                        subtitle: '例题与解题过程',
                        onTap: () => context.push(
                          AppRoutes.mathTextbookStudyOf(
                            bookId,
                            entry.lesson.id,
                            mode: AppRoutes.mathTextbookLearnMode,
                            exampleId: entry.example.id,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        } else if (selectedMode == AppRoutes.mathTextbookPracticeMode &&
            practiceEntries.isNotEmpty) {
          modeSlivers.add(
            SliverPadding(
              padding: const EdgeInsets.only(
                top: SpacingTokens.md,
                bottom: SpacingTokens.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: MasonryLayout(
                  key: const ValueKey('math-textbook-practice-masonry'),
                  columnCount: columns,
                  gap: SpacingTokens.sm,
                  children: [
                    for (final entry in practiceEntries)
                      AppTile(
                        icon: entry.icon,
                        iconColor: color,
                        title: entry.title,
                        titleMaxLines: 2,
                        subtitle: entry.subtitle,
                        subtitleMaxLines: 3,
                        onTap: !entry.enabled
                            ? null
                            : entry.original &&
                                  mathTextbookPracticeAvailability(
                                    entry.lesson,
                                    bookId,
                                  ).exerciseIds.isEmpty
                            ? () => context.push(
                                AppRoutes.mathTextbookStudyOf(
                                  bookId,
                                  entry.lesson.id,
                                  mode: AppRoutes.mathTextbookReadMode,
                                ),
                              )
                            : () => context.push(
                                AppRoutes.mathTextbookPracticeOf(
                                  bookId,
                                  entry.lesson.id,
                                  planId: entry.planId,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          );
        } else if (selectedMode != AppRoutes.mathTextbookLearnMode &&
            selectedMode != AppRoutes.mathTextbookPracticeMode) {
          for (final group in lessonGroups) {
            if (group.unit.isNotEmpty) {
              modeSlivers.add(
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SpacingTokens.md,
                    ),
                    child: Text(
                      group.unit,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              );
            }
            modeSlivers.add(
              SliverPadding(
                padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
                sliver: SliverCardGrid(
                  columnCount: columns,
                  itemCount: group.lessons.length,
                  itemBuilder: (context, index) {
                    final lesson = group.lessons[index];
                    final summary = summaries[lesson.id]!;
                    return AppTile(
                      icon: selectedMode == AppRoutes.mathTextbookReadMode
                          ? summary.read
                                ? Icons.check_circle_outline
                                : Icons.auto_stories_outlined
                          : summary.complete
                          ? Icons.check_circle_outline
                          : Icons.school_outlined,
                      iconColor: color,
                      title: lesson.title,
                      subtitle: selectedMode == AppRoutes.mathTextbookReadMode
                          ? summary.read
                                ? '本课已读'
                                : '按课时顺序阅读'
                          : summary.label,
                      onTap: () => context.push(
                        AppRoutes.mathTextbookStudyOf(
                          bookId,
                          lesson.id,
                          mode: selectedMode,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          }
        }
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md,
                0,
                SpacingTokens.md,
                SpacingTokens.md,
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  if (showIntro)
                    SliverPadding(
                      padding: EdgeInsets.only(
                        bottom: lessons.isEmpty ? 0 : SpacingTokens.sm,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (needsCourseUpdate)
                              AppTile(
                                icon: Icons.auto_stories_outlined,
                                iconColor: color,
                                title: '更新课时内容',
                                subtitle: '按讲解、例题和练习重新整理',
                                onTap: () => context.push(
                                  AppRoutes.mathTextbookReviewOf(bookId),
                                ),
                              ),
                            if (!hasModeContent) ...[
                              const SizedBox(height: SpacingTokens.md),
                              Text(
                                currentPages != null && pageLessons.isEmpty
                                    ? '当前页尚未关联课时。'
                                    : switch (selectedMode) {
                                        AppRoutes.mathTextbookLearnMode =>
                                          currentPages == null
                                              ? '本书尚未整理知识点与例题。'
                                              : '本课时尚未整理知识点与例题。',
                                        AppRoutes.mathTextbookPracticeMode =>
                                          currentPages == null
                                              ? '本书尚未整理练习。'
                                              : '本课时尚未整理练习。',
                                        _ => '还没有整理的课时。',
                                      },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: SpacingTokens.md,
                                ),
                                child: OutlinedButton(
                                  onPressed: () => context.push(
                                    AppRoutes.mathTextbookReviewOf(bookId),
                                  ),
                                  child: const Text('整理教材内容'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ...modeSlivers,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String? _validMode(String? mode) => switch (mode) {
    AppRoutes.mathTextbookReadMode ||
    AppRoutes.mathTextbookLearnMode ||
    AppRoutes.mathTextbookPracticeMode => mode,
    _ => null,
  };

  static String? _modeLabel(String? mode) => switch (_validMode(mode)) {
    AppRoutes.mathTextbookReadMode => '看一看',
    AppRoutes.mathTextbookLearnMode => '学一学',
    AppRoutes.mathTextbookPracticeMode => '做一做',
    _ => null,
  };
}

class _MathTextbookKnowledgePage extends StatelessWidget {
  const _MathTextbookKnowledgePage({
    required this.book,
    required this.lesson,
    required this.onRead,
    required this.onKnowledge,
  });

  final Textbook book;
  final MathTextbookLesson lesson;
  final VoidCallback onRead;
  final ValueChanged<MathTextbookKnowledgePoint> onKnowledge;

  @override
  Widget build(BuildContext context) {
    final points = mathTextbookStudyNotes(lesson);
    final examples = mathTextbookWorkedExamples(lesson);
    return AppScaffold(
      backgroundScene: PineInkScene.study,
      appBar: AppBar(title: Text(lesson.title)),
      body: SafeArea(
        child: points.isEmpty && examples.isEmpty
            ? AppEmptyState(
                icon: Icons.lightbulb_outline,
                title: '本课暂无知识点与例题',
                description: '可以先看一看本课完整内容。',
                actions: [
                  TextButton.icon(
                    onPressed: onRead,
                    icon: const Icon(Icons.auto_stories_outlined),
                    label: const Text('看一看本课内容'),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(SpacingTokens.md),
                itemCount: points.length + examples.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: SpacingTokens.sm),
                itemBuilder: (context, index) {
                  if (index >= points.length) {
                    final example = examples[index - points.length];
                    return AppTile(
                      icon: Icons.menu_book_outlined,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: example.title,
                      titleMaxLines: 2,
                      subtitle: '例题与解题过程',
                      onTap: () => context.push(
                        AppRoutes.mathTextbookStudyOf(
                          book.pdfSha256,
                          lesson.id,
                          mode: AppRoutes.mathTextbookLearnMode,
                          exampleId: example.id,
                        ),
                      ),
                    );
                  }
                  final point = points[index];
                  return AppTile(
                    icon: Icons.lightbulb_outline,
                    iconColor: Theme.of(context).colorScheme.primary,
                    title: point.title,
                    titleMaxLines: 2,
                    subtitle: point.summary,
                    subtitleMaxLines: 3,
                    onTap: () => onKnowledge(point),
                  );
                },
              ),
      ),
    );
  }
}

class MathTextbookKnowledgeNotesPage extends StatelessWidget {
  const MathTextbookKnowledgeNotesPage({
    super.key,
    required this.point,
    required this.book,
    required this.lesson,
  });
  final MathTextbookKnowledgePoint point;
  final Textbook book;
  final MathTextbookLesson lesson;

  @override
  Widget build(BuildContext context) {
    final blocks = mathTextbookKnowledgeImageBlocks(lesson, point);
    return AppScaffold(
      backgroundScene: PineInkScene.study,
      appBar: AppBar(title: Text(point.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  point.summary,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (blocks.isNotEmpty)
                  MathTextbookKnowledgeImages(
                    book: book,
                    point: point,
                    blocks: blocks,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MathTextbookPracticeOverviewPage extends ConsumerWidget {
  const _MathTextbookPracticeOverviewPage({
    required this.book,
    required this.lesson,
    required this.summary,
    required this.availability,
    required this.onRead,
    required this.onOriginal,
    required this.onPlan,
    required this.onConfigure,
    required this.onHistory,
  });

  final Textbook book;
  final MathTextbookLesson lesson;
  final MathTextbookLessonProgress summary;
  final MathTextbookPracticeAvailability availability;
  final VoidCallback onRead, onOriginal, onConfigure, onHistory;
  final ValueChanged<MathTextbookPracticePlan> onPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final learning = lesson.learning;
    final plans = learning?.practicePlans ?? <MathTextbookPracticePlan>[];
    final latestProgress = ref
        .watch(mathTextbookProgressProvider(book.pdfSha256))
        .valueOrNull;
    final currentSummary = latestProgress == null
        ? summary
        : mathTextbookLessonProgress(
            lesson,
            book.pdfSha256,
            latestProgress,
            availability: availability,
          );
    final hasOriginal =
        learning != null &&
        !learning.noExercises &&
        learning.exercises.isNotEmpty;
    if (!hasOriginal && plans.isEmpty) {
      return AppScaffold(
        backgroundScene: PineInkScene.study,
        appBar: AppBar(title: Text(lesson.title)),
        body: SafeArea(
          child: AppEmptyState(
            icon: Icons.edit_note_outlined,
            title: '本课暂无练习',
            description: '可以先看一看本课完整内容。',
            actions: [
              TextButton.icon(
                onPressed: onRead,
                icon: const Icon(Icons.auto_stories_outlined),
                label: const Text('看一看本课内容'),
              ),
            ],
          ),
        ),
      );
    }
    return AppScaffold(
      backgroundScene: PineInkScene.study,
      appBar: AppBar(title: Text(lesson.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            if (hasOriginal)
              AppTile(
                icon: Icons.edit_note_outlined,
                iconColor: Theme.of(context).colorScheme.primary,
                title: '教材原题',
                subtitle: learning.noExercises
                    ? '原书本课没有独立习题'
                    : availability.exerciseIds.length <
                          learning.exercises.length
                    ? '共 ${learning.exercises.length} 组 · 可练 ${availability.exerciseIds.length} 组纸上题'
                    : '共 ${learning.exercises.length} 组 · 已通过 ${currentSummary.originalPassed} 组',
                onTap: onOriginal,
              ),
            if (plans.isNotEmpty) ...[
              if (hasOriginal) const SizedBox(height: SpacingTokens.lg),
              Text('本课巩固', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: SpacingTokens.sm),
              for (final plan in plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
                  child: AppTile(
                    icon: Icons.fitness_center_outlined,
                    iconColor: Theme.of(context).colorScheme.primary,
                    title: plan.title,
                    subtitle: availability.planIds.contains(plan.id)
                        ? plan.kind == MathTextbookPracticeKind.parentTask
                              ? mathTextbookPaperTaskInstruction(
                                  plan.task,
                                  previewVisible: false,
                                )
                              : '${mathTextbookPracticeLabel(plan.kind)} · ${plan.count} 题'
                        : '答案与练习范围待核对',
                    subtitleMaxLines: 3,
                    onTap: availability.planIds.contains(plan.id)
                        ? () => onPlan(plan)
                        : null,
                  ),
                ),
            ],
            if (learning != null &&
                (availability.exerciseIds.length < learning.exercises.length ||
                    availability.planIds.length <
                        learning.practicePlans.length))
              TextButton(onPressed: onConfigure, child: const Text('配置本课自动练习')),
            TextButton(onPressed: onHistory, child: const Text('查看作答记录与待核对项')),
          ],
        ),
      ),
    );
  }
}

class MathTextbookStudyPage extends ConsumerStatefulWidget {
  const MathTextbookStudyPage({
    super.key,
    required this.bookId,
    required this.lessonId,
    this.mode,
    this.knowledgePointId,
    this.exampleId,
    this.viewerBuilder,
  });
  final String bookId, lessonId;
  final String? mode;
  final String? knowledgePointId;
  final String? exampleId;
  final TextbookViewerBuilder? viewerBuilder;
  @override
  ConsumerState<MathTextbookStudyPage> createState() =>
      _MathTextbookStudyPageState();
}

class _MathTextbookStudyPageState extends ConsumerState<MathTextbookStudyPage> {
  final int _profileRevision = ProfileScope.revision;
  bool _saving = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final book = ref
        .watch(textbookLocalListProvider)
        .where(
          (b) =>
              b.pdfSha256 == widget.bookId && b.subject == TextbookSubject.math,
        )
        .firstOrNull;
    final courseState = ref.watch(mathTextbookCourseProvider(widget.bookId));
    final lesson = courseState.valueOrNull?.currentLessons
        .where((lesson) => lesson.id == widget.lessonId)
        .firstOrNull;
    if (book == null) {
      return _statusPage(
        '本课学习',
        const AppEmptyState(
          icon: Icons.menu_book_outlined,
          title: '本书已移除',
          description: '请返回课本重新选择。',
        ),
      );
    }
    return courseState.when(
      loading: () => _statusPage(
        lesson?.title ?? '本课学习',
        const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _statusPage(
        lesson?.title ?? '本课学习',
        AppEmptyState(
          icon: Icons.error_outline,
          title: '课时暂时无法读取',
          description: mathTextbookDisplayError(error, '请返回重试。'),
        ),
      ),
      data: (course) {
        final selectedLesson = course?.currentLessons
            .where((value) => value.id == widget.lessonId)
            .firstOrNull;
        if (selectedLesson == null) {
          return _statusPage(
            '本课学习',
            const AppEmptyState(
              icon: Icons.school_outlined,
              title: '课时已更新',
              description: '请返回本书重新选择。',
            ),
          );
        }
        return ref
            .watch(mathTextbookProgressProvider(widget.bookId))
            .when(
              loading: () => _statusPage(
                selectedLesson.title,
                const Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _statusPage(
                selectedLesson.title,
                AppEmptyState(
                  icon: Icons.error_outline,
                  title: '学习记录暂时无法读取',
                  description: mathTextbookDisplayError(error, '请返回重试。'),
                ),
              ),
              data: (progress) => _pageForMode(
                book,
                selectedLesson,
                progress ??
                    MathTextbookProgress(
                      profileId: ProfileScope.currentId,
                      bookId: book.pdfSha256,
                      editionId: book.learningEditionId,
                    ),
              ),
            );
      },
    );
  }

  Widget _statusPage(String title, Widget body) => AppScaffold(
    backgroundScene: PineInkScene.study,
    appBar: AppBar(title: Text(title)),
    body: SafeArea(child: body),
  );

  Widget _pageForMode(
    Textbook book,
    MathTextbookLesson lesson,
    MathTextbookProgress progress,
  ) {
    if (widget.exampleId != null) {
      final example = mathTextbookWorkedExamples(lesson)
          .where((value) => value.id == widget.exampleId)
          .firstOrNull;
      if (example == null) {
        return _statusPage(
          lesson.title,
          const AppEmptyState(
            icon: Icons.menu_book_outlined,
            title: '例题已更新',
            description: '请返回本课重新选择。',
          ),
        );
      }
      return MathTextbookSourceContentPage(
        book: book,
        title: example.title,
        blocks: example.blocks,
        workedExample: true,
      );
    }
    final availability = mathTextbookPracticeAvailability(
      lesson,
      book.pdfSha256,
    );
    final summary = mathTextbookLessonProgress(
      lesson,
      book.pdfSha256,
      progress,
      availability: availability,
    );
    return switch (widget.mode) {
      AppRoutes.mathTextbookReadMode => _reader(book, lesson, summary),
      AppRoutes.mathTextbookLearnMode => _knowledgePage(book, lesson),
      AppRoutes.mathTextbookPracticeMode => _MathTextbookPracticeOverviewPage(
        book: book,
        lesson: lesson,
        summary: summary,
        availability: availability,
        onRead: () => _openOriginalLesson(book, lesson),
        onOriginal: () {
          if (availability.exerciseIds.isEmpty) {
            _openOriginalLesson(book, lesson);
          } else {
            context.push(
              AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id),
            );
          }
        },
        onPlan: (plan) => context.push(
          AppRoutes.mathTextbookPracticeOf(
            book.pdfSha256,
            lesson.id,
            planId: plan.id,
          ),
        ),
        onConfigure: () => context.push(
          AppRoutes.mathTextbookLessonOf(book.pdfSha256, lesson.id),
        ),
        onHistory: () =>
            context.push(AppRoutes.mathTextbookHistoryOf(book.pdfSha256)),
      ),
      _ => AppScaffold(
        backgroundScene: PineInkScene.study,
        appBar: AppBar(title: Text(lesson.title)),
        body: SafeArea(child: _content(book, lesson, progress)),
      ),
    };
  }

  Widget _reader(
    Textbook book,
    MathTextbookLesson lesson,
    MathTextbookLessonProgress summary,
  ) => TextbookReaderPage(
    bookId: book.pdfSha256,
    initialPage: lesson.startPage,
    title: lesson.title,
    viewerBuilder: widget.viewerBuilder,
    bottomAction: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          ColoredCard(
            color: Theme.of(context).colorScheme.error,
            child: Text(_error!),
          ),
        OutlinedButton.icon(
          onPressed: _saving || summary.read ? null : () => _read(book, lesson),
          icon: Icon(summary.read ? Icons.check : Icons.done_all),
          label: Text(
            _saving
                ? '正在保存…'
                : summary.read
                ? '本课已读'
                : '看完本课，标记已读',
          ),
        ),
      ],
    ),
  );

  Widget _knowledgePage(Textbook book, MathTextbookLesson lesson) {
    final pointId = widget.knowledgePointId;
    final point = pointId == null
        ? null
        : mathTextbookStudyNotes(lesson)
              .where((value) => value.id == pointId)
              .firstOrNull;
    if (pointId == null) {
      return _MathTextbookKnowledgePage(
        book: book,
        lesson: lesson,
        onRead: () => _openOriginalLesson(book, lesson),
        onKnowledge: (knowledge) =>
            _showContent(book, lesson, knowledge: knowledge),
      );
    }
    if (point == null) {
      return _statusPage(
        lesson.title,
        const AppEmptyState(
          icon: Icons.lightbulb_outline,
          title: '知识点已更新',
          description: '请返回本书重新选择。',
        ),
      );
    }
    return MathTextbookKnowledgeNotesPage(
      point: point,
      book: book,
      lesson: lesson,
    );
  }

  void _openOriginalLesson(Textbook book, MathTextbookLesson lesson) {
    context.push(
      AppRoutes.mathTextbookStudyOf(
        book.pdfSha256,
        lesson.id,
        mode: AppRoutes.mathTextbookReadMode,
      ),
    );
  }

  void _showContent(
    Textbook book,
    MathTextbookLesson lesson, {
    MathTextbookKnowledgePoint? knowledge,
  }) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => knowledge != null
            ? MathTextbookKnowledgeNotesPage(
                point: knowledge,
                book: book,
                lesson: lesson,
              )
            : MathTextbookSourceContentPage(
                book: book,
                title: lesson.title,
                blocks: lesson.blocks,
              ),
      ),
    );
  }

  void _showKnowledge(Textbook book, MathTextbookLesson lesson) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _MathTextbookKnowledgePage(
          book: book,
          lesson: lesson,
          onRead: () => _openOriginalLesson(book, lesson),
          onKnowledge: (knowledge) =>
              _showContent(book, lesson, knowledge: knowledge),
        ),
      ),
    );
  }

  void _showPractice(
    Textbook book,
    MathTextbookLesson lesson,
    MathTextbookLessonProgress summary,
    MathTextbookPracticeAvailability availability,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _MathTextbookPracticeOverviewPage(
          book: book,
          lesson: lesson,
          summary: summary,
          availability: availability,
          onRead: () => _openOriginalLesson(book, lesson),
          onOriginal: () {
            if (availability.exerciseIds.isEmpty) {
              _openOriginalLesson(book, lesson);
            } else {
              context.push(
                AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id),
              );
            }
          },
          onPlan: (plan) => context.push(
            AppRoutes.mathTextbookPracticeOf(
              book.pdfSha256,
              lesson.id,
              planId: plan.id,
            ),
          ),
          onConfigure: () => context.push(
            AppRoutes.mathTextbookLessonOf(book.pdfSha256, lesson.id),
          ),
          onHistory: () =>
              context.push(AppRoutes.mathTextbookHistoryOf(book.pdfSha256)),
        ),
      ),
    );
  }

  Future<void> _read(Textbook book, MathTextbookLesson lesson) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (ProfileScope.revision != _profileRevision) {
        throw StateError('孩子档案已切换，请返回后重新打开本课');
      }
      await ref
          .read(mathTextbookLearningRepositoryProvider(book.pdfSha256))!
          .markRead(lesson.id, lesson.contentDigest(book.pdfSha256));
      ref.invalidate(mathTextbookProgressProvider(book.pdfSha256));
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = mathTextbookDisplayError(error, '已读标记未保存，请重试。'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _content(
    Textbook book,
    MathTextbookLesson lesson,
    MathTextbookProgress progress,
  ) {
    final color = Theme.of(context).colorScheme.primary;
    final availability = mathTextbookPracticeAvailability(
      lesson,
      book.pdfSha256,
    );
    final summary = mathTextbookLessonProgress(
      lesson,
      book.pdfSha256,
      progress,
      availability: availability,
    );
    final learning = lesson.learning;
    final knowledgePoints = mathTextbookStudyNotes(lesson);
    final examples = mathTextbookWorkedExamples(lesson);
    final hasPractice =
        (learning?.exercises.isNotEmpty ?? false) ||
        (learning?.practicePlans.isNotEmpty ?? false);
    return ListView(
      key: PageStorageKey(
        'math-study-${progress.profileId}-${book.pdfSha256}-${lesson.id}',
      ),
      padding: const EdgeInsets.all(SpacingTokens.md),
      children: [
        if ((learning?.unitTitle.isNotEmpty ?? false) &&
            learning!.unitTitle != lesson.title)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.md),
            child: Text(learning.unitTitle),
          ),
        AppTile(
          icon: Icons.auto_stories_outlined,
          iconColor: color,
          title: '看一看',
          subtitle: '按原书顺序查看本课内容',
          onTap: () => _showContent(book, lesson),
        ),
        const SizedBox(height: SpacingTokens.md),
        AppTile(
          icon: Icons.lightbulb_outline,
          iconColor: color,
          title: '学一学',
          subtitle: knowledgePoints.isEmpty && examples.isEmpty
              ? '本课暂无知识点与例题'
              : [
                  if (knowledgePoints.isNotEmpty)
                    '${knowledgePoints.length} 个知识要点',
                  if (examples.isNotEmpty) '${examples.length} 个讲解例题',
                ].join(' · '),
          onTap: () => _showKnowledge(book, lesson),
        ),
        const SizedBox(height: SpacingTokens.md),
        AppTile(
          icon: Icons.edit_note_outlined,
          iconColor: color,
          title: '做一做',
          subtitle: hasPractice ? '教材原题与本课巩固练习' : '本课暂无练习',
          onTap: () => _showPractice(book, lesson, summary, availability),
        ),
        const SizedBox(height: SpacingTokens.lg),
        if (_error != null)
          ColoredCard(
            color: Theme.of(context).colorScheme.error,
            child: Text(_error!),
          ),
        OutlinedButton.icon(
          onPressed: _saving || summary.read ? null : () => _read(book, lesson),
          icon: Icon(summary.read ? Icons.check : Icons.done_all),
          label: Text(
            _saving
                ? '正在保存…'
                : summary.read
                ? '本课已读'
                : '看完本课，标记已读',
          ),
        ),
      ],
    );
  }
}
