import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_review_content.dart';
import 'package:poemath/features/textbook/widgets/textbook_review_layout.dart';

class MathTextbookReviewPage extends ConsumerStatefulWidget {
  const MathTextbookReviewPage({super.key, required this.bookId});
  final String bookId;
  @override
  ConsumerState<MathTextbookReviewPage> createState() =>
      _MathTextbookReviewPageState();
}

class _MathTextbookReviewPageState extends ConsumerState<MathTextbookReviewPage>
    with WidgetsBindingObserver {
  late final MathTextbookGenerationController _generation;
  bool _opening = false;
  bool _attempted = false;
  bool _navigating = false;
  @override
  void initState() {
    super.initState();
    _generation = ref.read(mathTextbookGenerationProvider.notifier);
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

  Future<void> _generate(Textbook book, {MathTextbookLesson? lesson}) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      assertParentAccess(context);
      final request = await showDialog<({String title, int start, int end})>(
        context: context,
        builder: (_) => _LessonRangeDialog(book: book, lesson: lesson),
      );
      if (!mounted || request == null) return;
      final authorize = ParentAccessService.instance.captureAuthorization();
      final books = ref.read(textbookRepositoryProvider);
      void check() {
        authorize();
        assertParentAccess(context);
        if (books.find(book.pdfSha256)?.subject != TextbookSubject.math) {
          throw const FormatException('教材已移除或学科已变更');
        }
      }

      check();
      await _generation.start(
        book: book,
        title: request.title,
        startPage: request.start,
        endPage: request.end,
        authorize: check,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '数学整理入口失败',
        tag: 'MathTextbook',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法开始整理，请重新打开后重试')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _generateBook(Textbook book, {bool refresh = false}) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      assertParentAccess(context);
      final entries = await ref.read(textbookCatalogProvider.future);
      if (!mounted) return;
      final path = await ref.read(textbookPathProvider(book.pdfSha256).future);
      if (!mounted) return;
      if (path == null ||
          !entries.any((entry) => entry.book.pdfSha256 == book.pdfSha256)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              path == null
                  ? '请先下载或导入这本书的 PDF'
                  : '此 PDF 尚无可核验的书目来源，可阅读原书或手动整理课时',
            ),
          ),
        );
        return;
      }
      assertParentAccess(context);
      final authorize = ParentAccessService.instance.captureAuthorization(),
          books = ref.read(textbookRepositoryProvider);
      void check() {
        authorize();
        assertParentAccess(context);
        if (books.find(book.pdfSha256)?.subject != TextbookSubject.math) {
          throw const FormatException('本书已移除或学科已变更');
        }
      }

      check();
      await _generation.startBook(
        book: book,
        authorize: check,
        refresh: refresh,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '数学全书整理未启动',
        tag: 'MathTextbook',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('全书整理未完成，已保存草稿保留，请重新打开后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _removeLesson(
    Textbook book,
    MathTextbookCourse course,
    MathTextbookLesson lesson,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('移除这个课时区间？'),
        content: Text('“${lesson.title}”将从当前课程移除，孩子的历史作答保留。可重新按实际课时页范围整理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('移除课时'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      final authorize = ParentAccessService.instance.captureAuthorization();
      await ref
          .read(mathTextbookRepositoryProvider)
          .removeLesson(
            book,
            lesson.id,
            expectedRevision: course.revision,
            authorize: () {
              authorize();
              assertParentAccess(context);
            },
          );
      ref.invalidate(mathTextbookCourseProvider(book.pdfSha256));
      ref.invalidate(mathTextbookLearningRepositoryProvider(book.pdfSha256));
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '数学课时移除失败',
        error: error,
        stackTrace: stackTrace,
        tag: 'MathTextbook',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('课时未移除，请重新打开后重试')));
      }
    }
  }

  Future<void> _openLesson(Textbook book, MathTextbookLesson lesson) async {
    if (_navigating) return;
    setState(() => _navigating = true);
    try {
      await _generation.stop(book.pdfSha256);
      if (!mounted) return;
      assertParentAccess(context);
      await context.push(
        AppRoutes.mathTextbookLessonOf(book.pdfSha256, lesson.id),
      );
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  Future<void> _showMore(Textbook book) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('更多', style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: SpacingTokens.sm),
            for (final option in const [
              ('edition', Icons.info_outline, '版次与来源', ''),
              ('refresh', Icons.refresh, '重新整理原书', '保留人工修改'),
              ('lesson', Icons.add, '整理一个完整课时', '补充或调整目录未能定位的课时'),
              ('read', Icons.menu_book_outlined, '查看原书目录', ''),
              ('history', Icons.fact_check_outlined, '查看作答与家长核对', ''),
            ])
              AppTile(
                flat: true,
                flatTrailingEdgeAligned: true,
                icon: option.$2,
                iconColor: Theme.of(sheet).colorScheme.primary,
                title: option.$3,
                subtitle: option.$4,
                onTap: () => Navigator.pop(sheet, option.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edition':
        await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('版次与来源'),
            content: Text(
              [book.title, book.publisher, book.editionNote].join('\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      case 'refresh':
        await _generateBook(book, refresh: true);
      case 'lesson':
        await _generate(book);
      case 'read':
        await context.push(AppRoutes.textbookReadOf(book.pdfSha256));
      case 'history':
        await context.push(
          AppRoutes.mathTextbookHistoryOf(book.pdfSha256, parent: true),
        );
    }
  }

  Future<void> _lessonActions(
    Textbook book,
    MathTextbookCourse course,
    MathTextbookLesson lesson,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTile(
              flat: true,
              icon: Icons.refresh,
              iconColor: Theme.of(sheet).colorScheme.primary,
              title: '重新整理此课',
              subtitle: '保留人工修改与审核，变化稿需比较后采纳',
              onTap: () => Navigator.pop(sheet, 'refresh'),
            ),
            AppTile(
              flat: true,
              icon: Icons.delete_outline,
              iconColor: Theme.of(sheet).colorScheme.primary,
              title: '移除课时区间',
              subtitle: '',
              onTap: () => Navigator.pop(sheet, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'refresh') await _generate(book, lesson: lesson);
    if (action == 'remove') await _removeLesson(book, course, lesson);
  }

  Widget _generationStatus(Textbook book, MathTextbookCourse? course) {
    final progress = ref.watch(mathTextbookGenerationProvider)[book.pdfSha256];
    final outline = course?.outline;
    if (progress == null && outline == null) return const SizedBox.shrink();
    final saved =
        outline?.completedLessonIds?.length ??
        outline?.ranges
            .where(
              (range) =>
                  course!.lessons.any((lesson) => lesson.id == range.lessonId),
            )
            .length ??
        0;
    final running = progress?.running == true;
    final done = running ? progress!.completed : saved;
    final total = running && progress!.total > 0
        ? progress.total
        : outline?.ranges.length ?? 0;
    if (!running &&
        progress?.failed != true &&
        (total > 0 && done == total || outline == null)) {
      return const SizedBox.shrink();
    }
    return TextbookReviewProgressCard(
      message: progress?.message ?? '已保存 $saved/$total 课，可继续整理',
      completed: done,
      total: total,
      running: running,
      onPause: () => _generation.pause(book.pdfSha256),
      onResume: _opening ? null : () => _generateBook(book),
    );
  }

  Future<void> _bookReview(Textbook book, MathTextbookCourse course) async {
    final saved = course.lessons.length;
    final approved = course.lessons
        .where((lesson) => lesson.isApproved(book.pdfSha256))
        .length;
    final total = course.outline?.ranges.length ?? saved;
    final pending = course.pendingLessons.length;
    final pages = course.lessons
        .expand((lesson) => lesson.blocks)
        .where((block) => block.kind == MathTextbookBlockKind.sourcePage)
        .expand((block) => block.sources.map((source) => source.page))
        .toSet()
        .length;
    final pageCount = book.pageCount;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('整书核对'),
        content: Text(
          '已保存 $saved/$total 课，$approved 课已审核。\n已保留 $pages/$pageCount 页原书对照。\n有 $pending 份新稿待比较。\n\n请按单元逐课核对范围、知识点、原题与巩固；整理完成的草稿仍需显式审核。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('继续逐课核对'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = ref
        .watch(textbookLocalListProvider)
        .where(
          (book) =>
              book.pdfSha256 == widget.bookId &&
              book.subject == TextbookSubject.math,
        )
        .firstOrNull;
    final course = ref.watch(mathTextbookCourseProvider(widget.bookId));
    final progress = ref.watch(mathTextbookGenerationProvider)[widget.bookId];
    return Scaffold(
      appBar: AppBar(
        title: const Text('内容审核'),
        actions: [
          if (book != null)
            IconButton(
              tooltip: '更多',
              onPressed: _opening || progress?.running == true
                  ? null
                  : () => _showMore(book),
              icon: const Icon(Icons.more_vert),
            ),
        ],
      ),
      body: book == null
          ? const AppEmptyState(
              icon: Icons.menu_book_outlined,
              title: '找不到教材',
              description: '请返回书籍管理重新选择。',
            )
          : course.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => AppEmptyState(
                icon: Icons.error_outline,
                title: '课程草稿读取失败',
                description: '已有文件保留，请重新读取后继续核对。',
                actions: [
                  TextButton(
                    onPressed: () => ref.invalidate(
                      mathTextbookCourseProvider(widget.bookId),
                    ),
                    child: const Text('重试读取'),
                  ),
                ],
              ),
              data: (data) {
                if (data != null) {
                  return MathTextbookReviewContent(
                    book: book,
                    course: data,
                    progress: _generationStatus(book, data),
                    running:
                        _opening || _navigating || progress?.running == true,
                    onLesson: (lesson) => _openLesson(book, lesson),
                    onLessonActions: (lesson) =>
                        _lessonActions(book, data, lesson),
                    onBookReview: () => _bookReview(book, data),
                  );
                }
                final path = ref.watch(textbookPathProvider(widget.bookId));
                final entries = ref.watch(textbookCatalogProvider);
                if (!_attempted && path.hasValue && entries.hasValue) {
                  _attempted = true;
                  if (path.valueOrNull != null &&
                      entries.valueOrNull!.any(
                        (entry) => entry.book.pdfSha256 == widget.bookId,
                      )) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _generateBook(book);
                    });
                  }
                }
                return AppEmptyState(
                  icon: Icons.fact_check_outlined,
                  title: '从原书整理课程草稿',
                  description: path.isLoading || entries.isLoading
                      ? '正在检查本机原书与书目…'
                      : path.hasError || entries.hasError
                      ? '原书或书目读取失败，可从右上角重试整理。'
                      : path.valueOrNull == null
                      ? '请先下载或导入原书 PDF。之后首次进入会在本机逐课整理，内容仍需审核。'
                      : !entries.valueOrNull!.any(
                          (entry) => entry.book.pdfSha256 == widget.bookId,
                        )
                      ? '此 PDF 尚无可核验的书目来源，暂不支持自动整理。可阅读原书，或从右上角手动整理课时。'
                      : '在本机逐课整理；完成的课目会逐课显示。无法可靠归类的内容会保留待整理。',
                  actions: [
                    SizedBox(
                      width: double.infinity,
                      child: _generationStatus(book, null),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _LessonRangeDialog extends StatefulWidget {
  const _LessonRangeDialog({required this.book, this.lesson});
  final Textbook book;
  final MathTextbookLesson? lesson;
  @override
  State<_LessonRangeDialog> createState() => _LessonRangeDialogState();
}

class _LessonRangeDialogState extends State<_LessonRangeDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.lesson?.title ?? '');
  late final _start = TextEditingController(
    text: widget.lesson?.startPage.toString() ?? '',
  );
  late final _end = TextEditingController(
    text: widget.lesson?.endPage.toString() ?? '',
  );
  String? _page(String? input) {
    final value = int.tryParse(input ?? '');
    return value == null || value < 1 || value > widget.book.pageCount
        ? '请输入 1～${widget.book.pageCount} 的页数'
        : null;
  }

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.lesson == null ? '整理完整课时' : '重新整理此课'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('填写阅读器显示的 PDF 页码，含开头和结尾页；一次最多 40 页。跨页题目请一并纳入。'),
            if (widget.lesson != null)
              const Text('原有修改和审核记录会保留。内容有变化时，生成待比较的新结果。'),
            const SizedBox(height: SpacingTokens.md),
            TextFormField(
              controller: _title,
              maxLength: 200,
              decoration: const InputDecoration(labelText: '课时名称'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请填写课时名称' : null,
            ),
            TextFormField(
              controller: _start,
              enabled: widget.lesson == null,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '起始 PDF 页'),
              validator: _page,
            ),
            const SizedBox(height: SpacingTokens.sm),
            TextFormField(
              controller: _end,
              enabled: widget.lesson == null,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '结束 PDF 页'),
              validator: (v) {
                final error = _page(v);
                if (error != null) return error;
                final first = int.tryParse(_start.text), last = int.parse(v!);
                if (first == null || last < first || last - first >= 40) {
                  return '结束页须不小于起始页，且最多 40 页';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, (
            title: _title.text.trim(),
            start: int.parse(_start.text),
            end: int.parse(_end.text),
          ));
        },
        child: const Text('开始整理'),
      ),
    ],
  );
}
