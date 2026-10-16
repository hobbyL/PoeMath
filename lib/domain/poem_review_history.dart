import 'dart:convert';

class CompletedPoemReview {
  const CompletedPoemReview({
    required this.id,
    required this.cycleId,
    required this.poemId,
    required this.reviewedAt,
    required this.roundBefore,
    required this.roundAfter,
    this.score,
  });
  final String id;
  final String cycleId;
  final String poemId;
  final DateTime reviewedAt;
  final int roundBefore;
  final int roundAfter;
  final double? score;

  Map<String, dynamic> toJson() => {
        'id': id,
        'cycleId': cycleId,
        'poemId': poemId,
        'reviewedAt': reviewedAt.toIso8601String(),
        'roundBefore': roundBefore,
        'roundAfter': roundAfter,
        'score': score,
      };

  factory CompletedPoemReview.fromJson(Map<String, dynamic> json) {
    final score = json['score'];
    if (json['id'] is! String ||
        json['cycleId'] is! String ||
        json['poemId'] is! String ||
        json['reviewedAt'] is! String ||
        DateTime.tryParse(json['reviewedAt'] as String) == null ||
        json['roundBefore'] is! int ||
        json['roundAfter'] is! int ||
        (json['roundBefore'] as int) < 0 ||
        (json['roundAfter'] as int) > 5 ||
        json['roundAfter'] != (json['roundBefore'] as int) + 1 ||
        (score != null &&
            (score is! num || !score.isFinite || score < 0.8 || score > 1))) {
      throw const FormatException('无效的已完成复习记录');
    }
    return CompletedPoemReview(
      id: json['id'] as String,
      cycleId: json['cycleId'] as String,
      poemId: json['poemId'] as String,
      reviewedAt: DateTime.parse(json['reviewedAt'] as String),
      roundBefore: json['roundBefore'] as int,
      roundAfter: json['roundAfter'] as int,
      score: (score as num?)?.toDouble(),
    );
  }
}

/// 历史周期快照与真实完成事件同存于一次 Hive put，重放不追加重复事件。
class PoemReviewHistory {
  const PoemReviewHistory({
    required this.cycleId,
    this.cycleStartedAt,
    this.cycles = const [],
    this.reviews = const [],
  });
  final String cycleId;
  final DateTime? cycleStartedAt;
  final List<Map<String, dynamic>> cycles;
  final List<CompletedPoemReview> reviews;

  String encode() => jsonEncode(toJson());
  Map<String, dynamic> toJson() => {
        'v': 1,
        'cycleId': cycleId,
        'cycleStartedAt': cycleStartedAt?.toIso8601String(),
        'cycles': cycles,
        'reviews': reviews.map((event) => event.toJson()).toList(),
      };

  static PoemReviewHistory? decode(String? source) {
    if (source == null) return null;
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic>) throw const FormatException('无效的复习历史');
    return PoemReviewHistory.fromJson(json);
  }

  factory PoemReviewHistory.fromJson(Map<String, dynamic> json) {
    final started = json['cycleStartedAt'];
    if (json['v'] != 1 ||
        json['cycleId'] is! String ||
        (json['cycleId'] as String).isEmpty ||
        json['cycles'] is! List ||
        json['reviews'] is! List ||
        (started != null &&
            (started is! String || DateTime.tryParse(started) == null))) {
      throw const FormatException('无效的复习历史');
    }
    final cycles = (json['cycles'] as List<dynamic>).map((value) {
      if (value is! Map<String, dynamic> ||
          value['cycleId'] is! String ||
          value['currentRound'] is! int ||
          (value['currentRound'] as int) < 0 ||
          (value['currentRound'] as int) > 5 ||
          value['isCompleted'] is! bool ||
          value['archivedAt'] is! String ||
          DateTime.tryParse(value['archivedAt'] as String) == null) {
        throw const FormatException('无效的历史复习周期');
      }
      for (final key in [
        'cycleStartedAt',
        'lastReviewedAt',
        'nextReviewDate',
      ]) {
        if (value[key] != null &&
            (value[key] is! String ||
                DateTime.tryParse(value[key] as String) == null)) {
          throw const FormatException('无效的复习周期日期');
        }
      }
      final score = value['lastScore'];
      if (score != null &&
          (score is! num || !score.isFinite || score < 0 || score > 1)) {
        throw const FormatException('无效的复习周期得分');
      }
      return value;
    }).toList();
    return PoemReviewHistory(
      cycleId: json['cycleId'] as String,
      cycleStartedAt:
          started == null ? null : DateTime.parse(started as String),
      cycles: cycles,
      reviews: (json['reviews'] as List<dynamic>).map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('无效的复习事件');
        }
        return CompletedPoemReview.fromJson(value);
      }).toList(),
    );
  }

  PoemReviewHistory merge(Iterable<PoemReviewHistory> histories) {
    final all = [this, ...histories];
    return PoemReviewHistory(
      cycleId: cycleId,
      cycleStartedAt: cycleStartedAt,
      cycles: {
        for (final history in all)
          for (final cycle in history.cycles) cycle['cycleId'] as String: cycle,
      }.values.toList(),
      reviews: {
        for (final history in all)
          for (final event in history.reviews) event.id: event,
      }.values.toList()
        ..sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt)),
    );
  }
}
