import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/textbook_writing_progress.dart';
import 'package:poemath/data/repositories/textbook_writing_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/writing/stroke_data_provider.dart';

/// 与认一认共用加密 settings box（不新建 box，PRD R4）。
final textbookWritingBoxProvider =
    Provider<Box<dynamic>>((ref) => HiveBoxes.settings);

/// 整册写字进度；档案切换、数据恢复、同键写入均自动失效重读。
final textbookWritingProgressProvider = FutureProvider.autoDispose
    .family<WritingProgress?, String>((ref, id) async {
  final books = ref.watch(textbookListProvider);
  final courses = ref.watch(textbookCourseRepositoryProvider);
  final box = ref.watch(textbookWritingBoxProvider);
  final profile = ProfileScope.changes.listen((_) => ref.invalidateSelf());
  final epoch = HiveBoxes.meta
      .watch(key: 'practice_draft_epoch')
      .listen((_) => ref.invalidateSelf());
  final changes = HiveBoxes.settings
      .watch()
      .where((e) => e.key.toString().startsWith('textbook_writing_v1:'))
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(() {
    profile.cancel();
    epoch.cancel();
    changes.cancel();
  });
  final pack = await ref.watch(textbookCourseProvider(id).future);
  final book = books.where((b) => b.pdfSha256 == id).firstOrNull;
  if (book == null || pack == null) return null;
  // 笔顺资产决定字级指纹；未就绪时 isLoaded 为 false，hasStrokeDataSync 返回
  // false，此时构建的指纹会在资产就绪后自然失效重算（与内容变化同等对待）。
  final strokes = await ref.watch(writingStrokeDataProvider.future);
  return TextbookWritingRepository(
    book: book,
    editionId: pack.edition.id,
    courses: courses,
    box: box,
    hasStrokeData: strokes.hasStrokeDataSync,
  ).load();
});