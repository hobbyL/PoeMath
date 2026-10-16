import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';

class QualityReviewCompletion {
  const QualityReviewCompletion(
      {required this.poemId, required this.completedAt,});
  final String poemId;
  final DateTime completedAt;
}

/// 不同模式的计量单位不同，背诵的提示质量点不能当成答题正确率。
class PoemModeQuality {
  const PoemModeQuality(
      {required this.mode,
      required this.practices,
      required this.successful,
      required this.total,});
  final LearningActivityType mode;
  final int practices;
  final int successful;
  final int total;
}

class SkillQuality {
  const SkillQuality({
    required this.skill,
    required this.grade,
    required this.semester,
    required this.difficulty,
    required this.total,
    required this.correct,
    required this.previousTotal,
    required this.previousCorrect,
  });
  static const minimumSample = 5;
  final MathSkill skill;
  final int grade;
  final String? semester;
  final DifficultyLevel difficulty;
  final int total;
  final int correct;
  final int previousTotal;
  final int previousCorrect;
  double get accuracy => total == 0 ? 0 : correct / total;
  bool get isSmallSample => total < minimumSample;
  double? get change => isSmallSample || previousTotal < minimumSample
      ? null
      : accuracy - previousCorrect / previousTotal;
  bool get canPractice =>
      grade >= 1 && grade <= 6 && const ['上', '下'].contains(semester);
}

class LearningQualityReport {
  const LearningQualityReport({
    required this.skills,
    required this.unknownMathTotal,
    required this.classifiedMathTotal,
    required this.newPoems,
    required this.poemPracticeCount,
    required this.completedReviews,
    required this.poemHistoryUnknown,
    this.newlyMasteredPoems = 0,
    this.poemModes = const [],
    this.masteryHistoryUnknown = false,
  });
  final List<SkillQuality> skills;
  final int unknownMathTotal;
  final int classifiedMathTotal;
  final int newPoems;
  final int poemPracticeCount;
  final int completedReviews;
  final bool poemHistoryUnknown;
  final int newlyMasteredPoems;
  final List<PoemModeQuality> poemModes;
  final bool masteryHistoryUnknown;

  /// 只对有真实分母、册次明确的样本给出专项；小样本仅建议补充练习。
  List<SkillQuality> get recommendations {
    final candidates = skills
        .where(
          (skill) =>
              skill.canPractice &&
              (skill.isSmallSample || skill.accuracy < 0.8),
        )
        .toList()
      ..sort((a, b) {
        if (a.isSmallSample != b.isSmallSample) return a.isSmallSample ? 1 : -1;
        final byAccuracy = a.accuracy.compareTo(b.accuracy);
        return byAccuracy != 0 ? byAccuracy : b.total.compareTo(a.total);
      });
    return candidates.take(3).toList();
  }
}

class _SkillAccumulator {
  _SkillAccumulator(this.skill, this.grade, this.semester);
  final MathSkill skill;
  final int grade;
  final String? semester;
  DifficultyLevel difficulty = DifficultyLevel.medium;
  DateTime? latest;
  int total = 0;
  int correct = 0;
  int previousTotal = 0;
  int previousCorrect = 0;
}

/// 所有正确率只来自逐题作答，不从错题本的数量反推。
LearningQualityReport buildLearningQualityReport({
  required DateTime startInclusive,
  required DateTime endExclusive,
  required Iterable<MathSession> sessions,
  Iterable<ChallengeRecord> challenges = const [],
  Iterable<LearningActivity> activities = const [],
  Iterable<PoemProgress> poemProgress = const [],
  Iterable<QualityReviewCompletion> reviews = const [],
}) {
  if (!startInclusive.isBefore(endExclusive)) throw ArgumentError('报告时间窗无效');
  final previousStart =
      startInclusive.subtract(endExclusive.difference(startInclusive));
  bool current(DateTime date) =>
      !date.isBefore(startInclusive) && date.isBefore(endExclusive);
  final grouped = <String, _SkillAccumulator>{};
  var unknown = 0;
  var classified = 0;
  for (final session in sessions) {
    final date = session.finishedAt;
    if (date == null ||
        date.isBefore(previousStart) ||
        !date.isBefore(endExclusive)) {
      continue;
    }
    final inCurrent = current(date);
    final records = session.problemRecords.take(session.totalProblems).toList();
    if (inCurrent) unknown += session.totalProblems - records.length;
    for (final record in records) {
      final skill = MathSkill.fromId(record.skillId);
      if (skill == null) {
        if (inCurrent) unknown++;
        continue;
      }
      final key = '${skill.id}:${session.grade}:${session.semester}';
      final bucket = grouped.putIfAbsent(
          key, () => _SkillAccumulator(skill, session.grade, session.semester),);
      if (inCurrent) {
        classified++;
        bucket.total++;
        if (record.isCorrect) bucket.correct++;
        if (bucket.latest == null || date.isAfter(bucket.latest!)) {
          bucket.latest = date;
          bucket.difficulty = DifficultyLevel.values
                  .where((value) => value.name == session.difficulty)
                  .firstOrNull ??
              DifficultyLevel.medium;
        }
      } else {
        bucket.previousTotal++;
        if (record.isCorrect) bucket.previousCorrect++;
      }
    }
  }
  // 挑战当前只有总量；没有答对题的逐题知识点，不能混入任意专项的分母。
  for (final challenge in challenges) {
    if (current(challenge.createdAt)) unknown += challenge.totalAnswered;
  }
  final skills = grouped.values
      .where((bucket) => bucket.total > 0)
      .map(
        (bucket) => SkillQuality(
          skill: bucket.skill,
          grade: bucket.grade,
          semester: bucket.semester,
          difficulty: bucket.difficulty,
          total: bucket.total,
          correct: bucket.correct,
          previousTotal: bucket.previousTotal,
          previousCorrect: bucket.previousCorrect,
        ),
      )
      .toList()
    ..sort((a, b) {
      final order = a.skill.index.compareTo(b.skill.index);
      if (order != 0) return order;
      final grade = a.grade.compareTo(b.grade);
      return grade != 0
          ? grade
          : (a.semester ?? '').compareTo(b.semester ?? '');
    });
  final progress = poemProgress.toList();
  final newPoems = progress
      .where((poem) =>
          poem.firstStudiedAt != null && current(poem.firstStudiedAt!),)
      .map((poem) => poem.poemId)
      .toSet()
      .length;
  final practiceActivities = activities
      .where(
        (activity) =>
            current(activity.completedAt) &&
            const {
              LearningActivityType.poemRecitation,
              LearningActivityType.poemQuiz,
              LearningActivityType.poemDictation,
              LearningActivityType.readAlong,
            }.contains(activity.typeOrNull),
      )
      .toList();
  final modes = <PoemModeQuality>[];
  for (final mode in [
    LearningActivityType.poemQuiz,
    LearningActivityType.poemDictation,
    LearningActivityType.readAlong,
    LearningActivityType.poemRecitation,
  ]) {
    final matching = practiceActivities
        .where((activity) => activity.typeOrNull == mode)
        .toList();
    if (matching.isEmpty) continue;
    final comparable = mode != LearningActivityType.poemRecitation;
    modes.add(PoemModeQuality(
        mode: mode,
        practices: matching.length,
        successful: comparable
            ? matching.fold<int>(
                0, (sum, activity) => sum + activity.successfulItems,)
            : 0,
        total: comparable
            ? matching.fold<int>(
                0, (sum, activity) => sum + activity.totalItems,)
            : 0,),);
  }
  final newlyMastered = progress
      .where((poem) =>
          poem.firstMasteredAt != null && current(poem.firstMasteredAt!),)
      .map((poem) => poem.poemId)
      .toSet()
      .length;
  final completedReviews =
      reviews.where((review) => current(review.completedAt)).length;
  return LearningQualityReport(
    skills: skills,
    unknownMathTotal: unknown,
    classifiedMathTotal: classified,
    newPoems: newPoems,
    poemPracticeCount: practiceActivities.length,
    completedReviews: completedReviews,
    newlyMasteredPoems: newlyMastered,
    poemModes: modes,
    masteryHistoryUnknown: progress.any((poem) =>
        poem.status == LearningStatus.mastered && poem.firstMasteredAt == null,),
    poemHistoryUnknown: progress.any(
            (poem) => poem.studyCount > 0 && poem.firstStudiedAt == null,) ||
        progress.any((poem) =>
            poem.lastStudiedAt != null &&
            current(poem.lastStudiedAt!) &&
            !practiceActivities
                .any((activity) => activity.poemId == poem.poemId),),
  );
}
