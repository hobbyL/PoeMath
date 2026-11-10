import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/image_generation_client.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/image_generation_config.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

const secondary = ImageGenerationConfig(
  provider: ImageGenerationProviderConfig(
    name: '备用',
    baseUrl: 'https://b.example.com/v1',
    model: 'b1',
  ),
  apiKey: 'b-key',
  providerId: 'b',
  models: ['b1', 'b2'],
);
const config = ImageGenerationConfig(
  provider: ImageGenerationProviderConfig(
    name: '首选',
    baseUrl: 'https://a.example.com/v1',
    model: 'a1',
  ),
  apiKey: 'a-key',
  providerId: 'a',
  models: ['a1', 'a2'],
  fallbacks: [secondary],
);

http.Response imageResponse(Uint8List bytes) => http.Response(
  jsonEncode({
    'data': [
      {'b64_json': base64Encode(bytes)},
    ],
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  for (final downloadFailure in [false, true]) {
    test('DNS 失败只跳过不可达厂商，下载域名失败仍可换同厂商模型：$downloadFailure', () async {
      final png = await pictureStoryPng();
      final calls = <String>[];
      final selected = <String>[];
      final client = ImageGenerationClient(
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            expect(request.headers.containsKey('Authorization'), isFalse);
            throw const SocketException("Failed host lookup: 'private-cdn'");
          }
          final model = (jsonDecode(request.body) as Map)['model'] as String;
          calls.add(model);
          if (model == 'a1') {
            if (!downloadFailure) {
              throw const SocketException("Failed host lookup: 'private-host'");
            }
            return http.Response(
              jsonEncode({
                'data': [
                  {'url': 'https://private-cdn/image.png'},
                ],
              }),
              200,
            );
          }
          return imageResponse(png);
        }),
      );
      addTearDown(client.close);
      final bytes = await client.generate(
        config: config,
        prompt: '场景',
        onSuccess: (value) async => selected.add(value.provider.model),
      );
      expect(bytes, png);
      expect(calls, downloadFailure ? ['a1', 'a2'] : ['a1', 'b1']);
      expect(selected, [downloadFailure ? 'a2' : 'b1']);
    });
  }

  test('HTTP 408 和坏图片可跨模型厂商切换，后续题沿用成功候选', () async {
    final png = await pictureStoryPng();
    final calls = <String>[];
    final attempts = <int>[];
    final selected = <String>[];
    final client = ImageGenerationClient(
      httpClient: MockClient((request) async {
        final model = (jsonDecode(request.body) as Map)['model'] as String;
        calls.add(model);
        expect(
          request.headers['Authorization'],
          model.startsWith('a') ? 'Bearer a-key' : 'Bearer b-key',
        );
        if (model == 'a1') return http.Response('', 408);
        if (model == 'a2') return imageResponse(Uint8List.fromList([1, 2, 3]));
        return imageResponse(png);
      }),
    );
    addTearDown(client.close);
    for (var i = 0; i < 2; i++) {
      final bytes = await client.generate(
        config: config,
        prompt: '一个儿童场景',
        onAttempt: attempts.add,
        validate: (bytes) async {
          await PictureStoryImageService.normalizePreview(bytes);
        },
        onSuccess: (value) async {
          selected.add('${value.providerId}/${value.provider.model}');
        },
      );
      expect(bytes, png);
    }
    expect(calls, ['a1', 'a2', 'b1', 'b1']);
    expect(attempts, [1, 2, 3, 1]);
    expect(selected, ['b/b1', 'b/b1']);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 4);
  });

  test('401 跳过同厂商其他模型，每个失败候选只请求一次', () async {
    final calls = <String>[];
    final client = ImageGenerationClient(
      httpClient: MockClient((request) async {
        final model = (jsonDecode(request.body) as Map)['model'] as String;
        calls.add(model);
        return http.Response(
          'private provider body',
          model == 'a1' ? 401 : 503,
        );
      }),
    );
    addTearDown(client.close);
    for (var i = 0; i < 2; i++) {
      await expectLater(
        client.generate(config: config, prompt: '场景'),
        throwsA(isA<ImageGenerationException>()),
      );
    }
    expect(calls, ['a1', 'b1', 'b2']);
  });

  for (final quota in [false, true]) {
    test('${quota ? '首个请求失败后本机额度耗尽' : '暂停'}不继续切换，不误保存成功选择', () async {
      if (quota) await HiveBoxes.settings.put('cloud_daily_limit_image', 1);
      var active = true;
      var requests = 0;
      var saves = 0;
      final client = ImageGenerationClient(
        isActive: () => active,
        httpClient: MockClient((request) async {
          requests++;
          if (!quota) active = false;
          return http.Response('', 503);
        }),
      );
      try {
        await expectLater(
          client.generate(
            config: config,
            prompt: '场景',
            onSuccess: (_) async {
              saves++;
            },
          ),
          throwsA(
            quota
                ? isA<CloudQuotaExceededException>()
                : isA<ImageGenerationCancelled>(),
          ),
        );
        expect(requests, 1);
        expect(saves, 0);
      } finally {
        client.close();
      }
    });
  }

  test('请求超时可切换其他模型；默认设置保存失败不重复生图', () async {
    final png = await pictureStoryPng();
    final calls = <String>[];
    final client = ImageGenerationClient(
      timeout: const Duration(milliseconds: 100),
      httpClient: MockClient((request) async {
        final model = (jsonDecode(request.body) as Map)['model'] as String;
        calls.add(model);
        if (model == 'a1') return Completer<http.Response>().future;
        return imageResponse(png);
      }),
    );
    addTearDown(client.close);
    final bytes = await client.generate(
      config: config,
      prompt: '场景',
      onSuccess: (_) async {
        throw StateError('write failure');
      },
    );
    expect(bytes, png);
    expect(calls, ['a1', 'a2']);
  });
}
