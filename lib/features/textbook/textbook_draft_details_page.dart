import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/theme/typography_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/domain/textbook_course_diff.dart';
import 'package:poemath/domain/textbook_course_mutations.dart';
import 'package:poemath/domain/textbook_pinyin_font.dart';
import 'package:poemath/domain/textbook_text_display.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/textbook_course_editor_page.dart';
import 'package:poemath/features/textbook/textbook_source_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';

typedef _PinyinHint = ({String character, String? decoded, bool valid});

/// 条目短、可以直接列出增删的类别；段落和习题改用差异位置展示。
const _listDifferenceCategories = {
  'recognitionCharacters',
  'writingCharacters',
  'words',
};

List<_PinyinHint> _pinyinHints(TextbookDraftCandidate candidate) {
  final hints = <_PinyinHint>[];
  for (final hint in candidate.pinyin) {
    final separator = hint.indexOf(': ');
    if (separator <= 0) continue;
    final character = hint.substring(0, separator);
    final raw = hint.substring(separator + 2);
    final decoded = decodeTextbookPinyinFont(raw);
    final valid = decoded != null && isTextbookPinyin(decoded);
    hints.add((character: character, decoded: decoded, valid: valid));
  }
  return hints;
}

/// 旧草稿里可能仍存着拼音字体的 ASCII 编码；编辑页展示前统一解码。
List<String> _decodedPinyinHints(TextbookDraftCandidate candidate) => [
      for (final hint in _pinyinHints(candidate))
        '${hint.character}: ${hint.decoded ?? '字体编码待核对'}',
    ];

List<String> _pendingPinyinHints(TextbookDraftCandidate candidate) => [
      for (final hint in _pinyinHints(candidate))
        if (!hint.valid) '${hint.character}: ${hint.decoded ?? '字体编码待核对'}',
    ];

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
            pinyinHints: _decodedPinyinHints(candidate),
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
            pinyinHints: _decodedPinyinHints(candidate),
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
      final navigator = Navigator.of(context, rootNavigator: true);
      final dialog = DialogRoute<bool>(
        context: context,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        builder: (context) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          actionsPadding: const EdgeInsets.fromLTRB(
            SpacingTokens.lg,
            0,
            SpacingTokens.lg,
            SpacingTokens.lg,
          ),
          title: Padding(
            padding: const EdgeInsets.fromLTRB(
              SpacingTokens.lg,
              SpacingTokens.lg,
              SpacingTokens.lg,
              0,
            ),
            child: Row(
              children: [
                const Expanded(child: Text('调整原书范围')),
                const SizedBox(width: SpacingTokens.sm),
                TextButton(
                  onPressed: () => _page(plan.startPage),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: AlignmentDirectional.centerEnd,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('原书页'),
                      // 补偿 chevron 字形的右侧留白，对齐保存按钮的可见边缘。
                      Transform.translate(
                        offset: const Offset(SpacingTokens.sm, 0),
                        child: const Icon(
                          Icons.chevron_right,
                          size: SpacingTokens.lg,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
      final yes = await navigator.push(dialog);
      // 输入框会随退出动画继续构建，等路由移除后再释放控制器。
      await dialog.completed;
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
    final contentStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('原书与待整理内容'),
        actions: [
          IconButton(
            tooltip: _saving ? '正在整理本课…' : '重新整理本课',
            onPressed: _saving || data.asData?.value?.generation == null
                ? null
                : _retry,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
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
          final currentView = doc.pack.lessons
              .firstWhere((l) => l.id == widget.lessonId)
              .toJson();
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
              if (generation.errors[widget.lessonId] != null)
                Text('此课整理失败：${generation.errors[widget.lessonId]}'),
              if (difference != null) ...[
                const Divider(height: SpacingTokens.xl),
                Text('生成差异', style: theme.textTheme.titleLarge),
                const Text('已保留当前人工版本。核对两个版本后，可采纳完整生成版本或保留当前版本。'),
                const SizedBox(height: SpacingTokens.md),
                _DifferenceSummary(
                  difference: textbookCourseDiff(
                    current: currentView,
                    generated: difference,
                    categories: TextbookCoursePack.categories,
                  ),
                ),
                for (final (label, view) in [
                  ('当前版本', currentView),
                  ('生成版本', difference),
                ])
                  ColoredCard(
                    color: theme.colorScheme.primary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        for (final category
                            in TextbookCoursePack.categories) ...[
                          const SizedBox(height: SpacingTokens.md),
                          Text(
                            '${textbookCourseCategoryLabels[category]} · '
                            '${((view[category] as List?) ?? const []).length}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: TypographyTokens.fsSection,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if ((view[category] as List?)?.isNotEmpty ?? false)
                            SelectableText(
                              textbookCategoryContent(
                                category,
                                view[category] as List,
                              ),
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
                style: theme.textTheme.titleMedium,
              ),
              if (candidateList.isEmpty)
                Text(
                  '没有未分类候选。各类内容是否完整，仍需对照原书核对。',
                  style: contentStyle,
                ),
              for (final candidate in candidateList)
                Padding(
                  padding: const EdgeInsets.only(top: SpacingTokens.md),
                  child: ColoredCard(
                    color: theme.colorScheme.secondary,
                    padding: const EdgeInsets.fromLTRB(
                      SpacingTokens.md,
                      SpacingTokens.md,
                      SpacingTokens.md,
                      SpacingTokens.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(candidate.reason, style: contentStyle),
                        const SizedBox(height: SpacingTokens.sm),
                        SelectableText(
                          textbookContinuousText(candidate.text),
                          style: contentStyle,
                        ),
                        if (candidate.pinyin.isNotEmpty) ...[
                          const SizedBox(height: SpacingTokens.xs),
                          Text(
                            _pendingPinyinHints(candidate).isEmpty
                                ? '原书注音线索已识别；如无缺失，可点右上角重新整理本课。'
                                : '待补齐：${_pendingPinyinHints(candidate).join(' · ')}',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: contentStyle,
                          ),
                        ],
                        TextButtonTheme(
                          data: TextButtonThemeData(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: SpacingTokens.sm,
                              ),
                              minimumSize: const Size(
                                0,
                                SpacingTokens.minTapTarget,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
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

class _DifferenceSummary extends StatelessWidget {
  const _DifferenceSummary({required this.difference});

  final TextbookCourseDifference difference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final changed = difference.categories.where((c) => !c.isSame).toList();
    return ColoredCard(
      color: theme.colorScheme.tertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '差异摘要',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          if (changed.isEmpty && !difference.hasPinyinDifference)
            Text('两个版本的可见内容一致。', style: style)
          else ...[
            for (final category in changed) ...[
              Text(
                '${textbookCourseCategoryLabels[category.category]}：'
                '当前 ${category.currentCount} 项 · 生成 ${category.generatedCount} 项',
                style: style?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (category.window case final window?)
                Text(
                  '差异位置：当前「${window.current}」· '
                  '生成「${window.generated}」',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              if (category.removed.isNotEmpty &&
                  _listDifferenceCategories.contains(category.category))
                Text(
                  '仅当前版本：${category.removed.join('、')}',
                  style: style,
                ),
              if (category.added.isNotEmpty &&
                  _listDifferenceCategories.contains(category.category))
                Text(
                  '仅生成版本：${category.added.join('、')}',
                  style: style,
                ),
            ],
            if (difference.hasPinyinDifference)
              Text(
                '正文注音完整度：当前 ${difference.currentAnnotatedParagraphs}/'
                '${difference.currentParagraphs} 段 · '
                '生成 ${difference.generatedAnnotatedParagraphs}/'
                '${difference.generatedParagraphs} 段',
                style: style,
              ),
          ],
        ],
      ),
    );
  }
}
