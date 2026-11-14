import 'dart:async';

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
import 'package:poemath/data/repositories/math_textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/domain/math_textbook_editing.dart';
import 'package:poemath/features/textbook/math_textbook_block_editor_page.dart';
import 'package:poemath/features/textbook/math_textbook_learning_editor_page.dart';
import 'package:poemath/features/textbook/math_textbook_labels.dart';
import 'package:poemath/features/textbook/providers/math_textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_content.dart';
import 'package:poemath/features/textbook/widgets/math_textbook_source_preview.dart';
import 'package:poemath/features/textbook/widgets/textbook_review_layout.dart';

class MathTextbookLessonPage extends ConsumerStatefulWidget {
  const MathTextbookLessonPage({
    super.key,
    required this.bookId,
    required this.lessonId,
  });
  final String bookId;
  final String lessonId;
  @override
  ConsumerState<MathTextbookLessonPage> createState() =>
      _MathTextbookLessonPageState();
}

class _MathTextbookLessonPageState extends ConsumerState<MathTextbookLessonPage>
    with WidgetsBindingObserver {
  late final MathTextbookCourseRepository _repository;
  late final TextbookRepository _books;
  Textbook? _book;
  MathTextbookCourse? _course;
  MathTextbookLesson? _lesson;
  final _title = TextEditingController();
  final _editingTime = Stopwatch();
  int _generation = 0;
  int _page = 1;
  bool _loading = true, _saving = false, _dirty = false, _reading = false;
  bool _foreground = true;
  bool _showSource = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(mathTextbookRepositoryProvider);
    _books = ref.read(textbookRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateClock();
  }

  void _updateClock() {
    if (_foreground && !_reading && !_saving && !_loading) {
      _editingTime.start();
    } else {
      _editingTime.stop();
    }
  }

  void _readingChanged(bool reading) {
    _reading = reading;
    _updateClock();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _updateClock();
    try {
      final book = _books.find(widget.bookId);
      if (book == null || book.subject != TextbookSubject.math) {
        throw const FormatException('数学教材已移除或学科已变更');
      }
      final generation = _repository.generation(book.pdfSha256);
      final course = await _repository.load(book);
      if (!mounted) return;
      _repository.checkGeneration(book.pdfSha256, generation);
      final lesson = course?.lessons
          .where((l) => l.id == widget.lessonId)
          .firstOrNull;
      if (course == null || lesson == null) {
        throw const FormatException('找不到这个课时，请返回重新选择');
      }
      setState(() {
        _book = book;
        _course = course;
        _lesson = lesson;
        _generation = generation;
        _page = lesson.startPage;
        _title.text = lesson.title;
        _dirty = false;
      });
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '课时草稿读取失败，请重试');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _updateClock();
      }
    }
  }

  void _report(Object error, StackTrace stackTrace, String fallback) {
    AppLogger.e(
      fallback,
      tag: 'MathTextbook',
      error: error,
      stackTrace: stackTrace,
    );
    if (mounted) {
      setState(
        () => _error = error is FormatException
            ? error.message.toString()
            : error is ParentAccessDenied
            ? '家长授权已结束，请重新解锁后保存'
            : fallback,
      );
    }
  }

  void Function() _authorization() {
    final authorize = ParentAccessService.instance.captureAuthorization();
    return () {
      authorize();
      assertParentAccess(context);
      if (_books.find(widget.bookId)?.subject != TextbookSubject.math) {
        throw const FormatException('教材已移除或学科已变更');
      }
      _repository.checkGeneration(widget.bookId, _generation);
    };
  }

  void _change(MathTextbookLesson lesson) => setState(() {
    _lesson = lesson;
    _dirty = true;
    _error = null;
  });

  Future<void> _edit(MathTextbookBlock block, {bool adding = false}) async {
    if (_saving) return;
    try {
      final check = _authorization();
      check();
      final result = await Navigator.of(context).push<MathTextbookBlock>(
        MaterialPageRoute(
          builder: (_) => ParentAccessBoundary(
            child: MathTextbookBlockEditorPage(
              book: _book!,
              block: block,
              startPage: _lesson!.startPage,
              endPage: _lesson!.endPage,
              onReadingChanged: _readingChanged,
            ),
          ),
        ),
      );
      if (!mounted || result == null) return;
      check();
      if (adding) {
        final blocks = [..._lesson!.blocks];
        final index = blocks.indexWhere(
          (b) =>
              b.kind == MathTextbookBlockKind.sourcePage &&
              b.sources.first.page == _page,
        );
        blocks.insert(index < 0 ? blocks.length : index, result);
        _change(_lesson!.edit(blocks: blocks));
      } else {
        _change(
          _lesson!.edit(
            blocks: [
              for (final b in _lesson!.blocks) b.id == result.id ? result : b,
            ],
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '修改未应用，请重试');
    }
  }

  Future<void> _blockAction(String action, int index) async {
    if (_saving) return;
    try {
      final check = _authorization();
      check();
      final blocks = [..._lesson!.blocks];
      final block = blocks[index];
      final previous = blocks
          .take(index)
          .where((b) => b.kind != MathTextbookBlockKind.sourcePage)
          .lastOrNull;
      if (action == 'merge' && previous != null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('与上一处内容合并？'),
            content: Text(
              '合并到“${previous.text.isEmpty ? mathTextbookBlockLabel(previous.kind) : previous.text.substring(0, previous.text.length.clamp(0, 40))}”。原书来源会一并保留，可用于跨页题目。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('合并内容'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
        check();
        blocks[blocks.indexOf(previous)] = mergeMathTextbookBlocks(
          previous,
          block,
        );
        blocks.removeAt(index);
      } else if (action == 'remove') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('移除这处整理内容？'),
            content: const Text('原书整页对照仍会保留。保存课时后生效。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('移除内容'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
        check();
        blocks.removeAt(index);
      } else if (action == 'up' && previous != null) {
        blocks.removeAt(index);
        blocks.insert(blocks.indexOf(previous), block);
      } else {
        return;
      }
      _change(_lesson!.edit(blocks: blocks));
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '内容未调整，请重试');
    }
  }

  Future<void> _save({bool approve = false}) async {
    if (_saving || _lesson == null) return;
    // 在第一个 await 前占位，避免双击重复保存或审核。
    setState(() {
      _saving = true;
      _error = null;
    });
    _updateClock();
    try {
      final check = _authorization();
      check();
      var lesson = MathTextbookLesson.fromJson(_lesson!.toJson());
      if (approve) {
        final reviewer = await showDialog<String>(
          context: context,
          builder: (_) =>
              _MathReviewDialog(reviewer: lesson.review?.reviewer ?? ''),
        );
        if (!mounted || reviewer == null) return;
        check();
        lesson = lesson.approve(
          pdfSha256: widget.bookId,
          reviewer: reviewer,
          editingMilliseconds: _editingTime.elapsedMilliseconds,
        );
      }
      final course = await _repository.saveLesson(
        _book!,
        lesson,
        expectedRevision: _course!.revision,
        generation: _generation,
        authorize: check,
      );
      if (!mounted) return;
      setState(() {
        _course = course;
        _lesson = lesson;
        _dirty = false;
      });
      ref.invalidate(mathTextbookCourseProvider(widget.bookId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? '本课内容审核已完成' : '课时草稿已保存')),
      );
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '课时未保存，修改内容保留，请重试');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _updateClock();
      }
    }
  }

  Future<void> _compare(MathTextbookLesson pending) async {
    if (_saving || _dirty) return;
    try {
      final check = _authorization();
      check();
      final accept = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ParentAccessBoundary(
            child: _MathComparisonPage(
              book: _book!,
              current: _lesson!,
              pending: pending,
            ),
          ),
        ),
      );
      if (!mounted || accept != true) return;
      check();
      setState(() => _saving = true);
      _updateClock();
      final course = await _repository.acceptPending(
        _book!,
        pending.id,
        expectedRevision: _course!.revision,
        generation: _generation,
        authorize: check,
      );
      if (!mounted) return;
      final lesson = course.lessons.firstWhere((l) => l.id == pending.id);
      setState(() {
        _course = course;
        _lesson = lesson;
        _title.text = lesson.title;
        _page = lesson.startPage;
      });
      ref.invalidate(mathTextbookCourseProvider(widget.bookId));
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '新结果未采纳，当前内容保留');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _updateClock();
      }
    }
  }

  Future<void> _read() async {
    _readingChanged(true);
    try {
      await context.push(AppRoutes.textbookReadOf(widget.bookId), extra: _page);
    } finally {
      _readingChanged(false);
    }
  }

  Future<void> _editLearning({
    MathTextbookLearningSection section = MathTextbookLearningSection.all,
    bool startAdding = false,
  }) async {
    if (_saving || _lesson == null) return;
    try {
      final check = _authorization();
      check();
      final learning = await Navigator.of(context).push<MathTextbookLearning>(
        MaterialPageRoute(
          builder: (_) => ParentAccessBoundary(
            child: MathTextbookLearningEditorPage(
              book: _book!,
              lesson: _lesson!,
              section: section,
              startAdding: startAdding,
            ),
          ),
        ),
      );
      if (!mounted || learning == null) return;
      check();
      final next = _lesson!.edit(learning: learning);
      if (next.contentDigest(widget.bookId) !=
          _lesson!.contentDigest(widget.bookId)) {
        _change(next);
      }
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, '学习配置未应用，请重新打开后重试');
    }
  }

  Future<void> _leave() async {
    if (_saving) return;
    if (_showSource) {
      setState(() => _showSource = false);
      return;
    }
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('课时有未保存的修改'),
          content: const Text('返回后会保留上次保存的内容。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('放弃修改并返回'),
            ),
          ],
        ),
      );
      if (!mounted || discard != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _overview(MathTextbookLesson lesson, MathTextbookLesson? pending) {
    final color = Theme.of(context).colorScheme.primary;
    final learning = lesson.learning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PDF 第 ${lesson.startPage}～${lesson.endPage} 页 · ${lesson.isApproved(widget.bookId) ? '已通过' : '待家长核对'}${_dirty ? ' · 有未保存修改' : ''}',
        ),
        const SizedBox(height: SpacingTokens.sm),
        AppTile(
          flat: true,
          flatTrailingEdgeAligned: true,
          icon: Icons.auto_stories_outlined,
          iconColor: color,
          title: '原书范围与待整理内容',
          subtitle: '核对课时名称、原书范围、公式、图形及生成差异',
          onTap: _saving ? null : () => setState(() => _showSource = true),
        ),
        if (pending != null) ...[
          const SizedBox(height: SpacingTokens.md),
          ColoredCard(
            color: Theme.of(context).colorScheme.secondary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('有一份新整理结果，当前人工内容和审核仍保留。'),
                TextButton(
                  onPressed: _saving || _dirty ? null : () => _compare(pending),
                  child: const Text('比较新整理结果'),
                ),
                if (_dirty) const Text('先保存当前修改，再比较。'),
              ],
            ),
          ),
        ],
        _learningSection('知识点', MathTextbookLearningSection.knowledge, [
          for (final point
              in learning?.knowledgePoints ?? <MathTextbookKnowledgePoint>[])
            (point.id, point.title, point.summary),
        ]),
        _learningSection('教材原题与题组', MathTextbookLearningSection.exercises, [
          for (final exercise
              in learning?.exercises ?? <MathTextbookExercise>[])
            (
              exercise.id,
              exercise.title,
              '${exercise.fields.length} 个作答项 · ${exercise.needsParent ? '含家长核对项' : '自动核对'}',
            ),
        ], noRequirement: learning?.noExercises == true),
        _learningSection('本课巩固', MathTextbookLearningSection.practice, [
          for (final plan
              in learning?.practicePlans ?? <MathTextbookPracticePlan>[])
            (plan.id, plan.title, mathTextbookPracticeLabel(plan.kind)),
        ]),
        const Divider(height: SpacingTokens.xl),
        AppTile(
          flat: true,
          flatTrailingEdgeAligned: true,
          icon: Icons.fact_check_outlined,
          iconColor: color,
          title: '核对内容范围',
          subtitle: learning?.coverageConfirmed == true
              ? '本课内容已逐页核对'
              : '核对知识点、完整题组、答案、单位和巩固范围',
          onTap: _saving
              ? null
              : () => _editLearning(
                  section: MathTextbookLearningSection.coverage,
                ),
        ),
        const SizedBox(height: SpacingTokens.md),
        _saveActions(),
      ],
    );
  }

  Widget _learningSection(
    String title,
    MathTextbookLearningSection section,
    List<(String, String, String)> rows, {
    bool noRequirement = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextbookReviewSectionHeader(
        title: '$title · ${rows.length}',
        actionLabel: '添加',
        actionIcon: Icons.add,
        actionIconAlignment: IconAlignment.start,
        onAction: _saving
            ? null
            : () => _editLearning(section: section, startAdding: true),
      ),
      if (rows.isEmpty)
        AppEmptyState(
          icon: Icons.menu_book_outlined,
          title: noRequirement ? '已核对：原书无此要求' : '尚未整理此类内容',
          description: noRequirement ? null : '可对照原书添加。',
          padding: const EdgeInsets.all(SpacingTokens.md),
        ),
      for (final row in rows)
        AppTile(
          key: ValueKey('math-lesson-content-${row.$1}'),
          flat: true,
          flatTrailingEdgeAligned: true,
          iconColor: Theme.of(context).colorScheme.primary,
          title: row.$2,
          subtitle: row.$3,
          subtitleMaxLines: 2,
          onTap: _saving ? null : () => _editLearning(section: section),
        ),
    ],
  );

  Widget _saveActions() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Wrap(
        spacing: SpacingTokens.sm,
        runSpacing: SpacingTokens.sm,
        children: [
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '正在保存…' : '保存草稿'),
          ),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _save(approve: true),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('核对完成，审核本课'),
          ),
        ],
      ),
      const SizedBox(height: SpacingTokens.md),
      const Text('修改文字、公式、来源或学习内容后，本课需要重新审核。未识别的图表继续保留原书对照。'),
      const SizedBox(height: SpacingTokens.lg),
    ],
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editingTime.stop();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lesson = _lesson;
    final pending = _course?.pendingLessons
        .where((l) => l.id == widget.lessonId)
        .firstOrNull;
    final indices = lesson == null
        ? <int>[]
        : [
            for (var i = 0; i < lesson.blocks.length; i++)
              if (lesson.blocks[i].kind != MathTextbookBlockKind.sourcePage &&
                  lesson.blocks[i].sources.any((s) => s.page == _page))
                i,
          ];
    final pageWarnings =
        lesson?.blocks
            .where(
              (b) =>
                  b.kind == MathTextbookBlockKind.sourcePage &&
                  b.sources.any((s) => s.page == _page),
            )
            .expand((b) => b.warnings)
            .toList() ??
        [];
    return PopScope<void>(
      canPop: !_dirty && !_saving && !_showSource,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_showSource ? '原书范围与待整理内容' : lesson?.title ?? '内容审核'),
          leading: IconButton(
            tooltip: '返回',
            onPressed: _saving ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            if (lesson != null)
              IconButton(
                tooltip: '核对内容范围',
                onPressed: _saving
                    ? null
                    : () => _editLearning(
                        section: MathTextbookLearningSection.coverage,
                      ),
                icon: const Icon(Icons.fact_check_outlined),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : lesson == null
            ? AppEmptyState(
                icon: Icons.error_outline,
                title: '课时暂时无法打开',
                description: _error ?? '请重新读取草稿。',
                actions: [
                  TextButton(onPressed: _load, child: const Text('重新读取')),
                ],
              )
            : SafeArea(
                child: ListView.builder(
                  key: PageStorageKey(
                    'math-review-${widget.bookId}-${widget.lessonId}-${_showSource ? 'source' : 'content'}',
                  ),
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  itemCount: _showSource ? indices.length + 2 : 1,
                  itemBuilder: (context, index) {
                    if (!_showSource) return _overview(lesson, pending);
                    if (index == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _title,
                            enabled: !_saving,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              labelText: '课时名称',
                            ),
                            onChanged: (value) =>
                                _change(lesson.edit(title: value)),
                          ),
                          Text(
                            'PDF 第 ${lesson.startPage}～${lesson.endPage} 页 · ${lesson.isApproved(widget.bookId) ? '已审核' : '待家长核对'}${_dirty ? ' · 有未保存修改' : ''}',
                          ),
                          const SizedBox(height: SpacingTokens.md),
                          AppTile(
                            icon: Icons.school_outlined,
                            iconColor: theme.colorScheme.primary,
                            title: '知识点、教材原题与本课巩固',
                            subtitle: lesson.learning == null
                                ? '尚未配置，孩子暂可阅读已审正文'
                                : '${lesson.learning!.knowledgePoints.length} 个知识点 · ${lesson.learning!.exercises.length} 组原题 · ${lesson.learning!.practicePlans.length} 项巩固${lesson.learning!.coverageConfirmed ? ' · 已核对覆盖' : ' · 待核对覆盖'}',
                            onTap: _saving ? null : _editLearning,
                          ),
                          if (pending != null) ...[
                            const SizedBox(height: SpacingTokens.md),
                            ColoredCard(
                              color: theme.colorScheme.secondary,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('有一份新整理结果，当前人工内容和审核仍保留。'),
                                  TextButton(
                                    onPressed: _saving || _dirty
                                        ? null
                                        : () => _compare(pending),
                                    child: const Text('比较新整理结果'),
                                  ),
                                  if (_dirty) const Text('先保存当前修改，再比较。'),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: SpacingTokens.md),
                          DropdownButtonFormField<int>(
                            isExpanded: true,
                            itemHeight: null,
                            key: ValueKey('lesson-page-$_page'),
                            initialValue: _page,
                            decoration: const InputDecoration(
                              labelText: '正在核对的原书页',
                            ),
                            items: [
                              for (
                                var p = lesson.startPage;
                                p <= lesson.endPage;
                                p++
                              )
                                DropdownMenuItem(
                                  value: p,
                                  child: Text('PDF 第 $p 页'),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (page) => setState(() => _page = page!),
                          ),
                          TextButton.icon(
                            onPressed: _saving ? null : _read,
                            icon: const Icon(Icons.menu_book_outlined),
                            label: const Text('打开本页原书'),
                          ),
                          ExpansionTile(
                            key: ValueKey('original-$_page'),
                            title: const Text('展开整页对照'),
                            children: [
                              MathTextbookSourcePreview(
                                book: _book!,
                                source: MathTextbookRegion(
                                  page: _page,
                                  left: 0,
                                  top: 0,
                                  right: 1,
                                  bottom: 1,
                                ),
                              ),
                            ],
                          ),
                          if (pageWarnings.isNotEmpty)
                            Text('本页待核提示：${pageWarnings.join('；')}'),
                          const SizedBox(height: SpacingTokens.md),
                          if (indices.isEmpty)
                            const Text('本页保留原书对照，可补充文字、公式或图表说明。'),
                        ],
                      );
                    }
                    if (index == indices.length + 1) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _edit(
                                    MathTextbookBlock(
                                      id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
                                      kind: MathTextbookBlockKind.text,
                                      spans: const [MathTextbookSpan.text('')],
                                      sources: [
                                        MathTextbookRegion(
                                          page: _page,
                                          left: 0,
                                          top: 0,
                                          right: 1,
                                          bottom: 1,
                                        ),
                                      ],
                                    ),
                                    adding: true,
                                  ),
                            icon: const Icon(Icons.add),
                            label: const Text('补充本页内容'),
                          ),
                          const SizedBox(height: SpacingTokens.lg),
                          _saveActions(),
                        ],
                      );
                    }
                    final blockIndex = indices[index - 1];
                    final block = lesson.blocks[blockIndex];
                    final hasPrevious = lesson.blocks
                        .take(blockIndex)
                        .any((b) => b.kind != MathTextbookBlockKind.sourcePage);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
                      child: ColoredCard(
                        color: theme.colorScheme.primary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppTile(
                              flat: true,
                              iconColor: theme.colorScheme.primary,
                              title:
                                  '${mathTextbookBlockLabel(block.kind)}${block.exerciseNumber == null ? '' : ' · ${block.exerciseNumber}'}',
                              subtitle:
                                  '来源：${block.sources.map((s) => 'PDF 第 ${s.page} 页').toSet().join('、')}',
                              trailing: PopupMenuButton<String>(
                                enabled: !_saving,
                                tooltip: '调整内容',
                                itemBuilder: (_) => [
                                  if (hasPrevious)
                                    const PopupMenuItem(
                                      value: 'merge',
                                      child: Text('与上一处内容合并'),
                                    ),
                                  if (hasPrevious)
                                    const PopupMenuItem(
                                      value: 'up',
                                      child: Text('移到上一处之前'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Text('移除内容'),
                                  ),
                                ],
                                onSelected: (action) =>
                                    _blockAction(action, blockIndex),
                              ),
                            ),
                            if (block.spans.isNotEmpty)
                              MathTextbookContent(spans: block.spans),
                            if (block.parentNote.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: SpacingTokens.sm,
                                ),
                                child: Text('家长说明：${block.parentNote}'),
                              ),
                            if (block.warnings.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: SpacingTokens.sm,
                                ),
                                child: Text(
                                  block.warnings.join('；'),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            TextButton.icon(
                              onPressed: _saving ? null : () => _edit(block),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('对照原书并修改'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _MathReviewDialog extends StatefulWidget {
  const _MathReviewDialog({required this.reviewer});
  final String reviewer;
  @override
  State<_MathReviewDialog> createState() => _MathReviewDialogState();
}

class _MathReviewDialogState extends State<_MathReviewDialog> {
  late final _reviewer = TextEditingController(text: widget.reviewer);
  final _checked = [false, false, false];
  @override
  void dispose() {
    _reviewer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('确认本课核对完成'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _reviewer,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: '审核人称呼',
              hintText: '如：妈妈',
            ),
            onChanged: (_) => setState(() {}),
          ),
          for (var i = 0; i < 3; i++)
            MergeSemantics(
              child: AppTile(
                flat: true,
                iconColor: Theme.of(context).colorScheme.primary,
                title: const [
                  '课时范围包含完整例题和相应练习',
                  '分数、上标和竖式均已与原书核对',
                  '图表与待补内容已对照或补充说明',
                ][i],
                subtitle: '',
                trailing: Checkbox(
                  value: _checked[i],
                  onChanged: (value) => setState(() => _checked[i] = value!),
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('继续核对'),
      ),
      FilledButton(
        onPressed: _checked.every((v) => v) && _reviewer.text.trim().isNotEmpty
            ? () => Navigator.pop(context, _reviewer.text.trim())
            : null,
        child: const Text('确认审核并保存'),
      ),
    ],
  );
}

class _MathComparisonPage extends StatelessWidget {
  const _MathComparisonPage({
    required this.book,
    required this.current,
    required this.pending,
  });
  final Textbook book;
  final MathTextbookLesson current;
  final MathTextbookLesson pending;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('比较整理结果'),
        bottom: const TabBar(
          tabs: [
            Tab(text: '当前内容'),
            Tab(text: '新整理结果'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          for (final lesson in [current, pending])
            ListView.builder(
              padding: const EdgeInsets.all(SpacingTokens.md),
              itemCount: lesson.blocks.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Text(
                    lesson.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  );
                }
                final block = lesson.blocks[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(top: SpacingTokens.sm),
                  child: ColoredCard(
                    color: Theme.of(context).colorScheme.primary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTile(
                          flat: true,
                          iconColor: Theme.of(context).colorScheme.primary,
                          title: mathTextbookBlockLabel(block.kind),
                          subtitle: block.sources
                              .map((s) => 'PDF 第 ${s.page} 页')
                              .toSet()
                              .join('、'),
                          trailing: const SizedBox.shrink(),
                        ),
                        if (block.spans.isNotEmpty)
                          MathTextbookContent(spans: block.spans),
                        if (block.parentNote.isNotEmpty)
                          Text('家长说明：${block.parentNote}'),
                        if (block.warnings.isNotEmpty)
                          Text(block.warnings.join('；')),
                        _MathComparisonSource(
                          key: ValueKey(block.id),
                          book: book,
                          sources: block.sources,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.sm,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('保留当前内容'),
              ),
              FilledButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      title: const Text('采纳新整理结果？'),
                      content: const Text('会替换本课当前内容，包括人工修改，并清除本课审核。请先完成比较。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('确认采纳'),
                        ),
                      ],
                    ),
                  );
                  if (context.mounted && confirmed == true) {
                    assertParentAccess(context);
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('采纳新整理结果'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MathComparisonSource extends StatefulWidget {
  const _MathComparisonSource({
    super.key,
    required this.book,
    required this.sources,
  });
  final Textbook book;
  final List<MathTextbookRegion> sources;
  @override
  State<_MathComparisonSource> createState() => _MathComparisonSourceState();
}

class _MathComparisonSourceState extends State<_MathComparisonSource> {
  int _source = 0;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ExpansionTile(
      title: const Text('展开原书对照'),
      children: [
        if (widget.sources.length > 1)
          DropdownButtonFormField<int>(
            initialValue: _source,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(labelText: '来源区域'),
            items: [
              for (var i = 0; i < widget.sources.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    '区域 ${i + 1} · PDF 第 ${widget.sources[i].page} 页',
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _source = value);
            },
          ),
        MathTextbookSourcePreview(
          book: widget.book,
          source: widget.sources[_source],
        ),
      ],
    ),
  );
}
