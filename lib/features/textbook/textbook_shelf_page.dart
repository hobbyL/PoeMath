import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/textbook_download_controller.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_cover_grid.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_cover.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_number_label.dart';

class TextbookShelfPage extends ConsumerStatefulWidget {
  const TextbookShelfPage({super.key});
  @override
  ConsumerState<TextbookShelfPage> createState() => _TextbookShelfPageState();
}

class _TextbookShelfPageState extends ConsumerState<TextbookShelfPage> {
  TextbookSubject _subject = TextbookSubject.chinese;
  Future<void> _open(TextbookCatalogEntry entry) async {
    await context.push(AppRoutes.textbookDetailOf(entry.book.pdfSha256));
    if (mounted) setState(() {});
  }

  Future<void> _read(TextbookCatalogEntry entry) async {
    await context.push(AppRoutes.textbookReadOf(entry.book.pdfSha256));
    if (mounted) setState(() {});
  }

  Widget _bookCard(TextbookCatalogEntry entry, TextStyle textStyle) {
    final book = entry.book;
    final theme = Theme.of(context);
    final path = ref.watch(textbookPathProvider(book.pdfSha256));
    final download = ref.watch(textbookDownloadsProvider)[book.pdfSha256];
    final installed = path.valueOrNull != null;
    final reading = ref
        .watch(textbookRepositoryProvider)
        .reading(ProfileScope.currentId, book.pdfSha256);
    final pageLabel = installed
        ? asyncTextbookPageLabel(
            ref.watch(
              textbookPrintedPageProvider((
                bookId: book.pdfSha256,
                page: reading.page.clamp(1, book.pageCount),
              )),
            ),
          )
        : '';
    final status =
        download?.label ??
        (installed
            ? '已下载 · $pageLabel'
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
      clipBehavior: Clip.antiAlias,
      onTap: () => _open(entry),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Semantics(
              label: book.title,
              image: true,
              excludeSemantics: true,
              child: entry.coverUrl != null
                  ? Image.network(
                      entry.coverUrl.toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => TextbookCoverPlaceholder(
                        title: book.title,
                        status: book.volumeLabel,
                      ),
                    )
                  : entry.coverAsset == null
                  ? TextbookCoverPlaceholder(
                      title: book.title,
                      status: book.volumeLabel,
                    )
                  : Image.asset(
                      entry.coverAsset!,
                      fit: BoxFit.cover,
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
                        overlayColor: Colors.transparent,
                        splashFactory: NoSplash.splashFactory,
                        fixedSize: const Size.square(
                          SpacingTokens.minTapTarget,
                        ),
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
                        final controller = ref.read(
                          textbookDownloadsProvider.notifier,
                        );
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(textbookDownloadCatalogProvider);
    final catalogRefresh = ref.watch(textbookCatalogRefreshProvider);
    final labelStyle = theme.textTheme.labelLarge!;
    final labelHeight =
        MediaQuery.textScalerOf(context).scale(labelStyle.fontSize!) *
        (labelStyle.height ?? 1);
    final toolbarHeight = math.max(
      kToolbarHeight,
      labelHeight + SpacingTokens.sm * 4,
    );
    final textStyle = DefaultTextStyle.of(context).style
        .merge(theme.textTheme.bodySmall)
        .copyWith(height: 1.5);
    return AppScaffold(
      backgroundScene: PineInkScene.study,
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: toolbarHeight,
        title: SegmentedButton<TextbookSubject>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(0, SpacingTokens.xxl),
            padding: const EdgeInsets.all(SpacingTokens.sm),
          ),
          segments: const [
            ButtonSegment(
              value: TextbookSubject.chinese,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('语文', maxLines: 1),
              ),
            ),
            ButtonSegment(
              value: TextbookSubject.math,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('数学', maxLines: 1),
              ),
            ),
            ButtonSegment(
              value: TextbookSubject.english,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('英语', maxLines: 1),
              ),
            ),
          ],
          selected: {_subject},
          onSelectionChanged: (values) =>
              setState(() => _subject = values.single),
        ),
        actions: [
          IconButton(
            tooltip: '刷新教材目录',
            onPressed: () => ref.invalidate(textbookCatalogRefreshProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            catalog.when(
              data: (catalogEntries) {
                final entries = catalogEntries
                    .where((entry) => entry.book.subject == _subject)
                    .toList();
                return entries.isEmpty && catalogRefresh.isLoading
                    ? const SliverToBoxAdapter(child: LinearProgressIndicator())
                    : entries.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppEmptyState(
                          icon: Icons.download_outlined,
                          title: '暂无可下载书籍',
                          description: catalogRefresh.hasError
                              ? '目录暂时无法读取，可重试。'
                              : '当前没有已整理且可下载的书目。',
                        ),
                      )
                    : TextbookCoverGrid(
                        itemCount: entries.length,
                        naturalRowHeight: true,
                        itemBuilder: (_, index) =>
                            _bookCard(entries[index], textStyle),
                      );
              },
              loading: () =>
                  const SliverToBoxAdapter(child: LinearProgressIndicator()),
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
                          onPressed: () {
                            ref.invalidate(textbookCatalogProvider);
                            ref.invalidate(textbookCatalogRefreshProvider);
                          },
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
