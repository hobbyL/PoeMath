// lib/data/models/llm_provider_config.dart
//
// 层级：data/models
// 职责：LLM 多厂商配置数据模型（非敏感字段）。
//       存储在 settings box 中（JSON 序列化），不使用 Hive adapter。
//       凭据（API Key）永不入本 model——编译期杜绝 Key 误入 Hive 列表，
//       对齐 webdav_config.dart 先例。

import 'dart:convert';
import 'dart:math';

/// LLM 厂商配置（非敏感字段）。
class LlmProviderConfig {
  LlmProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
  });

  /// 唯一标识（'p' + 毫秒时间戳 + 3 位随机）。
  final String id;

  /// 供应商显示名称，可空串（展示层兜底「配置 N」，不回写存储）。
  final String name;

  /// 已 normalize 的服务地址。
  final String baseUrl;

  /// 模型名。
  final String model;

  /// 生成唯一 id：'p' + 毫秒时间戳 + 3 位随机数字。
  static String generateId() {
    final suffix = Random().nextInt(1000).toString().padLeft(3, '0');
    return 'p${DateTime.now().millisecondsSinceEpoch}$suffix';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
      };

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) =>
      LlmProviderConfig(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        baseUrl: json['baseUrl'] as String,
        model: json['model'] as String,
      );

  /// 将配置列表序列化为 JSON 字符串。
  static String encodeList(List<LlmProviderConfig> configs) {
    return jsonEncode(configs.map((c) => c.toJson()).toList());
  }

  /// 从 JSON 字符串反序列化配置列表；坏 JSON 返回空列表。
  static List<LlmProviderConfig> decodeList(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final list = jsonDecode(jsonString) as List<dynamic>;
      return list
          .map((e) => LlmProviderConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Exception {
      return [];
    }
  }
}
