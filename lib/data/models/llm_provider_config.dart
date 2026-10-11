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
    this.models = const <String>[],
  });

  /// 唯一标识（'p' + 毫秒时间戳 + 3 位随机）。
  final String id;

  /// 供应商显示名称，可空串（展示层兜底「配置 N」，不回写存储）。
  final String name;

  /// 已 normalize 的服务地址。
  final String baseUrl;

  /// 默认模型名（场景未单独选模型时用它）；非空时须 ∈ [models]。
  final String model;

  /// 候选模型清单（去重、保序；含默认 [model]）。空 = 未配置模型。
  final List<String> models;

  /// 规整候选模型：去空白、去重、保序；[defaultModel] 非空且不在列表中
  /// 则插到首位，保证默认模型可被选中。
  static List<String> normalizeModels(
    Iterable<String> raw,
    String defaultModel,
  ) {
    final seen = <String>{};
    final out = <String>[];
    void add(String m) {
      final t = m.trim();
      if (t.isEmpty || !seen.add(t)) return;
      out.add(t);
    }

    final d = defaultModel.trim();
    if (d.isNotEmpty) add(d);
    for (final m in raw) {
      add(m);
    }
    return List<String>.unmodifiable(out);
  }

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
        'models': models,
      };

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) {
    // model 保持硬 cast（缺失=坏数据，由 decodeList 整体回退，防御行为不变）。
    final model = json['model'] as String;
    // 迁移：旧数据无 'models' → 用 [model]（model 非空）；新数据按原样规整。
    final rawModels = (json['models'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        (model.isEmpty ? const <String>[] : <String>[model]);
    return LlmProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      baseUrl: json['baseUrl'] as String,
      model: model,
      models: normalizeModels(rawModels, model),
    );
  }

  /// 将配置列表序列化为 JSON 字符串。
  static String encodeList(List<LlmProviderConfig> configs) {
    return jsonEncode(configs.map((c) => c.toJson()).toList());
  }

  /// 从 JSON 字符串反序列化配置列表；坏 JSON 或坏条目（非对象、
  /// 缺字段、字段类型错）一律返回空列表，不向调用方抛出。
  static List<LlmProviderConfig> decodeList(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final list = jsonDecode(jsonString) as List<dynamic>;
      return list
          .map((e) => LlmProviderConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Object {
      // TypeError 是 Error 不是 Exception，`on Exception` 捕不住硬 cast
      // 失败——须捕 Object 兜全，坏数据回退空列表（注释承诺），
      // 不得穿出 llmProviders getter。
      return [];
    }
  }
}
