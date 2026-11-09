import 'dart:async';
import 'dart:convert';

import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/features/math/word_problem/word_problem_practice_page.dart';

import 'package:poemath/core/services/backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/math_session_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/math/math_practice_page.dart';
import 'package:poemath/features/math/math_practice_request.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import '../../helpers/hive_test_helper.dart';

class _RecordingSoundService extends SoundService {
  _RecordingSoundService() : super(SettingsRepository());
  int completions = 0;
  @override
  Future<void> playCompletion() async => completions++;
}

MathProblem _addition({ProblemMode mode = ProblemMode.findResult}) =>
    MathProblem(
      operands: [NumberValue.fromInt(23), NumberValue.fromInt(14)],
      operators: [Operator.add],
      result: NumberValue.fromInt(37),
      grade: 2,
      mode: mode,
      semester: '上',
      skillId: 'addition',
    );

Map<String, dynamic> _checkpoint(MathProblem problem) => {
  'sessionId': 'pending-math-final',
  'startedAt': DateTime(2026, 10, 16, 10).toIso8601String(),
  'completedAt': DateTime(2026, 10, 16, 10, 1).toIso8601String(),
  'elapsedMilliseconds': 60000,
  'index': 0,
  'input': '37',
  'request': const MathPracticeRequest(
    grade: 2,
    semester: '上',
    count: 1,
    difficulty: DifficultyLevel.medium,
  ).toJson(),
  'problems': [problem.toJson()],
  'records': [
    ProblemRecord(
      problemText: problem.problemText,
      answerText: '37',
      userAnswer: '37',
      isCorrect: true,
      problem: problem.toJson(),
    ).toJson(),
  ],
};

class _HeldFinalSession extends MathSessionRepository {
  _HeldFinalSession(this.completed);
  final bool completed;
  final release = Completer<void>();
  bool entered = false;
  @override
  Future<void> save(MathSession session) async {
    await super.save(session);
    if (session.isComplete == completed) {
      entered = true;
      await release.future;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);
  for (final word in [false, true]) {
    for (final completed in [false, true]) {
      testWidgets(
        '${word ? '应用题' : '口算'}离页后恢复等待完整${completed ? '结算' : '检查点'}',
        (tester) async {
          final sessions = _HeldFinalSession(completed);
          final sound = _RecordingSoundService();
          addTearDown(() async {
            if (!sessions.release.isCompleted) sessions.release.complete();
            await tester.pumpWidget(const SizedBox.shrink());
            await drainHiveWritesForTesting(tester);
          });
          await tester.runAsync(() async {
            final draft = _checkpoint(_addition());
            if (!completed) draft.remove('completedAt');
            if (word) {
              final problem = LlmProblem(
                id: 'word-1',
                profileId: 'default',
                questionText: '23加14是多少？',
                unit: '个',
                operands: [23, 14],
                operators: ['+'],
                answer: 37,
                explanation: '',
                batchId: 'batch',
                createdAt: DateTime(2026, 10, 16),
                grade: 2,
                semester: '上',
                topic: 'addition',
                difficulty: 2,
              );
              await HiveBoxes.llmProblems.put('default_word-1', problem);
              draft['problems'] = [problem.toSnapshot()];
            }
            await PracticeDraftRepository().save(word ? 'word' : 'math', draft);
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  mathSessionRepositoryProvider.overrideWithValue(sessions),
                  soundServiceProvider.overrideWithValue(sound),
                ],
                child: MaterialApp(
                  home: word
                      ? const WordProblemPracticePage(
                          problems: [],
                          resume: true,
                        )
                      : const MathPracticePage(resume: true),
                ),
              ),
            );
            for (var i = 0; i < 100 && !sessions.entered; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          expect(sessions.entered, isTrue);
          await tester.pumpWidget(const SizedBox.shrink());
          Map<String, dynamic>? snapshot;
          Future<void>? restoring;
          await tester.runAsync(() async {
            restoring = PracticeDraftRepository.whileRestoring(() async {
              snapshot = jsonDecode(
                await BackupService().exportToJson(),
              ) as Map<String, dynamic>;
            });
            await Future<void>.delayed(Duration.zero);
            expect(snapshot, isNull, reason: '已登记的写入尚未完成，不能提前导出');
            sessions.release.complete();
          });
          for (var i = 0; i < 100 && snapshot == null; i++) {
            await tester.pump();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          }
          await tester.runAsync(() => restoring!);
          expect(snapshot, isNotNull);
          final savedSession =
              (snapshot!['mathSessions'] as List).single as Map;
          final stats = (snapshot!['userStats'] as List).single as Map;
          expect(savedSession['isComplete'], completed);
          expect(savedSession['starsEarned'], completed ? 3 : 0);
          expect(stats['totalStars'], completed ? 3 : 0);
          expect(stats['mathTotalProblems'], 1);
          if (completed) {
            final activity =
                (snapshot!['learningActivities'] as List).single as Map;
            final checkIn = (snapshot!['checkIns'] as List).single as Map;
            expect(activity['starsEarned'], 3);
            expect(checkIn['starsEarned'], 3);
            expect(
              PracticeDraftRepository().get(word ? 'word' : 'math'),
              isNull,
            );
          } else {
            expect(snapshot!['learningActivities'], isEmpty);
            expect(snapshot!['checkIns'], isEmpty);
          }
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          await drainHiveWritesForTesting(tester);
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
