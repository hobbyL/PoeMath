import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_cache_manager_sheet.dart';
import 'package:poemath/features/textbook/widgets/textbook_cover_grid.dart';
import 'package:poemath/features/textbook/widgets/textbook_import_dialog.dart';
import 'package:poemath/features/textbook/widgets/textbook_pdf_cover.dart';

class TextbookManagementPage extends ConsumerStatefulWidget {
  const TextbookManagementPage({super.key, this.pickPdf});
  final Future<PlatformFile?> Function()? pickPdf;
  @override
  ConsumerState<TextbookManagementPage> createState() =>
      _TextbookManagementPageState();
}

class _TextbookManagementPageState
    extends ConsumerState<TextbookManagementPage> {
  bool _busy = false;
  double? _progress;
  TextbookImportToken? _token;
  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    final files = ref.read(textbookFileServiceProvider);
    String? pickedPath;
    try {
      final file = widget.pickPdf != null
          ? await widget.pickPdf!()
          : (await FilePicker.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['pdf'],
              withData: false,
            ))
              ?.files
              .firstOrNull;
      pickedPath = file?.path;
      if (!mounted || file == null) return;
      if (file.path == null) {
        throw const TextbookFileException('文件无法读取，请选择设备上的 PDF');
      }
      // 文件选择/登记期间不保留转圈；阻止第二次导入仍由 _busy 控制。
      final details = await showDialog<TextbookImportDetails>(
        context: context,
        builder: (_) => TextbookImportDialog(fileName: file.name),
      );
      if (!mounted || details == null) return;
      final token = TextbookImportToken();
      _token = token;
      setState(() => _progress = 0);
      final imported = await files.importPdf(
        sourcePath: file.path!,
        token: token,
        onProgress: (copied, total) {
          if (mounted) setState(() => _progress = copied / total);
        },
      );
      if (!mounted) return;
      await ref.read(textbookRepositoryProvider).addIfAbsent(
            Textbook(
              pdfSha256: imported.sha256,
              title: details.title,
              grade: details.grade,
              semester: details.semester,
              publisher: details.publisher,
              editionNote: details.editionNote,
              originalFileName: file.name,
              pageCount: imported.pageCount,
              fileSize: imported.size,
              importedAt: DateTime.now(),
            ),
          );
      if (!mounted) return;
      ref.invalidate(textbookLocalListProvider);
      ref.invalidate(textbookPathProvider(imported.sha256));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('教材已导入，可离线阅读')));
    } on TextbookImportCancelled {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已取消导入')));
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '教材导入失败',
        tag: 'Textbook',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is TextbookFileException ? error.message : '教材登记失败，请重新导入',
            ),
          ),
        );
      }
    } finally {
      if (pickedPath != null) {
        try {
          await files.discardPickerCopy(pickedPath);
        } on Object {
          AppLogger.w('所选文件的临时副本未清理', tag: 'Textbook');
        }
      }
      _token = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _open(Textbook book) async {
    await context.push(AppRoutes.textbookManageDetailOf(book.pdfSha256));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = ref.watch(textbookLocalListProvider);
    final catalog = ref.watch(textbookCatalogProvider).valueOrNull ?? [];
    final cloudIds = catalog.map((entry) => entry.book.pdfSha256).toSet();
    final paths = {
      for (final book in books)
        book.pdfSha256: ref.watch(textbookPathProvider(book.pdfSha256)),
    };
    final actionStyle = IconButton.styleFrom(
      fixedSize: const Size.square(SpacingTokens.minTapTarget),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      padding: const EdgeInsets.all(SpacingTokens.sm),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('书籍管理', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            style: actionStyle,
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入',
          ),
          IconButton(
            style: actionStyle,
            onPressed: () => context.push(AppRoutes.textbookShelf),
            icon: const Icon(Icons.download_outlined),
            tooltip: '下载',
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            if (_progress != null)
              SliverPadding(
                padding: const EdgeInsets.all(SpacingTokens.md),
                sliver: SliverToBoxAdapter(
                  child: ColoredCard(
                    color: theme.colorScheme.primary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _progress! < 1
                              ? '正在导入 ${(100 * _progress!).round()}%'
                              : '正在检查 PDF…',
                        ),
                        const SizedBox(height: SpacingTokens.sm),
                        LinearProgressIndicator(
                          value: _progress! < 1 ? _progress : null,
                        ),
                        TextButton(
                          onPressed: () => _token?.cancel(),
                          child: const Text('取消导入'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (books.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    child: ColoredCard(
                      color: theme.colorScheme.primary,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.menu_book_outlined,
                            size: SpacingTokens.xxl,
                          ),
                          const SizedBox(height: SpacingTokens.md),
                          Text('暂无书籍', style: theme.textTheme.titleLarge),
                          const SizedBox(height: SpacingTokens.sm),
                          const Text(
                            '点击右上角导入或下载',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              TextbookCoverGrid(
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final book = books[index];
                  final title = '${book.title}\n${book.volumeLabel}';
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Semantics(
                        label: '${book.title}，${book.volumeLabel}',
                        button: true,
                        excludeSemantics: true,
                        onTap: () => _open(book),
                        child: ColoredCard(
                          key: ValueKey('textbook-card-${book.pdfSha256}'),
                          color: theme.colorScheme.primary,
                          padding: EdgeInsets.zero,
                          onTap: () => _open(book),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              SpacingTokens.radiusMedium,
                            ),
                            child: paths[book.pdfSha256]!.when(
                              data: (path) => path == null
                                  ? TextbookCoverPlaceholder(
                                      title: title,
                                      status:
                                          cloudIds.contains(book.pdfSha256)
                                              ? '可重新下载'
                                              : '需重新导入',
                                    )
                                  : TextbookPdfCover(
                                      path: path,
                                      title: title,
                                    ),
                              loading: () => TextbookCoverPlaceholder(
                                title: title,
                                status: '正在检查本地文件',
                              ),
                              error: (_, __) => TextbookCoverPlaceholder(
                                title: title,
                                status: '文件检查失败',
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 每本书独立的缓存入口：封面整卡仍是「打开书籍」，
                      // 这里只负责查看占用与清理可重建数据。
                      Positioned(
                        top: SpacingTokens.xs,
                        right: SpacingTokens.xs,
                        child: IconButton(
                          key: ValueKey('textbook-cache-${book.pdfSha256}'),
                          tooltip: '缓存管理',
                          onPressed: () => showTextbookCacheSheet(context, book),
                          style: IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.surface
                                .withValues(alpha: 0.9),
                            foregroundColor: theme.colorScheme.onSurface,
                            fixedSize:
                                const Size.square(SpacingTokens.minTapTarget),
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(
                            Icons.cleaning_services_outlined,
                            size: SpacingTokens.md,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
