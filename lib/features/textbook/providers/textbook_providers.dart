import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/textbook_file_service.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_catalog.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/repositories/textbook_course_repository.dart';
import 'package:poemath/data/repositories/textbook_catalog_repository.dart';
import 'package:poemath/data/repositories/textbook_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_download_controller.dart';
import 'package:poemath/core/services/textbook_course_generation_service.dart';
import 'package:poemath/data/models/textbook_course_draft.dart';
import 'package:poemath/features/textbook/providers/textbook_generation_controller.dart';

final textbookRepositoryProvider =
    Provider<TextbookRepository>((ref) => TextbookRepository());
final textbookFileServiceProvider =
    Provider<TextbookFileService>((ref) => TextbookFileService());
final textbookCourseRepositoryProvider = Provider<TextbookCourseRepository>(
  (ref) => TextbookCourseRepository(),
);
final textbookCourseProvider = FutureProvider.autoDispose
    .family<TextbookCoursePack?, String>((ref, id) async {
  final book = ref
      .watch(textbookListProvider)
      .where((book) => book.pdfSha256 == id)
      .firstOrNull;
  if (book == null) return null;
  return ref.watch(textbookCourseRepositoryProvider).load(book);
});
final textbookCourseDocumentProvider = FutureProvider.autoDispose
    .family<TextbookCourseDocument?, String>((ref, id) async {
  final book = ref
      .watch(textbookListProvider)
      .where((b) => b.pdfSha256 == id)
      .firstOrNull;
  if (book == null) return null;
  return ref.watch(textbookCourseRepositoryProvider).loadDocument(book);
});
final textbookGenerationServiceProvider =
    Provider<TextbookCourseGenerationService>(
  (ref) => TextbookCourseGenerationService(
    ref.watch(textbookCourseRepositoryProvider),
    ref.watch(textbookFileServiceProvider),
  ),
);
final textbookGenerationProvider = StateNotifierProvider<
    TextbookGenerationController, Map<String, TextbookGenerationProgress>>(
  (ref) => TextbookGenerationController(
      ref.watch(textbookGenerationServiceProvider), (id) {
    ref.invalidate(textbookCourseProvider(id));
    ref.invalidate(textbookCourseDocumentProvider(id));
  }),
);
final textbookLocalListProvider = Provider<List<Textbook>>(
  (ref) => ref.watch(textbookRepositoryProvider).list(),
);
final textbookCatalogProvider = FutureProvider<List<TextbookCatalogEntry>>(
  (ref) => const TextbookCatalogRepository().load(),
);
final textbookListProvider = Provider<List<Textbook>>((ref) {
  final local = ref.watch(textbookLocalListProvider);
  final catalog = ref.watch(textbookCatalogProvider).valueOrNull ?? [];
  final books = {for (final book in local) book.pdfSha256: book};
  for (final entry in catalog) {
    books.putIfAbsent(entry.book.pdfSha256, () => entry.book);
  }
  return books.values.toList();
});
final textbookDownloadsProvider = StateNotifierProvider<
    TextbookDownloadController, Map<String, TextbookDownloadState>>((ref) {
  return TextbookDownloadController(
    ref.watch(textbookFileServiceProvider),
    ref.watch(textbookRepositoryProvider),
    (id) {
      ref.invalidate(textbookLocalListProvider);
      ref.invalidate(textbookPathProvider(id));
    },
  );
});
final textbookPathProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, id) async {
  // 管理页反复进出时保留检查结果：否则每次先闪「正在检查本地文件」占位，
  // 再闪「正在生成封面」，即使封面早已缓存。导入、下载、删除 PDF 的
  // 入口都会显式 invalidate 本 provider。
  ref.keepAlive();
  final book = ref
      .watch(textbookLocalListProvider)
      .where((book) => book.pdfSha256 == id)
      .firstOrNull;
  if (book == null) return null;
  return ref.watch(textbookFileServiceProvider).installedPath(book);
});
