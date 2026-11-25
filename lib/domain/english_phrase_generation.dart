import 'dart:convert';

import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook_course.dart'
    show textbookContentDigest;

bool isEnglishPhraseSeed(EnglishTarget target) =>
    target.isAutoExtractedVocabulary &&
    EnglishPhraseSource.isWord(target.text) &&
    target.meaning.length <= 300;

class EnglishPhraseSeed {
  const EnglishPhraseSeed(this.target, this.missing);
  final EnglishTarget target;
  final int missing;
}

/// The semantic snapshot survives parser ID changes without regenerating words.
List<EnglishPhraseSeed> englishPhraseSeeds(EnglishLesson lesson) {
  final counts = <String, int>{};
  for (final phrase in lesson.phrases) {
    final key = phrase.phraseSource!.key;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final seen = <String>{};
  return [
    for (final target in lesson.targets)
      if (isEnglishPhraseSeed(target))
        if (EnglishPhraseSource.wordKey(target.text, target.meaning)
            case final key)
          if (seen.add(key) &&
              (counts[key] ?? 0) < EnglishPhraseSource.phrasesPerWord)
            EnglishPhraseSeed(
              target,
              EnglishPhraseSource.phrasesPerWord - (counts[key] ?? 0),
            ),
  ];
}

class EnglishPhraseBatch {
  EnglishPhraseBatch({
    required this.bookId,
    required this.lessonId,
    required List<EnglishPhraseSeed> seeds,
    required Iterable<String> existingTexts,
  }) : seeds = List.unmodifiable(seeds),
       existingTexts = Set.unmodifiable(
         existingTexts.map(EnglishPhraseSource.normalize),
       );

  static const maxWords = 6;
  static const maxWordsPerRun = 24;
  final String bookId, lessonId;
  final List<EnglishPhraseSeed> seeds;
  final Set<String> existingTexts;

  List<EnglishTarget> parse(String content, {required DateTime now}) {
    if (content.length > 24000 || seeds.isEmpty || seeds.length > maxWords) {
      throw const FormatException('短语响应范围无效');
    }
    // Accept a single JSON fence; never fish JSON out of arbitrary prose.
    final fenced = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(content.trim());
    final root = englishObject(jsonDecode(fenced?.group(1) ?? content.trim()));
    if (!_keys(root, {'items'})) throw const FormatException('短语响应结构无效');
    final items = englishList(root['items'], englishObject, max: maxWords);
    final ids = <String>{};
    for (final item in items) {
      final id = item['sourceId'];
      if (!_keys(item, {'sourceId', 'phrases'}) ||
          id is! String ||
          !seeds.any((s) => s.target.id == id) ||
          !ids.add(id)) {
        throw const FormatException('短语目标单词无效');
      }
    }
    final seen = {...existingTexts};
    final results = <EnglishTarget>[];
    for (final item in items) {
      final seed = seeds.firstWhere((s) => s.target.id == item['sourceId']);
      final phrases = englishList(item['phrases'], (v) => v, max: 6);
      var accepted = 0;
      for (final raw in phrases) {
        if (accepted >= seed.missing) break;
        if (raw is! Map<String, dynamic> ||
            !_keys(raw, {'text', 'meaning'}) ||
            raw['text'] is! String ||
            raw['meaning'] is! String) {
          continue;
        }
        final text = (raw['text'] as String).trim().replaceAll('’', "'");
        final meaning = (raw['meaning'] as String).trim();
        if (!EnglishPhraseSource.validPhrase(text, meaning, seed.target.text)) {
          continue;
        }
        final normalized = EnglishPhraseSource.normalize(text);
        if (!seen.add(normalized)) continue;
        final source = EnglishPhraseSource(
          lessonId: lessonId,
          targetId: seed.target.id,
          text: seed.target.text,
          meaning: seed.target.meaning,
          fingerprint: seed.target.fingerprint,
          generatedAt: now,
        );
        results.add(
          EnglishTarget.fromJson(
            EnglishTarget(
              id: 'ai-phrase-${textbookContentDigest({'book': bookId, 'lesson': lessonId, 'source': source.key, 'text': normalized})}',
              kind: EnglishTargetKind.vocabulary,
              text: text.replaceAll(RegExp(r' +'), ' '),
              meaning: meaning,
              sources: const [],
              origin: 'aiPhrase',
              phraseSource: source,
            ).toJson(),
          ),
        );
        accepted++;
      }
    }
    if (results.isEmpty) throw const FormatException('没有合格的新短语');
    return List.unmodifiable(results);
  }

  static bool _keys(Map<String, dynamic> value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);
}
