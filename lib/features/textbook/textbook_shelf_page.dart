import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/features/textbook/providers/textbook_download_controller.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_cover_grid.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_cover.dart';

class TextbookShelfPage extends ConsumerStatefulWidget {
  const TextbookShelfPage({super.key});
  @override
  ConsumerState<TextbookShelfPage> createState() => _TextbookShelfPageState();
}

class _TextbookShelfPageState extends ConsumerState<TextbookShelfPage> {
  Future<void> _open(TextbookCatalogEntry entry) async {
    await context.push(AppRoutes.textbookDetailOf(entry.book.pdfSha256));
    if (mounted) setState(() {});
  }

  Future<void> _read(TextbookCatalogEntry entry) async {
    await context.push(AppRoutes.textbookReadOf(entry.book.pdfSha256));
    if (mounted) setState(() {});
  }

  Widget _bookCard(
    TextbookCatalogEntry entry,
    TextStyle textStyle,
  ) {
    final book = entry.book;
    final theme = Theme.of(context);
    final path = ref.watch(textbookPathProvider(book.pdfSha256));
    final download = ref.watch(textbookDownloadsProvider)[book.pdfSha256];
    final installed = path.valueOrNull != null;
    final reading = ref
        .watch(textbookRepositoryProvider)
        .reading(ProfileScope.currentId, book.pdfSha256);
    final status = download?.label ??
        (installed
            ? '已下载 · 第 ${reading.page.clamp(1, book.pageCount)} 页'
            : path.isLoading
                ? '检查本地文件中'
                : '未下载 · ${(book.fileSize / (1024 * 1024)).toStringAsFixed(1)} MB');
    final active = download?.active == true;
    final failed = download?.status == TextbookDownloadStatus.failed;
    final action = active
        ? '取消下载${book.volumeLabel}'
        : installed
            ? '阅读${book.volumeLabel}'
            : failed
                ? '重试下载${book.volumeLabel}'
                : '下载${book.volumeLabel}';
    return ColoredCard(
      key: ValueKey('textbook-download-card-${book.pdfSha256}'),
      color: theme.colorScheme.primary,
      padding: EdgeInsets.zero,
      onTap: () => _open(entry),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Semantics(
                label: book.title,
                image: true,
                excludeSemantics: true,
                child: entry.coverAsset == null
                    ? TextbookCoverPlaceholder(
                        title: book.title,
                        status: book.volumeLabel,
                      )
                    : Image.asset(
                        entry.coverAsset!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => TextbookCoverPlaceholder(
                          title: book.title,
                          status: book.volumeLabel,
                        ),
                      ),
              ),
            ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: SpacingTokens.minTapTarget + SpacingTokens.sm,
                ),
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        SpacingTokens.sm,
                        SpacingTokens.sm,
                        SpacingTokens.sm,
                        SpacingTokens.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Tooltip(
                            message: entry.editionLabel,
                            child: Text(
                              entry.editionLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textStyle,
                            ),
                          ),
                          const SizedBox(height: SpacingTokens.xs),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(
                              right: SpacingTokens.minTapTarget,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: SpacingTokens.lg,
                              ),
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                heightFactor: 1,
                                child: Tooltip(
                                  message: status,
                                  child: Text(
                                    status,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textStyle.copyWith(
                                      color: failed
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // The hit target extends upward; it must not add 44px to
                    // the status line or leave its icon floating above the end.
                    PositionedDirectional(
                      end: SpacingTokens.sm,
                      bottom: SpacingTokens.sm,
                      child: IconButton(
                        style: IconButton.styleFrom(
                          fixedSize:
                              const Size.square(SpacingTokens.minTapTarget),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.standard,
                          padding: EdgeInsets.zero,
                          alignment: Alignment.bottomCenter,
                        ),
                        tooltip: action,
                        icon: Icon(
                          active
                              ? Icons.close
                              : installed
                                  ? Icons.auto_stories_outlined
                                  : failed
                                      ? Icons.refresh
                                      : Icons.download_outlined,
                          size: SpacingTokens.lg,
                        ),
                        onPressed: () {
                          final controller =
                              ref.read(textbookDownloadsProvider.notifier);
                          if (active) {
                            controller.cancel(book.pdfSha256);
                          } else if (installed) {
                            _read(entry);
                          } else {
                            controller.download(entry);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(textbookCatalogProvider);
    final textStyle = DefaultTextStyle.of(context)
        .style
        .merge(theme.textTheme.bodySmall)
        .copyWith(height: 1.5);
    return Scaffold(
      appBar: AppBar(title: const Text('教材下载')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            catalog.when(
              data: (entries) => entries.isEmpty
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('暂无可下载书籍')),
                    )
                  : TextbookCoverGrid(
                      itemCount: entries.length,
                      naturalRowHeight: true,
                      itemBuilder: (_, index) =>
                          _bookCard(entries[index], textStyle),
                    ),
              loading: () => const SliverToBoxAdapter(
                child: LinearProgressIndicator(),
              ),
              error: (_, __) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: ColoredCard(
                    color: theme.colorScheme.primary,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('教材目录暂时无法读取'),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(textbookCatalogProvider),
                          child: const Text('重新加载目录'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
