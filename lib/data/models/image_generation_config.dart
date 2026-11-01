import 'dart:convert';

import 'package:poemath/core/services/llm/llm_client.dart';

/// 可备份的生图配置。密钥仅由运行时配置持有。
class ImageGenerationProviderConfig {
  const ImageGenerationProviderConfig({
    required this.name,
    required this.baseUrl,
    required this.model,
  });

  static const settingsKey = 'image_generation_provider_v1';
  final String name;
  final String baseUrl;
  final String model;
  String get credentialHint => '${endpoint.origin}|$model';

  Uri get endpoint {
    final raw = baseUrl.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('生图服务地址不能包含账号、密钥或查询参数');
    }
    final withoutSuffix = raw.replaceFirst(
      RegExp(r'/images/generations/?$'),
      '',
    );
    final base = LlmClient.normalizeBaseUrl(withoutSuffix);
    if (base.userInfo.isNotEmpty || base.hasQuery || base.hasFragment) {
      throw const FormatException('生图服务地址不能包含账号、密钥或查询参数');
    }
    return base.replace(path: '${base.path}/images/generations');
  }

  ImageGenerationProviderConfig normalized() {
    final value = ImageGenerationProviderConfig(
      name: name.trim(),
      baseUrl: baseUrl.trim(),
      model: model.trim(),
    );
    if (value.name.runes.length > 80 ||
        value.baseUrl.length > 2048 ||
        value.model.isEmpty ||
        value.model.runes.length > 200) {
      throw const FormatException('请填写有效的生图服务地址和模型名称');
    }
    value.endpoint;
    return value;
  }

  Map<String, String> toJson() => {
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
      };
  String encode() => jsonEncode(toJson());

  factory ImageGenerationProviderConfig.fromJson(Object? raw) {
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map ||
        data['name'] is! String ||
        data['baseUrl'] is! String ||
        data['model'] is! String) {
      throw const FormatException('生图配置格式无效');
    }
    return ImageGenerationProviderConfig(
      name: data['name'] as String,
      baseUrl: data['baseUrl'] as String,
      model: data['model'] as String,
    ).normalized();
  }
}

class ImageGenerationConfig {
  const ImageGenerationConfig({required this.provider, required this.apiKey});
  final ImageGenerationProviderConfig provider;
  final String apiKey;
  @override
  String toString() => 'ImageGenerationConfig(model: ${provider.model}, '
      'apiKey: <不回显>)';
}
