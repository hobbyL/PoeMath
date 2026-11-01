import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/tencent/tencent_app_id_client.dart';

class _HeldClient extends http.BaseClient {
  final entered = Completer<void>();
  final aborted = Completer<void>();
  final reply = Completer<http.StreamedResponse>();
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    if (requests == 1) {
      entered.complete();
      (request as http.AbortableRequest).abortTrigger!.then((_) {
        if (!aborted.isCompleted) aborted.complete();
      });
      return reply.future;
    }
    return Future.value(
      http.StreamedResponse(
        Stream.value(utf8.encode('{"Response":{"AppId":1250000002}}')),
        200,
      ),
    );
  }
}

void main() {
  const credentials = TencentAsrCredentials(
    secretId: 'AKIDEXAMPLE',
    secretKey: 'SECRETKEYEXAMPLE',
  );

  test('使用 CAM GetUserAppId 固定签名查询 APPID，忽略不同的 UIN', () async {
    late http.Request captured;
    final client = TencentAppIdClient(
      clock: () => DateTime.utc(2024),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"Response":{"Uin":"100000000001","OwnerUin":"100000000002","AppId":1250000000}}',
          200,
        );
      }),
    );
    addTearDown(client.close);
    expect(await client.resolve(credentials: credentials), '1250000000');
    expect(captured.url, Uri.https('cam.tencentcloudapi.com'));
    expect(captured.method, 'POST');
    expect(captured.body, '{}');
    expect(captured.followRedirects, isFalse);
    expect(captured.headers['x-tc-action'], 'GetUserAppId');
    expect(captured.headers['x-tc-version'], '2019-01-16');
    expect(captured.headers['x-tc-timestamp'], '1704067200');
    expect(
      captured.headers['authorization'],
      'TC3-HMAC-SHA256 Credential=AKIDEXAMPLE/2024-01-01/cam/tc3_request, '
      'SignedHeaders=content-type;host;x-tc-action, '
      'Signature=46358ebd6082079a6af27ce13778741c88d351f72a15b235ebdbac7143ea8d51',
    );
  });

  test('同一密钥使用内存缓存，SK 更新后重新查询', () async {
    var requests = 0;
    final client = TencentAppIdClient(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(
          '{"Response":{"AppId":${1250000000 + requests}}}',
          200,
        );
      }),
    );
    addTearDown(client.close);
    expect(await client.resolve(credentials: credentials), '1250000001');
    expect(await client.resolve(credentials: credentials), '1250000001');
    expect(requests, 1);
    expect(
      await client.resolve(
        credentials: const TencentAsrCredentials(
          secretId: 'AKIDEXAMPLE',
          secretKey: 'NEWSECRETKEYEXAMPLE',
        ),
      ),
      '1250000002',
    );
    expect(requests, 2);
  });

  for (final payload in <String>[
    '{"Response":{"Uin":"1250000000"}}',
    '{"Response":{"AppId":0}}',
    '{"Response":{"AppId":-1}}',
    '{"Response":{"AppId":"1250000000"}}',
    '{"Response":{"AppId":1.5}}',
    'not-json',
  ]) {
    test('拒绝无效 APPID 响应 $payload，失败结果不缓存', () async {
      var requests = 0;
      final client = TencentAppIdClient(
        httpClient: MockClient(
          (_) async => http.Response(
            ++requests == 1 ? payload : '{"Response":{"AppId":1250000000}}',
            200,
          ),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.resolve(credentials: credentials),
        throwsA(
          isA<TencentAppIdException>().having(
            (error) => error.kind,
            'kind',
            TencentAppIdErrorKind.response,
          ),
        ),
      );
      expect(await client.resolve(credentials: credentials), '1250000000');
      expect(requests, 2);
    });
  }

  test('鉴权失败保留错误码但不使用服务端包含密钥的文案', () async {
    final client = TencentAppIdClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'Response': {
              'Error': {
                'Code': 'AuthFailure.SignatureFailure',
                'Message': '${credentials.secretId} ${credentials.secretKey}',
              },
            },
          }),
          200,
        ),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.resolve(credentials: credentials),
      throwsA(
        isA<TencentAppIdException>()
            .having(
              (error) => error.kind,
              'kind',
              TencentAppIdErrorKind.authentication,
            )
            .having(
              (error) => error.code,
              'code',
              'AuthFailure.SignatureFailure',
            )
            .having(
              (error) => error.message,
              'message',
              allOf(
                isNot(contains(credentials.secretId)),
                isNot(contains(credentials.secretKey)),
              ),
            ),
      ),
    );
  });

  test('取消查询会中止底层请求，晚到结果不缓存且同一连接池可继续查询', () async {
    final transport = _HeldClient();
    final client = TencentAppIdClient(httpClient: transport);
    addTearDown(client.close);
    final token = SpeechRecognitionCancelToken();
    final failure = expectLater(
      client.resolve(credentials: credentials, cancelToken: token),
      throwsA(isA<SpeechRecognitionCancelled>()),
    );
    await transport.entered.future;
    token.cancel();
    await failure;
    await transport.aborted.future;
    transport.reply.complete(
      http.StreamedResponse(
        Stream.value(utf8.encode('{"Response":{"AppId":1250000001}}')),
        200,
      ),
    );
    expect(await client.resolve(credentials: credentials), '1250000002');
    expect(await client.resolve(credentials: credentials), '1250000002');
    expect(transport.requests, 2);
  });

  test('查询超时报告网络错误', () async {
    final client = TencentAppIdClient(
      timeout: const Duration(milliseconds: 1),
      httpClient: MockClient((_) => Completer<http.Response>().future),
    );
    addTearDown(client.close);
    await expectLater(
      client.resolve(credentials: credentials),
      throwsA(
        isA<TencentAppIdException>().having(
          (error) => error.kind,
          'kind',
          TencentAppIdErrorKind.network,
        ),
      ),
    );
  });
}
