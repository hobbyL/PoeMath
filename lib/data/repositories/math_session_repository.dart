// lib/data/repositories/math_session_repository.dart
//
// 层级：data/repositories
// 职责：口算练习会话仓储。Profile-scoped。

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_session.dart';

class MathSessionRepository {
  /// 保存会话
  Future<void> save(MathSession session) async {
    final key = ProfileScope.key(session.id);
    await HiveBoxes.mathSessions.put(key, session);
  }

  /// 按 ID 获取
  MathSession? getById(String id) {
    return HiveBoxes.mathSessions.get(ProfileScope.key(id));
  }

  /// 获取当前 profile 的所有会话
  List<MathSession> getAll() {
    return HiveBoxes.mathSessions.values
        .where((s) => s.profileId == ProfileScope.currentId)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  /// 获取最近 N 次会话
  List<MathSession> getRecent({int limit = 10}) {
    final all = getAll();
    return all.take(limit).toList();
  }

  /// 按年级统计
  List<MathSession> byGrade(int grade) {
    return getAll().where((s) => s.grade == grade).toList();
  }

  /// 总做题数
  int get totalProblems {
    return getAll().fold<int>(0, (sum, s) => sum + s.totalProblems);
  }

  /// 总正确数
  int get totalCorrect {
    return getAll().fold<int>(0, (sum, s) => sum + s.correctCount);
  }

  /// 总正确率
  double get overallAccuracy {
    final total = totalProblems;
    return total > 0 ? totalCorrect / total : 0.0;
  }

  /// 今日做题总数
  int get todayProblems {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return getAll()
        .where(
          (s) =>
              s.finishedAt != null && s.finishedAt!.isAfter(todayStart),
        )
        .fold<int>(0, (sum, s) => sum + s.totalProblems);
  }
}
