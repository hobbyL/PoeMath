// test/features/poem/poem_read_along_settlement_test.dart
//
// 跟读完成结算回归测试（batch2 R6 / AC6）：
// - 整篇跟读完成后写入一条 readAlong 学习活动（totalItems=句数、
//   successfulItems=达标句数（>=0.6，与音效阈值一致）、poemId、
//   starsEarned、duration）；
// - 今日打卡汇总 addPoems:1 / addStars / addDuration；
// - 星星走 LearningRewardCalculator 的 readAlong 策略（当前明确 0 星）；
// - 「查看结果」连点不双记（activityId 幂等）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/check_in_repository.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/data/repositories/user_stats_repository.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/features/home/providers/home_providers.dart';
import 'package:poemath/features/poem/poem_read_along_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

class _MockTtsService extends Mock implements TtsService {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

final class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  /// stop() 返回的固定识别文本（模拟跟读结果）。
  final String recognizedText;

  _FakeSpeechRecognitionService({required this.recognizedText});

  int startCalls = 0;
  int stopCalls = 0;
  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start() async {
    startCalls++;
    _isRecording = true;
  }

  @override
  Future<SpeechRecognitionResult> stop() async {
    stopCalls++;
    _isRecording = false;
    return SpeechRecognitionResult(text: recognizedText);
  }

  @override
  Future<void> cancel() async {
    _isRecording = false;
  }

  @override
  Future<void> dispose() async {}
}

class _CountingStatsRepository extends UserStatsRepository {
  var starsAdded = 0;

  @override
  UserStats get() => UserStats(profileId: 'test');

  @override
  Future<void> addStars(int count, {String? activityId}) async {
    starsAdded += count;
  }
}

class _CountingCheckInRepository extends CheckInRepository {
  var updateCalls = 0;
  int poemsAdded = 0;
  int starsAdded = 0;
  int durationAdded = 0;

  @override
  Future<void> updateToday({
    String? activityId,
    int? addPoems,
    int? addMathTotal,
    int? addMathCorrect,
    int? addStars,
    int? addDuration,
  }) async {
    updateCalls++;
    poemsAdded += addPoems ?? 0;
    starsAdded += addStars ?? 0;
    durationAdded += addDuration ?? 0;
  }
}

class _CountingActivityRepository extends LearningActivityRepository {
  var recordCalls = 0;
  final List<LearningActivity> recorded = [];

  @override
  Future<bool> record({
    required String id,
    required LearningActivityType activityType,
    required int totalItems,
    required int successfulItems,
    required int starsEarned,
    required int durationSeconds,
    required DateTime completedAt,
    String? poemId,
  }) async {
    recordCalls++;
    recorded.add(
      LearningActivity(
        id: id,
        profileId: 'test',
        activityType: activityType.name,
        totalItems: totalItems,
        successfulItems: successfulItems,
        poemId: poemId,
        starsEarned: starsEarned,
        durationSeconds: durationSeconds,
        completedAt: completedAt,
      ),
    );
    return true;
  }
}

const _poemId = 'read-along-settle-poem';

final _poem = Poem(
  id: _poemId,
  title: '静夜思',
  author: '李白',
  dynasty: '唐',
  content: '床前明月光，\n疑是地上霜。',
  pinyin: '',
  layer: 'core',
);

const _verifiedSettings = SpeechRecognitionSettingsState(
  hasCredentials: true,
  isVerified: true,
);

void main() {
  late _MockTtsService tts;
  late _MockSettingsRepository settings;

  setUp(() {
    tts = _MockTtsService();
    settings = _MockSettingsRepository();
    when(() => tts.stop()).thenAnswer((_) async {});
    when(() => settings.hapticEnabled).thenReturn(false);
    when(() => settings.soundEnabled).thenReturn(false);
    when(() => settings.loadSpeechRecognitionSettings())
        .thenAnswer((_) async => _verifiedSettings);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required SpeechRecognitionService speech,
    required _CountingStatsRepository statsRepo,
    required _CountingCheckInRepository checkInRepo,
    required _CountingActivityRepository activityRepo,
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          ttsServiceProvider.overrideWithValue(tts),
          poemByIdProvider(_poemId).overrideWith((ref) => _poem),
          userStatsRepoProvider.overrideWith((ref) => statsRepo),
          checkInRepoProvider.overrideWith((ref) => checkInRepo),
          learningActivityRepositoryProvider
              .overrideWith((ref) => activityRepo),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              accessibleNavigation: true,
            ),
            child: PoemReadAlongPage(
              poemId: _poemId,
              speechRecognitionService: speech,
            ),
          ),
        ),
      ),
    );
  }

  /// 录一句：点击读一读 → 停止录音 → 等待评分展示。
  Future<void> recordOneLine(WidgetTester tester) async {
    await tester.tap(find.text('读一读'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('录音中'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('整篇完成后结算一条 readAlong 活动 + 打卡汇总，连点不双记', (tester) async {
    // 两句都识别为 '床前明月光'：第一句满分达标、第二句 0 分不达标。
    final speech = _FakeSpeechRecognitionService(recognizedText: '床前明月光');
    final statsRepo = _CountingStatsRepository();
    final checkInRepo = _CountingCheckInRepository();
    final activityRepo = _CountingActivityRepository();

    await pumpPage(
      tester,
      speech: speech,
      statsRepo: statsRepo,
      checkInRepo: checkInRepo,
      activityRepo: activityRepo,
    );
    await tester.pump(const Duration(seconds: 1));

    // 第一句：满分。
    await recordOneLine(tester);
    expect(find.text('100分', skipOffstage: false), findsOneWidget);
    await tester.tap(find.text('下一句'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 第二句：0 分。
    await recordOneLine(tester);
    expect(find.text('0分', skipOffstage: false), findsOneWidget);

    // 「查看结果」连点两次：幂等，只结算一次。
    final done = find.text('查看结果');
    expect(done, findsOneWidget);
    await tester.tap(done);
    await tester.tap(done);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 一条 readAlong 活动记录。
    expect(activityRepo.recordCalls, 1);
    final activity = activityRepo.recorded.single;
    expect(activity.activityType, 'readAlong');
    expect(activity.poemId, _poemId);
    expect(activity.totalItems, 2);
    expect(activity.successfulItems, 1, reason: '达标阈值与音效一致（>=0.6）');
    // readAlong 星级策略当前明确为 0 星（见 learning_reward_calculator）。
    expect(activity.starsEarned, 0);

    // 打卡汇总：+1 首诗、0 星、正时长；星星通道随策略为 0。
    expect(checkInRepo.updateCalls, 1);
    expect(checkInRepo.poemsAdded, 1);
    expect(checkInRepo.starsAdded, 0);
    expect(checkInRepo.durationAdded, greaterThanOrEqualTo(0));
    expect(statsRepo.starsAdded, 0);

    // 完成视图可见。
    expect(find.text('各句得分'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('「再练一次」后重新完成，按新一轮 activityId 再次结算', (tester) async {
    final speech = _FakeSpeechRecognitionService(recognizedText: '床前明月光');
    final statsRepo = _CountingStatsRepository();
    final checkInRepo = _CountingCheckInRepository();
    final activityRepo = _CountingActivityRepository();

    await pumpPage(
      tester,
      speech: speech,
      statsRepo: statsRepo,
      checkInRepo: checkInRepo,
      activityRepo: activityRepo,
    );
    await tester.pump(const Duration(seconds: 1));

    await recordOneLine(tester);
    await tester.tap(find.text('下一句'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await recordOneLine(tester);
    await tester.tap(find.text('查看结果'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(activityRepo.recordCalls, 1);

    // 再练一次 → 重新完成 → 新 activityId，允许第二次结算。
    await tester.tap(find.text('再练一次'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await recordOneLine(tester);
    await tester.tap(find.text('下一句'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await recordOneLine(tester);
    await tester.tap(find.text('查看结果'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(activityRepo.recordCalls, 2);
    expect(activityRepo.recorded.map((a) => a.id).toSet(), hasLength(2));
    expect(checkInRepo.updateCalls, 2);
    expect(checkInRepo.poemsAdded, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
