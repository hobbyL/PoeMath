// lib/core/services/llm/llm_client.dart
//
// OpenAI 兼容 Chat Completions 客户端：应用题情境文本生成 / 模型列表 / 连通性测试。
// 端点契约：POST {base}/chat/completions、GET {base}/models。
//
// 安全边界：API Key 仅出现在 `Authorization: Bearer` 请求头；
// 异常 message、toString、日志均不得包含 API Key。
// 数学内容（操作数/答案）永远来自本地生成器，本客户端只产出不可信草稿，
// 草稿必须经 WordProblemValidator 校验后才能入库。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

const _jsonContentType = 'application/json; charset=utf-8';

/// OpenAI 兼容 LLM 客户端。
final class LlmClient {
  LlmClient({
    http.Client? httpClient,
    Duration generateTimeout = const Duration(seconds: 60),
    Duration probeTimeout = const Duration(seconds: 15),
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _generateTimeout = generateTimeout,
        _probeTimeout = probeTimeout;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration _generateTimeout;
  final Duration _probeTimeout;

  static const String _chatPath = '/chat/completions';
  static const String _modelsPath = '/models';

  /// 拼接端点路径。不用 `Uri.resolve`：它对以 `/` 开头的路径做根相对
  /// 解析，会丢弃 base 中的 `/v1` 前缀。
  static Uri _join(Uri base, String path) =>
      base.replace(path: '${base.path}$path');

  /// 格式解析失败时的整批重试上限（不含首次请求，即最多发 3 次）。
  static const int _maxFormatRetries = 2;

  /// 合法 host 字符（域名 / IPv4 / localhost）。
  ///
  /// `Uri.tryParse` 会把空格等非法字符百分号编码进 host，因此需要显式
  /// 字符集校验拦截此类输入。
  static final RegExp _validHostPattern = RegExp(r'^[a-zA-Z0-9.-]+$');

  /// 回环 IPv4 段（127.0.0.0/8）。必须四段点分数字：
  /// 简单的 `startsWith('127.')` 会放行 `127.evil.com` 这类公网子域名。
  /// 段值合法性（0-255）由 socket 层兜底。
  static final RegExp _loopbackIpv4Pattern =
      RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$');

  /// 本地回环 host：http 明文 Bearer 仅放行这些地址（Ollama 等本地服务）。
  ///
  /// IPv6 字面量在 `uri.host` 中不带方括号（`[::1]` → `::1`），
  /// 两种形式都接受以防万一。
  static bool _isLoopbackHost(String host) =>
      host == 'localhost' ||
      _loopbackIpv4Pattern.hasMatch(host) ||
      host == '::1' ||
      host == '[::1]';

  /// 规范化服务地址：补 `https://` 前缀、去尾斜杠、末尾无 `/v1` 则补、
  /// 校验 scheme 与 host。非法输入抛 [FormatException]。
  static Uri normalizeBaseUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('服务地址不能为空');
    }
    if (!trimmed.contains('://')) {
      trimmed = 'https://$trimmed';
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.host.isEmpty ||
        !(_validHostPattern.hasMatch(uri.host) || _isLoopbackHost(uri.host))) {
      throw const FormatException('服务地址格式无效');
    }
    if (uri.scheme == 'http') {
      // 公网 host 走 http 会导致 API Key 明文传输，强制 https。
      if (!_isLoopbackHost(uri.host)) {
        throw const FormatException('公网地址必须使用 https，请检查服务地址');
      }
    } else if (uri.scheme != 'https') {
      throw const FormatException('服务地址仅支持 http/https');
    }
    // 末尾无 /v1 则补（OpenAI 兼容服务约定路径前缀）。
    if (!uri.path.endsWith('/v1')) {
      return uri.replace(path: '${uri.path == '/' ? '' : uri.path}/v1');
    }
    return uri;
  }

  /// 一批骨架生成应用题草稿（一批一请求；草稿按 index 与 skeleton 对齐，
  /// 缺失/多余即丢弃该题）。
  ///
  /// JSON 解析失败时同 prompt 整批重试，累计 [_maxFormatRetries] 次仍失败
  /// 抛 [LlmResponseFormatError]。
  Future<LlmBatchResult> generateWordProblems({
    required LlmConfig config,
    required List<ProblemSkeleton> skeletons,
    required int grade,
    required String semester,
    required String topic,
  }) async {
    if (skeletons.isEmpty) {
      return const LlmBatchResult(drafts: <LlmWordProblemDraft>[]);
    }
    final base = normalizeBaseUrl(config.baseUrl);
    final body = _buildGenerationBody(config, skeletons, grade, semester, topic);

    Object? lastFormatError;
    for (var attempt = 0; attempt <= _maxFormatRetries; attempt++) {
      final http.Response response;
      try {
        response = await _send(
          uri: _join(base, _chatPath),
          body: body,
          apiKey: config.apiKey,
          timeout: _generateTimeout,
          timeoutMessage: '生成应用题请求超时',
        );
      } on LlmException {
        rethrow; // 网络/鉴权/服务端错误不重试
      }

      try {
        final content = _extractAssistantContent(response);
        final drafts = _parseDrafts(content, skeletons);
        return LlmBatchResult(drafts: drafts);
      } on LlmResponseFormatError catch (error) {
        lastFormatError = error;
        // 同 prompt 重试
      }
    }
    throw LlmResponseFormatError(
      '模型输出格式无效（已重试 $_maxFormatRetries 次）：'
      '${(lastFormatError as LlmException?)?.message ?? '未知原因'}',
    );
  }

  /// 拉取模型列表；接口不支持或网络失败抛 [LlmModelsUnavailable]。
  ///
  /// 部分兼容实现（如 Ollama 旧版）不提供 /v1/models，调用方应捕获并
  /// 退化为手填模型名。
  Future<List<String>> listModels(LlmConfig config) async {
    final base = normalizeBaseUrl(config.baseUrl);
    http.Response response;
    try {
      response = await _httpClient
          .get(
            _join(base, _modelsPath),
            headers: _headersFor(config.apiKey, acceptOnly: true),
          )
          .timeout(_probeTimeout);
    } on TimeoutException {
      throw const LlmModelsUnavailable('获取模型列表超时');
    } on SocketException {
      throw const LlmModelsUnavailable('网络不可用，无法获取模型列表');
    } on http.ClientException {
      throw const LlmModelsUnavailable('获取模型列表网络请求失败');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const LlmModelsUnavailable('API Key 无效或未授权');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmModelsUnavailable(
        '模型列表接口不可用（HTTP ${response.statusCode}）',
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is List<Object?>) {
          final models = data
              .map((item) => item is Map<Object?, Object?>
                  ? item['id']?.toString()
                  : null,)
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toList()
            ..sort();
          return models;
        }
      } else if (decoded is List<Object?>) {
        // 少数实现直接返回数组（如某些代理）。
        // 仅保留 Map 的 id 与 String 元素；数字/布尔等垃圾条目丢弃。
        final models = decoded
            .map((item) => item is Map<Object?, Object?>
                ? item['id']?.toString()
                : item is String
                    ? item
                    : null,)
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList()
          ..sort();
        return models;
      }
      throw const LlmResponseFormatError('模型列表返回数据格式无效');
    } on LlmResponseFormatError {
      rethrow;
    } on FormatException {
      throw const LlmResponseFormatError('模型列表返回数据格式无效');
    }
  }

  /// 连通性测试：真实发送一次 `max_tokens: 1` 的小请求。
  ///
  /// 收到合法响应即通过（地址可达 + Key 有效 + 模型可用，完整链路）。
  Future<void> testConnection(LlmConfig config) async {
    final base = normalizeBaseUrl(config.baseUrl);
    final body = jsonEncode(<String, Object>{
      'model': config.model,
      'messages': <Map<String, String>>[
        {'role': 'user', 'content': '你好'},
      ],
      'max_tokens': 1,
    });
    await _send(
      uri: _join(base, _chatPath),
      body: body,
      apiKey: config.apiKey,
      timeout: _probeTimeout,
      timeoutMessage: '连接测试超时',
    );
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  // ============ Prompt 构造（design §3.2） ============

  String _buildGenerationBody(
    LlmConfig config,
    List<ProblemSkeleton> skeletons,
    int grade,
    String semester,
    String topic,
  ) {
    final topicLabel =
        WordProblemTopic.tryParse(topic)?.label ?? topic;
    final systemPrompt = StringBuffer()
      ..writeln('你是一名小学数学应用题作者。')
      ..writeln('我给你一组题目的结构骨架（数字、运算、答案、单位都已确定），')
      ..writeln('你只为每道题编写生活化的题面、单位与解题讲解。')
      ..writeln()
      ..writeln('铁律（违反任何一条该题作废）：')
      ..writeln('1. 只能使用给定骨架中的数字，不得增加、删减或改动任何数字；')
      ..writeln('2. 题面中不得出现答案本身；')
      ..writeln('3. 题面中不得出现任何运算符号（+ - × ÷ =）和算式；')
      ..writeln('4. 不得出现"第几个"这类序数表述；')
      ..writeln('5. 讲解分 2-3 步，只引用给定数字与答案，不得引入新数字；')
      ..writeln('6. 题面用词必须与运算语义一致：加法/乘法用"一共/共有"，')
      ..writeln('   减法用"还剩/找回/少了"，除法用"平均/每份"；')
      ..writeln('7. 所有数字用阿拉伯数字表示。')
      ..writeln()
      ..writeln('只输出严格 JSON 数组，不要输出任何其他文字：')
      ..writeln(
        '[{"index":1,"text":"题面","unit":"单位","explanation":"讲解"}]',);

    final userPrompt = StringBuffer()
      ..writeln('年级：小学$grade年级$semester学期')
      ..writeln('知识点：$topicLabel')
      ..writeln('请为以下 $topicLabel 应用题骨架编写题面：');
    for (var i = 0; i < skeletons.length; i++) {
      final s = skeletons[i];
      userPrompt
        .writeln(
          '${i + 1}. 数字 ${jsonEncode(s.operands)}，'
          '运算 ${jsonEncode(s.operators.map((o) => o.symbol).toList())}，'
          '答案单位提示：${s.unitHint}',
        );
    }

    return jsonEncode(<String, Object>{
      'model': config.model,
      'messages': <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt.toString()},
        {'role': 'user', 'content': userPrompt.toString()},
      ],
      'temperature': 0.8,
      // 按题数线性放大输出上限，防止大批次（20 题）被服务端默认
      // 输出上限截断 → JSON 不完整 → 整批重试再截断。
      'max_tokens': skeletons.length * 220 + 400,
    });
  }

  // ============ HTTP 与解析 ============

  Map<String, String> _headersFor(String apiKey, {bool acceptOnly = false}) {
    final headers = <String, String>{'Accept': _jsonContentType};
    if (acceptOnly) {
      // 空 Key（Ollama 等无鉴权服务）省略 Authorization 头。
      if (apiKey.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${apiKey.trim()}';
      }
      return headers;
    }
    headers['Content-Type'] = _jsonContentType;
    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    return headers;
  }

  Future<http.Response> _send({
    required Uri uri,
    required String body,
    required String apiKey,
    required Duration timeout,
    required String timeoutMessage,
  }) async {
    http.Response response;
    try {
      response = await _httpClient
          .post(uri, headers: _headersFor(apiKey), body: body)
          .timeout(timeout);
    } on TimeoutException {
      throw LlmNetworkError(timeoutMessage);
    } on SocketException {
      throw const LlmNetworkError('网络不可用，请检查网络后重试');
    } on http.ClientException {
      throw const LlmNetworkError('网络请求失败');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw LlmAuthError('API Key 无效或未授权（HTTP ${response.statusCode}）');
    }
    if (response.statusCode >= 500) {
      throw LlmServerError('LLM 服务暂时不可用（HTTP ${response.statusCode}）');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmServerError('LLM 服务请求失败（HTTP ${response.statusCode}）');
    }
    return response;
  }

  /// 提取 `choices[0].message.content`；缺失或非 200 结构抛格式错误。
  String _extractAssistantContent(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const LlmResponseFormatError('模型响应不是有效 JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LlmResponseFormatError('模型响应结构无效');
    }
    final choices = decoded['choices'];
    if (choices is! List<Object?> || choices.isEmpty) {
      final error = decoded['error'];
      if (error is Map<String, dynamic> && error['message'] is String) {
        throw LlmResponseFormatError('模型返回错误：${error['message']}');
      }
      throw const LlmResponseFormatError('模型响应缺少 choices');
    }
    final choice = choices.first;
    if (choice is! Map<Object?, Object?>) {
      throw const LlmResponseFormatError('模型响应 choices 结构无效');
    }
    final message = choice['message'];
    if (message is! Map<Object?, Object?>) {
      throw const LlmResponseFormatError('模型响应缺少 message');
    }
    final content = message['content']?.toString();
    if (content == null || content.trim().isEmpty) {
      throw const LlmResponseFormatError('模型输出内容为空');
    }
    return content;
  }

  /// 容错解析草稿：剥 markdown code fence、截取首个 `[` 到末个 `]`，
  /// 按 index（1-based）与 skeleton 对齐；缺失/多余/字段非法即丢弃该题。
  List<LlmWordProblemDraft> _parseDrafts(
    String content,
    List<ProblemSkeleton> skeletons,
  ) {
    final jsonText = _extractJsonArray(content);
    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const LlmResponseFormatError('模型输出不是有效 JSON 数组');
    }
    if (decoded is! List<Object?>) {
      throw const LlmResponseFormatError('模型输出不是 JSON 数组');
    }

    final draftsByIndex = <int, LlmWordProblemDraft>{};
    for (final item in decoded) {
      if (item is! Map<Object?, Object?>) continue;
      final index = item['index'];
      final text = item['text']?.toString();
      final unit = item['unit']?.toString();
      final explanation = item['explanation']?.toString();
      // index 兼容 int 与数字字符串（LLM 常见瑕疵 "index":"1"）；
      // 越界（含 < 1）的条目由下方与 skeleton 对齐时自然丢弃。
      final int parsedIndex;
      if (index is int) {
        parsedIndex = index;
      } else if (index is String && int.tryParse(index) != null) {
        parsedIndex = int.parse(index);
      } else {
        continue;
      }
      if (text == null || text.trim().isEmpty) continue;
      draftsByIndex[parsedIndex] = LlmWordProblemDraft(
        index: parsedIndex,
        text: text.trim(),
        unit: unit?.trim() ?? '',
        explanation: explanation?.trim() ?? '',
      );
    }

    final drafts = <LlmWordProblemDraft>[];
    for (var i = 0; i < skeletons.length; i++) {
      final draft = draftsByIndex[i + 1];
      if (draft != null) drafts.add(draft);
    }
    return drafts;
  }

  /// 剥 markdown code fence（```json ... ```）并截取首个 `[` 到末个 `]`。
  static String _extractJsonArray(String content) {
    var text = content.trim();
    // 剥 code fence：``` 或 ```json 开头、``` 结尾。
    final fencePattern = RegExp(r'^```[a-zA-Z]*\s*([\s\S]*?)\s*```$');
    final fenced = fencePattern.firstMatch(text);
    if (fenced != null) {
      text = fenced.group(1)!.trim();
    }
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) {
      throw const LlmResponseFormatError('模型输出中未找到 JSON 数组');
    }
    return text.substring(start, end + 1);
  }
}
