import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

import '../../helpers/hive_test_helper.dart';

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('默认每日AI30/识别60/云朗读120，可暂停或明确设为不限', () async {
    final usage = CloudUsageService();
    expect(CloudUsageKind.values.map(usage.limit), [30, 60, 120]);
    await usage.setLimit(CloudUsageKind.llm, 0);
    await expectLater(usage.reserve(CloudUsageKind.llm),
        throwsA(isA<CloudQuotaExceededException>()),);
    await usage.setLimit(CloudUsageKind.llm, null);
    expect(usage.limit(CloudUsageKind.llm), isNull);
    await usage.reserve(CloudUsageKind.llm);
  });

  test('多个实例并发请求也不能超额，拒绝的请求不计数', () async {
    final first = CloudUsageService();
    final second = CloudUsageService();
    await first.setLimit(CloudUsageKind.llm, 3);
    final accepted = await Future.wait(List.generate(20, (index) async {
      try {
        await (index.isEven ? first : second).reserve(CloudUsageKind.llm);
        return true;
      } on CloudQuotaExceededException {
        return false;
      }
    }),);
    expect(accepted.where((value) => value), hasLength(3));
    expect(second.used(CloudUsageKind.llm), 3);
  });

  test('额度及用量跨实例保留，跨日重开；额度与用量均随备份迁移', () async {
    var now = DateTime(2026, 10, 16, 23, 59);
    final usage = CloudUsageService(clock: () => now);
    await usage.setLimit(CloudUsageKind.asr, 1);
    await usage.reserve(CloudUsageKind.asr);
    final backup = BackupService();
    final json = await backup.exportToJson();
    // 额度上限与已用计数都随备份走：上限是家长设定，计数按日期分桶
    // （key 自带日期，恢复后当天的桶仍是本机自己的）。
    expect(json, contains('cloud_daily_limit'));
    expect(json, contains('cloud_usage'));
    await backup.restoreFromJson(json);
    await HiveBoxes.close();
    await HiveBoxes.init();
    final reopened = CloudUsageService(clock: () => now);
    expect(reopened.used(CloudUsageKind.asr), 1);
    expect(reopened.limit(CloudUsageKind.asr), 1);
    await expectLater(reopened.reserve(CloudUsageKind.asr),
        throwsA(isA<CloudQuotaExceededException>()),);
    now = DateTime(2026, 10, 17);
    expect(usage.used(CloudUsageKind.asr), 0);
    await usage.reserve(CloudUsageKind.asr);
    expect(usage.used(CloudUsageKind.asr), 1);
  });

  test('三类真实客户端的0额度均在HTTP之前拒绝', () async {
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
        llm.testConnection(const LlmConfig(
            baseUrl: 'https://api.example.com', apiKey: 'key', model: 'm',),),
        throwsA(isA<LlmNetworkError>()),);
    await expectLater(
        llm.chatStream(
            config: const LlmConfig(
                baseUrl: 'https://api.example.com', apiKey: 'key', model: 'm',),
            systemPrompt: '学习助手',
            messages: const [],).toList(),
        throwsA(isA<LlmNetworkError>()),);
    final asr = TencentAsrClient(httpClient: httpClient, usage: usage);
    await expectLater(
        asr.recognizePcm16(
            pcmBytes: Uint8List.fromList([0, 0]),
            credentials: const TencentAsrCredentials(
                secretId: 'id', secretKey: 'secret',),),
        throwsA(isA<TencentAsrException>()
            .having((e) => e.kind, 'kind', TencentAsrErrorKind.quota),),);
    final tts = WorkerTtsClient(httpClient: httpClient, usage: usage);
    await expectLater(
        tts.verify(WorkerTtsConfig(
            base: Uri.parse('https://tts.example.com'), apiKey: 'key',),),
        throwsA(isA<CloudQuotaExceededException>()),);
    expect(sends, 0);
    expect(CloudUsageKind.values.map(usage.used), everyElement(0));
  });

  test('发送后失败仍计数，再次请求达额不发网', () async {
    var sends = 0;
    final usage = CloudUsageService();
    await usage.setLimit(CloudUsageKind.llm, 1);
    final llm = LlmClient(
        usage: usage,
        httpClient: MockClient((request) async {
          sends++;
          return http.Response('', 500);
        }),);
    const config = LlmConfig(
        baseUrl: 'https://api.example.com', apiKey: 'key', model: 'm',);
    await expectLater(
        llm.testConnection(config), throwsA(isA<LlmServerError>()),);
    await expectLater(
        llm.testConnection(config), throwsA(isA<LlmNetworkError>()),);
    expect(sends, 1);
    expect(HiveBoxes.meta.get('cloud_usage:${usage.dayKey}:llm'), 1);
  });

  group('recentDaily 历史读取', () {
    // 固定"今天"为 2026-10-17，便于断言日期序列。
    final today = DateTime(2026, 10, 17, 9, 30);
    CloudUsageService svc() => CloudUsageService(clock: () => today);

    String key(DateTime d, CloudUsageKind k) =>
        'cloud_usage:${d.year}-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}:${k.key}';

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
      await HiveBoxes.meta.put(key(DateTime(2026, 10, 14), CloudUsageKind.llm), 5);

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
