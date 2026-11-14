import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

/// 学习入口只展示家长已添加且符合学习背景的教材。
/// 诗词页的临时筛选不改变孩子当前使用的课本册次。
final currentTextbooksProvider = Provider<List<Textbook>>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return ref
      .watch(textbookLocalListProvider)
      .where((book) {
        return book.subject == TextbookSubject.chinese &&
            book.grade == settings.selectedGrade &&
            book.semester == settings.selectedSemester;
      })
      .toList(growable: false);
});

final subjectTextbooksProvider =
    Provider.family<List<Textbook>, TextbookSubject>((ref, subject) {
      final settings = ref.watch(settingsRepositoryProvider);
      return ref
          .watch(textbookLocalListProvider)
          .where(
            (book) =>
                book.subject == subject &&
                book.grade == settings.selectedGrade &&
                book.semester == settings.selectedSemester,
          )
          .toList(growable: false);
    });
