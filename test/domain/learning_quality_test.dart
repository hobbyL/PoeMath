import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/domain/learning_quality.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';

MathSession session(DateTime date, String? skillId, int total, int correct,
        {int grade = 4, String? semester = '下',}) =>
    MathSession(
      id: '$date:$skillId',
      profileId: 'default',
      grade: grade,
      semester: semester,
      problemType: 'mixed',
      totalProblems: total,
      correctCount: correct,
      finishedAt: date,
      problemsJson: jsonEncode([
        for (var i = 0; i < total; i++)
          ProblemRecord(
                  problemText: '题$i',
                  answerText: '1',
                  userAnswer: i < correct ? '1' : '0',
                  isCorrect: i < correct,
                  skillId: skillId,)
              .toJson(),
      ]),
    );

void main() {
  final start = DateTime(2026, 10, 10);
  final end = DateTime(2026, 10, 17);

  test('从真实逐题分子分母聚合，半开时间窗对比前周期，旧记录和挑战计未知', () {
    final report = buildLearningQualityReport(
      startInclusive: start,
      endExclusive: end,
      sessions: [
        session(start, 'addition_carry', 5, 3),
        session(DateTime(2026, 10, 3), 'addition_carry', 5, 1),
        session(start, 'fraction', 2, 2),
        session(start, null, 3, 1),
        session(start, 'future_skill', 1, 1),
        session(end, 'addition_carry', 9, 9),
        session(DateTime(2026, 10, 2), 'addition_carry', 9, 9),
      ],
      challenges: [
        ChallengeRecord(
          id: 'challenge',
          profileId: 'default',
          mode: 'fixed',
          score: 0,
          totalAnswered: 6,
          correctCount: 6,
          bestCombo: 6,
          grade: 4,
          semester: '下',
          difficulty: 'medium',
          durationSeconds: 20,
          createdAt: start,
        ),
      ],
    );
    expect(report.classifiedMathTotal, 7);
    expect(report.unknownMathTotal, 10);
    final addition = report.skills.first;
    expect((addition.correct, addition.total), (3, 5));
    expect((addition.previousCorrect, addition.previousTotal), (1, 5));
    expect(addition.accuracy, 0.6);
    expect(addition.change, closeTo(0.4, 0.00001));
    expect(report.skills.last.isSmallSample, isTrue);
    expect(report.skills.last.change, isNull);
  });

  test('不同册次不混算；缺逐题明细不会按错题或session正确数伪造专项率', () {
    final missing = MathSession(
        id: 'missing',
        profileId: 'default',
        grade: 4,
        problemType: 'mixed',
        totalProblems: 8,
        correctCount: 7,
        finishedAt: start,
        problemsJson: 'broken',);
    final report = buildLearningQualityReport(
        startInclusive: start,
        endExclusive: end,
        sessions: [
          session(start, 'addition', 5, 5, semester: '上'),
          session(start, 'addition', 5, 1, semester: '下'),
          missing,
        ],);
    expect(report.skills.length, 2);
    expect(
        report.skills
            .map((skill) => (skill.semester, skill.correct, skill.total))
            .toSet(),
        {('上', 5, 5), ('下', 1, 5)},);
    expect(report.unknownMathTotal, 8);
    expect(report.recommendations.single.semester, '下');
  });

  test('最多三条建议，小样本不判断变化，未知册次不进入专项', () {
    final report = buildLearningQualityReport(
        startInclusive: start,
        endExclusive: end,
        sessions: [
          for (final skill in [
            'addition',
            'addition_carry',
            'subtraction',
            'subtraction_borrow',
            'fraction',
          ])
            session(start, skill, 5, 0),
          session(start, 'decimal', 1, 0, semester: null),
        ],);
    expect(report.recommendations.length, 3);
    expect(
        report.recommendations
            .every((skill) => skill.semester != null && skill.total == 5),
        isTrue,);
    final small =
        report.skills.singleWhere((skill) => skill.skill.id == 'decimal');
    expect(small.isSmallSample, isTrue);
    expect(small.change, isNull);
    expect(small.canPractice, isFalse);
  });

  test('诗词新学按首学日期，练习按活动次数，完成复习仅按真实事件', () {
    LearningActivity activity(
            String id, LearningActivityType type, DateTime date,) =>
        LearningActivity(
            id: id,
            profileId: 'default',
            activityType: type.name,
            totalItems: 5,
            successfulItems: 4,
            starsEarned: 2,
            durationSeconds: 20,
            completedAt: date,
            poemId: 'poem',);
    final report = buildLearningQualityReport(
      startInclusive: start,
      endExclusive: end,
      sessions: [],
      poemProgress: [
        PoemProgress(
            poemId: 'new',
            profileId: 'default',
            studyCount: 2,
            firstStudiedAt: start,
            lastStudiedAt: start,),
        PoemProgress(
            poemId: 'newMastery',
            profileId: 'default',
            status: LearningStatus.mastered,
            firstMasteredAt: start,
            firstStudiedAt: DateTime(2026, 1),),
        PoemProgress(
            poemId: 'masteryAtEnd',
            profileId: 'default',
            status: LearningStatus.mastered,
            firstMasteredAt: end,
            firstStudiedAt: DateTime(2026, 1),),
        PoemProgress(
            poemId: 'legacyMastery',
            profileId: 'default',
            status: LearningStatus.mastered,),
        PoemProgress(
            poemId: 'old',
            profileId: 'default',
            studyCount: 8,
            firstStudiedAt: DateTime(2026, 1),
            lastStudiedAt: start,),
        PoemProgress(poemId: 'legacy', profileId: 'default', studyCount: 8),
      ],
      activities: [
        activity('a', LearningActivityType.poemQuiz, start),
        activity('b', LearningActivityType.poemRecitation, start),
        activity('c', LearningActivityType.readAlong, start),
        activity('d', LearningActivityType.poemDictation, end),
      ],
      reviews: [
        QualityReviewCompletion(poemId: 'old', completedAt: start),
        QualityReviewCompletion(poemId: 'old', completedAt: end),
      ],
    );
    expect(report.newPoems, 1);
    expect(report.poemPracticeCount, 3);
    expect(report.completedReviews, 1);
    expect(report.newlyMasteredPoems, 1);
    expect(report.masteryHistoryUnknown, isTrue);
    expect(
        report.poemModes
            .map((mode) => (mode.mode, mode.successful, mode.total))
            .toSet(),
        {
          (LearningActivityType.poemQuiz, 4, 5),
          (LearningActivityType.poemRecitation, 0, 0),
          (LearningActivityType.readAlong, 4, 5),
        });
    expect(report.poemHistoryUnknown, isTrue);
  });

  test('不同诗词模式和新旧明细只按各自真实单位累计，不混用背诵质量点', () {
    LearningActivity activity(
            String id, LearningActivityType type, int total, int passed,) =>
        LearningActivity(
            id: id,
            profileId: 'default',
            activityType: type.name,
            totalItems: total,
            successfulItems: passed,
            starsEarned: 0,
            durationSeconds: 1,
            completedAt: start,
            poemId: 'poem',);
    final report = buildLearningQualityReport(
      startInclusive: start,
      endExclusive: end,
      sessions: [],
      activities: [
        activity('quiz', LearningActivityType.poemQuiz, 10, 8),
        activity('dictation', LearningActivityType.poemDictation, 4, 1),
        activity('targeted', LearningActivityType.poemDictation, 1, 1),
        activity('read', LearningActivityType.readAlong, 4, 3),
        activity('recite', LearningActivityType.poemRecitation, 12, 9),
      ],
    );
    expect(report.poemPracticeCount, 5);
    expect(
        report.poemModes
            .map((mode) =>
                (mode.mode, mode.practices, mode.successful, mode.total),)
            .toSet(),
        {
          (LearningActivityType.poemQuiz, 1, 8, 10),
          (LearningActivityType.poemDictation, 2, 2, 5),
          (LearningActivityType.readAlong, 1, 3, 4),
          (LearningActivityType.poemRecitation, 1, 0, 0),
        });
  });
}
