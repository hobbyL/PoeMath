// test/core/services/tts/worker_tts_client_test.dart
//
// 自建 Worker 语音合成客户端测试：请求体、验证探测、音色解析与错误映射。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';

const _apiKey = 'worker-secret-key-example';
final _base = Uri.parse('https://tts.cloudm.cc');

final _config = WorkerTtsConfig(base: _base, apiKey: _apiKey);

final _audioBytes = Uint8List.fromList(List<int>.filled(32, 9));

http.Response _audioResponse() => http.Response.bytes(
      _audioBytes,
      200,
      headers: const {'content-type': 'audio/mpeg'},
    );

http.Response _jsonError(String message, int statusCode) => http.Response.bytes(
      utf8.encode(jsonEncode(<String, Object>{'error': message})),
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('synthesize 发送正确请求体与认证头并返回 MP3 字节', () async {
    late http.Request captured;
    final client = WorkerTtsClient(
      httpClient: MockClient((request) async {
        captured = request;
        return _audioResponse();
      }),
    );

    final result = await client.synthesize(
      config: _config,
      text: '床前明月光',
      voice: 'zh-CN-XiaoxiaoNeural',
      style: 'poetry-reading',
      rate: '+100',
    );

    expect(result, orderedEquals(_audioBytes));
    expect(captured.method, 'POST');
    expect(captured.url.host, 'tts.cloudm.cc');
    expect(captured.url.path, '/api/v1/tts');
    expect(captured.headers['authorization'], 'Bearer $_apiKey');
    expect(
      captured.headers['content-type'],
      'application/json; charset=utf-8',
    );
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['text'], '床前明月光');
    expect(body['voice'], 'zh-CN-XiaoxiaoNeural');
    expect(body['rate'], '+100');
    expect(body['pitch'], '0');
    expect(body['style'], 'poetry-reading');
    expect(body['format'], kWorkerAudioFormat);
    // API Key 不得出现在请求体中（仅允许出现在认证头）。
    expect(captured.body, isNot(contains(_apiKey)));
  });

  test('401 映射为 authentication 且异常不暴露 API Key', () async {
    final client = WorkerTtsClient(
      httpClient: MockClient((_) async => _jsonError('未授权访问', 401)),
    );

    await expectLater(
      client.synthesize(
        config: _config,
        text: '床前明月光',
        voice: 'zh-CN-XiaoxiaoNeural',
        style: 'poetry-reading',
        rate: '0',
      ),
      throwsA(
        isA<WorkerTtsException>()
            .having(
              (error) => error.kind,
              'kind',
              WorkerTtsErrorKind.authentication,
            )
            .having(
              (error) => error.toString(),
              'redacted toString',
              allOf(isNot(contains(_apiKey)), isNot(contains('worker-secret'))),
            ),
      ),
    );
  });

  test('400 映射为 request 且透传服务端 message', () async {
    final client = WorkerTtsClient(
      httpClient: MockClient(
        (_) async => _jsonError('文本长度超过限制', 400),
      ),
    );

    await expectLater(
      client.synthesize(
        config: _config,
        text: '床前明月光',
        voice: 'zh-CN-XiaoxiaoNeural',
        style: 'poetry-reading',
        rate: '0',
      ),
      throwsA(
        isA<WorkerTtsException>()
            .having(
              (error) => error.kind,
              'kind',
              WorkerTtsErrorKind.request,
            )
            .having((error) => error.message, 'message', '文本长度超过限制'),
      ),
    );
  });

  test('5xx 与非 audio Content-Type 映射为 response', () async {
    final serverError = WorkerTtsClient(
      httpClient: MockClient((_) async => _jsonError('语音合成失败', 500)),
    );
    await expectLater(
      serverError.synthesize(
        config: _config,
        text: '床前明月光',
        voice: 'zh-CN-XiaoxiaoNeural',
        style: 'poetry-reading',
        rate: '0',
      ),
      throwsA(
        isA<WorkerTtsException>().having(
          (error) => error.kind,
          'kind',
          WorkerTtsErrorKind.response,
        ),
      ),
    );

    final wrongType = WorkerTtsClient(
      httpClient: MockClient(
        (_) async => http.Response(
          '{"error":"x"}',
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    await expectLater(
      wrongType.synthesize(
        config: _config,
        text: '床前明月光',
        voice: 'zh-CN-XiaoxiaoNeural',
        style: 'poetry-reading',
        rate: '0',
      ),
      throwsA(
        isA<WorkerTtsException>().having(
          (error) => error.kind,
          'kind',
          WorkerTtsErrorKind.response,
        ),
      ),
    );
  });

  test('网络异常与超时映射为 network', () async {
    final socketError = WorkerTtsClient(
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
    );
    await expectLater(
      socketError.synthesize(
        config: _config,
        text: '床前明月光',
        voice: 'zh-CN-XiaoxiaoNeural',
        style: 'poetry-reading',
        rate: '0',
      ),
      throwsA(
        isA<WorkerTtsException>().having(
          (error) => error.kind,
          'kind',
          WorkerTtsErrorKind.network,
        ),
      ),
    );

    final timeoutClient = WorkerTtsClient(
      httpClient: MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        return _audioResponse();
      }),
      synthesizeTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      timeoutClient.synthesize(
        config: _config,
        text: '床前明月光',
        voice: 'zh-CN-XiaoxiaoNeural',
        style: 'poetry-reading',
        rate: '0',
      ),
      throwsA(
        isA<WorkerTtsException>().having(
          (error) => error.kind,
          'kind',
          WorkerTtsErrorKind.network,
        ),
      ),
    );
  });

  test('verify 短文本真实合成：200 + audio 视为通过', () async {
    late http.Request captured;
    final client = WorkerTtsClient(
      httpClient: MockClient((request) async {
        captured = request;
        return _audioResponse();
      }),
    );

    await client.verify(_config);

    // 验证即一次完整合成：Key 进认证头、短文本 + 完整参数进 body。
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['text'], '你好');
    expect(body['voice'], kDefaultWorkerVoice);
    expect(body['rate'], '0');
    expect(body['pitch'], '0');
    expect(body['style'], 'general');
    expect(body['format'], kWorkerAudioFormat);
    expect(captured.headers['authorization'], 'Bearer $_apiKey');
    expect(captured.body, isNot(contains(_apiKey)));
  });

  test('verify 网络异常映射为 network（沿用 synthesize 分类）', () async {
    final client = WorkerTtsClient(
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
    );

    await expectLater(
      client.verify(_config),
      throwsA(
        isA<WorkerTtsException>().having(
          (error) => error.kind,
          'kind',
          WorkerTtsErrorKind.network,
        ),
      ),
    );
  });

  test('verify 401 映射为 authentication', () async {
    final client = WorkerTtsClient(
      httpClient: MockClient((_) async => _jsonError('无效的 API 密钥', 401)),
    );

    await expectLater(
      client.verify(_config),
      throwsA(
        isA<WorkerTtsException>().having(
          (error) => error.kind,
          'kind',
          WorkerTtsErrorKind.authentication,
        ),
      ),
    );
  });

  test('listVoices 解析音色列表且不携带认证头', () async {
    late http.Request captured;
    final client = WorkerTtsClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(<Object>[
              <String, Object>{
                'short_name': 'zh-CN-XiaoxiaoNeural',
                'local_name': '晓晓',
                'gender': 'Female',
                'locale': 'zh-CN',
                'style_list': <String>['chat', 'poetry-reading'],
              },
              <String, Object>{
                'short_name': 'zh-CN-YunxiNeuralDragonHD',
                'local_name': 'Yunxi DragonHD',
                'gender': 'Male',
                'locale': 'zh-CN',
                'style_list': <String>['narration-relaxed'],
              },
            ]),
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final voices = await client.listVoices(_base);

    expect(voices, hasLength(2));
    expect(captured.url.path, '/api/v1/voices');
    expect(captured.url.queryParameters['locale'], 'zh-CN');
    expect(captured.headers.containsKey('authorization'), isFalse);
    expect(voices[0].shortName, 'zh-CN-XiaoxiaoNeural');
    expect(voices[0].localName, '晓晓');
    expect(voices[0].isDragonHd, isFalse);
    expect(voices[0].styleList, contains('poetry-reading'));
    expect(voices[1].isDragonHd, isTrue);
  });

  test('listVoices 返回空数组与无效条目过滤', () async {
    final empty = WorkerTtsClient(
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
    expect(await empty.listVoices(_base), isEmpty);

    final dirty = WorkerTtsClient(
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode(<Object>[
              <String, Object>{'local_name': 'no short name'},
              <String, Object>{'short_name': ''},
              <String, Object>{'short_name': 'zh-CN-XiaoxiaoNeural'},
            ]),
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final voices = await dirty.listVoices(_base);
    expect(voices, hasLength(1));
    expect(voices[0].shortName, 'zh-CN-XiaoxiaoNeural');
    expect(voices[0].styleList, isEmpty);
  });

  test('normalizeBaseUrl 补 scheme、去尾斜杠并拦截非法输入', () {
    expect(
      WorkerTtsClient.normalizeBaseUrl('tts.cloudm.cc').toString(),
      'https://tts.cloudm.cc',
    );
    expect(
      WorkerTtsClient.normalizeBaseUrl('https://tts.cloudm.cc/').toString(),
      'https://tts.cloudm.cc',
    );
    expect(
      WorkerTtsClient.normalizeBaseUrl('https://tts.cloudm.cc///').toString(),
      'https://tts.cloudm.cc',
    );
    expect(
      WorkerTtsClient.normalizeBaseUrl('http://192.168.1.5:8787').toString(),
      'http://192.168.1.5:8787',
    );
    expect(
      () => WorkerTtsClient.normalizeBaseUrl(''),
      throwsFormatException,
    );
    expect(
      () => WorkerTtsClient.normalizeBaseUrl('ftp://example.com'),
      throwsFormatException,
    );
    expect(
      () => WorkerTtsClient.normalizeBaseUrl('not a url at all'),
      throwsFormatException,
    );
  });

  test('配置不完整时本地拦截且不发请求', () async {
    var requested = false;
    final client = WorkerTtsClient(
      httpClient: MockClient((_) async {
        requested = true;
        return _audioResponse();
      }),
    );

    await expectLater(
      client.synthesize(
        config: WorkerTtsConfig(base: _base, apiKey: ''),
        text: '床前明月光',
        voice: 'zh-CN-XiaoxiaoNeural',
        style: 'poetry-reading',
        rate: '0',
      ),
      throwsA(
        isA<WorkerTtsException>().having(
          (error) => error.kind,
          'kind',
          WorkerTtsErrorKind.authentication,
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test('空文本本地拦截且不发请求', () async {
    var requested = false;
    final client = WorkerTtsClient(
      httpClient: MockClient((_) async {
        requested = true;
        return _audioResponse();
      }),
    );

    await expectLater(
      client.synthesize(
        config: _config,
        text: '   ',
        voice: 'zh-CN-XiaoxiaoNeural',
        style: 'poetry-reading',
        rate: '0',
      ),
      throwsA(
        isA<WorkerTtsException>().having(
          (error) => error.kind,
          'kind',
          WorkerTtsErrorKind.request,
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test('workerRateFor 精确映射关键语速点', () {
    expect(workerRateFor(0.1), '-50');
    expect(workerRateFor(0.5), '0');
    expect(workerRateFor(1.0), '+100');
    // 分段线性中间值。
    expect(workerRateFor(0.3), '-25');
    expect(workerRateFor(0.75), '+50');
    // 越界收敛。
    expect(workerRateFor(0.0), '-50');
    expect(workerRateFor(1.5), '+100');
  });

  test('bestStyleFor 按优先级匹配并回退 general', () {
    expect(
      bestStyleFor(<String>['chat', 'poetry-reading', 'gentle']),
      'poetry-reading',
    );
    expect(bestStyleFor(<String>['chat', 'gentle']), 'gentle');
    expect(
      bestStyleFor(<String>['narration-professional', 'chat']),
      'narration-professional',
    );
    expect(bestStyleFor(<String>['chat']), 'chat');
    expect(bestStyleFor(<String>['excited']), 'general');
    expect(bestStyleFor(const <String>[]), 'general');
  });

  test('内置精选目录携带预设风格且晓晓为 poetry-reading', () {
    final xiaoxiao = kWorkerFallbackVoices.firstWhere(
      (voice) => voice.shortName == kDefaultWorkerVoice,
    );
    expect(xiaoxiao.bestStyle, 'poetry-reading');
    expect(xiaoxiao.localName, '晓晓');
    expect(kWorkerFallbackVoices, hasLength(5));
  });
}
