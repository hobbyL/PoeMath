import 'dart:convert';

enum PictureStoryAssessment {
  met('说清楚了'),
  developing('可以再补充'),
  uncertain('暂无法判断');

  const PictureStoryAssessment(this.label);
  final String label;
}

class PictureStoryFeedbackItem {
  const PictureStoryFeedbackItem({
    required this.id,
    required this.status,
    required this.evidence,
    required this.reason,
  });
  final String id;
  final PictureStoryAssessment status;
  final String evidence;
  final String reason;
  Map<String, Object> toJson() => {
    'id': id,
    'status': status.name,
    'evidence': evidence,
    'reason': reason,
  };
}

class PictureStorySuggestion {
  const PictureStorySuggestion({
    required this.original,
    required this.replacement,
    required this.reason,
  });
  final String original;
  final String replacement;
  final String reason;
  Map<String, String> toJson() => {
    'original': original,
    'replacement': replacement,
    'reason': reason,
  };
}

/// 结构正确不代表语义一定正确；仅接受本次原话作为引用。
class PictureStoryEvaluation {
  const PictureStoryEvaluation({
    required this.summary,
    required this.dimensions,
    required this.questions,
    required this.suggestions,
  });
  static const dimensionLabels = {
    'picture': '画面是否符合',
    'response': '问题是否回应',
    'expression': '表达是否清楚',
  };
  final String summary;
  final List<PictureStoryFeedbackItem> dimensions;
  final List<PictureStoryFeedbackItem> questions;
  final List<PictureStorySuggestion> suggestions;

  static PictureStoryEvaluation parse(
    String raw, {
    required String answer,
    required int questionCount,
  }) {
    if (raw.length > 24000) throw const FormatException('点评内容过长');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('点评格式不完整');
    }
    String text(Object? value, int max, {bool empty = false}) {
      if (value is! String ||
          value.runes.length > max ||
          (!empty && value.trim().isEmpty)) {
        throw const FormatException('点评文字不完整');
      }
      return value.trim();
    }

    String quote(Object? value) {
      final result = text(value, 1000, empty: true);
      if (result.isNotEmpty && !answer.contains(result)) {
        throw const FormatException('点评引用与孩子的原话不一致');
      }
      return result;
    }

    List<PictureStoryFeedbackItem> items(String key, List<String> ids) {
      final values = decoded[key];
      if (values is! List || values.length != ids.length) {
        throw const FormatException('点评项目不完整');
      }
      final result = <PictureStoryFeedbackItem>[];
      for (final value in values) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('点评项目无效');
        }
        final id = value['id'];
        final status = PictureStoryAssessment.values
            .where((s) => s.name == value['status'])
            .firstOrNull;
        if (id is! String ||
            !ids.contains(id) ||
            result.any((i) => i.id == id) ||
            status == null) {
          throw const FormatException('点评项目无效');
        }
        final evidence = quote(value['evidence']);
        if (status == PictureStoryAssessment.met && evidence.isEmpty) {
          throw const FormatException('肯定评价缺少原话依据');
        }
        result.add(
          PictureStoryFeedbackItem(
            id: id,
            status: status,
            evidence: evidence,
            reason: text(value['reason'], 500),
          ),
        );
      }
      return List.unmodifiable([
        for (final id in ids) result.singleWhere((i) => i.id == id),
      ]);
    }

    final suggestions = decoded['suggestions'];
    if (suggestions is! List || suggestions.length > 2) {
      throw const FormatException('修改建议格式无效');
    }
    return PictureStoryEvaluation(
      summary: text(decoded['summary'], 400),
      dimensions: items('dimensions', dimensionLabels.keys.toList()),
      questions: items('questions', [
        for (var i = 0; i < questionCount; i++) '${i + 1}',
      ]),
      suggestions: List.unmodifiable(
        suggestions.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('修改建议无效');
          }
          final original = quote(item['original']);
          if (original.isEmpty) throw const FormatException('修改建议缺少原句');
          return PictureStorySuggestion(
            original: original,
            replacement: text(item['replacement'], 1000),
            reason: text(item['reason'], 400),
          );
        }),
      ),
    );
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'summary': summary,
    'dimensions': dimensions.map((d) => d.toJson()).toList(),
    'questions': questions.map((q) => q.toJson()).toList(),
    'suggestions': suggestions.map((s) => s.toJson()).toList(),
  };

  String encode({required String answer, required List<String> prompts}) =>
      jsonEncode({
        'source': 'vision',
        ...toJson(),
        'answer': answer,
        'prompts': prompts,
      });
}

String unavailablePictureStoryFeedback(String reason) => jsonEncode({
  'source': 'unavailable',
  'text': '本次未获得 AI 点评',
  'suggestion': reason,
});
