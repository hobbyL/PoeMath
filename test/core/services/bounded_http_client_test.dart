import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:poemath/core/services/bounded_http_client.dart';
import 'package:poemath/core/services/webdav_service.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/llm/chat_completion.dart';

class _StreamClient extends http.BaseClient {
  _StreamClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

void main() {
  test('WebDAV PROPFIND 正文停滞时返回失败并实际取消', () async {
    var canceled = false;
    var aborted = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        canceled = true;
      },
    );
    final service = WebDavService(
      client: _StreamClient((request) async {
        (request as http.AbortableRequest)
            .abortTrigger!
            .then((_) => aborted = true);
        return http.StreamedResponse(body.stream, 207);
      }),
      timeout: const Duration(milliseconds: 30),
    );
    final config = WebDavConfig(
      id: 'test',
      name: 'test',
      url: 'https://example.invalid',
      username: 'synthetic',
      password: 'synthetic',
      remotePath: '/poemath',
    );
    expect(await service.testConnection(config), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(aborted, isTrue);
    expect(canceled, isTrue);
    service.dispose();
    await body.close();
  });

  test('上下文裁剪按完整轮次保留工具调用与结果，超大当前轮拒绝', () {
    final messages = [
      ChatMessage(role: ChatRole.user, content: '旧' * (256 * 1024)),
      const ChatMessage(role: ChatRole.assistant, content: '旧答复'),
      const ChatMessage(role: ChatRole.user, content: '本轮问题'),
      const ChatMessage(
        role: ChatRole.assistant,
        content: '',
        toolCalls: [
          ToolCall(id: 'tool-1', name: 'getProgress', argumentsJson: '{}'),
        ],
      ),
      const ChatMessage(
        role: ChatRole.tool,
        content: '进度',
        toolCallId: 'tool-1',
      ),
    ];
    expect(LlmClient.boundedChatContext(messages), messages.sublist(2));
    expect(
      () => LlmClient.boundedChatContext([messages.first]),
      throwsA(isA<LlmResponseFormatError>()),
    );
    final longHistory = [
      for (var i = 0; i < 101; i++)
        ChatMessage(role: ChatRole.user, content: '第 $i 轮'),
    ];
    final bounded = LlmClient.boundedChatContext(longHistory);
    expect(bounded.length, 100);
    expect(bounded.first.content, '第 1 轮');
  });

  test('响应头已到但正文停滞时总超时取消底层请求和订阅', () async {
    var canceled = false;
    var aborted = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        canceled = true;
      },
    );
    final client = BoundedHttpClient(
      _StreamClient((request) async {
        (request as http.AbortableRequest)
            .abortTrigger!
            .then((_) => aborted = true);
        return http.StreamedResponse(body.stream, 207);
      }),
      timeout: const Duration(milliseconds: 30),
    );
    await expectLater(
      client.get(Uri.https('example.invalid')),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(aborted, isTrue);
    expect(canceled, isTrue);
    await body.close();
  });

  test('无或虚假 Content-Length 时按实际字节拒绝超限', () async {
    for (final length in [null, 1]) {
      final client = BoundedHttpClient(
        _StreamClient(
          (_) async => http.StreamedResponse(
            Stream.fromIterable([
              [1, 2],
              [3, 4],
            ]),
            200,
            contentLength: length,
          ),
        ),
        maxResponseBytes: 3,
      );
      await expectLater(
        client.get(Uri.https('example.invalid')),
        throwsFormatException,
      );
    }
  });

  test('持续分片也受总期限约束，close 不关闭共享客户端', () async {
    var canceled = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        canceled = true;
      },
    );
    var requestCount = 0;
    final shared = _StreamClient((_) async {
      requestCount++;
      return http.StreamedResponse(
        requestCount == 1 ? body.stream : Stream.value([1]),
        200,
      );
    });
    final client =
        BoundedHttpClient(shared, timeout: const Duration(milliseconds: 40));
    final timer =
        Timer.periodic(const Duration(milliseconds: 5), (_) => body.add([1]));
    await expectLater(
      client.get(Uri.https('example.invalid')),
      throwsA(isA<TimeoutException>()),
    );
    timer.cancel();
    expect(canceled, isTrue);
    client.close();
    expect((await shared.get(Uri.https('example.invalid'))).bodyBytes, [1]);
    await body.close();
  });

  test('主动 close 立即取消在途请求', () async {
    final sent = Completer<void>();
    final aborted = Completer<void>();
    final client = BoundedHttpClient(
      _StreamClient((request) async {
        (request as http.AbortableRequest)
            .abortTrigger!
            .then((_) => aborted.complete());
        sent.complete();
        return Completer<http.StreamedResponse>().future;
      }),
    );
    final pending = client.get(Uri.https('example.invalid'));
    final failed =
        expectLater(pending, throwsA(isA<http.RequestAbortedException>()));
    await sent.future;
    client.close();
    await failed;
    await aborted.future;
  });

  test('不支持取消的客户端晚到响应也取消正文订阅', () async {
    final sent = Completer<void>();
    final response = Completer<http.StreamedResponse>();
    final canceled = Completer<void>();
    final body =
        StreamController<List<int>>(onCancel: () => canceled.complete());
    final client = BoundedHttpClient(_StreamClient((_) {
      sent.complete();
      return response.future;
    }),);
    final pending = client.get(Uri.https('example.invalid'));
    final failure =
        expectLater(pending, throwsA(isA<http.RequestAbortedException>()));
    await sent.future;
    client.close();
    await failure;
    response.complete(http.StreamedResponse(body.stream, 200));
    await canceled.future;
    await body.close();
  });

  test('SSE 无换行片段在未完成行达到上限时拒绝', () async {
    await expectLater(
      boundedLines(Stream.fromIterable(['123', '456']), maxChars: 5).toList(),
      throwsFormatException,
    );
    expect(
      await boundedLines(Stream.fromIterable(['a\r', '\nb\nc'])).toList(),
      ['a', 'b', 'c'],
    );
  });
}
