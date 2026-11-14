import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_progress.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/domain/math_textbook_progress.dart';
import 'package:poemath/domain/math_textbook_practice.dart';
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
                            ref,
                            book,
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
    WidgetRef ref,
    Textbook book,
    MathTextbookCourse? course,
    Map<String, MathTextbookLessonProgress> summaries,
  ) {
    final color = Theme.of(context).colorScheme.primary;
    final lessons = [...?course?.lessons]
      ..sort((a, b) => a.startPage.compareTo(b.startPage));
    final read = summaries.values.where((summary) => summary.read).length;
    final completed = summaries.values
        .where((summary) => summary.complete)
        .length;
    final selected =
        ref
            .watch(textbookRepositoryProvider)
            .currentBook(ProfileScope.currentId, TextbookSubject.math)
            ?.pdfSha256 ==
        bookId;
    return ListView.builder(
      padding: const EdgeInsets.all(SpacingTokens.md),
      itemCount: lessons.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredCard(
                color: color,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${book.title} · ${book.volumeLabel}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: SpacingTokens.sm),
                    Text(book.editionNote),
                    Text(
                      '可学 ${lessons.length} 课 · 已读 $read 课 · 练习完成 $completed 课',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTile(
                icon: Icons.menu_book_outlined,
                iconColor: color,
                title: '打开原书',
                subtitle: '${book.pageCount} 页 · 可离线阅读',
                onTap: () => context.push(AppRoutes.textbookReadOf(bookId)),
              ),
              const SizedBox(height: SpacingTokens.sm),
              if (selected)
                const Text('这是当前使用的数学课本')
              else
                OutlinedButton(
                  onPressed: () async {
                    await ref
                        .read(textbookRepositoryProvider)
                        .selectBook(ProfileScope.currentId, book);
                    ref.invalidate(textbookLocalListProvider);
                  },
                  child: const Text('设为当前数学课本'),
                ),
              if (lessons.isEmpty) ...[
                const SizedBox(height: SpacingTokens.lg),
                const Text('还没有整理的课时，可以先阅读原书。'),
              ],
              if (lessons.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.md,
                  ),
                  child: OutlinedButton(
                    onPressed: () =>
                        context.push(AppRoutes.mathTextbookReviewOf(bookId)),
                    child: const Text('整理课时'),
                  ),
                ),
            ],
          );
        }
        final lesson = lessons[index - 1], summary = summaries[lesson.id]!;
        final unit = lesson.learning?.unitTitle ?? '';
        final previousUnit = index == 1
            ? null
            : lessons[index - 2].learning?.unitTitle ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (unit.isNotEmpty && unit != previousUnit)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.md,
                  ),
                  child: Text(
                    unit,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              AppTile(
                icon: summary.complete
                    ? Icons.check_circle_outline
                    : Icons.school_outlined,
                iconColor: color,
                title: lesson.title,
                subtitle:
                    '${summary.label}\nPDF 第 ${lesson.startPage}～${lesson.endPage} 页',
                onTap: () => context.push(
                  AppRoutes.mathTextbookStudyOf(bookId, lesson.id),
                ),
              ),
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
                      final lesson = course?.lessons
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
        if (learning?.unitTitle.isNotEmpty ?? false) Text(learning!.unitTitle),
        const SizedBox(height: SpacingTokens.sm),
        Text(summary.label),
        const SizedBox(height: SpacingTokens.md),
        AppTile(
          icon: Icons.auto_stories_outlined,
          iconColor: color,
          title: '阅读本课内容',
          subtitle: '文字、公式和原书图形',
          onTap: () => _showContent(book, lesson),
        ),
        const SizedBox(height: SpacingTokens.md),
        for (final k
            in learning?.knowledgePoints ?? <MathTextbookKnowledgePoint>[])
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.md),
            child: ColoredCard(
              color: color,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(k.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: SpacingTokens.sm),
                  Text(k.summary),
                  TextButton(
                    onPressed: () => _showContent(book, lesson, knowledge: k),
                    child: const Text('查看对应原书内容'),
                  ),
                ],
              ),
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
                  ? '${mathTextbookPracticeLabel(plan.kind)} · ${plan.kind == MathTextbookPracticeKind.parentTask ? 1 : plan.count} 题'
                  : '答案与练习范围待核对',
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
