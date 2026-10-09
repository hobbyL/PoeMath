// lib/core/services/llm/llm_explain_providers.dart
//
// 层级：core/services/llm
// 职责：AI 讲解（诗词讲解 / 口算解析）共用的 http.Client 注入口。
//
// 与 llm_settings_page 的注入口同构：默认按 ProviderScope 缓存单个
// client（onDispose 关闭，复用连接池），测试覆写为 MockClient 拦截网络层。
// LlmClient 注入后不持有所有权，其 close() 不会关闭这里的 client。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// AI 讲解请求使用的 http.Client。
final llmExplainHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
