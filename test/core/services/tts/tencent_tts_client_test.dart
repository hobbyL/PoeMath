// test/core/services/tts/tencent_tts_client_test.dart
//
// 腾讯云语音合成客户端测试：请求体、签名头、音频解析与错误映射。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tts/tencent_tts_client.dart';
import 'package:poemath/core/services/tts/tts_models.dart';

const credentials = TencentAsrCredentials(
  secretId: 'AKIDEXAMPLE',
  secretKey: 'SECRETKEYEXAMPLE',
);

http.Response errorResponse(String code, {int statusCode = 400}) {
  return http.Response(
    jsonEncode(<String, Object>{
      'Response': <String, Object>{
        'Error': <String, Object>{'Code': code, 'Message': 'server details'},
        'RequestId': 'request-id',
      },
    }),
    statusCode,
  );
}

void main() {
  test('发送 TextToVoice 请求并返回解码音频字节', () async {
    final audio = Uint8List.fromList(List<int>.filled(64, 7));
    late http.Request capturedRequest;
    final httpClient = MockClient((request) async {
      capturedRequest = request;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, Object>{
            'Response': <String, Object>{
              'Audio': base64Encode(audio),
              'SessionId': 'session-id',
              'RequestId': 'request-id',
            },
          }),
        ),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final client = TencentTtsClient(
      httpClient: httpClient,
      clock: () => DateTime.utc(2024),
    );

    final result = await client.synthesize(
      text: '床前明月光',
      credentials: credentials,
      voiceType: 101001,
      speed: 1.0,
    );

    expect(result, orderedEquals(audio));
    expect(capturedRequest.method, 'POST');
    expect(
      capturedRequest.url.host,
      'tts.tencentcloudapi.com',
    );
    expect(capturedRequest.headers['x-tc-action'], 'TextToVoice');
    expect(capturedRequest.headers['x-tc-version'], '2019-08-23');
    expect(capturedRequest.headers['x-tc-timestamp'], '1704067200');
    expect(
      capturedRequest.headers['content-type'],
      'application/json; charset=utf-8',
    );
    final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    expect(body['Text'], '床前明月光');
    expect(body['VoiceType'], 101001);
    expect(body['Speed'], 1.0);
    expect(body['Codec'], 'mp3');
    expect(body['Volume'], 0);
    expect(body['SessionId'], isNotEmpty);
    expect(capturedRequest.body, isNot(contains(credentials.secretId)));
    expect(capturedRequest.body, isNot(contains(credentials.secretKey)));
  });

  test('凭据不完整时抛出鉴权异常且不发请求', () async {
    var requested = false;
    final client = TencentTtsClient(
      httpClient: MockClient((_) async {
        requested = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      client.synthesize(
        text: '床前明月光',
        credentials: const TencentAsrCredentials(
          secretId: 'AKIDEXAMPLE',
          secretKey: '',
        ),
        voiceType: 101001,
      ),
      throwsA(
        isA<TencentTtsException>().having(
          (error) => error.kind,
          'kind',
          TencentTtsErrorKind.authentication,
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test('超过 150 个汉字在本地拦截且不发请求', () async {
    var requested = false;
    final client = TencentTtsClient(
      httpClient: MockClient((_) async {
        requested = true;
        return http.Response('{}', 200);
      }),
    );
    final longText = '床' * 151;

    await expectLater(
      client.synthesize(
        text: longText,
        credentials: credentials,
        voiceType: 101001,
      ),
      throwsA(
        isA<TencentTtsException>().having(
          (error) => error.kind,
          'kind',
          TencentTtsErrorKind.request,
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test('英文按 500 字母加权，超过上限在本地拦截', () async {
    final client = TencentTtsClient(
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );

    await expectLater(
      client.synthesize(
        text: 'a' * 501,
        credentials: credentials,
        voiceType: 101001,
      ),
      throwsA(
        isA<TencentTtsException>().having(
          (error) => error.kind,
          'kind',
          TencentTtsErrorKind.request,
        ),
      ),
    );
  });

  test('空文本视为请求错误', () async {
    final client = TencentTtsClient(
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );

    await expectLater(
      client.synthesize(
        text: '   ',
        credentials: credentials,
        voiceType: 101001,
      ),
      throwsA(
        isA<TencentTtsException>().having(
          (error) => error.kind,
          'kind',
          TencentTtsErrorKind.request,
        ),
      ),
    );
  });

  test('服务未开通映射为 serviceNotEnabled', () async {
    final client = TencentTtsClient(
      httpClient: MockClient(
        (_) async => errorResponse('UnsupportedOperation.ServerNotOpen'),
      ),
    );

    await expectLater(
      client.synthesize(
        text: '床前明月光',
        credentials: credentials,
        voiceType: 101001,
      ),
      throwsA(
        isA<TencentTtsException>()
            .having(
              (error) => error.kind,
              'kind',
              TencentTtsErrorKind.serviceNotEnabled,
            )
            .having(
              (error) => error.message,
              'message',
              contains('开通语音合成'),
            ),
      ),
    );
  });

  test('额度耗尽与欠费映射为 quota', () async {
    for (final code in [
      'UnsupportedOperation.NoFreeAccount',
      'UnsupportedOperation.PkgExhausted',
      'UnsupportedOperation.AccountArrears',
    ]) {
      final client = TencentTtsClient(
        httpClient: MockClient((_) async => errorResponse(code)),
      );

      await expectLater(
        client.synthesize(
          text: '床前明月光',
          credentials: credentials,
          voiceType: 101001,
        ),
        throwsA(
          isA<TencentTtsException>().having(
            (error) => error.kind,
            'kind',
            TencentTtsErrorKind.quota,
          ),
        ),
      );
    }
  });

  test('鉴权失败映射为 authentication 且不暴露密钥', () async {
    final client = TencentTtsClient(
      httpClient: MockClient(
        (_) async => errorResponse('AuthFailure.SignatureFailure'),
      ),
    );

    await expectLater(
      client.synthesize(
        text: '床前明月光',
        credentials: credentials,
        voiceType: 101001,
      ),
      throwsA(
        isA<TencentTtsException>()
            .having(
              (error) => error.kind,
              'kind',
              TencentTtsErrorKind.authentication,
            )
            .having(
              (error) => error.toString(),
              'redacted message',
              allOf(
                isNot(contains(credentials.secretId)),
                isNot(contains(credentials.secretKey)),
              ),
            ),
      ),
    );
  });

  test('网络异常映射为 network', () async {
    final client = TencentTtsClient(
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
    );

    await expectLater(
      client.synthesize(
        text: '床前明月光',
        credentials: credentials,
        voiceType: 101001,
      ),
      throwsA(
        isA<TencentTtsException>().having(
          (error) => error.kind,
          'kind',
          TencentTtsErrorKind.network,
        ),
      ),
    );
  });

  test('非 JSON 响应与空音频映射为 response', () async {
    final malformed = TencentTtsClient(
      httpClient: MockClient((_) async => http.Response('not json', 200)),
    );
    await expectLater(
      malformed.synthesize(
        text: '床前明月光',
        credentials: credentials,
        voiceType: 101001,
      ),
      throwsA(
        isA<TencentTtsException>().having(
          (error) => error.kind,
          'kind',
          TencentTtsErrorKind.response,
        ),
      ),
    );

    final emptyAudio = TencentTtsClient(
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode('{"Response":{"Audio":"","RequestId":"id"}}'),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await expectLater(
      emptyAudio.synthesize(
        text: '床前明月光',
        credentials: credentials,
        voiceType: 101001,
      ),
      throwsA(
        isA<TencentTtsException>().having(
          (error) => error.kind,
          'kind',
          TencentTtsErrorKind.response,
        ),
      ),
    );
  });
}
