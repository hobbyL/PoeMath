import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/llm/chat_message.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/core/services/picture_story_generation_service.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

void main() {
  for (final mode in [
    'ordinary',
    'generation',
    'generation-timeout',
    'cancel',
  ]) {
    testWidgets('慢响应按场景限时，出题延长后仍支持超时和暂停：$mode', (tester) async {
      final response = Completer<http.Response>();
      final transport = MockClient((_) => response.future);
      final client = mode == 'ordinary'
          ? createRuntimeLlmClient(
              httpClient: transport,
              settings: SettingsRepository(),
              isActive: () => true,
              onSelectionChanged: () {},
            )
          : createRuntimeLlmClient(
              httpClient: transport,
              settings: SettingsRepository(),
              isActive: () => true,
              onSelectionChanged: () {},
              chatTimeout: PictureStoryGenerationService.requestTimeout,
            );
      Object? failure;
      String? content;
      final pending = client
          .chatComplete(
            config: const LlmConfig(
              baseUrl: 'https://model.example.com/v1',
              apiKey: '',
              model: 'gpt-4o',
            ),
            systemPrompt: 'test',
            messages: const [ChatMessage(role: ChatRole.user, content: 'test')],
            stream: true,
          )
          .then<void>(
            (value) => content = value.content,
            onError: (Object error) => failure = error,
          );
      try {
        await tester.pump();
        await tester.pump(const Duration(seconds: 91));
        expect(content, isNull);
        if (mode == 'ordinary') {
          expect(failure, isA<LlmNetworkError>());
        } else {
          expect(failure, isNull);
          if (mode == 'generation') {
            await tester.pump(const Duration(seconds: 29));
            response.complete(
              http.Response(
                '{"choices":[{"message":{"content":"complete"}}]}',
                200,
              ),
            );
            await tester.pump();
            expect(content, 'complete');
            expect(failure, isNull);
          } else if (mode == 'cancel') {
            client.close();
            await tester.pump();
            expect(failure, isA<LlmGenerationCancelled>());
          } else {
            await tester.pump(const Duration(seconds: 90));
            expect(failure, isA<LlmNetworkError>());
          }
        }
        await pending;
      } finally {
        client.close();
        transport.close();
      }
    });
  }
}
