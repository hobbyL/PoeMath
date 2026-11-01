import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/image_generation_client.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/image_generation_config.dart';

import '../../helpers/hive_test_helper.dart';

const _provider = ImageGenerationProviderConfig(
  name: '测试生图',
  baseUrl: 'https://image.example.com/v1',
  model: 'image-model',
);
const _config =
    ImageGenerationConfig(provider: _provider, apiKey: 'private-image-key');

class _WaitingUsage extends CloudUsageService {
  final reached = Completer<void>();
  final proceed = Completer<void>();
  @override
  Future<void> reserve(CloudUsageKind kind, {void Function()? check}) async {
    reached.complete();
    await proceed.future;
    await super.reserve(kind, check: check);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  test('配置接受基础地址和完整端点，拒绝不安全地址，序列化不携带未知密钥', () {
    for (final base in [
      'image.example.com',
      'https://image.example.com/v1/',
      'https://image.example.com/v1/images/generations/',
    ]) {
      expect(
        ImageGenerationProviderConfig(name: '', baseUrl: base, model: 'img')
            .endpoint
            .toString(),
        'https://image.example.com/v1/images/generations',
      );
    }
    for (final base in [
      'http://image.example.com',
      'https://secret@image.example.com/v1',
      'https://image.example.com/v1?api_key=secret',
      'https://image.example.com/v1#secret',
    ]) {
      expect(
        () => ImageGenerationProviderConfig(
          name: '',
          baseUrl: base,
          model: 'img',
        ).normalized(),
        throwsFormatException,
      );
    }
    final restored = ImageGenerationProviderConfig.fromJson(
      {..._provider.toJson(), 'apiKey': 'must-not-travel'},
    );
    expect(restored.encode(), isNot(contains('must-not-travel')));
    expect(restored.toJson().keys, ['name', 'baseUrl', 'model']);
    expect(_config.toString(), isNot(contains(_config.apiKey)));
  });

  test('每次只请求一张；兼容 GPT Image 默认 Base64，实际请求才计入生图额度', () async {
    final source = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
    var sends = 0;
    final client = ImageGenerationClient(
      httpClient: MockClient((request) async {
        sends++;
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://image.example.com/v1/images/generations',
        );
        expect(request.headers['Authorization'], 'Bearer private-image-key');
        expect(request.followRedirects, isFalse);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {
          'model': 'image-model',
          'prompt': '画面描述',
          'n': 1,
          'size': '1024x1024',
        });
        expect(body, isNot(contains('response_format')));
        return http.Response(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode(source)},
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);
    expect(await client.generate(config: _config, prompt: '画面描述'), source);
    expect(sends, 1);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 1);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 0);
  });

  test('URL 图片下载不带 API Key，下载不会再次增加生图额度', () async {
    final requests = <http.Request>[];
    final client = ImageGenerationClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'url':
                      'https://cdn.example.com/picture.png?signature=private',
                }
              ],
            }),
            200,
          );
        }
        expect(request.url.host, 'cdn.example.com');
        expect(
          request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')),
        );
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );
    addTearDown(client.close);
    expect(await client.generate(config: _config, prompt: '一个场景'), [1, 2, 3]);
    expect(requests.length, 2);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 1);
  });

  test('只有文字和非 HTTPS 图片地址均失败；不自动重试，不泄漏供应商回包中的密钥', () async {
    for (final response in [
      http.Response.bytes(
        utf8.encode(jsonEncode({'message': '稍后为你生成图片'})),
        200,
      ),
      http.Response(
        jsonEncode({
          'data': [
            {'url': 'http://cdn.example.com/image.png'},
          ],
        }),
        200,
      ),
      http.Response(
        'private-image-key https://image.example.com/?key=private-image-key',
        401,
      ),
      http.Response('private-image-key', 429),
    ]) {
      var sends = 0;
      final client = ImageGenerationClient(
        httpClient: MockClient((_) async {
          sends++;
          return response;
        }),
      );
      try {
        await expectLater(
          client.generate(config: _config, prompt: '画面'),
          throwsA(
            isA<ImageGenerationException>().having(
              (e) => e.message,
              'safe message',
              isNot(contains('private-image-key')),
            ),
          ),
        );
        expect(sends, 1);
      } finally {
        client.close();
      }
    }
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 4);
  });

  test('额度为零和请求前取消均不会发出 HTTP', () async {
    var sends = 0;
    final transport = MockClient((_) async {
      sends++;
      return http.Response('{}', 200);
    });
    await HiveBoxes.settings.put('cloud_daily_limit_image', 0);
    final client = ImageGenerationClient(httpClient: transport);
    addTearDown(client.close);
    await expectLater(
      client.generate(config: _config, prompt: '画面'),
      throwsA(isA<CloudQuotaExceededException>()),
    );
    final cancelled =
        ImageGenerationClient(httpClient: transport, isActive: () => false);
    addTearDown(cancelled.close);
    await expectLater(
      cancelled.generate(config: _config, prompt: '画面'),
      throwsA(isA<ImageGenerationCancelled>()),
    );
    expect(sends, 0);
    expect(CloudUsageService.instance.used(CloudUsageKind.imageGeneration), 0);
  });

  test('等待预留额度时授权失效，队列恢复后仍不发出请求', () async {
    final usage = _WaitingUsage();
    var active = true;
    var sends = 0;
    final client = ImageGenerationClient(
      usage: usage,
      isActive: () => active,
      httpClient: MockClient((_) async {
        sends++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    final work = client.generate(config: _config, prompt: '画面');
    final expectation =
        expectLater(work, throwsA(isA<ImageGenerationCancelled>()));
    await usage.reached.future;
    active = false;
    usage.proceed.complete();
    await expectation;
    expect(sends, 0);
    expect(usage.used(CloudUsageKind.imageGeneration), 0);
  });
}
