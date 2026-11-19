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
import 'package:poemath/features/textbook/math_textbook_labels.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_study_content.dart';

class MathTextbookBookPage extends ConsumerWidget {
  const MathTextbookBookPage({super.key, required this.bookId});
  final String bookId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(mathTextbookProfileProvider);
    final book = ref
        .watch(textbookLocalListProvider)
        .where(
          (b) => b.pdfSha256 == bookId && b.subject == TextbookSubject.math,
        )
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('数学课本'),
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
                    data: (_) => ref
                        .watch(mathTextbookBookLearningProvider(bookId))
                        .when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
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
                          ),
                        ),
                  ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    MathTextbookCourse? course,
    Map<String, MathTextbookLessonProgress> summaries,
  ) {
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
    final showIntro = lessons.isEmpty || needsCourseUpdate;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ResponsiveLayout.columns(constraints.maxWidth);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            SpacingTokens.md,
            0,
            SpacingTokens.md,
            SpacingTokens.md,
          ),
          child: CustomScrollView(
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
                        if (lessons.isEmpty) ...[
                          const SizedBox(height: SpacingTokens.md),
                          const Text('还没有整理的课时。'),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: SpacingTokens.md,
                            ),
                            child: OutlinedButton(
                              onPressed: () => context.push(
                                AppRoutes.mathTextbookReviewOf(bookId),
                              ),
                              child: const Text('整理课时'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              for (final group in lessonGroups) ...[
                if (group.unit.isNotEmpty)
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
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
                  sliver: SliverCardGrid(
                    columnCount: columns,
                    itemCount: group.lessons.length,
                    itemBuilder: (context, index) {
                      final lesson = group.lessons[index];
                      final summary = summaries[lesson.id]!;
                      return AppTile(
                        icon: summary.complete
                            ? Icons.check_circle_outline
                            : Icons.school_outlined,
                        iconColor: color,
                        title: lesson.title,
                        subtitle: summary.label,
                        onTap: () => context.push(
                          AppRoutes.mathTextbookStudyOf(bookId, lesson.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class MathTextbookStudyPage extends ConsumerStatefulWidget {
  const MathTextbookStudyPage({
    super.key,
    required this.bookId,
    required this.lessonId,
  });
  final String bookId, lessonId;
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
    return Scaffold(
      appBar: AppBar(title: const Text('本课学习')),
      body: SafeArea(
        child: book == null
            ? const AppEmptyState(
                icon: Icons.menu_book_outlined,
                title: '本书已移除',
                description: '请返回课本重新选择。',
              )
            : ref
                  .watch(mathTextbookCourseProvider(widget.bookId))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => AppEmptyState(
                      icon: Icons.error_outline,
                      title: '课时暂时无法读取',
                      description: mathTextbookDisplayError(error, '请返回重试。'),
                    ),
                    data: (course) {
                      final lesson = course?.currentLessons
                          .where((l) => l.id == widget.lessonId)
                          .firstOrNull;
                      if (lesson == null) {
                        return const AppEmptyState(
                          icon: Icons.school_outlined,
                          title: '课时已更新',
                          description: '请返回本书重新选择。',
                        );
                      }
                      return ref
                          .watch(mathTextbookProgressProvider(widget.bookId))
                          .when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (error, _) => AppEmptyState(
                              icon: Icons.error_outline,
                              title: '学习记录暂时无法读取',
                              description: mathTextbookDisplayError(
                                error,
                                '请返回重试。',
                              ),
                            ),
                            data: (progress) => _content(
                              book,
                              lesson,
                              progress ??
                                  MathTextbookProgress(
                                    profileId: ProfileScope.currentId,
                                    bookId: book.pdfSha256,
                                    editionId: book.learningEditionId,
                                  ),
                            ),
                          );
                    },
                  ),
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
        builder: (_) => MathTextbookSourceContentPage(
          book: book,
          title: knowledge?.title ?? lesson.title,
          knowledgePoint: knowledge != null,
          blocks: knowledge == null
              ? lesson.blocks
              : lesson.blocks
                    .where((b) => knowledge.blockIds.contains(b.id))
                    .toList(),
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
    final originalReady =
        learning != null && availability.exerciseIds.isNotEmpty;
    return ListView(
      key: PageStorageKey(
        'math-study-${progress.profileId}-${book.pdfSha256}-${lesson.id}',
      ),
      padding: const EdgeInsets.all(SpacingTokens.md),
      children: [
        Text(lesson.title, style: Theme.of(context).textTheme.headlineSmall),
        if ((learning?.unitTitle.isNotEmpty ?? false) &&
            learning!.unitTitle != lesson.title)
          Text(learning.unitTitle),
        const SizedBox(height: SpacingTokens.sm),
        Text(summary.label),
        const SizedBox(height: SpacingTokens.md),
        AppTile(
          icon: Icons.auto_stories_outlined,
          iconColor: color,
          title: '阅读本课内容',
          subtitle: '按原书顺序阅读讲解、例题与练习',
          onTap: () => _showContent(book, lesson),
        ),
        const SizedBox(height: SpacingTokens.md),
        if (learning?.knowledgePoints.isNotEmpty ?? false) ...[
          Text('知识与例题', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: SpacingTokens.sm),
        ],
        for (final k
            in learning?.knowledgePoints ?? <MathTextbookKnowledgePoint>[])
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.md),
            child: AppTile(
              icon: Icons.lightbulb_outline,
              iconColor: color,
              title: k.title,
              titleMaxLines: 2,
              subtitle: k.summary,
              subtitleMaxLines: 3,
              onTap: () => _showContent(book, lesson, knowledge: k),
            ),
          ),
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
        const SizedBox(height: SpacingTokens.lg),
        AppTile(
          icon: Icons.edit_note_outlined,
          iconColor: color,
          title: '教材原题',
          subtitle: learning == null
              ? '阅读本课内容中的例题与习题'
              : learning.noExercises
              ? '原书本课没有独立习题'
              : originalReady
              ? availability.exerciseIds.length < learning.exercises.length
                    ? '共 ${learning.exercises.length} 组 · 可练 ${availability.exerciseIds.length} 组纸上题'
                    : '共 ${learning.exercises.length} 组 · 已通过 ${summary.originalPassed} 组'
              : '可在本课内容中对照原书学习',
          onTap: originalReady
              ? () => context.push(
                  AppRoutes.mathTextbookPracticeOf(book.pdfSha256, lesson.id),
                )
              : learning?.noExercises == true
              ? null
              : () => _showContent(book, lesson),
        ),
        if (learning?.practicePlans.isNotEmpty ?? false) ...[
          const SizedBox(height: SpacingTokens.lg),
          Text('本课巩固', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: SpacingTokens.sm),
        ],
        for (final plan
            in learning?.practicePlans ?? <MathTextbookPracticePlan>[])
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: AppTile(
              icon: Icons.fitness_center_outlined,
              iconColor: color,
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
                  ? () => context.push(
                      AppRoutes.mathTextbookPracticeOf(
                        book.pdfSha256,
                        lesson.id,
                        planId: plan.id,
                      ),
                    )
                  : null,
            ),
          ),
        if (learning != null &&
            (availability.exerciseIds.length < learning.exercises.length ||
                availability.planIds.length < learning.practicePlans.length))
          TextButton(
            onPressed: () => context.push(
              AppRoutes.mathTextbookLessonOf(book.pdfSha256, lesson.id),
            ),
            child: const Text('配置本课自动练习'),
          ),
        TextButton(
          onPressed: () =>
              context.push(AppRoutes.mathTextbookHistoryOf(book.pdfSha256)),
          child: const Text('查看作答记录与待核对项'),
        ),
      ],
    );
  }
}
