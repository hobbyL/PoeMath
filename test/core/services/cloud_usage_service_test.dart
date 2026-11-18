import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/parent_access_test_helper.dart';

void main() {
  test('用量队列等待后复验取消状态，拒绝不占用次数且后续仍可预留', () async {
    final usage = CloudUsageService();
    final first = usage.reserve(CloudUsageKind.asr);
    var active = true;
    final next = usage.reserve(
      CloudUsageKind.asr,
      check: () {
        if (!active) throw StateError('synthetic cancellation');
      },
    );
    final rejection = expectLater(next, throwsStateError);
    active = false;
    await first;
    await rejection;
    expect(usage.used(CloudUsageKind.asr), 1);
    await usage.reserve(CloudUsageKind.asr);
    expect(usage.used(CloudUsageKind.asr), 2);
  });
  setUp(setUpHiveForTesting);
  tearDown(() async {
    lockParentForTesting();
    await tearDownHiveForTesting();
  });

  test('未设置家长PIN不能直改每日额度，普通学习请求仍可预留', () async {
    final usage = CloudUsageService();
    await expectLater(
      usage.setLimit(CloudUsageKind.llm, null),
      throwsA(isA<ParentAccessDenied>()),
    );
    expect(usage.limit(CloudUsageKind.llm), 30);
    await usage.reserve(CloudUsageKind.llm);
    expect(usage.used(CloudUsageKind.llm), 1);
  });

  test('默认每日AI30/识别60/云朗读120/生图10，可暂停或明确设为不限', () async {
    await unlockParentForTesting();
    final usage = CloudUsageService();
    expect(CloudUsageKind.values.map(usage.limit), [30, 60, 120, 10]);
    await usage.setLimit(CloudUsageKind.llm, 0);
    await expectLater(
      usage.reserve(CloudUsageKind.llm),
      throwsA(isA<CloudQuotaExceededException>()),
    );
    await usage.setLimit(CloudUsageKind.llm, null);
    expect(usage.limit(CloudUsageKind.llm), isNull);
    await usage.reserve(CloudUsageKind.llm);
  });

  test('多个实例并发请求也不能超额，拒绝的请求不计数', () async {
    await unlockParentForTesting();
    final first = CloudUsageService();
    final second = CloudUsageService();
    await first.setLimit(CloudUsageKind.llm, 3);
    final accepted = await Future.wait(
      List.generate(20, (index) async {
        try {
          await (index.isEven ? first : second).reserve(CloudUsageKind.llm);
          return true;
        } on CloudQuotaExceededException {
          return false;
        }
      }),
    );
    expect(accepted.where((value) => value), hasLength(3));
    expect(second.used(CloudUsageKind.llm), 3);
  });

  test('额度及用量跨实例保留，备份只迁移额度而保留本机用量', () async {
    await unlockParentForTesting();
    var now = DateTime(2026, 10, 16, 23, 59);
    final usage = CloudUsageService(clock: () => now);
    await usage.setLimit(CloudUsageKind.asr, 1);
    await usage.reserve(CloudUsageKind.asr);
    final backup = BackupService();
    final json = await backup.exportToJson();
    // 家长额度配置可迁移，用量是设备事实，恢复不能降低本机已用量。
    expect(json, contains('cloud_daily_limit'));
    expect(json, isNot(contains('cloud_usage')));
    final legacy = jsonDecode(json) as Map<String, dynamic>;
    legacy['cloudUsage'] = {'cloud_usage:2026-10-16:asr': 0};
    await backup.restoreFromJson(jsonEncode(legacy));
    expect(usage.used(CloudUsageKind.asr), 1);
    await backup.restoreFromJson(json);
    await HiveBoxes.close();
    await HiveBoxes.init();
    final reopened = CloudUsageService(clock: () => now);
    expect(reopened.used(CloudUsageKind.asr), 1);
    expect(reopened.limit(CloudUsageKind.asr), 1);
    await expectLater(
      reopened.reserve(CloudUsageKind.asr),
      throwsA(isA<CloudQuotaExceededException>()),
    );
    now = DateTime(2026, 10, 17);
    expect(usage.used(CloudUsageKind.asr), 0);
    await usage.reserve(CloudUsageKind.asr);
    expect(usage.used(CloudUsageKind.asr), 1);
  });

  test('三类真实客户端的0额度均在HTTP之前拒绝', () async {
    await unlockParentForTesting();
    var sends = 0;
    final httpClient = MockClient((request) async {
      sends++;
      return http.Response('', 500);
    });
    final usage = CloudUsageService();
    for (final kind in CloudUsageKind.values) {
      await usage.setLimit(kind, 0);
    }
    final llm = LlmClient(httpClient: httpClient, usage: usage);
    await expectLater(
      llm.explain(
        config: const LlmConfig(
          baseUrl: 'https://api.example.com',
          apiKey: 'key',
          model: 'm',
        ),
        systemPrompt: '',
        userPrompt: '',
      ),
      throwsA(isA<LlmNetworkError>()),
    );
    await expectLater(
      llm
          .chatStream(
            config: const LlmConfig(
              baseUrl: 'https://api.example.com',
              apiKey: 'key',
              model: 'm',
            ),
            systemPrompt: '学习助手',
            messages: const [],
          )
          .toList(),
      throwsA(isA<LlmNetworkError>()),
    );
    final asr = TencentAsrClient(httpClient: httpClient, usage: usage);
    await expectLater(
      asr.recognizePcm16(
        pcmBytes: Uint8List.fromList([0, 0]),
        credentials: const TencentAsrCredentials(
          secretId: 'id',
          secretKey: 'secret',
        ),
      ),
      throwsA(
        isA<TencentAsrException>().having(
          (e) => e.kind,
          'kind',
          TencentAsrErrorKind.quota,
        ),
      ),
    );
    final tts = WorkerTtsClient(httpClient: httpClient, usage: usage);
    await expectLater(
      tts.verify(
        WorkerTtsConfig(
          base: Uri.parse('https://tts.example.com'),
          apiKey: 'key',
        ),
      ),
      throwsA(isA<CloudQuotaExceededException>()),
    );
    expect(sends, 0);
    expect(CloudUsageKind.values.map(usage.used), everyElement(0));
  });

  const config = LlmConfig(
    baseUrl: 'https://api.example.com',
    apiKey: 'key',
    model: 'm',
  );

  http.Response answer(String text) => http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'choices': [
          {
            'message': {'content': text},
            'finish_reason': 'stop',
          },
        ],
      }),
    ),
    200,
  );

  test('失败不扣次，成功后才达额，连接测试不扣且可在达额后使用', () async {
    await unlockParentForTesting();
    final usage = CloudUsageService();
    await usage.setLimit(CloudUsageKind.llm, 1);
    var sends = 0;
    var fail = true;
    LlmClient client() => LlmClient(
      usage: usage,
      httpClient: MockClient((_) async {
        sends++;
        return fail ? http.Response('', 500) : answer('有效回答');
      }),
    );
    final first = client();
    addTearDown(first.close);
    await expectLater(
      first.explain(config: config, systemPrompt: '', userPrompt: ''),
      throwsA(isA<LlmServerError>()),
    );
    expect(usage.used(CloudUsageKind.llm), 0);
    fail = false;
    final retry = client();
    addTearDown(retry.close);
    expect(
      (await retry.explain(
        config: config,
        systemPrompt: '',
        userPrompt: '',
      )).text,
      '有效回答',
    );
    expect(usage.used(CloudUsageKind.llm), 1);
    await expectLater(
      retry.explain(config: config, systemPrompt: '', userPrompt: ''),
      throwsA(isA<LlmNetworkError>()),
    );
    expect(sends, 2);
    await retry.testConnection(config);
    expect(sends, 3);
    expect(usage.used(CloudUsageKind.llm), 1);
  });

  for (final crossProvider in [false, true]) {
    for (final succeeds in [false, true]) {
      test(
        '${crossProvider ? '跨供应商' : '模型'}重试${succeeds ? '最终成功只扣一次' : '全部失败不扣次'}',
        () async {
          await unlockParentForTesting();
          var sends = 0;
          final usage = CloudUsageService();
          await usage.setLimit(CloudUsageKind.llm, 1);
          final promoted = <String>[];
          final client = LlmClient(
            usage: usage,
            onModelSucceeded: (_, model) async => promoted.add(model),
            httpClient: MockClient((_) async {
              sends++;
              return succeeds && sends == 2
                  ? answer('回退成功')
                  : http.Response('', 500);
            }),
          );
          addTearDown(client.close);
          final result = client.explain(
            config: LlmConfig(
              baseUrl: 'https://example.com',
              apiKey: '',
              model: 'A',
              models: crossProvider ? const ['A'] : const ['A', 'B', 'C'],
              fallbacks: crossProvider
                  ? const [
                      LlmConfig(
                        baseUrl: 'https://other.example',
                        apiKey: 'other',
                        model: 'B',
                      ),
                    ]
                  : const [],
            ),
            systemPrompt: '',
            userPrompt: '',
          );
          if (succeeds) {
            expect((await result).text, '回退成功');
            expect(sends, 2);
            expect(usage.used(CloudUsageKind.llm), 1);
            expect(promoted, ['B']);
          } else {
            await expectLater(result, throwsA(isA<LlmServerError>()));
            expect(sends, crossProvider ? 2 : 3);
            expect(usage.used(CloudUsageKind.llm), 0);
            expect(promoted, isEmpty);
          }
        },
      );
    }
  }

  test('升级后保留旧请求计数但不拿它判断成功次数，成功计数跨重启保留', () async {
    await unlockParentForTesting();
    final usage = CloudUsageService();
    await usage.setLimit(CloudUsageKind.llm, 1);
    final oldKey = 'cloud_usage:${usage.dayKey}:llm';
    await HiveBoxes.meta.put(oldKey, 30);
    expect(usage.used(CloudUsageKind.llm), 0);
    await usage.trackLlmSuccess(() async => '回答');
    expect(HiveBoxes.meta.get(oldKey), 30);
    expect(usage.used(CloudUsageKind.llm), 1);
    await HiveBoxes.close();
    await HiveBoxes.init();
    expect(CloudUsageService().used(CloudUsageKind.llm), 1);
    await expectLater(
      CloudUsageService().trackLlmSuccess(() async => '不应执行'),
      throwsA(isA<CloudQuotaExceededException>()),
    );
  });

  test('嵌套客户端操作和内部流合并一次，工具结果不单独扣次', () async {
    final usage = CloudUsageService();
    await usage.trackLlmSuccess(() async {
      await CloudUsageService().trackLlmSuccess(() async => '工具结果');
      expect(usage.used(CloudUsageKind.llm), 0);
      expect(await usage.trackLlmStream(() => Stream.value('最终回答')).toList(), [
        '最终回答',
      ]);
      return true;
    });
    expect(usage.used(CloudUsageKind.llm), 1);
  });

  test('在途名额不落盘且区分忙碌提示，失败释放名额后可继续请求', () async {
    await unlockParentForTesting();
    final usage = CloudUsageService();
    await usage.setLimit(CloudUsageKind.llm, 1);
    final started = Completer<void>();
    final finish = Completer<void>();
    final first = usage.trackLlmSuccess(() async {
      started.complete();
      await finish.future;
      throw StateError('失败');
    });
    final failure = expectLater(first, throwsStateError);
    await started.future;
    expect(usage.used(CloudUsageKind.llm), 0);
    await expectLater(
      CloudUsageService().trackLlmSuccess(() async => '不应执行'),
      throwsA(
        isA<CloudQuotaExceededException>().having(
          (error) => error.message,
          'message',
          'AI 正在处理中，请稍后重试',
        ),
      ),
    );
    finish.complete();
    await failure;
    await usage.trackLlmSuccess(() async => '成功');
    expect(usage.used(CloudUsageKind.llm), 1);
  });

  test('无效结果与完成前取消不扣，队列仍可接受成功结果', () async {
    final usage = CloudUsageService();
    await usage.trackLlmSuccess(() async => false, isSuccessful: (ok) => ok);
    var active = true;
    await expectLater(
      usage.trackLlmSuccess(
        () async {
          active = false;
        },
        check: () {
          if (!active) throw StateError('已取消');
        },
      ),
      throwsStateError,
    );
    expect(usage.used(CloudUsageKind.llm), 0);
    await usage.trackLlmSuccess(() async => '成功');
    expect(usage.used(CloudUsageKind.llm), 1);
  });

  test('流式提前取消和部分回答后异常不扣，完整结束扣一次', () async {
    final usage = CloudUsageService();
    Stream<String> partial() async* {
      yield '部分回答';
      throw StateError('流中断');
    }

    expect(await usage.trackLlmStream(partial).take(1).toList(), ['部分回答']);
    expect(usage.used(CloudUsageKind.llm), 0);
    await expectLater(usage.trackLlmStream(partial).toList(), throwsStateError);
    expect(usage.used(CloudUsageKind.llm), 0);
    expect(await usage.trackLlmStream(() => Stream.value('完成')).toList(), [
      '完成',
    ]);
    expect(usage.used(CloudUsageKind.llm), 1);
  });

  test('跨午夜按操作开始日计次，新一天可独立使用且清理过期用量', () async {
    await unlockParentForTesting();
    var now = DateTime(2026, 10, 16, 23, 59);
    final usage = CloudUsageService(clock: () => now);
    await usage.setLimit(CloudUsageKind.llm, 1);
    await HiveBoxes.meta.put('cloud_usage:2026-09-01:llm', 10);
    await usage.trackLlmSuccess(() async {
      now = DateTime(2026, 10, 17);
    });
    expect(usage.used(CloudUsageKind.llm), 0);
    expect(usage.usedOn(DateTime(2026, 10, 16), CloudUsageKind.llm), 1);
    expect(HiveBoxes.meta.containsKey('cloud_usage:2026-09-01:llm'), isFalse);
    await usage.trackLlmSuccess(() async => '新一天');
    expect(usage.used(CloudUsageKind.llm), 1);
  });

  for (final explain in [false, true]) {
    for (final ending in ['EOF', 'length', 'content_filter', 'error', 'stop']) {
      test(
        '${explain ? '讲解' : '助手'}流遇到 $ending ${ending == 'stop' ? '正常完成才扣次' : '不扣次数'}',
        () async {
          await unlockParentForTesting();
          final usage = CloudUsageService();
          await usage.setLimit(CloudUsageKind.llm, 1);
          String event(Map<String, Object?> payload) =>
              'data: ${jsonEncode(payload)}\n\n';
          final partial = event({
            'choices': [
              {
                'delta': {'content': '先回答了一部分'},
              },
            ],
          });
          final end = ending == 'EOF'
              ? ''
              : ending == 'error'
              ? event({
                  'error': {'message': 'synthetic error'},
                })
              : event({
                  'choices': [
                    {'delta': <String, Object?>{}, 'finish_reason': ending},
                  ],
                });
          final promoted = <String>[];
          final client = LlmClient(
            usage: usage,
            onModelSucceeded: (_, model) async => promoted.add(model),
            httpClient: MockClient(
              (_) async =>
                  http.Response.bytes(utf8.encode('$partial$end'), 200),
            ),
          );
          addTearDown(client.close);
          final stream = explain
              ? client.explainStream(
                  config: config,
                  systemPrompt: '',
                  userPrompt: '',
                )
              : client.chatStream(
                  config: config,
                  systemPrompt: '',
                  messages: const [],
                );
          if (ending == 'stop') {
            expect(await stream.toList(), ['先回答了一部分']);
            expect(usage.used(CloudUsageKind.llm), 1);
          } else {
            await expectLater(stream.toList(), throwsA(isA<LlmException>()));
            expect(usage.used(CloudUsageKind.llm), 0);
            expect(promoted, isEmpty);
            await usage.trackLlmSuccess(() async => '下次成功');
            expect(usage.used(CloudUsageKind.llm), 1);
          }
        },
      );
    }
  }

  group('recentDaily 历史读取', () {
    // 固定"今天"为 2026-10-17，便于断言日期序列。
    final today = DateTime(2026, 10, 17, 9, 30);
    CloudUsageService svc() => CloudUsageService(clock: () => today);

    String key(DateTime d, CloudUsageKind k) =>
        'cloud_usage:${d.year}-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}:${k.counterKey}';

    test('返回连续 7 天、升序、末项为今天', () async {
      final usage = svc();
      final daily = usage.recentDaily(7);

      expect(daily, hasLength(7));
      expect(daily.last.date, DateTime(2026, 10, 17));
      expect(daily.first.date, DateTime(2026, 10, 11));
      // 连续递增（不能跳日，否则柱状图时间轴错位）。
      for (var i = 1; i < daily.length; i++) {
        expect(
          daily[i].date.difference(daily[i - 1].date).inDays,
          1,
          reason: '第 $i 天与前一天应相邻',
        );
      }
    });

    test('缺失日期补 0，不跳过', () async {
      final usage = svc();
      // 只在"3 天前"写一条，其余日期无记录。
      await HiveBoxes.meta.put(
        key(DateTime(2026, 10, 14), CloudUsageKind.llm),
        5,
      );

      final daily = usage.recentDaily(7);
      expect(daily, hasLength(7), reason: '不能因为缺数据而少返回天数');
      final at14 = daily.firstWhere((d) => d.date == DateTime(2026, 10, 14));
      expect(at14.of(CloudUsageKind.llm), 5);
      expect(at14.of(CloudUsageKind.asr), 0);
      // 相邻日期仍为 0 且位置正确。
      final at15 = daily.firstWhere((d) => d.date == DateTime(2026, 10, 15));
      expect(at15.of(CloudUsageKind.llm), 0);
    });

    test('三类分别读取，互不串位', () async {
      final usage = svc();
      await HiveBoxes.meta.put(key(today, CloudUsageKind.llm), 3);
      await HiveBoxes.meta.put(key(today, CloudUsageKind.asr), 7);
      await HiveBoxes.meta.put(key(today, CloudUsageKind.tts), 11);

      final todayUsage = usage.recentDaily(3).last;
      expect(todayUsage.of(CloudUsageKind.llm), 3);
      expect(todayUsage.of(CloudUsageKind.asr), 7);
      expect(todayUsage.of(CloudUsageKind.tts), 11);
      expect(todayUsage.total, 21);
    });

    test('存量数据为非数字时按 0 处理', () async {
      final usage = svc();
      await HiveBoxes.meta.put(key(today, CloudUsageKind.llm), 'oops');
      expect(usage.recentDaily(1).last.of(CloudUsageKind.llm), 0);
    });

    test('负数存量按 0 处理', () async {
      final usage = svc();
      await HiveBoxes.meta.put(key(today, CloudUsageKind.llm), -3);
      expect(usage.recentDaily(1).last.of(CloudUsageKind.llm), 0);
    });

    test('usedOn 与当日 used 一致', () async {
      final usage = svc();
      await HiveBoxes.meta.put(key(today, CloudUsageKind.tts), 4);
      expect(usage.usedOn(today, CloudUsageKind.tts), 4);
      expect(usage.used(CloudUsageKind.tts), 4);
    });
  });
}
