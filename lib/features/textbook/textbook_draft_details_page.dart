import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/domain/textbook_course_mutations.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_course_editor_page.dart';
import 'package:poemath/features/textbook/textbook_source_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';

class TextbookDraftDetailsPage extends ConsumerStatefulWidget {
  const TextbookDraftDetailsPage({
    super.key,
    required this.book,
    required this.lessonId,
  });
  final Textbook book;
  final String lessonId;
  @override
  ConsumerState<TextbookDraftDetailsPage> createState() =>
      _TextbookDraftDetailsState();
}

class _TextbookDraftDetailsState
    extends ConsumerState<TextbookDraftDetailsPage> {
  bool _saving = false;
  void _reload() {
    ref.invalidate(textbookCourseDocumentProvider(widget.book.pdfSha256));
    ref.invalidate(textbookCourseProvider(widget.book.pdfSha256));
  }

  void _error(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FormatException ? error.message.toString() : '保存失败，请重试',
          ),
        ),
      );
    }
  }

  Future<void> _resolve(TextbookCourseDocument doc, bool accept) async {
    if (_saving) return;
    if (accept) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('采纳这一课的生成差异？'),
          content: const Text('将采用下方完整生成版本，并使这一课的内容和范围重新待审。请先核对当前版本中的人工修改。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('采纳并重新审核'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(textbookCourseRepositoryProvider).resolveDifference(
            widget.book,
            widget.lessonId,
            accept: accept,
            previous: doc.pack,
          );
      if (mounted) _reload();
    } on Object catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _candidate(
    TextbookCourseDocument doc,
    TextbookDraftCandidate candidate,
  ) async {
    final original = doc.pack.nodes
        .where((n) => candidate.id == '${n.id}-pinyin')
        .firstOrNull;
    if (original != null) {
      await Navigator.of(context).push<TextbookCoursePack>(
        MaterialPageRoute(
          builder: (_) => TextbookCourseEditorPage(
            book: widget.book,
            pack: doc.pack,
            node: original,
            pinyinHints: candidate.pinyin,
          ),
        ),
      );
      if (mounted) _reload();
      return;
    }
    var lessonId = widget.lessonId;
    var category = candidate.category;
    final selected = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('整理为课程内容'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: lessonId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '所属课目'),
                  items: [
                    for (final l in doc.pack.lessons)
                      DropdownMenuItem(
                        value: l.id,
                        child: Text(
                          l.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => update(() => lessonId = v!),
                ),
                const SizedBox(height: SpacingTokens.md),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '内容类别'),
                  items: [
                    for (final e in textbookCourseCategoryLabels.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ),
                  ],
                  onChanged: (v) => update(() => category = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续编辑'),
            ),
          ],
        ),
      ),
    );
    if (selected != true || !mounted) return;
    try {
      final id = 'manual-${DateTime.now().microsecondsSinceEpoch}';
      final pack = addTextbookCourseTarget(
        doc.pack,
        lessonId,
        category,
        id: id,
        text: category == 'recognitionCharacters' ||
                category == 'writingCharacters'
            ? '新'
            : '待填写',
        pages: candidate.pages,
      );
      final saved = await Navigator.of(context).push<TextbookCoursePack>(
        MaterialPageRoute(
          builder: (_) => TextbookCourseEditorPage(
            book: widget.book,
            pack: pack,
            previous: doc.pack,
            node: pack.nodes.firstWhere((n) => n.id == id),
            creating: true,
            initialText: candidate.text,
            pinyinHints: candidate.pinyin,
          ),
        ),
      );
      if (saved != null && mounted) await _dismiss(doc, candidate);
    } on Object catch (error) {
      _error(error);
    }
  }

  Future<void> _dismiss(
    TextbookCourseDocument doc,
    TextbookDraftCandidate candidate,
  ) async {
    try {
      await ref.read(textbookCourseRepositoryProvider).updateGeneration(
            widget.book,
            doc.generation!.runId,
            (g) => g.copyWith(
              removed: {...g.removed, 'candidate:${candidate.id}'}.toList(),
              candidates: {
                ...g.candidates,
                widget.lessonId: (g.candidates[widget.lessonId] ?? [])
                    .where((c) => c.id != candidate.id)
                    .toList(),
              },
            ),
          );
      if (mounted) _reload();
    } on Object catch (error) {
      _error(error);
    }
  }

  Future<void> _range(
    TextbookCourseDocument doc,
    TextbookDraftPlan plan,
  ) async {
    final first = TextEditingController(text: '${plan.startPage}');
    final last = TextEditingController(text: '${plan.endPage}');
    final title = TextEditingController(text: plan.title);
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('调整原书范围'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '正文标题锚点'),
                ),
                TextField(
                  controller: first,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '起始 PDF 页'),
                ),
                TextField(
                  controller: last,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '结束 PDF 页（可含下一课首页）',
                  ),
                ),
                const Text('保存后暂停当前任务。再次继续整理会核对这一课，保留人工修改。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存范围'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
      final start = int.tryParse(first.text);
      final end = int.tryParse(last.text);
      if (start == null ||
          end == null ||
          start < 1 ||
          end < start ||
          end > widget.book.pageCount ||
          title.text.trim().isEmpty) {
        throw const FormatException('请填写有效标题和 PDF 页码范围');
      }
      final repository = ref.read(textbookCourseRepositoryProvider);
      await ref
          .read(textbookGenerationProvider.notifier)
          .stop(widget.book.pdfSha256);
      await repository.updateGeneration(
        widget.book,
        doc.generation!.runId,
        (g) => g.copyWith(
          phase: 'paused',
          completed: g.completed.where((id) => id != plan.id).toList(),
          plans: [
            for (final p in g.plans)
              if (p.id != plan.id)
                p
              else
                TextbookDraftPlan(
                  id: p.id,
                  startPage: start,
                  endPage: end,
                  title: title.text.trim(),
                  nextTitle: p.nextTitle,
                  printedPage: start == p.startPage ? p.printedPage : null,
                  edited: true,
                ),
          ],
        ),
      );
      if (mounted) _reload();
    } on Object catch (error) {
      _error(error);
    } finally {
      first.dispose();
      last.dispose();
      title.dispose();
    }
  }

  Future<void> _page(int page) => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => TextbookCourseSourcePage(
            book: widget.book,
            sources: [
              TextbookSourcePage(page, null, 'text_extracted'),
            ],
          ),
        ),
      );

  Future<void> _retry() async {
    if (_saving) return;
    setState(() => _saving = true);
    final controller = ref.read(textbookGenerationProvider.notifier);
    try {
      final catalog = await ref.read(textbookCatalogProvider.future);
      if (!mounted) return;
      final path =
          await ref.read(textbookPathProvider(widget.book.pdfSha256).future);
      final entry = catalog
          .where((e) => e.book.pdfSha256 == widget.book.pdfSha256)
          .firstOrNull;
      if (path == null || entry == null) {
        throw const FormatException('请先下载或导入对应书库中的原书 PDF');
      }
      await controller.stop(widget.book.pdfSha256);
      if (!mounted) return;
      await controller.start(
        widget.book,
        entry,
        path,
        lessonId: widget.lessonId,
      );
      if (mounted) _reload();
    } on Object catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data =
        ref.watch(textbookCourseDocumentProvider(widget.book.pdfSha256));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('原书与待整理内容')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton(
            onPressed: _reload,
            child: const Text('读取失败，重试'),
          ),
        ),
        data: (doc) {
          final generation = doc?.generation;
          if (doc == null || generation == null) {
            return const Center(child: Text('这份草稿由人工导入，可在课目页直接添加、编辑内容。'));
          }
          final plan = generation.plans
              .where((p) => p.id == widget.lessonId)
              .firstOrNull;
          final candidateList = generation.candidates[widget.lessonId] ?? [];
          final difference = generation.pending[widget.lessonId];
          return ListView(
            padding: const EdgeInsets.all(SpacingTokens.md),
            children: [
              if (plan != null)
                AppTile(
                  flat: true,
                  flatTrailingEdgeAligned: true,
                  icon: Icons.article_outlined,
                  iconColor: theme.colorScheme.primary,
                  title: 'PDF 第${plan.startPage}–${plan.endPage}页',
                  subtitle:
                      '标题锚点：${plan.title} · ${generation.completed.contains(plan.id) ? '已整理，待审核' : '尚待整理'}',
                  onTap: () => _range(doc, plan),
                ),
              if (plan != null)
                TextButton(
                  onPressed: () => _page(plan.startPage),
                  child: const Text('查看原书起始页'),
                ),
              if (generation.errors[widget.lessonId] != null)
                Text('此课整理失败：${generation.errors[widget.lessonId]}'),
              TextButton.icon(
                onPressed: _saving ? null : _retry,
                icon: const Icon(Icons.refresh),
                label: Text(_saving ? '正在整理本课…' : '重新整理本课（保留人工修改）'),
              ),
              if (difference != null) ...[
                const Divider(height: SpacingTokens.xl),
                Text('生成差异', style: theme.textTheme.titleLarge),
                const Text('已保留当前人工版本。核对两个版本后，可采纳完整生成版本或保留当前版本。'),
                for (final view in [
                  doc.pack.lessons
                      .firstWhere((l) => l.id == widget.lessonId)
                      .toJson(),
                  difference,
                ])
                  ColoredCard(
                    color: theme.colorScheme.primary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          identical(view, difference) ? '生成版本' : '当前版本',
                          style: theme.textTheme.titleMedium,
                        ),
                        for (final c in TextbookCoursePack.categories) ...[
                          Text(
                            '${textbookCourseCategoryLabels[c]} · ${(view[c] as List).length}',
                          ),
                          for (final target in view[c] as List)
                            SelectableText(
                              (target as Map)['text'] as String? ??
                                  target['prompt'] as String? ??
                                  target['instruction'] as String? ??
                                  '',
                            ),
                        ],
                      ],
                    ),
                  ),
                Wrap(
                  spacing: SpacingTokens.md,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => _resolve(doc, false),
                      child: const Text('保留当前版本'),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : () => _resolve(doc, true),
                      child: const Text('采纳生成版本'),
                    ),
                  ],
                ),
              ],
              const Divider(height: SpacingTokens.xl),
              Text(
                '待整理内容 · ${candidateList.length}',
                style: theme.textTheme.titleLarge,
              ),
              if (candidateList.isEmpty)
                const Text('没有未分类候选。各类内容是否完整，仍需对照原书核对。'),
              for (final candidate in candidateList)
                Padding(
                  padding: const EdgeInsets.only(top: SpacingTokens.md),
                  child: ColoredCard(
                    color: theme.colorScheme.secondary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(candidate.reason),
                        const SizedBox(height: SpacingTokens.sm),
                        SelectableText(candidate.text),
                        if (candidate.pinyin.isNotEmpty)
                          SelectableText(
                            candidate.pinyin.join(' · '),
                          ),
                        Wrap(
                          spacing: SpacingTokens.sm,
                          children: [
                            for (final page in candidate.pages)
                              TextButton(
                                onPressed: () => _page(page),
                                child: Text('原书第$page页'),
                              ),
                            TextButton(
                              onPressed: () => _candidate(doc, candidate),
                              child: const Text('选择归属并编辑'),
                            ),
                            TextButton(
                              onPressed: () => _dismiss(doc, candidate),
                              child: const Text('忽略此候选'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
