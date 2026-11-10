import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:poemath/core/services/bounded_http_client.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/network_errors.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/models/image_generation_config.dart';

class ImageGenerationException implements Exception {
  const ImageGenerationException(this.message, {this.skipProvider = false});
  final String message;
  final bool skipProvider;
  @override
  String toString() => message;
}

class ImageGenerationCancelled extends ImageGenerationException {
  const ImageGenerationCancelled() : super('生成已暂停，可稍后继续');
}

/// 每次只请求一张；失败时顺序尝试已配置候选，每个候选在本批次最多失败一次。
class ImageGenerationClient {
  ImageGenerationClient({
    http.Client? httpClient,
    CloudUsageService? usage,
    this._isActive,
    Duration timeout = const Duration(seconds: 180),
  }) : _inner = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _usage = usage ?? CloudUsageService.instance {
    _http = BoundedHttpClient(
      _inner,
      timeout: timeout,
      maxResponseBytes: 28 * 1024 * 1024,
    );
  }

  final http.Client _inner;
  final bool _ownsClient;
  final CloudUsageService _usage;
  final bool Function()? _isActive;
  late final BoundedHttpClient _http;
  bool _closed = false;
  final _failed = <(String?, String, String)>{};
  final _unavailable = <(String?, String)>{};
  final _preferred = <ImageGenerationConfig, ImageGenerationConfig>{};
  ImageGenerationException? _lastFailure;

  (String?, String) _providerKey(ImageGenerationConfig config) =>
      (config.providerId, config.provider.endpoint.toString());
  (String?, String, String) _modelKey(ImageGenerationConfig config) => (
    config.providerId,
    config.provider.endpoint.toString(),
    config.provider.model,
  );

  void _check() {
    if (_closed || !(_isActive?.call() ?? true)) {
      throw const ImageGenerationCancelled();
    }
  }

  /// 家长主动测试时生成一张预览图，经过完整解码校验后才认定模型可用。
  Future<Uint8List> testConnection(ImageGenerationConfig config) async {
    final bytes = await generate(
      config: config,
      prompt:
          '生成一张简单的儿童绘本插画：一只小猫坐在花园里看一朵花。'
          '画面清晰、温暖，不要文字。',
    );
    _check();
    final preview = await PictureStoryImageService.normalizePreview(bytes);
    _check();
    return preview;
  }

  Future<Uint8List> generate({
    required ImageGenerationConfig config,
    required String prompt,
    Future<void> Function(Uint8List bytes)? validate,
    void Function(int attempt)? onAttempt,
    Future<void> Function(ImageGenerationConfig successful)? onSuccess,
  }) async {
    _check();
    if (prompt.trim().isEmpty || prompt.runes.length > 4000) {
      throw const ImageGenerationException('画面描述为空或过长，请修改后重试');
    }
    final seen = <(String?, String, String)>{};
    final candidates = [
      if (_preferred[config] case final preferred?) preferred,
      for (final provider in [config, ...config.fallbacks])
        for (final model in provider.candidateModels) provider.withModel(model),
    ];
    var attempt = 0;
    for (final candidate in candidates) {
      _check();
      final key = _modelKey(candidate);
      if (!seen.add(key) ||
          _failed.contains(key) ||
          _unavailable.contains(_providerKey(candidate))) {
        continue;
      }
      onAttempt?.call(++attempt);
      _check();
      late Uint8List bytes;
      try {
        bytes = await _generateSingle(config: candidate, prompt: prompt);
        _check();
        await validate?.call(bytes);
        _check();
      } on ImageGenerationCancelled {
        rethrow;
      } on CloudQuotaExceededException {
        rethrow;
      } on Object catch (error) {
        _check();
        // 只转换本步骤的网络/图片错误；本地存储与默认设置写入在重试范围外。
        if (error is! ImageGenerationException &&
            error is! PictureStoryImageException) {
          rethrow;
        }
        final failure = error is ImageGenerationException
            ? error
            : const ImageGenerationException('服务没有返回可以读取的图片');
        _lastFailure = failure;
        _failed.add(key);
        if (failure.skipProvider) _unavailable.add(_providerKey(candidate));
        AppLogger.w('生图候选失败：${failure.message}', tag: 'PictureStory');
        continue;
      }
      _preferred[config] = candidate;
      if (onSuccess != null) {
        try {
          await onSuccess(candidate);
        } on Object {
          _check();
          AppLogger.w('生图已成功，默认配置暂未保存', tag: 'PictureStory');
        }
      }
      _check();
      return bytes;
    }
    throw _lastFailure ?? const ImageGenerationException('没有可用的生图模型，请检查配置');
  }

  Future<Uint8List> _generateSingle({
    required ImageGenerationConfig config,
    required String prompt,
  }) async {
    _check();
    final endpoint = config.provider.normalized().endpoint;
    var downloading = false;
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..body = jsonEncode({
        'model': config.provider.model,
        'prompt': prompt,
        'n': 1,
        'size': '1024x1024',
      });
    if (config.apiKey.trim().isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    }
    try {
      await _usage.reserve(CloudUsageKind.imageGeneration, check: _check);
      _check();
      final timer = Stopwatch()..start();
      final stream = await _http.sendBounded(request);
      final headersMs = timer.elapsedMilliseconds;
      final response = await http.Response.fromStream(stream);
      AppLogger.d(
        '生图响应：首包 ${headersMs}ms，完整接收 ${timer.elapsedMilliseconds}ms，'
        '${response.bodyBytes.length} bytes',
        tag: 'PictureStory',
      );
      _checkStatus(response.statusCode);
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['data'] is! List) {
        throw const FormatException();
      }
      final data = decoded['data'] as List;
      if (data.length != 1 || data.first is! Map) {
        throw const FormatException();
      }
      final item = data.first as Map;
      final encoded = item['b64_json'];
      if (encoded is String && encoded.isNotEmpty) {
        if (encoded.length >
            ((PictureStoryImageService.maxSourceBytes + 2) ~/ 3) * 4) {
          throw const ImageGenerationException('生成图片超过 20 MB，请调整模型后重试');
        }
        return _checkedBytes(base64Decode(encoded));
      }
      final url = item['url'];
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException();
      }
      // 图片地址可能是另一个域名；不得传递生图密钥。
      final download = http.Request('GET', uri)..followRedirects = false;
      downloading = true;
      final downloaded = await http.Response.fromStream(
        await _http.sendBounded(download),
      );
      _checkStatus(downloaded.statusCode, fromProvider: false);
      return _checkedBytes(downloaded.bodyBytes);
    } on ImageGenerationException {
      rethrow;
    } on CloudQuotaExceededException {
      rethrow;
    } on TimeoutException {
      throw const ImageGenerationException('生图响应超时，请稍后重试');
    } on FormatException {
      throw const ImageGenerationException('服务没有返回有效图片，请检查生图接口和模型');
    } on SocketException catch (error) {
      _check();
      if (isHostLookupFailure(error)) {
        throw ImageGenerationException(
          '无法解析图片服务地址，请检查网络或 DNS 后重试',
          skipProvider: !downloading,
        );
      }
      throw const ImageGenerationException('图片请求失败，请检查网络后重试');
    } on Object {
      if (_closed || !(_isActive?.call() ?? true)) {
        throw const ImageGenerationCancelled();
      }
      throw const ImageGenerationException('图片请求失败，请检查网络或服务配置');
    }
  }

  static Uint8List _checkedBytes(Uint8List bytes) {
    if (bytes.isEmpty ||
        bytes.length > PictureStoryImageService.maxSourceBytes) {
      throw const ImageGenerationException('生成图片为空或超过 20 MB');
    }
    return bytes;
  }

  static void _checkStatus(int status, {bool fromProvider = true}) {
    if (status == 200) return;
    throw ImageGenerationException(switch (status) {
      401 => '生图密钥无效，请检查 API Key',
      403 => '生图服务拒绝访问，请检查模型权限',
      408 || 504 => '生图服务请求超时，请稍后重试',
      429 => '生图服务暂时限流或额度不足，请稍后重试',
      >= 500 => '生图服务暂时不可用，请稍后重试',
      _ => '生图请求失败（HTTP $status），请检查接口和模型',
    }, skipProvider: fromProvider && status == 401);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _http.close();
    if (_ownsClient) _inner.close();
  }
}
