// lib/core/services/backup_service.dart
//
// 层级：core/services
// 职责：数据备份与恢复服务。
//       导出所有用户动态数据为 JSON，或从 JSON 恢复。
//       静态数据（诗词、作者、公式）由 asset 加载，不参与备份。

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/formula_favorite.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/poem_favorite.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/models/challenge_record.dart';

/// 备份数据版本号，用于兼容性检查。
const int _backupVersion = 1;

class BackupService {
  /// 导出所有用户数据为 JSON 字符串。
  String exportToJson() {
    final data = <String, dynamic>{
      'version': _backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'poemProgress': _exportPoemProgress(),
      'poemFavorites': _exportPoemFavorites(),
      'reviewSchedules': _exportReviewSchedules(),
      'mathMistakes': _exportMathMistakes(),
      'mathSessions': _exportMathSessions(),
      'formulaFavorites': _exportFormulaFavorites(),
      'achievements': _exportAchievements(),
      'checkIns': _exportCheckIns(),
      'userStats': _exportUserStats(),
      'challengeRecords': _exportChallengeRecords(),
      'settings': _exportSettings(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 导出并保存到临时文件，返回文件路径。
  Future<String> exportToFile() async {
    final json = exportToJson();
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/poemath_backup_$timestamp.json');
    await file.writeAsString(json);
    return file.path;
  }

  /// 从 JSON 字符串恢复数据。
  ///
  /// 返回恢复的记录总数。
  /// 如果版本不兼容，抛出 [FormatException]。
  /// 恢复失败时自动回滚到恢复前的数据状态。
  Future<int> restoreFromJson(String jsonString) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonString) as Map<String, dynamic>;
    } on FormatException {
      throw const FormatException('无效的备份文件格式');
    }

    final version = data['version'] as int? ?? 0;
    if (version > _backupVersion) {
      throw FormatException('备份文件版本 ($version) 高于当前支持版本');
    }

    // 恢复前先快照当前数据，失败时用于回滚
    final snapshot = exportToJson();

    try {
      return await _doRestore(data);
    } on Object {
      // 恢复失败，回滚到快照
      try {
        final rollback =
            jsonDecode(snapshot) as Map<String, dynamic>;
        await _doRestore(rollback);
      } on Object {
        // 回滚也失败，数据可能不完整，但至少尝试过了
      }
      rethrow;
    }
  }

  /// 执行实际的数据恢复，返回记录总数。
  Future<int> _doRestore(Map<String, dynamic> data) async {
    var count = 0;

    count += await _restorePoemProgress(
      data['poemProgress'] as List<dynamic>? ?? [],
    );
    count += await _restorePoemFavorites(
      data['poemFavorites'] as List<dynamic>? ?? [],
    );
    count += await _restoreReviewSchedules(
      data['reviewSchedules'] as List<dynamic>? ?? [],
    );
    count += await _restoreMathMistakes(
      data['mathMistakes'] as List<dynamic>? ?? [],
    );
    count += await _restoreMathSessions(
      data['mathSessions'] as List<dynamic>? ?? [],
    );
    count += await _restoreFormulaFavorites(
      data['formulaFavorites'] as List<dynamic>? ?? [],
    );
    count += await _restoreAchievements(
      data['achievements'] as List<dynamic>? ?? [],
    );
    count += await _restoreCheckIns(
      data['checkIns'] as List<dynamic>? ?? [],
    );
    count += await _restoreUserStats(
      data['userStats'] as List<dynamic>? ?? [],
    );
    count += await _restoreChallengeRecords(
      data['challengeRecords'] as List<dynamic>? ?? [],
    );
    _restoreSettings(data['settings'] as Map<String, dynamic>? ?? {});

    return count;
  }

  /// 从文件路径恢复。
  Future<int> restoreFromFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw const FormatException('备份文件不存在');
    }
    final json = await file.readAsString();
    return restoreFromJson(json);
  }

  // ============ 导出 ============

  List<Map<String, dynamic>> _exportPoemProgress() {
    return HiveBoxes.poemProgress.values.map((p) {
      return <String, dynamic>{
        'poemId': p.poemId,
        'profileId': p.profileId,
        'status': p.status.index,
        'masteryLevel': p.masteryLevel,
        'studyCount': p.studyCount,
        'lastStudiedAt': p.lastStudiedAt?.toIso8601String(),
        'firstStudiedAt': p.firstStudiedAt?.toIso8601String(),
        'stars': p.stars,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportPoemFavorites() {
    return HiveBoxes.poemFavorites.values.map((f) {
      return <String, dynamic>{
        'poemId': f.poemId,
        'profileId': f.profileId,
        'createdAt': f.createdAt.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportReviewSchedules() {
    return HiveBoxes.reviewSchedules.values.map((r) {
      return <String, dynamic>{
        'poemId': r.poemId,
        'profileId': r.profileId,
        'currentRound': r.currentRound,
        'nextReviewDate': r.nextReviewDate.toIso8601String(),
        'lastReviewedAt': r.lastReviewedAt?.toIso8601String(),
        'isCompleted': r.isCompleted,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportMathMistakes() {
    return HiveBoxes.mathMistakes.values.map((m) {
      return <String, dynamic>{
        'id': m.id,
        'profileId': m.profileId,
        'problemText': m.problemText,
        'correctAnswer': m.correctAnswer,
        'userAnswer': m.userAnswer,
        'problemType': m.problemType,
        'grade': m.grade,
        'errorType': m.errorType,
        'solutionStepsJson': m.solutionStepsJson,
        'createdAt': m.createdAt.toIso8601String(),
        'isResolved': m.isResolved,
        'retryCount': m.retryCount,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportMathSessions() {
    return HiveBoxes.mathSessions.values.map((s) {
      return <String, dynamic>{
        'id': s.id,
        'profileId': s.profileId,
        'grade': s.grade,
        'problemType': s.problemType,
        'totalProblems': s.totalProblems,
        'correctCount': s.correctCount,
        'durationSeconds': s.durationSeconds,
        'starsEarned': s.starsEarned,
        'startedAt': s.startedAt.toIso8601String(),
        'finishedAt': s.finishedAt?.toIso8601String(),
        'semester': s.semester,
        'difficulty': s.difficulty,
        'problemsJson': s.problemsJson,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportFormulaFavorites() {
    return HiveBoxes.formulaFavorites.values.map((f) {
      return <String, dynamic>{
        'formulaId': f.formulaId,
        'profileId': f.profileId,
        'createdAt': f.createdAt.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportAchievements() {
    return HiveBoxes.achievements.values.map((a) {
      return <String, dynamic>{
        'id': a.id,
        'profileId': a.profileId,
        'title': a.title,
        'description': a.description,
        'iconName': a.iconName,
        'isUnlocked': a.isUnlocked,
        'unlockedAt': a.unlockedAt?.toIso8601String(),
        'progress': a.progress,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportCheckIns() {
    return HiveBoxes.checkIns.values.map((c) {
      return <String, dynamic>{
        'profileId': c.profileId,
        'date': c.date,
        'poemCount': c.poemCount,
        'mathTotalCount': c.mathTotalCount,
        'mathCorrectCount': c.mathCorrectCount,
        'starsEarned': c.starsEarned,
        'durationSeconds': c.durationSeconds,
        'isCheckedIn': c.isCheckedIn,
        'activitySources': c.activitySources,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportUserStats() {
    return HiveBoxes.userStats.values.map((s) {
      return <String, dynamic>{
        'profileId': s.profileId,
        'totalStars': s.totalStars,
        'currentStreak': s.currentStreak,
        'longestStreak': s.longestStreak,
        'poemsLearned': s.poemsLearned,
        'poemsMastered': s.poemsMastered,
        'mathTotalProblems': s.mathTotalProblems,
        'mathTotalCorrect': s.mathTotalCorrect,
        'level': s.level,
        'createdAt': s.createdAt.toIso8601String(),
        'mathBestStreak': s.mathBestStreak,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportChallengeRecords() {
    return HiveBoxes.challengeRecords.values.map((r) {
      return <String, dynamic>{
        'id': r.id,
        'profileId': r.profileId,
        'mode': r.mode,
        'score': r.score,
        'totalAnswered': r.totalAnswered,
        'correctCount': r.correctCount,
        'bestCombo': r.bestCombo,
        'grade': r.grade,
        'semester': r.semester,
        'difficulty': r.difficulty,
        'durationSeconds': r.durationSeconds,
        'createdAt': r.createdAt.toIso8601String(),
      };
    }).toList();
  }

  Map<String, dynamic> _exportSettings() {
    final box = HiveBoxes.settings;
    final result = <String, dynamic>{};
    for (final key in box.keys) {
      result[key.toString()] = box.get(key);
    }
    return result;
  }

  // ============ 恢复 ============

  Future<int> _restorePoemProgress(List<dynamic> items) async {
    final box = HiveBoxes.poemProgress;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = PoemProgress(
        poemId: m['poemId'] as String,
        profileId: m['profileId'] as String,
        status: LearningStatus.values[m['status'] as int? ?? 0],
        masteryLevel: m['masteryLevel'] as int? ?? 0,
        studyCount: m['studyCount'] as int? ?? 0,
        lastStudiedAt: _parseDateTime(m['lastStudiedAt']),
        firstStudiedAt: _parseDateTime(m['firstStudiedAt']),
        stars: m['stars'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_${obj.poemId}', obj);
    }
    return items.length;
  }

  Future<int> _restorePoemFavorites(List<dynamic> items) async {
    final box = HiveBoxes.poemFavorites;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = PoemFavorite(
        poemId: m['poemId'] as String,
        profileId: m['profileId'] as String,
        createdAt: _parseDateTime(m['createdAt']),
      );
      await box.put('${obj.profileId}_${obj.poemId}', obj);
    }
    return items.length;
  }

  Future<int> _restoreReviewSchedules(List<dynamic> items) async {
    final box = HiveBoxes.reviewSchedules;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = ReviewSchedule(
        poemId: m['poemId'] as String,
        profileId: m['profileId'] as String,
        currentRound: m['currentRound'] as int? ?? 0,
        nextReviewDate:
            _parseDateTime(m['nextReviewDate']) ?? DateTime.now(),
        lastReviewedAt: _parseDateTime(m['lastReviewedAt']),
        isCompleted: m['isCompleted'] as bool? ?? false,
      );
      await box.put('${obj.profileId}_${obj.poemId}', obj);
    }
    return items.length;
  }

  Future<int> _restoreMathMistakes(List<dynamic> items) async {
    final box = HiveBoxes.mathMistakes;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = MathMistake(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        problemText: m['problemText'] as String,
        correctAnswer: m['correctAnswer'] as String,
        userAnswer: m['userAnswer'] as String,
        problemType: m['problemType'] as String,
        grade: m['grade'] as int,
        errorType: m['errorType'] as String?,
        solutionStepsJson: m['solutionStepsJson'] as String?,
        createdAt: _parseDateTime(m['createdAt']),
        isResolved: m['isResolved'] as bool? ?? false,
        retryCount: m['retryCount'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreMathSessions(List<dynamic> items) async {
    final box = HiveBoxes.mathSessions;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = MathSession(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        grade: m['grade'] as int,
        problemType: m['problemType'] as String,
        totalProblems: m['totalProblems'] as int,
        correctCount: m['correctCount'] as int? ?? 0,
        durationSeconds: m['durationSeconds'] as int? ?? 0,
        starsEarned: m['starsEarned'] as int? ?? 0,
        startedAt: _parseDateTime(m['startedAt']),
        finishedAt: _parseDateTime(m['finishedAt']),
        semester: m['semester'] as String?,
        difficulty: m['difficulty'] as String?,
        problemsJson: m['problemsJson'] as String?,
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreFormulaFavorites(List<dynamic> items) async {
    final box = HiveBoxes.formulaFavorites;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = FormulaFavorite(
        formulaId: m['formulaId'] as String,
        profileId: m['profileId'] as String,
        createdAt: _parseDateTime(m['createdAt']),
      );
      await box.put('${obj.profileId}_${obj.formulaId}', obj);
    }
    return items.length;
  }

  Future<int> _restoreAchievements(List<dynamic> items) async {
    final box = HiveBoxes.achievements;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = Achievement(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        title: m['title'] as String,
        description: m['description'] as String? ?? '',
        iconName: m['iconName'] as String? ?? 'trophy',
        isUnlocked: m['isUnlocked'] as bool? ?? false,
        unlockedAt: _parseDateTime(m['unlockedAt']),
        progress: (m['progress'] as num?)?.toDouble() ?? 0.0,
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreCheckIns(List<dynamic> items) async {
    final box = HiveBoxes.checkIns;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = CheckIn(
        profileId: m['profileId'] as String,
        date: m['date'] as String,
        poemCount: m['poemCount'] as int? ?? 0,
        mathTotalCount: m['mathTotalCount'] as int? ?? 0,
        mathCorrectCount: m['mathCorrectCount'] as int? ?? 0,
        starsEarned: m['starsEarned'] as int? ?? 0,
        durationSeconds: m['durationSeconds'] as int? ?? 0,
        isCheckedIn: m['isCheckedIn'] as bool? ?? true,
        activitySources: m['activitySources'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_${obj.date}', obj);
    }
    return items.length;
  }

  Future<int> _restoreUserStats(List<dynamic> items) async {
    final box = HiveBoxes.userStats;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = UserStats(
        profileId: m['profileId'] as String,
        totalStars: m['totalStars'] as int? ?? 0,
        currentStreak: m['currentStreak'] as int? ?? 0,
        longestStreak: m['longestStreak'] as int? ?? 0,
        poemsLearned: m['poemsLearned'] as int? ?? 0,
        poemsMastered: m['poemsMastered'] as int? ?? 0,
        mathTotalProblems: m['mathTotalProblems'] as int? ?? 0,
        mathTotalCorrect: m['mathTotalCorrect'] as int? ?? 0,
        level: m['level'] as int? ?? 0,
        createdAt: _parseDateTime(m['createdAt']),
        mathBestStreak: m['mathBestStreak'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_stats', obj);
    }
    return items.length;
  }

  Future<int> _restoreChallengeRecords(List<dynamic> items) async {
    final box = HiveBoxes.challengeRecords;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = ChallengeRecord(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        mode: m['mode'] as String,
        score: m['score'] as int,
        totalAnswered: m['totalAnswered'] as int,
        correctCount: m['correctCount'] as int,
        bestCombo: m['bestCombo'] as int? ?? 0,
        grade: m['grade'] as int,
        semester: m['semester'] as String,
        difficulty: m['difficulty'] as String,
        durationSeconds: m['durationSeconds'] as int? ?? 0,
        createdAt: _parseDateTime(m['createdAt']),
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  void _restoreSettings(Map<String, dynamic> items) {
    final box = HiveBoxes.settings;
    // 不清除 settings，采用覆盖策略
    for (final entry in items.entries) {
      box.put(entry.key, entry.value);
    }
  }

  // ============ 工具 ============

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
