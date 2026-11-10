import 'dart:convert';

import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/data/models/llm_provider_config.dart';

/// 可备份的生图配置。密钥仅由运行时配置持有。
class ImageGenerationProviderConfig {
  const ImageGenerationProviderConfig({
    required this.name,
    required this.baseUrl,
    required this.model,
  });

  static const settingsKey = 'image_generation_provider_v1';
  static const providersSettingsKey = 'image_generation_providers_v1';
  static const activeProviderSettingsKey =
      'image_generation_active_provider_id';
  final String name;
  final String baseUrl;
  final String model;
  String get credentialHint => '${endpoint.origin}|$model';

  Uri get baseEndpoint => endpoint.replace(
        path: endpoint.path.replaceFirst(RegExp(r'/images/generations$'), ''),
      );

  factory ImageGenerationProviderConfig.fromProvider(
    LlmProviderConfig config,
  ) =>
      ImageGenerationProviderConfig(
        name: config.name,
        baseUrl: config.baseUrl,
        model: config.model,
      );

  static LlmProviderConfig normalizeProvider(LlmProviderConfig config) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(config.id) ||
        config.models.any((model) => model.runes.length > 200)) {
      throw const FormatException('生图供应商或候选模型配置无效');
    }
    final image =
        ImageGenerationProviderConfig.fromProvider(config).normalized();
    return LlmProviderConfig(
      id: config.id,
      name: image.name,
      baseUrl: image.baseEndpoint.toString(),
      model: image.model,
      models: LlmProviderConfig.normalizeModels(config.models, image.model),
    );
  }

  /// 复用普通供应商的数据结构，并在本层校验生图地址及模型约束。
  static List<LlmProviderConfig> decodeProviders(Object? raw) {
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! List) {
      throw const FormatException('生图供应商列表格式无效');
    }
    final providers = <LlmProviderConfig>[];
    final ids = <String>{};
    for (final item in data) {
      if (item is! Map ||
          item['id'] is! String ||
          item['name'] is! String ||
          item['baseUrl'] is! String ||
          item['model'] is! String ||
          item.containsKey('models') &&
              (item['models'] is! List ||
                  (item['models'] as List).any((model) => model is! String))) {
        throw const FormatException('生图供应商配置格式无效');
      }
      final provider = normalizeProvider(
        LlmProviderConfig(
          id: item['id'] as String,
          name: item['name'] as String,
          baseUrl: item['baseUrl'] as String,
          model: item['model'] as String,
          models: item['models'] == null
              ? const <String>[]
              : (item['models'] as List).cast<String>(),
        ),
      );
      if (!ids.add(provider.id)) {
        throw const FormatException('生图供应商配置重复');
      }
      providers.add(provider);
    }
    return List.unmodifiable(providers);
  }

  static String encodeProviders(List<LlmProviderConfig> providers) =>
      LlmProviderConfig.encodeList(
        decodeProviders(
          providers.map((provider) => provider.toJson()).toList(),
        ),
      );

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
  const ImageGenerationConfig({
    required this.provider,
    required this.apiKey,
    this.providerId,
    this.models = const [],
    this.fallbacks = const [],
    this.selectionSignature,
  });
  final ImageGenerationProviderConfig provider;
  final String apiKey;
  final String? providerId;
  final List<String> models;
  final List<ImageGenerationConfig> fallbacks;

  /// 只含配置与手动编辑版本，用于拒绝旧请求覆盖新选择；不含密钥。
  final String? selectionSignature;

  List<String> get candidateModels =>
      LlmProviderConfig.normalizeModels(models, provider.model);

  ImageGenerationConfig withModel(String model) => ImageGenerationConfig(
    provider: ImageGenerationProviderConfig(
      name: provider.name,
      baseUrl: provider.baseUrl,
      model: model,
    ),
    apiKey: apiKey,
    providerId: providerId,
    models: models,
    fallbacks: fallbacks,
    selectionSignature: selectionSignature,
  );
  @override
  String toString() => 'ImageGenerationConfig(model: ${provider.model}, '
      'apiKey: <不回显>)';
}
