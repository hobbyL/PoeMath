// lib/features/profile/llm_provider_display.dart
//
// 层级：features/profile
// 职责：LLM 厂商配置的展示名 / 宿主名纯函数 —— 供应商设置页列表、
//       使用场景设置页的绑定摘要与选择弹层共用，避免「配置 N」兜底
//       与 host 解析逻辑在拆分后的多页之间重复漂移。
//
// 纯函数无状态：不读写存储、不依赖 context / ref。

import 'package:poemath/data/models/llm_provider_config.dart';

/// 列表行显示名：空名兜底「配置 N」（N 为 1-based 序号，不回写存储）。
String providerDisplayName(int index, LlmProviderConfig config) {
  final name = config.name.trim();
  if (name.isNotEmpty) return name;
  return '配置 ${index + 1}';
}

/// baseUrl 宿主名摘要（列表副标题；解析失败回退原串）。
String providerHostSummary(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  final host = uri?.host ?? '';
  if (host.isNotEmpty) return host;
  return baseUrl;
}
