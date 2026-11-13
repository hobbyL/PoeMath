import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/widgets/textbook_page_number_label.dart';

final recentTextbookProvider =
    Provider.autoDispose<({Textbook book, int page})?>((ref) {
      final profile = ProfileScope.changes.listen((_) => ref.invalidateSelf());
      ref.onDispose(profile.cancel);
      final profileId = ProfileScope.currentId;
      final repo = ref.watch(textbookRepositoryProvider);
      final changes = repo
          .watchReading(profileId)
          .listen((_) => ref.invalidateSelf());
      ref.onDispose(changes.cancel);
      final book = repo.recentBook(profileId);
      return book == null
          ? null
          : (
              book: book,
              page: repo
                  .reading(profileId, book.pdfSha256)
                  .page
                  .clamp(1, book.pageCount),
            );
    });

class TextbookResumeCard extends ConsumerWidget {
  const TextbookResumeCard({super.key, required this.book, required this.page});

  final Textbook book;
  final int page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final path = ref.watch(textbookPathProvider(book.pdfSha256));
    final status = path.when(
      data: (value) => value == null ? ' · 课本文件缺失，点击恢复' : '',
      loading: () => ' · 正在检查文件',
      error: (_, __) => ' · 文件检查失败，点击重试',
    );
    final pageLabel = asyncTextbookPageLabel(
      ref.watch(
        textbookPrintedPageProvider((bookId: book.pdfSha256, page: page)),
      ),
    );
    return AppTile(
      icon: Icons.menu_book_outlined,
      iconColor: theme.colorScheme.primary,
      title: '继续读《${book.title}》',
      subtitle: '$pageLabel · ${book.volumeLabel}$status',
      onTap: () async {
        if (path.hasError) {
          ref.invalidate(textbookPathProvider(book.pdfSha256));
        }
        await context.push(AppRoutes.textbookDetailOf(book.pdfSha256));
      },
    );
  }
}
