import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/poem_favorite.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/domain/poem_review_history.dart';

/// 固定作品身份。旧链接、用户记录和旧备份仍可使用别名。
class PoemIdentity {
  const PoemIdentity._();

  static const aliases = <String, String>{
    'poem_ext_032': 'poem_core_039',
    'poem_ext_049': 'poem_core_104',
    'poem_exp_657': 'poem_ext_064',
    'poem_exp_656': 'poem_core_035',
    'poem_exp_659': 'poem_core_052',
    'poem_exp_661': 'poem_core_004',
    'poem_exp_662': 'poem_core_075',
    'poem_exp_663': 'poem_core_048',
    'poem_exp_673': 'poem_core_120',
  };

  static String canonical(String id) => aliases[id] ?? id;

  static Map<String, dynamic> progressMap(PoemProgress p) => {
        'poemId': p.poemId,
        'profileId': p.profileId,
        'status': p.status.index,
        'masteryLevel': p.masteryLevel,
        'studyCount': p.studyCount,
        'lastStudiedAt': p.lastStudiedAt?.toIso8601String(),
        'firstStudiedAt': p.firstStudiedAt?.toIso8601String(),
        'stars': p.stars,
        'firstMasteredAt': p.firstMasteredAt?.toIso8601String(),
      };

  static PoemProgress progress(Map<String, dynamic> m) => PoemProgress(
        poemId: canonical(m['poemId'] as String),
        profileId: m['profileId'] as String,
        status: LearningStatus.values[m['status'] as int? ?? 0],
        masteryLevel: m['masteryLevel'] as int? ?? 0,
        studyCount: m['studyCount'] as int? ?? 0,
        stars: m['stars'] as int? ?? 0,
        firstStudiedAt: _date(m['firstStudiedAt']),
        lastStudiedAt: _date(m['lastStudiedAt']),
        firstMasteredAt: _date(m['firstMasteredAt']),
      );

  static Map<String, dynamic> favoriteMap(PoemFavorite f) => {
        'poemId': f.poemId,
        'profileId': f.profileId,
        'createdAt': f.createdAt.toIso8601String(),
      };

  static PoemFavorite favorite(Map<String, dynamic> m) => PoemFavorite(
        poemId: canonical(m['poemId'] as String),
        profileId: m['profileId'] as String,
        createdAt: _date(m['createdAt']),
      );

  static Map<String, dynamic> reviewMap(ReviewSchedule r) => {
        'poemId': r.poemId,
        'profileId': r.profileId,
        'currentRound': r.currentRound,
        'nextReviewDate': r.nextReviewDate.toIso8601String(),
        'lastReviewedAt': r.lastReviewedAt?.toIso8601String(),
        'isCompleted': r.isCompleted,
        'lastScore': r.lastScore,
        'historyJson': r.historyJson,
      };

  static ReviewSchedule review(Map<String, dynamic> m) => ReviewSchedule(
        poemId: canonical(m['poemId'] as String),
        profileId: m['profileId'] as String,
        currentRound: m['currentRound'] as int? ?? 0,
        nextReviewDate: _date(m['nextReviewDate']) ?? DateTime.now(),
        lastReviewedAt: _date(m['lastReviewedAt']),
        isCompleted: m['isCompleted'] as bool? ?? false,
        lastScore: (m['lastScore'] as num?)?.toDouble(),
        historyJson: m['historyJson'] as String?,
      );

  /// 纯合并：输入是迁移前快照，输出可安全重复写入。
  static List<Map<String, dynamic>> merge(String kind, List<dynamic> records) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final raw in records) {
      final m = Map<String, dynamic>.from(raw as Map);
      final key = '${m['profileId']}_${canonical(m['poemId'] as String)}';
      groups.putIfAbsent(key, () => []).add(m);
    }
    return groups.values.map((group) {
      final id = canonical(group.first['poemId'] as String);
      group.sort(
        (a, b) => (a['poemId'] as String).compareTo(b['poemId'] as String),
      );
      var result = Map<String, dynamic>.from(group.first);
      if (kind == 'progress') {
        for (final field in ['status', 'masteryLevel']) {
          result[field] = group
              .map((m) => m[field] as int? ?? 0)
              .reduce((a, b) => a > b ? a : b);
        }
        for (final field in ['studyCount', 'stars']) {
          result[field] =
              group.fold<int>(0, (n, m) => n + (m[field] as int? ?? 0));
        }
        result['firstStudiedAt'] =
            _extremeDate(group, 'firstStudiedAt', earliest: true);
        result['lastStudiedAt'] = _extremeDate(group, 'lastStudiedAt');
        result['firstMasteredAt'] =
            _extremeDate(group, 'firstMasteredAt', earliest: true);
      } else if (kind == 'favorite') {
        result['createdAt'] = _extremeDate(group, 'createdAt', earliest: true);
      } else if (kind == 'review') {
        int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
          final aStarted = PoemReviewHistory.decode(a['historyJson'] as String?)
              ?.cycleStartedAt;
          final bStarted = PoemReviewHistory.decode(b['historyJson'] as String?)
              ?.cycleStartedAt;
          final cycle =
              (aStarted ?? DateTime(1)).compareTo(bStarted ?? DateTime(1));
          if (cycle != 0) return cycle;
          final completed = (a['isCompleted'] == true ? 1 : 0)
              .compareTo(b['isCompleted'] == true ? 1 : 0);
          if (completed != 0) return completed;
          final round = (a['currentRound'] as int? ?? 0)
              .compareTo(b['currentRound'] as int? ?? 0);
          if (round != 0) return round;
          return (_date(a['lastReviewedAt']) ?? DateTime(1))
              .compareTo(_date(b['lastReviewedAt']) ?? DateTime(1));
        }

        for (final candidate in group.skip(1)) {
          if (compare(candidate, result) > 0) {
            result = Map<String, dynamic>.from(candidate);
          }
        }
        final winnerHistory =
            PoemReviewHistory.decode(result['historyJson'] as String?);
        final allHistories = group
            .map(
              (row) => PoemReviewHistory.decode(row['historyJson'] as String?),
            )
            .whereType<PoemReviewHistory>()
            .toList();
        if (allHistories.isNotEmpty) {
          result['historyJson'] =
              (winnerHistory ?? const PoemReviewHistory(cycleId: 'legacy'))
                  .merge(allHistories)
                  .encode();
        }
      }
      result['poemId'] = id;
      return result;
    }).toList();
  }

  static DateTime? _date(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  static String? _extremeDate(
    List<Map<String, dynamic>> rows,
    String field, {
    bool earliest = false,
  }) {
    final dates =
        rows.map((m) => _date(m[field])).whereType<DateTime>().toList()..sort();
    if (dates.isEmpty) return null;
    return (earliest ? dates.first : dates.last).toIso8601String();
  }
}
