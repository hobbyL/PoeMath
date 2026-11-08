import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_realtime_asr_client.dart';

import '../../../helpers/tencent_realtime_socket.dart';

const _credentials = TencentAsrCredentials(
  secretId: 'synthetic-id',
  secretKey: 'synthetic-key',
  appId: '123456',
);

class _MalformedHandshake extends TestTencentRealtimeSocket {
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = incoming.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    incoming.add('{"code":"invalid","voice_id":"synthetic"}');
    return subscription;
  }
}

void main() {
  test('连接超时后晚到的 WebSocket 必须关闭', () async {
    final connected = Completer<WebSocket>();
    final socket = TestTencentRealtimeSocket();
    final client = TencentRealtimeAsrClient(
      timeout: const Duration(milliseconds: 10),
      connectSocket: (_) => connected.future,
    );
    addTearDown(client.close);
    await expectLater(
      client.connect(credentials: _credentials),
      throwsA(
        isA<TencentRealtimeAsrException>().having(
          (error) => error.kind,
          'kind',
          TencentRealtimeErrorKind.network,
        ),
      ),
    );
    connected.complete(socket);
    await Future<void>.delayed(Duration.zero);
    expect(socket.closed, isTrue);
    if (!socket.closed) await socket.close();
  });

  test('畸形握手转成响应错误并关闭连接，不泄漏异步类型异常', () async {
    final socket = _MalformedHandshake();
    final client = TencentRealtimeAsrClient(
      timeout: const Duration(milliseconds: 30),
      connectSocket: (_) async => socket,
    );
    addTearDown(client.close);
    await expectLater(
      client.connect(credentials: _credentials),
      throwsA(
        isA<TencentRealtimeAsrException>().having(
          (error) => error.kind,
          'kind',
          TencentRealtimeErrorKind.response,
        ),
      ),
    );
    expect(socket.closed, isTrue);
  });

  test('中途断开不能把尚未收到 final 的部分转写当作完整结果', () async {
    final socket = TestTencentRealtimeSocket()..holdResult = true;
    final client = TencentRealtimeAsrClient(connectSocket: (_) async => socket);
    addTearDown(client.close);
    final session = await client.connect(credentials: _credentials);
    socket.receiveText('未完成的转写');
    final ending = expectLater(
      session.end(),
      throwsA(
        isA<TencentRealtimeAsrException>().having(
          (error) => error.kind,
          'kind',
          TencentRealtimeErrorKind.network,
        ),
      ),
    );
    await socket.endSent.future;
    await socket.incoming.close();
    await ending;
    expect(socket.closed, isTrue);
  });

  test('畸形结果字段不逃出流回调，也不返回伪造的成功转写', () async {
    final socket = TestTencentRealtimeSocket()..holdResult = true;
    final client = TencentRealtimeAsrClient(connectSocket: (_) async => socket);
    addTearDown(client.close);
    final session = await client.connect(credentials: _credentials);
    final ending = expectLater(
      session.end(),
      throwsA(
        isA<TencentRealtimeAsrException>().having(
          (error) => error.kind,
          'kind',
          TencentRealtimeErrorKind.response,
        ),
      ),
    );
    await socket.endSent.future;
    socket.incoming.add(
      jsonEncode({
        'code': 0,
        'result': {
          'index': 'invalid',
          'voice_text_str': '错误结果',
          'slice_type': 2,
        },
        'final': 1,
      }),
    );
    await socket.incoming.close();
    await ending;
    expect(socket.closed, isTrue);
  });
}
