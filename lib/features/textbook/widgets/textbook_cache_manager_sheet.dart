// lib/features/textbook/widgets/textbook_cache_manager_sheet.dart
//
// 层级：features/textbook/widgets（单本书的缓存管理）
// 职责：列出这本书在本机保存了什么、各占多少空间，并允许逐项清理可重建数据。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

Future<void> showTextbookCacheSheet(BuildContext context, Textbook book) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => TextbookCacheSheet(book: book),
  );
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 KB';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// 一本教材的存储清单。
///
/// 原书只展示不清理（需要重新导入/下载）；课程内容（读一读/认一认/
/// 写一写）可删除，但不能自动重建，确认框里会明确提醒；其余派生缓存
/// 随时可重建。
class TextbookCacheSheet extends ConsumerStatefulWidget {
  const TextbookCacheSheet({super.key, required this.book});

  final Textbook book;

  @override
  ConsumerState<TextbookCacheSheet> createState() => _TextbookCacheSheetState();
}

class _TextbookCacheSheetState extends ConsumerState<TextbookCacheSheet> {
  TextbookStorageUsage? _usage;
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final usage = await ref
          .read(textbookFileServiceProvider)
          .storageUsage(widget.book);
      if (!mounted) return;
      setState(() {
        _usage = usage;
        _loading = false;
        _failed = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<bool> _confirm(
    String label, {
    String? warning,
    bool danger = false,
  }) async {
    final theme = Theme.of(context);
    final verb = danger ? '删除' : '清理';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('$verb$label？'),
        content: Text(
          warning ?? '清理后再次用到会重新生成，不影响原书、课程内容与学习进度。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(verb),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _clear(
    String label,
    Future<void> Function() action, {
    String? warning,
    bool danger = false,
  }) async {
    if (_busy || !await _confirm(label, warning: warning, danger: danger)) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(danger ? '已删除$label' : '已清理$label')),
      );
      await _load();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(danger ? '删除失败，请稍后重试' : '清理失败，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 删除本书：连同书目、阅读位置与学习进度一并清除，不可恢复。
  ///
  /// 顺序：进度 → 课程 → 原书文件与缓存 → 书目登记。书目登记最后删，
  /// 中途失败时本书仍在列表中可重试，不会产生「幽灵书」。
  Future<void> _deleteBook() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('删除本书？'),
        content: const Text(
          '将一并删除：\n'
          '· 原书 PDF 及其封面、目录缓存\n'
          '· 朗读音频\n'
          '· 课程内容（含待确认差异与审核记录）\n'
          '· 书目登记\n'
          '· 全部档案的阅读位置\n'
          '· 全部档案的认一认、写一写学习进度\n\n'
          '学习进度删除后不可恢复；重新导入同一 PDF 将从零开始。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除本书'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = widget.book.pdfSha256;
    setState(() => _busy = true);
    try {
      await ref
          .read(textbookProgressCleanupProvider)
          .deleteBookProgress(id); // 1. 学习进度（可先删，重导入后从零开始）
      await ref
          .read(textbookCourseRepositoryProvider)
          .clear(widget.book); // 2. 课程数据
      await ref
          .read(textbookFileServiceProvider)
          .removePdf(id); // 3. 原书与派生缓存
      await ref
          .read(textbookRepositoryProvider)
          .delete(id); // 4. 书目与阅读位置
      if (!mounted) return;
      // 先关闭 sheet 再失效 provider，否则 sheet 会因 provider 失效重建。
      Navigator.of(context).pop();
      ref.invalidate(textbookLocalListProvider);
      ref.invalidate(textbookPathProvider(id));
      ref.invalidate(textbookCourseProvider(id));
      ref.invalidate(textbookCourseDocumentProvider(id));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败，已删除的部分不会恢复，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row({
    required Key key,
    Key? deleteKey,
    String? deleteTooltip,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onDelete,
  }) {
    final theme = Theme.of(context);
    return AppTile(
      key: key,
      icon: icon,
      iconColor: theme.colorScheme.primary,
      title: title,
      subtitle: subtitle,
      subtitleMaxLines: 2,
      trailing: onDelete == null
          ? Icon(
              Icons.shield_outlined,
              size: SpacingTokens.md,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : Tooltip(
              key: deleteKey,
              message: deleteTooltip ?? '清理$title',
              child: GestureDetector(
                onTap: _busy ? null : onDelete,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: SpacingTokens.minTapTarget,
                  height: SpacingTokens.minTapTarget,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Icon(
                      Icons.delete_outline,
                      size: SpacingTokens.md,
                      color: _busy ? theme.disabledColor : theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = _usage;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            SpacingTokens.md,
            0,
            SpacingTokens.md,
            SpacingTokens.md,
          ),
          child: Column(
            key: const ValueKey('textbook-cache-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.book.title,
                key: const ValueKey('cache-book-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: SpacingTokens.xs),
              Text(
                '缓存管理',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(SpacingTokens.md),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_failed || usage == null)
                const Text(
                  '缓存统计失败，请稍后重试',
                  key: ValueKey('cache-failed'),
                  textAlign: TextAlign.center,
                )
              else ...[
                ColoredCard(
                  color: theme.colorScheme.primary,
                  child: Row(
                    children: [
                      Text(
                        usage.hasDerived ? '可清理缓存' : '暂无缓存',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Text(
                        _formatBytes(usage.derivedBytes),
                        key: const ValueKey('cache-derived-total'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!usage.hasDerived) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    '目录提取、封面和朗读音频会在使用时自动生成。',
                    key: const ValueKey('cache-empty'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: SpacingTokens.sm),
                _row(
                  key: const ValueKey('cache-row-pdf'),
                  icon: Icons.picture_as_pdf_outlined,
                  title: '原书 PDF',
                  subtitle: usage.pdfBytes > 0
                      ? '${_formatBytes(usage.pdfBytes)} · 阅读必需'
                      : '未保存',
                ),
                const SizedBox(height: SpacingTokens.sm),
                _row(
                  key: const ValueKey('cache-row-cover'),
                  deleteKey: const ValueKey('cache-delete-cover'),
                  icon: Icons.image_outlined,
                  title: '封面',
                  subtitle: usage.coverBytes > 0
                      ? '${_formatBytes(usage.coverBytes)} · 可重新生成'
                      : '未生成',
                  onDelete: () => _clear(
                    '封面',
                    () => ref
                        .read(textbookFileServiceProvider)
                        .clearCover(widget.book),
                  ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                _row(
                  key: const ValueKey('cache-row-content'),
                  deleteKey: const ValueKey('cache-delete-content'),
                  icon: Icons.toc_outlined,
                  title: '目录与提取内容',
                  subtitle: usage.contentFiles > 0
                      ? '${usage.contentFiles} 个文件 · '
                          '${_formatBytes(usage.contentBytes)} · 可重新生成'
                      : '未生成',
                  onDelete: () => _clear(
                    '目录与提取内容',
                    () => ref
                        .read(textbookFileServiceProvider)
                        .clearExtractedContent(widget.book),
                  ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                _row(
                  key: const ValueKey('cache-row-audio'),
                  deleteKey: const ValueKey('cache-delete-audio'),
                  icon: Icons.graphic_eq_outlined,
                  title: '朗读音频（句子/字/词）',
                  subtitle: usage.audioFiles > 0
                      ? '${usage.audioFiles} 段 · '
                          '${_formatBytes(usage.audioBytes)} · 可重新生成'
                      : '未生成',
                  onDelete: () => _clear(
                    '朗读音频',
                    () => ref
                        .read(textbookFileServiceProvider)
                        .clearNarration(widget.book),
                  ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                _row(
                  key: const ValueKey('cache-row-course'),
                  deleteKey: const ValueKey('cache-delete-course'),
                  deleteTooltip: '删除课程内容',
                  icon: Icons.school_outlined,
                  title: '课程内容',
                  subtitle: usage.courseBytes > 0
                      ? '${_formatBytes(usage.courseBytes)} · '
                          '读一读/认一认/写一写内容，删除后需重新生成'
                      : '未生成',
                  onDelete: () => _clear(
                    '课程内容',
                    () async {
                      await ref
                          .read(textbookCourseRepositoryProvider)
                          .clear(widget.book);
                      ref.invalidate(
                        textbookCourseProvider(widget.book.pdfSha256),
                      );
                      ref.invalidate(
                        textbookCourseDocumentProvider(widget.book.pdfSha256),
                      );
                    },
                    warning: '读一读、认一认、写一写的内容来自课程数据，删除后不会自动'
                        '恢复，需要重新生成或重新导入课程 JSON。原书、缓存与学习进度'
                        '不受影响。',
                    danger: true,
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('cache-clear-all'),
                        onPressed: _busy || !usage.hasDerived
                            ? null
                            : () => _clear(
                                  '全部缓存',
                                  () => ref
                                      .read(textbookFileServiceProvider)
                                      .clearDerived(widget.book),
                                ),
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('清理全部缓存'),
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    Builder(
                      builder: (context) {
                        final id = widget.book.pdfSha256;
                        final generationBusy = ref
                                .watch(textbookGenerationProvider)[id]
                                ?.running ??
                            false;
                        final downloading = ref
                                .watch(textbookDownloadsProvider)[id]
                                ?.active ??
                            false;
                        final blocked = generationBusy || downloading;
                        final button = OutlinedButton.icon(
                          key: const ValueKey('cache-delete-book'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(color: theme.colorScheme.error),
                          ),
                          onPressed: _busy || blocked ? null : _deleteBook,
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: const Text('删除本书'),
                        );
                        if (!blocked) return button;
                        return Tooltip(
                          message: generationBusy
                              ? '课程整理进行中，请稍后再试'
                              : '下载进行中，请稍后再试',
                          child: button,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
