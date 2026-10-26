import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/data/repositories/textbook_recognition_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

final textbookRecognitionBoxProvider =
    Provider<Box<dynamic>>((ref) => HiveBoxes.settings);

final textbookRecognitionProgressProvider = FutureProvider.autoDispose
    .family<RecognitionProgress?, String>((ref, id) async {
  final books = ref.watch(textbookListProvider);
  final courses = ref.watch(textbookCourseRepositoryProvider);
  final box = ref.watch(textbookRecognitionBoxProvider);
  final profile = ProfileScope.changes.listen((_) => ref.invalidateSelf());
  final epoch = HiveBoxes.meta
      .watch(key: 'practice_draft_epoch')
      .listen((_) => ref.invalidateSelf());
  final changes = HiveBoxes.settings
      .watch()
      .where((e) => e.key.toString().startsWith('textbook_recognition_v1:'))
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(() {
    profile.cancel();
    epoch.cancel();
    changes.cancel();
  });
  final pack = await ref.watch(textbookCourseProvider(id).future);
  final book = books.where((b) => b.pdfSha256 == id).firstOrNull;
  if (book == null || pack == null) return null;
  return TextbookRecognitionRepository(
    book: book,
    editionId: pack.edition.id,
    courses: courses,
    box: box,
  ).load();
});
