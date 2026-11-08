import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';

import '../../helpers/hive_test_helper.dart';

class _ObservedUsage extends CloudUsageService {
  void Function()? onQueued;

  @override
  Future<void> reserve(CloudUsageKind kind, {void Function()? check}) {
    final reservation = super.reserve(kind, check: check);
    onQueued?.call();
    return reservation;
  }
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('云朗读请求在额度队列中取消不消耗次数', () async {
    final usage = _ObservedUsage();
    var requests = 0;
    final client = WorkerTtsClient(
      usage: usage,
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('', 500);
      }),
    );
    addTearDown(client.close);
    usage.onQueued = client.cancelPending;
    await expectLater(
      client.verify(WorkerTtsConfig(
        base: Uri.parse('https://example.com'),
        apiKey: 'synthetic',
      )),
      throwsA(isA<WorkerTtsException>()),
    );
    expect(requests, 0);
    expect(usage.used(CloudUsageKind.tts), 0);
    usage.onQueued = null;
    await usage.reserve(CloudUsageKind.tts);
    expect(usage.used(CloudUsageKind.tts), 1);
  });

  for (final streaming in [false, true]) {
    test('${streaming ? '流式' : '普通'}请求在额度队列中取消不消耗次数', () async {
      final usage = _ObservedUsage();
      var active = true;
      var requests = 0;
      usage.onQueued = () => active = false;
      final client = LlmClient(
        usage: usage,
        isActive: () => active,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
      );
      addTearDown(client.close);
      const config = LlmConfig(
        baseUrl: 'https://example.com',
        apiKey: 'synthetic',
        model: 'synthetic-model',
      );
      await expectLater(
        streaming
            ? client
                  .chatStream(
                    config: config,
                    systemPrompt: '学习助手',
                    messages: const [],
                  )
                  .toList()
            : client.testConnection(config),
        throwsA(isA<LlmGenerationCancelled>()),
      );
      expect(requests, 0);
      expect(usage.used(CloudUsageKind.llm), 0);

      // 被拒绝的排队请求不能破坏共享额度队列。
      usage.onQueued = null;
      await usage.reserve(CloudUsageKind.llm);
      expect(usage.used(CloudUsageKind.llm), 1);
    });
  }
}
