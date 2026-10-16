import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/llm_explain_providers.dart';
import 'package:poemath/core/services/speech/speech_audio_recorder.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/core/services/haptic_service.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/repositories/llm_problem_repository.dart';
import 'package:poemath/features/assistant/assistant_chat_controller.dart';
import 'package:poemath/features/assistant/tools/assistant_tools_provider.dart';
import 'package:poemath/features/math/word_problem/word_problem_validator.dart';
import 'package:poemath/features/math/word_problem/word_problem_practice_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_preview_page.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/data/repositories/learning_activity_repository.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import '../../helpers/hive_test_helper.dart';

class MemoryStore extends SecureCredentialStore {
  final keys = <String, String>{};
  String? workerKey;
  bool failWorkerWrite = false;
  @override
  Future<String?> readLlmApiKeyFor(String id) async => keys[id];
  @override
  Future<void> saveLlmApiKeyFor(String id, String key) async {
    keys[id] = key;
  }

  @override
  Future<TencentAsrCredentials?> readTencentAsrCredentials() async => null;
  @override
  Future<String?> readWorkerTtsApiKey() async => workerKey;
  @override
  Future<void> saveWorkerTtsApiKey(String key) async {
    if (failWorkerWrite) {
      throw StateError('injected secure-store write failure');
    }
    workerKey = key;
  }

  @override
  Future<String?> readLlmApiKey() async => null;
  @override
  Future<void> deleteWorkerTtsApiKey() async {
    workerKey = null;
  }

  @override
  Future<void> deleteLlmApiKeyFor(String id) async {
    keys.remove(id);
  }
}

class AudioRecorder implements SpeechAudioRecorder {
  late StreamController<Uint8List> controller;
  int cancels = 0;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<Stream<Uint8List>> startStream() async {
    controller = StreamController<Uint8List>(
      onCancel: () {
        cancels++;
      },
    );
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    unawaited(controller.close());
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

class AsrSettings extends SettingsRepository {
  @override
  Future<TencentAsrCredentials?> readTencentAsrCredentials() async =>
      const TencentAsrCredentials(
        secretId: 'fake-id',
        secretKey: 'fake-secret',
      );
}

class GatedHaptic extends HapticService {
  GatedHaptic(this.gate) : super(SettingsRepository());
  final Completer<void> gate;
  @override
  Future<void> medium() => gate.future;
  @override
  Future<void> heavy() => gate.future;
}

class GatedProblemRepo extends LlmProblemRepository {
  final gate = Completer<void>();
  @override
  Future<void> addAll(List<LlmProblem> problems) => gate.future;
}

class CloudSettings extends SettingsRepository {
  @override
  bool get ttsCloudEnabled => true;
  @override
  Future<bool> isWorkerTtsVerified() async => true;
  @override
  Future<WorkerTtsConfig?> readWorkerTtsConfig() async => WorkerTtsConfig(
        base: Uri.parse('https://fake.example.com'),
        apiKey: 'fake-key',
      );
}

class CloudPlayer implements CloudAudioPlayer {
  int plays = 0;
  @override
  Future<void> play(Uint8List bytes) async {
    plays++;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

LlmProblem problem(String id, String text) => LlmProblem(
      id: id,
      profileId: 'default',
      questionText: text,
      unit: '个',
      operands: [12, 4],
      operators: ['-'],
      answer: 8,
      explanation: '',
      batchId: 'batch',
      createdAt: DateTime(2026),
      grade: 2,
      semester: '上',
      topic: 'subtraction',
      difficulty: 2,
    );

Widget routed(Widget page, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, __) => page),
            GoRoute(
              path: '/word-problem/library',
              builder: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );

http.Response completion({bool tool = false}) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': tool ? null : 'ok',
              if (tool)
                'tool_calls': [
                  {
                    'id': 'call1',
                    'type': 'function',
                    'function': {
                      'name': 'nonexistent_test_tool',
                      'arguments': '{}',
                    },
                  }
                ],
            },
          }
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('恢复失败后精确删除原本不存在的设置', () async {
    final store = MemoryStore()..failWorkerWrite = true;
    final backup = BackupService(secureStore: store);
    expect(HiveBoxes.settings.containsKey('theme_mode'), isFalse);
    final node =
        jsonDecode(await backup.exportToJson()) as Map<String, dynamic>;
    node['settings'] = {'theme_mode': 'dark'};
    node['credentials'] = await encryptCredentials(
      {kCredKeyWorkerTtsApiKey: 'fake-new-key'},
      'fake-passphrase',
    );
    await expectLater(
      backup.restoreFromJson(
        jsonEncode(node),
        passphrase: 'fake-passphrase',
      ),
      throwsStateError,
    );
    expect(HiveBoxes.settings.containsKey('theme_mode'), isFalse);
  });

  test('多厂商备份包含所有厂商的 Key', () async {
    final store = MemoryStore();
    final settings = SettingsRepository(credentialStore: store);
    for (final id in ['p1', 'p2']) {
      await settings.saveLlmProviderConfig(
        id: id,
        name: id,
        baseUrl: 'https://$id.example.com',
        model: 'fake-model',
        apiKey: 'fake-key-$id',
      );
    }
    final node = jsonDecode(
      await BackupService(secureStore: store)
          .exportToJson(passphrase: 'fake-passphrase'),
    ) as Map<String, dynamic>;
    final payload = await decryptCredentials(
      node['credentials'] as Map<String, dynamic>,
      'fake-passphrase',
    );
    expect(payload[kCredKeyLlmApiKey], 'fake-key-p1');
    expect(
      jsonDecode(payload[kCredKeyLlmProviderKeys]!),
      {'p1': 'fake-key-p1', 'p2': 'fake-key-p2'},
    );
    store.keys.clear();
    await HiveBoxes.settings.clear();
    await BackupService(secureStore: store)
        .restoreFromJson(jsonEncode(node), passphrase: 'fake-passphrase');
    expect(store.keys, {'p1': 'fake-key-p1', 'p2': 'fake-key-p2'});
    expect(
      jsonDecode((node['settings'] as Map)['llm_providers'] as String),
      hasLength(2),
    );
  });

  test('清除上下文后工具调用保留完整展示历史', () async {
    final store = MemoryStore();
    await SettingsRepository(credentialStore: store).saveLlmProviderConfig(
      id: 'p1',
      name: 'test',
      baseUrl: 'https://fake.example.com',
      model: 'test',
      apiKey: 'fake-key',
    );
    var rounds = 0;
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map;
      if (body['stream'] == true) {
        return http.Response(
          'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': 'new-answer'},
                  }
                ],
              })}\n\ndata: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      return completion(tool: rounds++ == 0);
    });
    final container = ProviderContainer(
      overrides: [
        secureCredentialStoreProvider.overrideWithValue(store),
        llmExplainHttpClientProvider.overrideWithValue(client),
        assistantToolsProvider.overrideWithValue([]),
      ],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(assistantChatControllerProvider.notifier);
    ctrl.loadConversation(const [
      ChatMessage(role: ChatRole.user, content: 'old-question'),
      ChatMessage(role: ChatRole.assistant, content: 'old-answer'),
    ]);
    expect(ctrl.clearContext(), isTrue);
    await ctrl.send('new-question');
    final state = container.read(assistantChatControllerProvider);
    expect(
      state.messages.map((m) => m.content),
      containsAllInOrder(['old-question', 'old-answer', 'new-question']),
    );
    expect(state.contextBaseIndex, 2);
    expect(state.messages.first.content, 'old-question');
  });

  test('重新载入时恢复独立的上下文切点', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(assistantChatControllerProvider.notifier);
    ctrl.loadConversation(
      const [ChatMessage(role: ChatRole.user, content: 'old')],
    );
    ctrl.clearContext();
    final history = container.read(assistantChatControllerProvider).messages;
    ctrl.loadConversation(history, contextBaseIndex: 1);
    expect(container.read(assistantChatControllerProvider).contextBaseIndex, 1);
  });

  test('加法骨架拒绝减法题意和错误讲解', () {
    final error = WordProblemValidator.validate(
      draft: const LlmWordProblemDraft(
        index: 1,
        text: '小明有5个苹果，小红有3个苹果，小明比小红多几个苹果？',
        unit: '个',
        explanation: '5减去3等于8',
      ),
      skeleton: const ProblemSkeleton(
        operands: [5, 3],
        operators: [Operator.add],
        answer: 8,
        unitHint: '个',
        difficulty: 1,
      ),
    );
    expect(error, isNotNull);
  });

  test('ASR 旧 stop 完成不能取消新一轮录音订阅', () async {
    final response = Completer<http.Response>();
    final entered = Completer<void>();
    final recorder = AudioRecorder();
    final client = MockClient((req) async {
      entered.complete();
      return response.future;
    });
    final service = TencentSpeechRecognitionService(
      recorder: recorder,
      tencentClient: TencentAsrClient(httpClient: client),
      settingsRepository: AsrSettings(),
    );
    await service.start();
    recorder.controller.add(Uint8List(320));
    final oldStop =
        expectLater(service.stop(), throwsA(isA<SpeechRecognitionException>()));
    await entered.future;
    await service.cancel();
    await service.start();
    final newStream = recorder.controller;
    expect(newStream.hasListener, isTrue);
    response.complete(
      http.Response(
        jsonEncode({
          'Response': {'Result': 'old-result'},
        }),
        200,
      ),
    );
    await oldStop;
    expect(service.isRecording, isTrue);
    expect(newStream.hasListener, isTrue);
    await service.cancel();
    await newStream.close();
  });

  testWidgets('触觉挂起时禁止推进，作答记录仍属于原题', (tester) async {
    final gate = Completer<void>();
    final p1 = problem('p1', 'first-question');
    final p2 = problem('p2', 'second-question');
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.llmProblems.put('default_p1', p1);
      await HiveBoxes.llmProblems.put('default_p2', p2);
    });
    await tester.pumpWidget(
      routed(
        WordProblemPracticePage(problems: [p1, p2]),
        overrides: [
          hapticServiceProvider.overrideWithValue(GatedHaptic(gate)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('8').last);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check_rounded));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('下一题'));
    await tester.pump();
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(HiveBoxes.llmProblems.get('default_p1')!.attempts, 1);
    expect(HiveBoxes.llmProblems.get('default_p2')!.attempts, 0);
    final session = HiveBoxes.mathSessions.values.single;
    expect(session.totalProblems, 1);
    expect(jsonDecode(session.problemsJson!).single['q'], 'first-question');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('应用题入库中离页，完成后不访问已销毁 ref', (tester) async {
    final repo = GatedProblemRepo();
    final data = const WordProblemPreviewData(
      grade: 2,
      semester: '上',
      topicName: 'subtraction',
      items: [
        WordProblemPreviewItem(
          skeleton: ProblemSkeleton(
            operands: [12, 4],
            operators: [Operator.subtract],
            answer: 8,
            unitHint: '个',
            difficulty: 2,
          ),
          draft: LlmWordProblemDraft(
            index: 1,
            text: '小明有12个苹果，吃了4个，还剩几个？',
            unit: '个',
            explanation: '',
          ),
          rejectReason: null,
        ),
      ],
    );
    await tester.pumpWidget(
      routed(
        WordProblemPreviewPage(data: data),
        overrides: [
          llmProblemRepositoryProvider.overrideWithValue(repo),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final errors = <Object>[];
    await runZonedGuarded(
      () async {
        await tester.tap(find.text('确认入库 1 题'));
      },
      (e, s) {
        errors.add(e);
      },
    );
    await tester.pumpWidget(const SizedBox.shrink());
    repo.gate.complete();
    await tester.pump();
    expect(errors, isEmpty);
  });

  test('停止后丢弃晚到的云端试听合成', () async {
    final gate = Completer<http.Response>();
    final entered = Completer<void>();
    final client = MockClient((req) async {
      entered.complete();
      return gate.future;
    });
    final player = CloudPlayer();
    final tts = TtsService(
      CloudSettings(),
      cloudClient: WorkerTtsClient(httpClient: client),
      cloudPlayer: player,
    );
    final preview = tts.previewCloud('test');
    await entered.future;
    await tts.stop();
    gate.complete(
      http.Response.bytes(
        [1, 2, 3, 4],
        200,
        headers: {'content-type': 'audio/mpeg'},
      ),
    );
    await preview;
    expect(player.plays, 0);
    tts.dispose();
  });

  testWidgets('应用题连续完成两轮，使用不同 ID 且均结算成功', (tester) async {
    final gate = Completer<void>()..complete();
    final p = problem('p1', 'one-question');
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.llmProblems.put('default_p1', p);
    });
    await tester.pumpWidget(
      routed(
        WordProblemPracticePage(problems: [p]),
        overrides: [
          hapticServiceProvider.overrideWithValue(GatedHaptic(gate)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final errors = <Object>[];
    Future<void> answerAndFinish({bool capture = false}) async {
      await tester.tap(find.text('8').last);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.check_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        if (capture) {
          await runZonedGuarded(
            () async {
              await tester.tap(find.text('查看成绩'));
            },
            (e, s) {
              errors.add(e);
            },
          );
        } else {
          await tester.tap(find.text('查看成绩'));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    }

    await answerAndFinish();
    final firstId = HiveBoxes.mathSessions.values.single.id;
    expect(find.text('再练一组'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('再练一组'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await answerAndFinish(capture: true);
    expect(HiveBoxes.mathSessions.length, 2);
    expect(
      HiveBoxes.mathSessions.values.map((s) => s.id).toSet(),
      hasLength(2),
    );
    expect(HiveBoxes.mathSessions.values.map((s) => s.id), contains(firstId));
    expect(errors, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('同轮活动重放幂等，异 payload 仍拒绝', () async {
    final repo = LearningActivityRepository();
    Future<bool> record(DateTime time) => repo.record(
          id: 'retry-id',
          activityType: LearningActivityType.mathPractice,
          totalItems: 1,
          successfulItems: 1,
          starsEarned: 1,
          durationSeconds: 1,
          completedAt: time,
        );
    await record(DateTime(2026));
    expect(await record(DateTime(2026)), isFalse);
    await expectLater(
      record(DateTime(2026).add(const Duration(seconds: 1))),
      throwsStateError,
    );
  });

  test('备份拒绝越界题量，读取回退安全默认', () async {
    final backup = BackupService(secureStore: MemoryStore());
    final data =
        jsonDecode(await backup.exportToJson()) as Map<String, dynamic>;
    data['settings'] = {'math_batch_size': -1};
    await backup.restoreFromJson(jsonEncode(data));
    final size = SettingsRepository().mathBatchSize;
    expect(size, 10);
    expect(
      MathEngine.generateBatch(grade: 1, semester: '上', count: size),
      hasLength(10),
    );
  });
}
