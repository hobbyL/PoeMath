import 'dart:convert';

import 'package:poemath/data/models/textbook_course.dart';

/// 内部检查点不进入课程 v1 导出，也不改变内容审核摘要。
class TextbookCourseDocument {
  const TextbookCourseDocument(this.pack, [this.generation]);
  final TextbookCoursePack pack;
  final TextbookDraftManifest? generation;
  Map<String, dynamic> toJson() => generation == null
      ? pack.toJson()
      : {
          'storageVersion': 2,
          'coursePack': pack.toJson(),
          'generation': generation!.toJson(),
        };
  factory TextbookCourseDocument.fromJson(Map<String, dynamic> raw) {
    if (!raw.containsKey('storageVersion')) {
      return TextbookCourseDocument(TextbookCoursePack.fromJson(raw));
    }
    _keys(raw, {'storageVersion', 'coursePack', 'generation'});
    if (raw['storageVersion'] != 2) {
      throw const FormatException('本机课程存储版本不支持');
    }
    final pack = TextbookCoursePack.fromJson(_map(raw['coursePack']));
    final generation = TextbookDraftManifest.fromJson(_map(raw['generation']));
    final ids = pack.lessons.map((l) => l.id).toSet();
    if (generation.plans.any(
          (p) => !ids.contains(p.id) || p.endPage > pack.edition.pageCount,
        ) ||
        generation.completed
            .any((id) => !generation.plans.any((p) => p.id == id)) ||
        generation.candidates.keys.any((id) => !ids.contains(id)) ||
        generation.pending.keys.any((id) => !ids.contains(id))) {
      throw const FormatException('课程生成检查点与课目不匹配');
    }
    // 差异候选同样须能通过课程严格解码器，不能成为不受检验的内容入口。
    for (final entry in generation.pending.entries) {
      final test = pack.toJson();
      final lessons = test['lessons'] as List;
      lessons[lessons.indexWhere((l) => (l as Map)['id'] == entry.key)] =
          entry.value;
      TextbookCoursePack.fromJson(test);
    }
    return TextbookCourseDocument(pack, generation);
  }
}

class TextbookDraftPlan {
  const TextbookDraftPlan({
    required this.id,
    required this.startPage,
    required this.endPage,
    required this.title,
    this.nextTitle,
    this.printedPage,
    this.edited = false,
  });
  final String id;
  final int startPage;
  final int endPage;
  final String title;
  final String? nextTitle;
  final int? printedPage;
  final bool edited;
  Map<String, dynamic> toJson() => {
        'id': id,
        'startPage': startPage,
        'endPage': endPage,
        'title': title,
        'nextTitle': nextTitle,
        'printedPage': printedPage,
        'edited': edited,
      };
  factory TextbookDraftPlan.fromJson(Map<String, dynamic> raw) {
    _keys(
      raw,
      {'id', 'startPage', 'endPage', 'title', 'nextTitle', 'printedPage'},
      optional: {'edited'},
    );
    final start = raw['startPage'] as int;
    final end = raw['endPage'] as int;
    if (start < 1 || end < start || (raw['title'] as String).trim().isEmpty) {
      throw const FormatException('课程原书范围无效');
    }
    return TextbookDraftPlan(
      id: raw['id'] as String,
      startPage: start,
      endPage: end,
      title: raw['title'] as String,
      nextTitle: raw['nextTitle'] as String?,
      printedPage: raw['printedPage'] as int?,
      edited: raw['edited'] as bool? ?? false,
    );
  }
}

class TextbookDraftCandidate {
  const TextbookDraftCandidate({
    required this.id,
    required this.text,
    required this.reason,
    required this.pages,
    this.category = 'paragraphs',
    this.pinyin = const [],
  });
  final String id;
  final String text;
  final String reason;
  final List<int> pages;
  final String category;

  /// 原书局部注音线索；不能直接冒充严格模型的完整注音。
  final List<String> pinyin;
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'reason': reason,
        'pages': pages,
        'category': category,
        'pinyin': pinyin,
      };
  factory TextbookDraftCandidate.fromJson(Map<String, dynamic> raw) {
    _keys(raw, {'id', 'text', 'reason', 'pages', 'category', 'pinyin'});
    final pages = (raw['pages'] as List).cast<int>();
    if (!TextbookCoursePack.categories.contains(raw['category']) ||
        pages.isEmpty ||
        pages.any((p) => p < 1) ||
        (raw['id'] as String).isEmpty ||
        (raw['text'] as String).trim().isEmpty ||
        (raw['reason'] as String).trim().isEmpty) {
      throw const FormatException('待整理内容无效');
    }
    return TextbookDraftCandidate(
      id: raw['id'] as String,
      text: raw['text'] as String,
      reason: raw['reason'] as String,
      pages: List.unmodifiable(pages),
      category: raw['category'] as String,
      pinyin: List.unmodifiable((raw['pinyin'] as List).cast<String>()),
    );
  }
}

class TextbookDraftManifest {
  const TextbookDraftManifest({
    required this.runId,
    required this.parserVersion,
    required this.phase,
    required this.plans,
    this.completed = const [],
    this.baselines = const {},
    this.candidates = const {},
    this.pending = const {},
    this.removed = const [],
    this.errors = const {},
  });
  final String runId;
  final int parserVersion;
  final String phase;
  final List<TextbookDraftPlan> plans;
  final List<String> completed;
  final Map<String, String> baselines;
  final Map<String, List<TextbookDraftCandidate>> candidates;
  final Map<String, Map<String, dynamic>> pending;
  final List<String> removed;
  final Map<String, String> errors;
  TextbookDraftManifest copyWith({
    String? phase,
    List<TextbookDraftPlan>? plans,
    List<String>? completed,
    Map<String, String>? baselines,
    Map<String, List<TextbookDraftCandidate>>? candidates,
    Map<String, Map<String, dynamic>>? pending,
    List<String>? removed,
    Map<String, String>? errors,
  }) =>
      TextbookDraftManifest(
        runId: runId,
        parserVersion: parserVersion,
        phase: phase ?? this.phase,
        plans: plans ?? this.plans,
        completed: completed ?? this.completed,
        baselines: baselines ?? this.baselines,
        candidates: candidates ?? this.candidates,
        pending: pending ?? this.pending,
        removed: removed ?? this.removed,
        errors: errors ?? this.errors,
      );
  Map<String, dynamic> toJson() => {
        'runId': runId,
        'parserVersion': parserVersion,
        'phase': phase,
        'plans': plans.map((p) => p.toJson()).toList(),
        'completed': completed,
        'baselines': baselines,
        'candidates': candidates.map(
          (key, value) => MapEntry(key, value.map((c) => c.toJson()).toList()),
        ),
        'pending': pending,
        'removed': removed,
        'errors': errors,
      };
  factory TextbookDraftManifest.fromJson(Map<String, dynamic> raw) {
    _keys(raw, {
      'runId',
      'parserVersion',
      'phase',
      'plans',
      'completed',
      'baselines',
      'candidates',
      'pending',
      'removed',
      'errors',
    });
    if ((raw['runId'] as String).isEmpty ||
        (raw['parserVersion'] as int) < 1 ||
        !{'running', 'paused', 'ready', 'failed'}.contains(raw['phase'])) {
      throw const FormatException('课程生成状态无效');
    }
    final plans = (raw['plans'] as List)
        .map((p) => TextbookDraftPlan.fromJson(_map(p)))
        .toList();
    if (plans.map((p) => p.id).toSet().length != plans.length) {
      throw const FormatException('课程生成课目重复');
    }
    return TextbookDraftManifest(
      runId: raw['runId'] as String,
      parserVersion: raw['parserVersion'] as int,
      phase: raw['phase'] as String,
      plans: List.unmodifiable(plans),
      completed: List.unmodifiable((raw['completed'] as List).cast<String>()),
      baselines:
          Map.unmodifiable(_map(raw['baselines']).cast<String, String>()),
      candidates: Map.unmodifiable(
        _map(raw['candidates']).map(
          (k, v) => MapEntry(
            k,
            List<TextbookDraftCandidate>.unmodifiable(
              (v as List).map((c) => TextbookDraftCandidate.fromJson(_map(c))),
            ),
          ),
        ),
      ),
      pending: Map.unmodifiable(
        _map(raw['pending']).map((k, v) => MapEntry(k, _map(v))),
      ),
      removed: List.unmodifiable((raw['removed'] as List).cast<String>()),
      errors: Map.unmodifiable(_map(raw['errors']).cast<String, String>()),
    );
  }
}

String textbookDraftBaseline(Map<String, dynamic> raw) =>
    textbookTextDigest(jsonEncode(raw));
Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException('本机课程记录须为对象');
  return value;
}

void _keys(
  Map<String, dynamic> raw,
  Set<String> keys, {
  Set<String> optional = const {},
}) {
  if (!keys.every(raw.containsKey) ||
      raw.keys.any((key) => !keys.contains(key) && !optional.contains(key))) {
    throw const FormatException('本机课程记录字段不完整或包含未知字段');
  }
}
