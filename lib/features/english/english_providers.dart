import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/english_course_generation_service.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/english_progress.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/models/textbook_page_text.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/data/repositories/english_progress_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/domain/english_course_parser.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

final englishCourseRepositoryProvider = Provider(
  (ref) => EnglishCourseRepository(),
);
final englishBookProvider = Provider.family<Textbook?, String>(
  (ref, id) => ref
      .watch(textbookListProvider)
      .where((b) => b.pdfSha256 == id && b.subject == TextbookSubject.english)
      .firstOrNull,
);
final englishCourseProvider = FutureProvider.autoDispose
    .family<EnglishCourse?, String>((ref, id) {
      final book = ref.watch(englishBookProvider(id));
      return book == null
          ? null
          : ref.watch(englishCourseRepositoryProvider).load(book);
    });

/// Recover numbered picture-card order from the cached original page layout.
/// English courses predating this evidence can use the ordering immediately
/// without replacing their reviewed lesson data.
final englishTargetCardNumberProvider = FutureProvider.autoDispose
    .family<Map<String, int>, (String, String)>((ref, key) async {
      try {
        final book = ref.watch(englishBookProvider(key.$1));
        if (book == null) return const {};
        final files = ref.read(textbookFileServiceProvider);
        final courseFuture = ref.watch(englishCourseProvider(key.$1).future);
        final course = await courseFuture;
        final lesson = course?.lesson(key.$2);
        if (lesson == null) return const {};
        final sourcesByPage = <int, Map<String, EnglishSource>>{};
        for (final target in lesson.targets) {
          if (target.kind != EnglishTargetKind.sentence) continue;
          final source =
              target.sources
                  .where((source) => lesson.containsPage(source.page))
                  .firstOrNull ??
              target.sources.first;
          sourcesByPage.putIfAbsent(source.page, () => {})[target.id] = source;
        }
        if (sourcesByPage.isEmpty) return const {};

        final cache = files.contentCache(book);
        final layouts = <int, TextbookPageText>{};
        final missingPages = <int>[];
        for (final page in sourcesByPage.keys) {
          final layout = await cache.cachedPageLayout(page);
          if (layout == null) {
            missingPages.add(page);
          } else {
            layouts[page] = layout;
          }
        }
        if (missingPages.isNotEmpty) {
          final path = await files.installedPath(book);
          if (path != null) {
            final source = await NativeTextbookPdfSource.open(
              path: path,
              book: book,
              cache: cache,
              token: TextbookDraftToken(),
            );
            try {
              for (final page in missingPages) {
                layouts[page] = await source.page(page);
              }
            } finally {
              await source.close();
            }
          }
        }
        final result = <String, int>{};
        for (final entry in sourcesByPage.entries) {
          final layout = layouts[entry.key];
          if (layout == null) continue;
          final lines = englishPageLines(layout);
          for (final target in entry.value.entries) {
            final number = englishNumberedCardForSource(target.value, lines);
            if (number != null) result[target.key] = number;
          }
        }
        return result;
      } on Object {
        // Missing derived page layout falls back to geometric reading order.
        return const {};
      }
    });

final _englishSettingsChanges = StreamProvider(
  (ref) => HiveBoxes.settings.watch().map((e) => e.key),
);
final _englishProfiles = StreamProvider((ref) => ProfileScope.changes);
final _englishEpoch = StreamProvider(
  (ref) => HiveBoxes.meta.watch(key: 'practice_draft_epoch'),
);
final englishProgressRepositoryProvider = Provider.autoDispose
    .family<EnglishProgressRepository?, String>((ref, id) {
      ref.watch(_englishProfiles);
      ref.watch(_englishEpoch);
      final book = ref.watch(englishBookProvider(id));
      return book == null
          ? null
          : EnglishProgressRepository(
              book,
              ref.watch(englishCourseRepositoryProvider),
              activities: ref.watch(learningActivityRepositoryProvider),
            );
    });
final englishDraftChangesProvider = StreamProvider(
  (ref) => PracticeDraftRepository().changes(),
);
final englishSavedProgressProvider =
    Provider.autoDispose<List<EnglishProgress>>((ref) {
      ref.watch(_englishSettingsChanges);
      ref.watch(_englishProfiles);
      return EnglishProgressRepository.savedForProfile();
    });
final englishProgressProvider = Provider.autoDispose
    .family<EnglishProgress?, String>((ref, id) {
      ref.watch(_englishSettingsChanges);
      return ref.watch(englishProgressRepositoryProvider(id))?.load() ??
          ref
              .watch(englishSavedProgressProvider)
              .where((p) => p.bookId == id)
              .firstOrNull;
    });

String get englishVoiceSettingKey => ProfileScope.key('english_voice_v1');
String englishVoiceKey(Map<String, String> voice) =>
    '${voice['locale']}|${voice['name']}';
final englishVoicesProvider =
    FutureProvider.autoDispose<List<Map<String, String>>>(
      (ref) => ref.watch(ttsServiceProvider).getVoices(language: 'en'),
    );
final englishVoiceProvider = Provider<Map<String, String>?>((ref) {
  ref.watch(_englishSettingsChanges);
  ref.watch(_englishProfiles);
  final voices = ref.watch(englishVoicesProvider).valueOrNull ?? [];
  final raw = HiveBoxes.settings.get(englishVoiceSettingKey);
  Map<String, String>? saved;
  if (raw is String) {
    try {
      saved = (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );
    } on Object {
      /* stale setting */
    }
  }
  if (saved != null) {
    final exact = voices
        .where((v) => englishVoiceKey(v) == englishVoiceKey(saved!))
        .firstOrNull;
    if (exact != null) return exact;
  }
  return voices
          .where(
            (v) => v['locale'] == 'en-US' && v['network_required'] != 'true',
          )
          .firstOrNull ??
      voices.where((v) => v['network_required'] != 'true').firstOrNull ??
      voices.firstOrNull;
});

class EnglishGenerationState {
  const EnglishGenerationState({
    this.running = false,
    this.message = '',
    this.done = 0,
    this.total = 0,
  });
  final bool running;
  final String message;
  final int done, total;
}

final englishGenerationProvider =
    StateNotifierProvider<
      EnglishGenerationController,
      Map<String, EnglishGenerationState>
    >(
      (ref) => EnglishGenerationController(
        EnglishCourseGenerationService(
          ref.watch(englishCourseRepositoryProvider),
          ref.watch(textbookFileServiceProvider),
        ),
        (id) => ref.invalidate(englishCourseProvider(id)),
      ),
    );

class EnglishGenerationController
    extends StateNotifier<Map<String, EnglishGenerationState>> {
  EnglishGenerationController(this.service, this.changed) : super({});
  final EnglishCourseGenerationService service;
  final void Function(String) changed;
  TextbookDraftToken? _token;
  Future<void>? _active;
  String? _book;
  bool _disposed = false;
  int _request = 0;
  void pause(String id) {
    if (_book == id) {
      _request++;
      _token?.cancel();
    }
  }

  Future<void> drain() async {
    final active = _active;
    if (active != null) await active;
  }

  Future<void> start(
    Textbook book,
    void Function() authorize, {
    bool refresh = false,
  }) async {
    final request = ++_request;
    if (_active != null) {
      _token?.cancel();
      await drain();
    }
    if (_disposed || request != _request) return;
    authorize();
    final token = TextbookDraftToken(authorize: authorize);
    _token = token;
    _book = book.pdfSha256;
    void update(String message, int done, int total, {bool running = true}) {
      if (!_disposed) {
        state = {
          ...state,
          book.pdfSha256: EnglishGenerationState(
            running: running,
            message: message,
            done: done,
            total: total,
          ),
        };
      }
    }

    update('准备整理原书', 0, 0);
    final work = () async {
      try {
        await service.run(
          book,
          token,
          (m, d, t) => update(m, d, t),
          () => changed(book.pdfSha256),
          refresh: refresh,
        );
      } on TextbookDraftCancelled {
        update(
          '已暂停，已保存课时保留',
          state[book.pdfSha256]?.done ?? 0,
          state[book.pdfSha256]?.total ?? 0,
          running: false,
        );
      } on Object {
        update(
          '整理未完成，可继续重试；已保存内容保留',
          state[book.pdfSha256]?.done ?? 0,
          state[book.pdfSha256]?.total ?? 0,
          running: false,
        );
      } finally {
        if (!_disposed) {
          final last = state[book.pdfSha256]!;
          update(last.message, last.done, last.total, running: false);
        }
      }
    }();
    _active = work;
    try {
      await work;
    } finally {
      if (identical(_active, work)) {
        _active = null;
        _token = null;
        _book = null;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }
}
