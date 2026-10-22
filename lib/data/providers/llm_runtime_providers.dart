import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

/// 只刷新 LLM 配置展示，不重建依赖设置仓储的 TTS / ASR 服务。
final llmSelectionVersionProvider = StateProvider<int>((ref) => 0);

/// 生产请求共用的受限默认模型回写接线。
LlmClient createRuntimeLlmClient({
  required http.Client httpClient,
  required SettingsRepository settings,
  required bool Function() isActive,
  required void Function() onSelectionChanged,
}) =>
    LlmClient(
      httpClient: httpClient,
      isActive: isActive,
      onModelSucceeded: (config, model) async {
        final changed = await settings.promoteSuccessfulLlmModel(
          config,
          model,
          isActive: isActive,
        );
        if (changed && isActive()) onSelectionChanged();
      },
    );
