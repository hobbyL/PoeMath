import 'dart:async';

import 'package:http/http.dart' as http;

/// Each request has its own cancellation, total deadline and body budget.
/// Closing this wrapper leaves an injected connection pool available.
class BoundedHttpClient extends http.BaseClient {
  BoundedHttpClient(
    this.inner, {
    this.timeout = const Duration(seconds: 60),
    this.maxResponseBytes = 2 * 1024 * 1024,
  });

  final http.Client inner;
  final Duration timeout;
  final int maxResponseBytes;
  final Set<void Function()> _cancel = {};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest source) =>
      sendBounded(source);

  Future<http.StreamedResponse> sendBounded(
    http.BaseRequest source, {
    Duration? deadline,
  }) async {
    if (_closed) throw http.RequestAbortedException(source.url);
    final aborted = Completer<void>();
    final stopped = Completer<void>();
    Object? failure;
    void cancel([Object? reason]) {
      failure ??= reason ?? http.RequestAbortedException(source.url);
      if (!aborted.isCompleted) aborted.complete();
      if (!stopped.isCompleted) stopped.complete();
    }

    void closeRequest() => cancel();
    _cancel.add(closeRequest);
    final limit = deadline ?? timeout;
    final timer = Timer(limit, () => cancel(TimeoutException('请求超时', limit)));
    void release() {
      timer.cancel();
      _cancel.remove(closeRequest);
    }

    final request = http.AbortableRequest(
      source.method,
      source.url,
      abortTrigger: aborted.future,
    )
      ..headers.addAll(source.headers)
      ..followRedirects = source.followRedirects
      ..maxRedirects = source.maxRedirects
      ..persistentConnection = source.persistentConnection;
    // Application requests are buffered Request objects, never multipart uploads.
    if (source is http.Request) {
      request.bodyBytes = source.bodyBytes;
    } else {
      release();
      throw ArgumentError('不支持的网络请求类型');
    }
    if (source is http.Abortable) {
      (source as http.Abortable).abortTrigger?.then((_) => cancel());
    }
    try {
      final response = await Future.any<http.StreamedResponse>([
        inner.send(request).then((response) {
          // A client without Abortable support may return after cancellation.
          if (failure != null) {
            unawaited(response.stream.listen((_) {}).cancel());
            throw failure!;
          }
          return response;
        }),
        stopped.future.then((_) => throw failure!),
      ]);
      if ((response.contentLength ?? 0) > maxResponseBytes) {
        cancel(const FormatException('响应内容超过允许大小'));
        // Cancel the response subscription even for clients without Abortable support.
        await response.stream.listen((_) {}).cancel();
        throw failure!;
      }
      final controller = StreamController<List<int>>();
      StreamSubscription<List<int>>? subscription;
      var bytes = 0;
      var finished = false;
      void finish([Object? error, StackTrace? stack]) {
        if (finished) return;
        finished = true;
        release();
        if (error != null) controller.addError(error, stack);
        unawaited(controller.close());
        unawaited(subscription?.cancel());
      }

      stopped.future.then((_) => finish(failure));
      controller
        ..onListen = () {
          if (finished) {
            unawaited(response.stream.listen((_) {}).cancel());
            return;
          }
          subscription = response.stream.listen(
            (chunk) {
              bytes += chunk.length;
              if (bytes > maxResponseBytes) {
                cancel(const FormatException('响应内容超过允许大小'));
                finish(failure);
                return;
              }
              if (!finished) controller.add(chunk);
            },
            onError: (Object error, StackTrace stack) =>
                finish(failure ?? error, stack),
            onDone: () => finish(),
          );
        }
        ..onPause = () {
          subscription?.pause();
        }
        ..onResume = () {
          subscription?.resume();
        }
        ..onCancel = () {
          cancel();
          finish();
        };
      return http.StreamedResponse(
        controller.stream,
        response.statusCode,
        headers: response.headers,
        request: request,
        contentLength: response.contentLength,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } on Object {
      cancel();
      release();
      rethrow;
    }
  }

  Future<http.Response> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? deadline,
  }) async {
    final request = http.Request(method, uri)..headers.addAll(headers ?? {});
    if (body is String) request.body = body;
    if (body is List<int>) request.bodyBytes = body;
    return http.Response.fromStream(
      await sendBounded(request, deadline: deadline),
    );
  }

  @override
  void close() {
    _closed = true;
    cancelPending();
  }

  void cancelPending() {
    for (final cancel in _cancel.toList()) {
      cancel();
    }
  }
}

/// Limits the unfinished SSE line before LineSplitter can buffer it indefinitely.
Stream<String> boundedLines(
  Stream<String> input, {
  int maxChars = 64 * 1024,
}) async* {
  var pending = '';
  await for (final chunk in input) {
    for (final part in chunk.split('\n').indexed) {
      if (part.$1 > 0) {
        yield pending.endsWith('\r')
            ? pending.substring(0, pending.length - 1)
            : pending;
        pending = '';
      }
      if (pending.length + part.$2.length > maxChars) {
        throw const FormatException('流式响应单行超过允许大小');
      }
      pending += part.$2;
    }
  }
  if (pending.isNotEmpty) yield pending;
}
