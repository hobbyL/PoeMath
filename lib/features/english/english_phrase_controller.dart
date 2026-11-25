import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:poemath/core/services/english_phrase_generation_service.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/domain/english_phrase_generation.dart';
import 'package:poemath/features/english/english_providers.dart';

final englishPhraseControllerProvider = ChangeNotifierProvider.autoDispose
    .family<EnglishPhraseController, (String, String)>((ref, key) {
      final book = ref.read(englishBookProvider(key.$1));
      final controller = EnglishPhraseController(
        book: book,
        lessonId: key.$2,
        courses: ref.read(englishCourseRepositoryProvider),
        settings: ref.read(settingsRepositoryProvider),
        httpClient: ref.read(llmExplainHttpClientProvider),
        isBookAvailable: () => ref.read(englishBookProvider(key.$1)) != null,
        onChanged: () => ref.invalidate(englishCourseProvider(key.$1)),
        onSelectionChanged: () =>
            ref.read(llmSelectionVersionProvider.notifier).state++,
      );
      ref.listen(englishBookProvider(key.$1), (_, next) {
        if (next == null) controller.cancel();
      });
      return controller;
    });

/// Owns one visible lesson request, including a validated-but-unsaved batch.
class EnglishPhraseController extends ChangeNotifier {
  EnglishPhraseController({
    required this.book,
    required this.lessonId,
    required this.courses,
    required this.settings,
    required this.httpClient,
    required this.isBookAvailable,
    required this.onChanged,
    required this.onSelectionChanged,
  }) {
    _courseEpoch = courses.generationEpoch(book?.pdfSha256 ?? '');
    _profiles = ProfileScope.changes.listen((_) => cancel());
    _epochs = HiveBoxes.meta
        .watch(key: 'practice_draft_epoch')
        .listen((_) => cancel());
  }

  final Textbook? book;
  final String lessonId;
  final EnglishCourseRepository courses;
  final SettingsRepository settings;
  final http.Client httpClient;
  final bool Function() isBookAvailable;
  final VoidCallback onChanged, onSelectionChanged;
  final _profileId = ProfileScope.currentId;
  final _profileRevision = ProfileScope.revision;
  final _guard = PracticeDraftRepository();
  late final int _courseEpoch;
  static final _owners = <(String, String), EnglishPhraseController>{};
  late final StreamSubscription<String> _profiles;
  late final StreamSubscription<dynamic> _epochs;
  LlmClient? _client;
  bool _disposed = false;
  int _run = 0;
  bool busy = false, needsConfiguration = false;
  int completed = 0, total = 0;
  String? message;
  ({EnglishCourse course, List<EnglishTarget> phrases})? _unsaved;
  bool get hasUnsaved => _unsaved != null;

  bool _active(int run) {
    if (_disposed ||
        run != _run ||
        book == null ||
        _courseEpoch != courses.generationEpoch(book!.pdfSha256) ||
        _profileId != ProfileScope.currentId ||
        _profileRevision != ProfileScope.revision ||
        !isBookAvailable()) {
      return false;
    }
    try {
      _guard.assertCurrent();
      return true;
    } on StateError {
      return false;
    }
  }

  void _check(int run) {
    if (!_active(run)) throw const LlmGenerationCancelled();
  }

  void cancel({bool notify = true}) {
    if (_disposed) return;
    _run++;
    _client?.close();
    _client = null;
    _unsaved = null;
    if (busy) message = '已停止，已保存的短语可继续学习';
    busy = false;
    if (notify) notifyListeners();
  }

  void settingsReturned() {
    if (_disposed) return;
    needsConfiguration = false;
    message = null;
    notifyListeners();
  }

  Future<EnglishCourse> _save(int run) async {
    final pending = _unsaved!;
    _check(run);
    final saved = await _guard.guard(
      () => courses.appendPhrases(
        book!,
        lessonId: lessonId,
        expectedRevision: pending.course.revision,
        phrases: pending.phrases,
        check: () => _check(run),
      ),
    );
    _check(run);
    _unsaved = null;
    onChanged();
    return saved;
  }

  Future<void> generate() async {
    if (busy || _disposed) return;
    final run = ++_run;
    if (!_active(run)) {
      message = '课本或学习档案已变化，请重新进入';
      notifyListeners();
      return;
    }
    final scope = (book!.pdfSha256, lessonId);
    final previous = _owners[scope];
    if (previous != null && previous != this) previous.cancel();
    _owners[scope] = this;
    busy = true;
    needsConfiguration = false;
    message = null;
    completed = total = 0;
    notifyListeners();
    LlmClient? client;
    try {
      if (_unsaved != null) {
        await _save(run);
        message = '短语已保存';
        return;
      }
      final promptOverride = settings.englishPhraseGenerationPromptOverride;
      final loaded = await courses.load(book!);
      _check(run);
      final initialLesson = loaded?.lesson(lessonId);
      if (loaded == null || initialLesson == null) {
        throw const FormatException('请先整理本课单词');
      }
      var course = loaded;
      final seeds = englishPhraseSeeds(initialLesson)
          .take(EnglishPhraseBatch.maxWordsPerRun)
          .toList();
      total = seeds.length;
      if (seeds.isEmpty) return;
      final config = await settings.readLlmConfigForScenario(
        LlmScenario.englishPhrase,
      );
      _check(run);
      if (config == null) {
        needsConfiguration = true;
        message = '请先配置大模型服务';
        return;
      }
      client = createRuntimeLlmClient(
        httpClient: httpClient,
        settings: settings,
        isActive: () => _active(run),
        onSelectionChanged: onSelectionChanged,
      );
      _client = client;
      final service = EnglishPhraseGenerationService(client);
      notifyListeners();
      for (
        var start = 0;
        start < seeds.length;
        start += EnglishPhraseBatch.maxWords
      ) {
        _check(run);
        final current = await courses.load(book!);
        _check(run);
        if (current == null || current.revision != course.revision) {
          throw const FormatException('课程已变化，请重新生成短语');
        }
        final lesson = course.lesson(lessonId)!;
        final chunk = seeds
            .skip(start)
            .take(EnglishPhraseBatch.maxWords)
            .toList();
        final phrases = await service.generate(
          config: config,
          batch: EnglishPhraseBatch(
            bookId: book!.pdfSha256,
            lessonId: lessonId,
            seeds: chunk,
            existingTexts: lesson.targets
                .where((t) => t.isLearnableVocabulary)
                .map((t) => t.text),
          ),
          grade: book!.grade,
          semester: book!.semester,
          unitTitle: lesson.unitTitle,
          lessonTitle: lesson.title,
          promptOverride: promptOverride,
          isActive: () => _active(run),
        );
        _check(run);
        _unsaved = (course: course, phrases: phrases);
        course = await _save(run);
        completed += chunk.length;
        notifyListeners();
      }
      message = englishPhraseSeeds(course.lesson(lessonId)!).isEmpty
          ? null
          : '已保存可用短语，可继续补齐';
    } on LlmGenerationCancelled {
      if (!_disposed && run == _run) message = '已停止，已保存的短语可继续学习';
    } on FormatException catch (e) {
      if (!_disposed && run == _run) {
        _unsaved = null;
        message = e.message;
      }
    } on LlmException catch (e) {
      if (!_disposed && run == _run) message = e.message;
    } on Object {
      if (!_disposed && run == _run) {
        message = hasUnsaved ? '短语尚未保存，请重试保存' : '短语生成失败，请重试';
      }
    } finally {
      client?.close();
      if (identical(_client, client)) _client = null;
      if (identical(_owners[scope], this) && run == _run) _owners.remove(scope);
      if (!_disposed && run == _run) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _run++;
    _disposed = true;
    _client?.close();
    _profiles.cancel();
    _epochs.cancel();
    _owners.removeWhere((_, value) => identical(value, this));
    super.dispose();
  }
}
