import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';

void main() {
  const credentials = TencentAsrCredentials(
    secretId: 'AKIDEXAMPLE',
    secretKey: 'SECRETKEYEXAMPLE',
  );

  group('TencentTc3Signer', () {
    test('匹配独立计算的固定签名向量并使用 UTC 日期', () {
      const body = '{"EngSerViceType":"16k_zh"}';
      final result = TencentTc3Signer.sign(
        secretId: credentials.secretId,
        secretKey: credentials.secretKey,
        service: 'asr',
        host: 'asr.tencentcloudapi.com',
        action: 'SentenceRecognition',
        version: '2019-06-14',
        timestamp: 1704067200,
        body: body,
      );

      expect(result.date, '2024-01-01');
      expect(
        result.signature,
        'a18cc4b12db40593b8f21eec701861369450a1c60e52479e405896756b04429a',
      );
      expect(
        result.authorization,
        'TC3-HMAC-SHA256 Credential=AKIDEXAMPLE/'
        '2024-01-01/asr/tc3_request, '
        'SignedHeaders=content-type;host;x-tc-action, '
        'Signature=a18cc4b12db40593b8f21eec701861369450a1c60e52479e405896756b04429a',
      );
      expect(
        result.canonicalRequest,
        contains('x-tc-action:sentencerecognition'),
      );
    });
  });

  group('TencentAsrClient', () {
    test('发送 PCM16 请求并解析非空识别文字', () async {
      late http.Request capturedRequest;
      final httpClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode(<String, Object>{
            'Response': <String, Object>{
              'Result': ' 床前明月光 ',
              'RequestId': 'request-id',
            },
          }),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final client = TencentAsrClient(
        httpClient: httpClient,
        clock: () => DateTime.utc(2024),
      );

      final result = await client.recognizePcm16(
        pcmBytes: Uint8List.fromList(<int>[0, 0, 1, 0]),
        credentials: credentials,
      );

      expect(result, '床前明月光');
      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.headers['x-tc-action'], 'SentenceRecognition');
      expect(capturedRequest.headers['x-tc-version'], '2019-06-14');
      expect(capturedRequest.headers['x-tc-timestamp'], '1704067200');
      expect(
        capturedRequest.headers['content-type'],
        'application/json; charset=utf-8',
      );
      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['EngSerViceType'], '16k_zh');
      expect(body['SourceType'], 1);
      expect(body['VoiceFormat'], 'pcm');
      expect(body['DataLen'], 4);
      expect(body['Data'], base64Encode(<int>[0, 0, 1, 0]));
      expect(capturedRequest.body, isNot(contains(credentials.secretId)));
      expect(capturedRequest.body, isNot(contains(credentials.secretKey)));
    });

    test('映射腾讯鉴权错误且不暴露密钥', () async {
      final client = TencentAsrClient(
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode(<String, Object>{
              'Response': <String, Object>{
                'Error': <String, Object>{
                  'Code': 'AuthFailure.SignatureFailure',
                  'Message': 'server details',
                },
                'RequestId': 'request-id',
              },
            }),
            400,
          );
        }),
      );

      await expectLater(
        client.recognizePcm16(
          pcmBytes: Uint8List.fromList(<int>[0, 0]),
          credentials: credentials,
        ),
        throwsA(
          isA<TencentAsrException>()
              .having(
                (error) => error.kind,
                'kind',
                TencentAsrErrorKind.authentication,
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

    test('空识别文字视为失败', () async {
      final client = TencentAsrClient(
        httpClient: MockClient((_) async {
          return http.Response(
            '{"Response":{"Result":"","RequestId":"id"}}',
            200,
          );
        }),
      );

      await expectLater(
        client.recognizePcm16(
          pcmBytes: Uint8List.fromList(<int>[0, 0]),
          credentials: credentials,
        ),
        throwsA(
          isA<TencentAsrException>().having(
            (error) => error.kind,
            'kind',
            TencentAsrErrorKind.response,
          ),
        ),
      );
    });

    test('错误码类型异常时仍映射为安全的响应错误', () async {
      final client = TencentAsrClient(
        httpClient: MockClient((_) async {
          return http.Response(
            '{"Response":{"Error":{"Code":123,"Message":"bad"}}}',
            500,
          );
        }),
      );

      await expectLater(
        client.recognizePcm16(
          pcmBytes: Uint8List.fromList(<int>[0, 0]),
          credentials: credentials,
        ),
        throwsA(
          isA<TencentAsrException>().having(
            (error) => error.kind,
            'kind',
            TencentAsrErrorKind.response,
          ),
        ),
      );
    });

    test('请求超时映射为网络错误', () async {
      final client = TencentAsrClient(
        httpClient: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        client.recognizePcm16(
          pcmBytes: Uint8List.fromList(<int>[0, 0]),
          credentials: credentials,
        ),
        throwsA(
          isA<TencentAsrException>().having(
            (error) => error.kind,
            'kind',
            TencentAsrErrorKind.network,
          ),
        ),
      );
    });

    test('拒绝奇数字节和超过 60 秒的 PCM', () async {
      final client = TencentAsrClient(
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      await expectLater(
        client.recognizePcm16(
          pcmBytes: Uint8List.fromList(<int>[0]),
          credentials: credentials,
        ),
        throwsA(isA<TencentAsrException>()),
      );
      await expectLater(
        client.recognizePcm16(
          pcmBytes: Uint8List(TencentAsrClient.maxRawBytes + 2),
          credentials: credentials,
        ),
        throwsA(isA<TencentAsrException>()),
      );
    });
  });
}
