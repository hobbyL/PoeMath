import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

/// 只刷新 LLM 配置展示，不重建依赖设置仓储的 TTS / ASR 服务。
final llmSelectionVersionProvider = StateProvider<int>((ref) => 0);

/// 生产请求共用的受限默认模型回写接线。
LlmClient createRuntimeLlmClient({
  required http.Client httpClient,
  required SettingsRepository settings,
  required bool Function() isActive,
  required void Function() onSelectionChanged,
  Duration chatTimeout = const Duration(seconds: 90),
}) {
  final acceptedSelections =
      <LlmConfig, ({String signature, String providerId, String model})>{};

  Future<void> saveAcceptedCompletion(
    LlmConfig request,
    LlmConfig successful, {
    void Function(String signature)? onSelectionSaved,
  }) async {
    if (!isActive()) return;
    var source = request;
    var target = successful;
    final accepted = acceptedSelections[request];
    if (accepted != null) {
      if (settings.pictureStoryLlmSelectionSignature != accepted.signature) {
        return;
      }
      if (accepted.providerId == successful.selection?.providerId &&
          accepted.model == successful.model) {
        return;
      }
      // 同一批后续看图请求仍使用原配置；再次回写须依据上次已保存的选择。
      final latest = await settings.readLlmConfigForScenario(
        request.selection!.scenario,
      );
      if (latest == null ||
          !isActive() ||
          settings.pictureStoryLlmSelectionSignature != accepted.signature) {
        return;
      }
      final matches = [latest, ...latest.fallbacks].where(
        (candidate) =>
            candidate.selection?.providerId ==
                successful.selection?.providerId &&
            candidate.baseUrl == successful.baseUrl &&
            candidate.apiKey == successful.apiKey &&
            candidate.candidateModels.contains(successful.model),
      );
      if (matches.isEmpty) return;
      source = latest;
      target = matches.first.withModel(successful.model);
    }
    String? savedSignature;
    final changed = await settings.promoteSuccessfulLlmSelection(
      source,
      target,
      isActive: isActive,
      onSelectionSaved: (signature) {
        savedSignature = SettingsRepository.llmSelectionSignatureFrom(
          signature,
        );
        onSelectionSaved?.call(signature);
      },
    );
    if (changed) {
      acceptedSelections[request] = (
        signature: savedSignature!,
        providerId: target.selection!.providerId,
        model: target.model,
      );
      if (isActive()) onSelectionChanged();
    }
  }

  return LlmClient(
    httpClient: httpClient,
    chatTimeout: chatTimeout,
    isActive: isActive,
    onSelectionSucceeded: (request, successful) async {
      final changed = await settings.promoteSuccessfulLlmSelection(
        request,
        successful,
        isActive: isActive,
      );
      if (changed && isActive()) onSelectionChanged();
    },
    onCompletionAccepted: saveAcceptedCompletion,
  );
}
