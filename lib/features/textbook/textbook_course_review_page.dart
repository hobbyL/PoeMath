import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/domain/textbook_course_mutations.dart';
import 'package:poemath/features/textbook/textbook_course_editor_page.dart';
import 'package:poemath/features/textbook/textbook_draft_details_page.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_generation_controller.dart';
import 'package:poemath/features/textbook/textbook_course_node_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';

class TextbookCourseReviewPage extends ConsumerStatefulWidget {
  const TextbookCourseReviewPage({
    super.key,
    required this.bookId,
    this.pickDraftPath,
  });
  final String bookId;
  final Future<String?> Function()? pickDraftPath;
  @override
  ConsumerState<TextbookCourseReviewPage> createState() =>
      _TextbookCourseReviewPageState();
}

class _TextbookCourseReviewPageState
    extends ConsumerState<TextbookCourseReviewPage>
    with WidgetsBindingObserver {
  bool _importing = false;
  bool _attempted = false;
  bool _starting = false;
  late final TextbookGenerationController _generationController;
  @override
  void initState() {
    super.initState();
    _generationController = ref.read(textbookGenerationProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generationController.pause(widget.bookId);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _generationController.pause(widget.bookId);
    }
  }

  Future<void> _generate(Textbook book, {bool refresh = false}) async {
    if (_starting || _importing) return;
    _starting = true;
    try {
      final catalog = await ref.read(textbookCatalogProvider.future);
      if (!mounted) return;
      final entry =
          catalog.where((e) => e.book.pdfSha256 == book.pdfSha256).firstOrNull;
      final path = await ref.read(textbookPathProvider(book.pdfSha256).future);
      if (!mounted) return;
      if (entry == null || path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              path == null
                  ? '请先下载或导入这本书的 PDF'
                  : '此 PDF 尚无可核验的书目来源，可阅读原书或导入课程草稿',
            ),
          ),
        );
        return;
      }
      await _generationController.start(book, entry, path, refresh: refresh);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '课程整理准备失败',
        tag: 'TextbookCourse',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('原书或书目读取失败，请重试整理'),
          ),
        );
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _export(Textbook book) async {
    try {
      final pack = await ref.read(textbookCourseRepositoryProvider).load(book);
      if (pack == null || !mounted) return;
      await FilePicker.saveFile(
        dialogTitle: '导出待审核草稿',
        fileName: 'course-${book.pdfSha256.substring(0, 12)}-draft.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(
          utf8.encode(
            const JsonEncoder.withIndent('  ').convert(pack.toJson()),
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('草稿导出失败，请重试')));
      }
    }
  }

  Future<void> _showMore(Textbook book) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => Consumer(
        builder: (sheetContext, sheetRef, _) {
          final pack = sheetRef
              .watch(textbookCourseProvider(book.pdfSha256))
              .valueOrNull;
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '更多',
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  if (pack != null)
                    AppTile(
                      flat: true,
                      flatTrailingEdgeAligned: true,
                      icon: Icons.info_outline,
                      iconColor: Theme.of(sheetContext).colorScheme.primary,
                      title: '版次与来源',
                      subtitle: '',
                      trailingText: textbookCourseReviewLabel(pack.edition),
                      onTap: () => Navigator.pop(sheetContext, 'edition'),
                    ),
                  AppTile(
                    flat: true,
                    flatTrailingEdgeAligned: true,
                    icon: Icons.file_open_outlined,
                    iconColor: Theme.of(sheetContext).colorScheme.primary,
                    title: '导入课程草稿',
                    subtitle: '',
                    onTap: () => Navigator.pop(sheetContext, 'import'),
                  ),
                  AppTile(
                    flat: true,
                    flatTrailingEdgeAligned: true,
                    icon: Icons.file_download_outlined,
                    iconColor: Theme.of(sheetContext).colorScheme.primary,
                    title: '导出草稿 JSON',
                    subtitle: '',
                    onTap: () => Navigator.pop(sheetContext, 'export'),
                  ),
                  AppTile(
                    flat: true,
                    flatTrailingEdgeAligned: true,
                    icon: Icons.refresh,
                    iconColor: Theme.of(sheetContext).colorScheme.primary,
                    title: '重新整理原书',
                    subtitle: '保留人工修改',
                    onTap: () => Navigator.pop(sheetContext, 'refresh'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || _importing) return;
    switch (action) {
      case 'edition':
        final pack =
            ref.read(textbookCourseProvider(book.pdfSha256)).valueOrNull;
        if (pack != null) {
          await _open(book, pack, nodeId: pack.edition.id);
        }
      case 'import':
        await _import(book);
      case 'export':
        await _export(book);
      case 'refresh':
        await _generate(book, refresh: true);
    }
  }

  Future<void> _import(Textbook book) async {
    if (_importing) return;
    final files = ref.read(textbookFileServiceProvider);
    setState(() => _importing = true);
    String? pickerPath;
    try {
      if (widget.pickDraftPath != null) {
        pickerPath = await widget.pickDraftPath!();
      } else {
        final selection = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        pickerPath = selection?.files.single.path;
      }
      if (pickerPath == null || !mounted) return;
      final repository = ref.read(textbookCourseRepositoryProvider);
      final pack = await repository.readDraft(book, pickerPath);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入课程草稿？'),
          content: Text(
            '${pack.edition.title} · ${pack.lessons.length} 篇课目\n\n如果已有草稿，将替换本机内容和审核结果。导入文件中的待审状态会保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入草稿'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _generationController.stop(book.pdfSha256);
      await repository.importDraft(book, pack);
      if (mounted) {
        ref.invalidate(textbookCourseProvider(book.pdfSha256));
        ref.invalidate(textbookCourseDocumentProvider(book.pdfSha256));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已导入课程草稿，可逐项编辑和审核')));
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '课程草稿导入失败',
        tag: 'TextbookCourse',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message : '课程草稿导入失败，请重试',
            ),
          ),
        );
      }
    } finally {
      if (pickerPath != null) {
        try {
          await files.discardPickerCopy(pickerPath);
        } on Object catch (error) {
          AppLogger.e('课程导入临时副本清理失败', tag: 'TextbookCourse', error: error);
        }
      }
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _open(
    Textbook book,
    TextbookCoursePack pack, {
    String? nodeId,
    String? lessonId,
  }) async {
    try {
      // A just-finished generation may still be refreshing the visible list.
      // Open the durable latest pack so the editor doesn't inherit that snapshot.
      pack =
          await ref.read(textbookCourseRepositoryProvider).load(book) ?? pack;
      if (!mounted) return;
      await Navigator.of(context).push<Object?>(
        MaterialPageRoute(
          builder: (_) => lessonId != null
              ? _TextbookCourseLessonPage(
                  book: book,
                  pack: pack,
                  lessonId: lessonId,
                )
              : TextbookCourseNodePage(book: book, pack: pack, nodeId: nodeId!),
        ),
      );
      if (mounted) ref.invalidate(textbookCourseProvider(book.pdfSha256));
      if (mounted) {
        ref.invalidate(textbookCourseDocumentProvider(book.pdfSha256));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('课程读取失败，请重试打开'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = ref
        .watch(textbookListProvider)
        .where((book) => book.pdfSha256 == widget.bookId)
        .firstOrNull;
    return PopScope(
      canPop: !_importing,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('内容审核'),
          actions: [
            if (book != null)
              IconButton(
                tooltip: '更多',
                onPressed: _importing ? null : () => _showMore(book),
                icon: const Icon(Icons.more_vert),
              ),
          ],
        ),
        body: book == null
            ? const Center(child: Text('找不到教材，请返回书籍管理重新选择。'))
            : _importing
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: SpacingTokens.md),
                        Text('正在导入课程草稿…'),
                      ],
                    ),
                  )
                : ref.watch(textbookCourseProvider(widget.bookId)).when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(SpacingTokens.lg),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('课程草稿读取失败。可重试，或重新导入有效草稿。'),
                              TextButton(
                                onPressed: () => ref.invalidate(
                                  textbookCourseProvider(
                                    widget.bookId,
                                  ),
                                ),
                                child: const Text('重试读取'),
                              ),
                              TextButton(
                                onPressed: () => _import(book),
                                child: const Text('重新导入'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      data: (pack) {
                        final path =
                            ref.watch(textbookPathProvider(widget.bookId));
                        final entries = ref.watch(textbookCatalogProvider);
                        if (pack == null &&
                            !_attempted &&
                            path.hasValue &&
                            entries.hasValue) {
                          _attempted = true;
                          if (path.valueOrNull != null &&
                              entries.valueOrNull!.any(
                                (e) => e.book.pdfSha256 == widget.bookId,
                              )) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _generate(book);
                            });
                          }
                        }
                        return pack == null
                            ? SingleChildScrollView(
                                child: Center(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.all(SpacingTokens.lg),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.fact_check_outlined,
                                          size: SpacingTokens.minTapTarget,
                                        ),
                                        const SizedBox(
                                          height: SpacingTokens.md,
                                        ),
                                        const Text('从原书整理课程草稿'),
                                        const SizedBox(
                                          height: SpacingTokens.sm,
                                        ),
                                        Text(
                                          path.isLoading || entries.isLoading
                                              ? '正在检查本机原书与书目…'
                                              : path.hasError ||
                                                      entries.hasError
                                                  ? '原书或书目读取失败，可从右上角重试整理。'
                                                  : path.valueOrNull == null
                                                      ? '请先下载或导入原书 PDF。之后首次进入会在本机逐课整理，内容仍需审核。'
                                                      : !entries.valueOrNull!
                                                              .any(
                                                          (e) =>
                                                              e.book
                                                                  .pdfSha256 ==
                                                              widget.bookId,
                                                        )
                                                          ? '此 PDF 尚无可核验的书目来源，暂不支持自动整理。可阅读原书，或从右上角导入课程草稿。'
                                                          : '在本机逐课整理；完成的课目会逐课显示。无法可靠归类的内容会保留待整理。',
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(
                                          height: SpacingTokens.lg,
                                        ),
                                        _generationStatus(book),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : _content(book, pack);
                      },
                    ),
      ),
    );
  }

  Widget _content(Textbook book, TextbookCoursePack pack) {
    final theme = Theme.of(context);
    final nodes = pack.nodes.toList();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          children: [
            Text(pack.edition.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              '${pack.edition.editionLabel} · ${nodes.where((node) => node.isApproved).length}/${nodes.length} 项已通过',
            ),
            const SizedBox(height: SpacingTokens.md),
            _generationStatus(book),
            for (final unit in pack.units) ...[
              const Divider(height: SpacingTokens.xl),
              Wrap(
                key: ValueKey('course-unit-${unit.id}'),
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: SpacingTokens.md,
                children: [
                  Text(unit.title, style: theme.textTheme.titleMedium),
                  TextButton.icon(
                    onPressed: () => _open(book, pack, nodeId: unit.id),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, SpacingTokens.minTapTarget),
                      padding: const EdgeInsetsDirectional.only(
                        start: SpacingTokens.sm,
                      ),
                      iconSize: SpacingTokens.lg,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_right),
                    label: Text(
                      '单元审核 · ${textbookCourseReviewLabel(unit)}',
                    ),
                  ),
                ],
              ),
              for (final id in unit.lessonIds)
                Builder(
                  builder: (context) {
                    final lesson =
                        pack.lessons.firstWhere((lesson) => lesson.id == id);
                    return AppTile(
                      key: ValueKey('course-lesson-$id'),
                      flat: true,
                      flatTrailingEdgeAligned: true,
                      iconColor: theme.colorScheme.primary,
                      title:
                          '${lesson.lessonNumber == null ? '' : '${lesson.lessonNumber} · '}${lesson.title}',
                      subtitle:
                          '${lesson.targets.where((node) => node.isApproved).length}/${lesson.targets.length} 项内容已通过',
                      trailingText: textbookCourseReviewLabel(lesson),
                      onTap: () => _open(book, pack, lessonId: id),
                    );
                  },
                ),
            ],
            const Divider(height: SpacingTokens.xl),
            AppTile(
              flat: true,
              flatTrailingEdgeAligned: true,
              iconColor: theme.colorScheme.primary,
              title: '整包核对',
              subtitle: pack.isPublishable
                  ? '已满足发布条件'
                  : '还有 ${pack.publicationIssues.length} 项发布条件待处理',
              onTap: () => _open(book, pack, nodeId: '@pack'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _generationStatus(Textbook book) {
    final progress = ref.watch(textbookGenerationProvider)[book.pdfSha256];
    final generation = ref
        .watch(textbookCourseDocumentProvider(book.pdfSha256))
        .valueOrNull
        ?.generation;
    if (progress == null && generation == null) return const SizedBox.shrink();
    final running = progress?.running ?? false;
    final done = progress?.done ?? generation!.completed.length;
    final total = progress?.total ?? generation!.plans.length;
    final ready = !running && (progress?.phase ?? generation?.phase) == 'ready';
    if (ready) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
      child: ColoredCard(
        color: Theme.of(context).colorScheme.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              progress?.message ?? '已保存 $done/$total 课，可继续整理',
            ),
            if (running) ...[
              const SizedBox(height: SpacingTokens.sm),
              LinearProgressIndicator(value: total > 0 ? done / total : null),
            ],
            TextButton(
              onPressed: running
                  ? () => ref
                      .read(textbookGenerationProvider.notifier)
                      .pause(book.pdfSha256)
                  : () => _generate(book),
              child: Text(running ? '暂停整理' : '继续整理'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextbookCourseLessonPage extends ConsumerStatefulWidget {
  const _TextbookCourseLessonPage({
    required this.book,
    required this.pack,
    required this.lessonId,
  });
  final Textbook book;
  final TextbookCoursePack pack;
  final String lessonId;
  @override
  ConsumerState<_TextbookCourseLessonPage> createState() =>
      _TextbookCourseLessonPageState();
}

class _TextbookCourseLessonPageState
    extends ConsumerState<_TextbookCourseLessonPage> {
  late TextbookCoursePack _pack = widget.pack;
  bool _reloading = false;
  String? _error;
  TextbookCourseLesson get _lesson =>
      _pack.lessons.firstWhere((lesson) => lesson.id == widget.lessonId);

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _reloading = true;
        _error = null;
      });
    }
    try {
      final pack =
          await ref.read(textbookCourseRepositoryProvider).load(widget.book);
      if (pack == null ||
          !pack.lessons.any((lesson) => lesson.id == widget.lessonId)) {
        throw const FormatException('课程草稿已变化，请返回重新选择');
      }
      if (mounted) setState(() => _pack = pack);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error is FormatException ? error.message : '更新后的课程读取失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  Future<void> _openNode(String id, {String? vocabularyCategory}) async {
    await Navigator.of(context).push<TextbookCoursePack>(
      MaterialPageRoute(
        builder: (_) => TextbookCourseNodePage(
          book: widget.book,
          pack: _pack,
          nodeId: id,
          vocabularyCategory: vocabularyCategory,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _openParagraphs() async {
    final paragraphs = _lesson.paragraphs;
    if (paragraphs.isEmpty) return;
    await Navigator.of(context).push<TextbookCoursePack>(
      MaterialPageRoute(
        builder: (_) => TextbookCourseNodePage(
          book: widget.book,
          pack: _pack,
          nodeId: paragraphs.first.id,
          paragraphIds: [for (final paragraph in paragraphs) paragraph.id],
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _coverage() async {
    await Navigator.of(context).push<TextbookCoursePack>(
      MaterialPageRoute(
        builder: (_) => _TextbookCoveragePage(
          book: widget.book,
          pack: _pack,
          lesson: _lesson,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _add(String category) async {
    try {
      final id = 'manual-${DateTime.now().microsecondsSinceEpoch}';
      final temporary = addTextbookCourseTarget(
        _pack,
        widget.lessonId,
        category,
        id: id,
        text: category == 'recognitionCharacters' ||
                category == 'writingCharacters'
            ? '新'
            : '待填写',
      );
      await Navigator.of(context).push<TextbookCoursePack>(
        MaterialPageRoute(
          builder: (_) => TextbookCourseEditorPage(
            book: widget.book,
            pack: temporary,
            node: temporary.nodes.firstWhere((n) => n.id == id),
            previous: _pack,
            creating: true,
            clearInitialText: true,
          ),
        ),
      );
      if (mounted) await _reload();
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    }
  }

  Future<void> _draftDetails() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TextbookDraftDetailsPage(
          book: widget.book,
          lessonId: widget.lessonId,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lesson = _lesson;
    final groups = <String, List<TextbookCourseNode>>{
      'paragraphs': lesson.paragraphs,
      'recognitionCharacters': lesson.recognitionCharacters,
      'writingCharacters': lesson.writingCharacters,
      'words': lesson.words,
      'recitations': lesson.recitations,
      'exercises': lesson.exercises,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(lesson.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '核对内容范围',
            onPressed: _reloading || _error != null ? null : _coverage,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(SpacingTokens.minTapTarget),
            ),
            icon: const Icon(Icons.fact_check_outlined),
          ),
        ],
      ),
      body: _reloading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(onPressed: _reload, child: const Text('重试读取')),
                    ],
                  ),
                )
              : SafeArea(
                  top: false,
                  bottom: false,
                  child: ListView(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    children: [
                      AppTile(
                        flat: true,
                        flatTrailingEdgeAligned: true,
                        icon: Icons.auto_stories_outlined,
                        iconColor: theme.colorScheme.primary,
                        title: '原书范围与待整理内容',
                        subtitle: '核对标题起点、局部注音、未分类内容及生成差异',
                        onTap: _draftDetails,
                      ),
                      for (final entry in groups.entries) ...[
                        const Divider(height: SpacingTokens.xl),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              entry.key == 'paragraphs'
                                  ? textbookCourseCategoryLabels[entry.key]!
                                  : '${textbookCourseCategoryLabels[entry.key]} · ${entry.value.length}',
                              style: theme.textTheme.titleMedium,
                            ),
                            TextButton.icon(
                              onPressed: () => _add(entry.key),
                              icon: const Icon(Icons.add),
                              label: const Text('添加'),
                            ),
                          ],
                        ),
                        const SizedBox(height: SpacingTokens.xs),
                        if (lesson.coverage[entry.key] !=
                            TextbookCoverage.pending)
                          Text(
                            textbookCourseCoverageLabels[
                                lesson.coverage[entry.key]]!,
                            style: theme.textTheme.bodySmall,
                          ),
                        if (entry.value.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: SpacingTokens.md,
                            ),
                            child: Text(
                              lesson.coverage[entry.key] ==
                                      TextbookCoverage.notApplicable
                                  ? '已核对：原书无此要求'
                                  : '尚未整理此类内容，可对照原书添加。',
                            ),
                          ),
                        if (entry.value.isNotEmpty &&
                            (entry.key == 'paragraphs' ||
                                entry.value.first is TextbookCourseVocabulary))
                          AppTile(
                            key: ValueKey('course-target-${entry.key}'),
                            flat: true,
                            flatTrailingEdgeAligned: true,
                            iconColor: theme.colorScheme.primary,
                            title: '',
                            subtitle: entry.value
                                .cast<TextbookCourseParagraph>()
                                .map((paragraph) => paragraph.text)
                                .join(' ')
                                .replaceAll(RegExp(r'\s+'), ' ')
                                .trim(),
                            subtitleMaxLines: 2,
                            trailingText: textbookCourseReviewLabelFor(
                              entry.value,
                            ),
                            onTap: entry.key == 'paragraphs'
                                ? _openParagraphs
                                : () => _openNode(
                                      entry.value.first.id,
                                      vocabularyCategory: entry.key,
                                    ),
                          )
                        else
                          for (final node in entry.value)
                            AppTile(
                              key: ValueKey('course-target-${node.id}'),
                              flat: true,
                              flatTrailingEdgeAligned: true,
                              iconColor: theme.colorScheme.primary,
                              title: node is TextbookCourseParagraph
                                  ? node.text
                                  : textbookCourseNodeTitle(node),
                              subtitle: '',
                              subtitleMaxLines: 2,
                              trailingText: textbookCourseReviewLabel(node),
                              onTap: () => _openNode(node.id),
                            ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _TextbookCoveragePage extends ConsumerStatefulWidget {
  const _TextbookCoveragePage({
    required this.book,
    required this.pack,
    required this.lesson,
  });
  final Textbook book;
  final TextbookCoursePack pack;
  final TextbookCourseLesson lesson;
  @override
  ConsumerState<_TextbookCoveragePage> createState() =>
      _TextbookCoveragePageState();
}

class _TextbookCoveragePageState extends ConsumerState<_TextbookCoveragePage> {
  late final _values = Map<String, TextbookCoverage>.of(widget.lesson.coverage);
  bool _saving = false;

  Future<void> _pickCoverage(String category) async {
    if (_saving) return;
    final hasContent =
        (widget.lesson.toJson()[category] as List<dynamic>).isNotEmpty;
    final value = await showModalBottomSheet<TextbookCoverage>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  textbookCourseCategoryLabels[category]!,
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                for (final entry in textbookCourseCoverageLabels.entries)
                  if (entry.key == TextbookCoverage.pending ||
                      hasContent == (entry.key == TextbookCoverage.complete))
                    Semantics(
                      selected: _values[category] == entry.key,
                      child: AppTile(
                        flat: true,
                        flatTrailingEdgeAligned: true,
                        iconColor: Theme.of(sheetContext).colorScheme.primary,
                        title: entry.value,
                        subtitle: '',
                        trailingIcon: _values[category] == entry.key
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        onTap: () => Navigator.pop(sheetContext, entry.key),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
    if (value != null && mounted && !_saving) {
      setState(() => _values[category] = value);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final pack =
          updateTextbookCourseCoverage(widget.pack, widget.lesson.id, _values);
      await ref
          .read(textbookCourseRepositoryProvider)
          .save(widget.book, pack, previous: widget.pack);
      if (mounted) Navigator.pop(context, pack);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(error is FormatException ? error.message : '保存失败，请重试'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('核对内容范围')),
        body: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
                child: Text('请逐类对照原书。“原书无此要求”需要确认，不能因为草稿为空就选择。'),
              ),
              const SizedBox(height: SpacingTokens.sm),
              for (final category in TextbookCoursePack.categories)
                AppTile(
                  key: ValueKey('coverage-$category'),
                  flat: true,
                  flatTrailingEdgeAligned: true,
                  iconColor: Theme.of(context).colorScheme.primary,
                  title: textbookCourseCategoryLabels[category]!,
                  subtitle: '',
                  trailingText: _values[category] == TextbookCoverage.pending
                      ? null
                      : textbookCourseCoverageLabels[_values[category]]!,
                  onTap: _saving ? null : () => _pickCoverage(category),
                ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存范围核对'),
            ),
          ),
        ),
      ),
    );
  }
}
