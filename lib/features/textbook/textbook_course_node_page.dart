import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/domain/textbook_course_mutations.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_course_editor_page.dart';
import 'package:poemath/features/textbook/textbook_source_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';

class TextbookCourseNodePage extends ConsumerStatefulWidget {
  const TextbookCourseNodePage({
    super.key,
    required this.book,
    required this.pack,
    required this.nodeId,
    this.paragraphIds = const [],
    this.vocabularyCategory,
  });
  final Textbook book;
  final TextbookCoursePack pack;
  final String nodeId;
  final List<String> paragraphIds;
  final String? vocabularyCategory;
  @override
  ConsumerState<TextbookCourseNodePage> createState() =>
      _TextbookCourseNodePageState();
}

class _TextbookCourseNodePageState
    extends ConsumerState<TextbookCourseNodePage> {
  late TextbookCoursePack _pack = widget.pack;
  final _reviewer = TextEditingController(text: '家长');
  final _notes = TextEditingController();
  final _checks = <String>{};
  bool _saving = false;
  bool get _isParagraphGroup => widget.paragraphIds.isNotEmpty;
  bool get _isVocabularyGroup => widget.vocabularyCategory != null;
  bool get _isGroup => _isParagraphGroup || _isVocabularyGroup;
  TextbookCourseNode? get _node =>
      _pack.nodes.where((node) => node.id == widget.nodeId).firstOrNull;
  List<TextbookCourseParagraph> get _paragraphs => _pack.lessons
      .expand((lesson) => lesson.paragraphs)
      .where((paragraph) => widget.paragraphIds.contains(paragraph.id))
      .toList(growable: false);
  List<TextbookCourseVocabulary> get _vocabulary {
    final lesson = _pack.lessons
        .where(
          (lesson) => lesson.targets.any((node) => node.id == widget.nodeId),
        )
        .firstOrNull;
    return switch (widget.vocabularyCategory) {
      'recognitionCharacters' => lesson?.recognitionCharacters ?? const [],
      'writingCharacters' => lesson?.writingCharacters ?? const [],
      'words' => lesson?.words ?? const [],
      _ => const [],
    };
  }

  List<TextbookCourseNode> get _reviewNodes {
    if (_isParagraphGroup) return _paragraphs;
    if (_isVocabularyGroup) return _vocabulary;
    final node = _node;
    return node == null ? const [] : [node];
  }

  TextbookCourseLesson? get _paragraphLesson {
    final ids = _paragraphs.map((paragraph) => paragraph.id).toSet();
    return _pack.lessons
        .where(
          (lesson) =>
              ids.isNotEmpty &&
              lesson.paragraphs.any((paragraph) => ids.contains(paragraph.id)),
        )
        .firstOrNull;
  }

  @override
  void dispose() {
    _reviewer.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<TextbookCourseNode?> _pickNode(String action) async {
    final nodes = _reviewNodes;
    if (nodes.length <= 1) return nodes.firstOrNull;
    return showModalBottomSheet<TextbookCourseNode>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '选择要$action的${_isParagraphGroup ? '段落' : '字词'}',
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              for (final (index, node) in nodes.indexed)
                AppTile(
                  flat: true,
                  flatTrailingEdgeAligned: true,
                  iconColor: Theme.of(sheetContext).colorScheme.primary,
                  title: _isParagraphGroup
                      ? '第 ${index + 1} 段'
                      : textbookCourseNodeTitle(node),
                  subtitle: _isParagraphGroup
                      ? (node as TextbookCourseParagraph).text
                      : '',
                  subtitleMaxLines: 2,
                  onTap: () => Navigator.pop(sheetContext, node),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit() async {
    final node = _isGroup ? await _pickNode('编辑') : _node;
    if (node == null || !mounted) return;
    final result = await Navigator.of(context).push<TextbookCoursePack>(
      MaterialPageRoute(
        builder: (_) => TextbookCourseEditorPage(
          book: widget.book,
          pack: _pack,
          node: node,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _pack = result;
        _checks.clear();
      });
    }
  }

  Future<void> _decide(String decision) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      var reviewedJson = _pack.toJson();
      final reviewedAt = DateTime.now();
      for (final node in _reviewNodes) {
        reviewedJson = reviewTextbookCourse(
          input: reviewedJson,
          nodeId: node.id,
          reviewer: _reviewer.text,
          decision: decision,
          checks: _checks.toList(),
          notes: _notes.text,
          at: reviewedAt,
        );
      }
      if (_reviewNodes.isEmpty) {
        reviewedJson = reviewTextbookCourse(
          input: reviewedJson,
          nodeId: widget.nodeId,
          reviewer: _reviewer.text,
          decision: decision,
          checks: _checks.toList(),
          notes: _notes.text,
          at: reviewedAt,
        );
      }
      final reviewed = TextbookCoursePack.fromJson(reviewedJson);
      await ref
          .read(textbookCourseRepositoryProvider)
          .save(widget.book, reviewed, previous: _pack);
      if (mounted) Navigator.pop(context, reviewed);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '教材审核保存失败',
        tag: 'TextbookCourse',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message : '审核保存失败，请重试；填写内容已保留',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_saving) return;
    final node = _isGroup ? await _pickNode('删除') : _node;
    if (node == null || !mounted) return;
    final lesson = _pack.lessons
        .where((l) => l.targets.any((n) => n.id == node.id))
        .firstOrNull;
    if (lesson == null) return;
    try {
      final links = lesson.recitations
          .where((r) => r.ranges.any((p) => p.paragraphId == node.id))
          .length;
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除此项内容？'),
          content: Text(
            links > 0
                ? '此段被 $links 个背诵目标引用。确认后将一并删除这些目标，相关范围需要重新核对。'
                : '此项将从本机草稿移除；重新整理原书不会自动恢复它。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认删除'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
      final updated =
          removeTextbookCourseTarget(_pack, node.id, removeReferences: true);
      setState(() => _saving = true);
      await ref
          .read(textbookCourseRepositoryProvider)
          .save(widget.book, updated, previous: _pack);
      if (mounted) Navigator.pop(context, updated);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message.toString()
                  : '保存失败，内容已保留，请重试',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _heading(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _sourceButton(List<TextbookSourcePage> sources) => TextButton.icon(
        key: const ValueKey('course-source-button'),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, SpacingTokens.minTapTarget),
          padding: const EdgeInsetsDirectional.only(start: SpacingTokens.sm),
          iconSize: SpacingTokens.lg,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _saving || sources.isEmpty
            ? null
            : () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => TextbookCourseSourcePage(
                      book: widget.book,
                      sources: sources,
                    ),
                  ),
                ),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.chevron_right),
        label: const Text('原书'),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = _node;
    final reviewNodes = _reviewNodes;
    final required = reviewNodes.isEmpty
        ? const ['coverage', 'content']
        : {
            for (final current in reviewNodes) ...current.requiredChecks,
          }.toList(growable: false);
    final allChecked = required.isNotEmpty && required.every(_checks.contains);
    final review = reviewNodes
            .map((current) => current.review)
            .where((current) => current.reviewer != null)
            .firstOrNull ??
        node?.review ??
        _pack.review;
    final sources = <TextbookSourcePage>[];
    final sourcePages = <int>{};
    for (final current in reviewNodes) {
      for (final source in current.sources) {
        if (sourcePages.add(source.pdfPage)) sources.add(source);
      }
      if (current is TextbookCourseExercise) {
        for (final source in current.answerSources) {
          if (sourcePages.add(source.pdfPage)) sources.add(source);
        }
      }
    }
    final approved = reviewNodes.isNotEmpty
        ? reviewNodes.every((current) => current.isApproved)
        : _pack.review.approves(
            _pack.toJson(),
            const ['coverage', 'content'],
          );
    final title = _isParagraphGroup
        ? '课文与注音'
        : _isVocabularyGroup
            ? textbookCourseCategoryLabels[widget.vocabularyCategory]!
            : node == null
                ? '整包核对'
                : textbookCourseNodeTitle(node);
    final status = approved
        ? '已通过'
        : _isGroup
            ? textbookCourseReviewLabelFor(reviewNodes)
            : node == null
                ? '待整包核对'
                : textbookCourseReviewLabel(node);
    final paragraphLesson = _paragraphLesson;
    final contentHeading = _isParagraphGroup
        ? paragraphLesson?.title
        : node is TextbookCourseExercise
            ? node.promptHeading?.replaceFirst(RegExp(r'。\s*$'), '')
            : null;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '$title · $status',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (node != null &&
                _pack.lessons.any((l) => l.targets.any((n) => n.id == node.id)))
              IconButton(
                tooltip: '删除此项内容',
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            if (node != null)
              IconButton(
                tooltip: '编辑内容',
                onPressed: _saving ? null : _edit,
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            children: [
              if (node != null)
                ColoredCard(
                  color: theme.colorScheme.primary,
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (contentHeading != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SpacingTokens.xs,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: SpacingTokens.minTapTarget,
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: SpacingTokens.minTapTarget +
                                        SpacingTokens.lg,
                                  ),
                                  child: Text(
                                    contentHeading,
                                    maxLines: _isParagraphGroup ? 1 : null,
                                    overflow: _isParagraphGroup
                                        ? TextOverflow.ellipsis
                                        : null,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: _sourceButton(sources),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            SpacingTokens.md,
                            SpacingTokens.sm,
                            SpacingTokens.md,
                            SpacingTokens.md,
                          ),
                          child: KeyedSubtree(
                            key: const ValueKey('course-content-body'),
                            child: _isParagraphGroup
                                ? TextbookCourseParagraphsContent(
                                    paragraphs: _paragraphs,
                                  )
                                : TextbookCourseContent(
                                    pack: _pack,
                                    node: node,
                                    showExerciseHeading: false,
                                  ),
                          ),
                        ),
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.only(
                            top: SpacingTokens.xs,
                            right: SpacingTokens.xs,
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: _sourceButton(sources),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            SpacingTokens.md,
                            0,
                            SpacingTokens.md,
                            SpacingTokens.md,
                          ),
                          child: KeyedSubtree(
                            key: const ValueKey('course-content-body'),
                            child: _isVocabularyGroup
                                ? TextbookCourseVocabularyContent(
                                    vocabulary: _vocabulary,
                                  )
                                : TextbookCourseContent(
                                    pack: _pack,
                                    node: node,
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                Text(
                  '${_pack.edition.title}\n${_pack.lessons.length} 篇课目 · 内容修订 ${_pack.contentRevision}\n整包核对仅确认内容；发布仍需单独满足许可条件。',
                ),
              if (review.reviewer != null) ...[
                _heading(context, '上次审核'),
                Text(
                  '${review.reviewer} · ${review.reviewedAt!.toLocal().toIso8601String().split('.').first.replaceFirst('T', ' ')}',
                ),
                Text(review.notes ?? ''),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
                child: _ReviewCheckOption(
                  key: const ValueKey('course-review-select-all'),
                  label: '逐项核对',
                  labelStyle: theme.textTheme.titleMedium,
                  trailingCheckbox: true,
                  value: allChecked
                      ? true
                      : required.any(_checks.contains)
                          ? null
                          : false,
                  enabled: !_saving && required.isNotEmpty,
                  onChanged: (selected) => setState(() {
                    if (selected) {
                      _checks.addAll(required);
                    } else {
                      _checks.removeAll(required);
                    }
                  }),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: SpacingTokens.sm,
                  runSpacing: SpacingTokens.xs,
                  children: [
                    for (final check in required)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth,
                        ),
                        child: _ReviewCheckOption(
                          label: textbookCourseCheckLabels[check]!,
                          value: _checks.contains(check),
                          enabled: !_saving,
                          onChanged: (value) => setState(() {
                            if (value) {
                              _checks.add(check);
                            } else {
                              _checks.remove(check);
                            }
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
              TextField(
                controller: _reviewer,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '审核人',
                  helperText: '请填写实际核对人的姓名或称呼',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
              TextField(
                controller: _notes,
                enabled: !_saving,
                minLines: 1,
                maxLines: null,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '核对说明 / 退回原因',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: SpacingTokens.lg),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Wrap(
              spacing: SpacingTokens.md,
              runSpacing: SpacingTokens.sm,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving ||
                          _reviewer.text.trim().isEmpty ||
                          _notes.text.trim().isEmpty
                      ? null
                      : () => _decide('rejected'),
                  child: const Text('退回修改'),
                ),
                FilledButton.icon(
                  onPressed: _saving ||
                          !required.every(_checks.contains) ||
                          _reviewer.text.trim().isEmpty ||
                          _notes.text.trim().isEmpty
                      ? null
                      : () => _decide('approved'),
                  icon: const Icon(Icons.check),
                  label: Text(_saving ? '保存中…' : '通过审核'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewCheckOption extends StatelessWidget {
  const _ReviewCheckOption({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.labelStyle,
    this.trailingCheckbox = false,
  });

  final String label;
  final bool? value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final TextStyle? labelStyle;
  final bool trailingCheckbox;

  @override
  Widget build(BuildContext context) {
    final checkbox = Checkbox(
      value: value,
      tristate: value == null,
      onChanged: enabled ? (_) => onChanged(!(value ?? false)) : null,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
    );
    final labelWidget = Flexible(child: Text(label, style: labelStyle));
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          onTap: enabled ? () => onChanged(!(value ?? false)) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: SpacingTokens.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailingCheckbox) ...[
                    labelWidget,
                    const SizedBox(width: SpacingTokens.xs),
                  ],
                  checkbox,
                  if (!trailingCheckbox) ...[
                    const SizedBox(width: SpacingTokens.xs),
                    labelWidget,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
