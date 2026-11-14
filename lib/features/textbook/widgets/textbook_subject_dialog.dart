import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

Future<TextbookSubject?> confirmTextbookSubject(
  BuildContext context,
  WidgetRef ref,
  Textbook book,
) async {
  try {
    final repository = ref.read(textbookRepositoryProvider);
    final authorize = ParentAccessService.instance.captureAuthorization();
    final currentBook = repository.find(book.pdfSha256) ?? book;
    final currentSubject = currentBook.subject == TextbookSubject.unknown
        ? book.subject
        : currentBook.subject;
    final subject = await showModalBottomSheet<TextbookSubject>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * .7,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: SpacingTokens.md),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.md,
                ),
                child: Text(
                  '确认教材学科',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheet).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.sm,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final subject in TextbookSubject.values.where(
                        (s) => s != TextbookSubject.unknown,
                      ))
                        AppTile(
                          flat: true,
                          flatTrailingEdgeAligned: true,
                          selected: subject == currentSubject,
                          iconColor: Theme.of(sheet).colorScheme.primary,
                          trailingIcon: subject == currentSubject
                              ? Icons.check_rounded
                              : Icons.chevron_right,
                          title: subject.label,
                          subtitle: '',
                          onTap: () => Navigator.pop(sheet, subject),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
            ],
          ),
        ),
      ),
    );
    if (subject == null || !context.mounted) return null;
    void check() {
      authorize();
      assertParentAccess(context);
    }

    check();
    await repository.setSubject(book.pdfSha256, subject, authorize: check);
    if (!context.mounted) return null;
    ref.invalidate(textbookLocalListProvider);
    return subject;
  } on Object catch (error, stackTrace) {
    AppLogger.e(
      '教材学科保存失败',
      tag: 'Textbook',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('学科未保存，请重新打开后重试')));
    }
    return null;
  }
}
