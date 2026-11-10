import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/image_generation_client.dart';
import 'package:poemath/core/services/picture_story_generation_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/data/models/image_generation_config.dart';
import 'package:poemath/data/providers/llm_runtime_providers.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

import 'picture_story_fixture.dart';

/// 确定性挂起某个真实流水线步骤，不用固定延迟猜测网络进度。
class GenerationGate {
  final entered = Completer<void>();
  final _released = Completer<void>();

  Future<void> wait() async {
    if (!entered.isCompleted) entered.complete();
    await _released.future;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

class GenerationTestSettings extends SettingsRepository {
  final gates = <String, GenerationGate>{};
  int imageConfigReads = 0;
  bool failRead = false;

  @override
  Future<ImageGenerationConfig?> readImageGenerationConfig() async {
    imageConfigReads++;
    await gates['config']?.wait();
    if (failRead) throw StateError('synthetic storage failure');
    return super.readImageGenerationConfig();
  }
}

/// 真实配置、草稿、图片与发布链；只有 HTTP 响应是本地可控数据。
class PictureStoryGenerationHarness {
  PictureStoryGenerationHarness._(this.directory, this.png);

  final Directory directory;
  final Uint8List png;
  final settings = GenerationTestSettings();
  late final images = PictureStoryImageService(
    directoryProvider: () async => directory,
  );
  late final repository = PictureStoryRepository(images: images);
  late final chat = MockClient(_chat);
  late final imageTransport = MockClient(_image);
  late final service = PictureStoryGenerationService(
    images: images,
    repository: repository,
    backup: BackupService(
      pictureStoryImages: images,
      pictureStoryRepository: repository,
    ),
    llmFactory: (active) => createRuntimeLlmClient(
      httpClient: chat,
      settings: settings,
      isActive: active,
      onSelectionChanged: () => promotions++,
    ),
    imageFactory: (active) =>
        ImageGenerationClient(httpClient: imageTransport, isActive: active),
  );
  final order = <String>[];
  final models = <String>[];
  int imageCalls = 0;
  int captionCalls = 0;
  int planningCalls = 0;
  int promotions = 0;
  bool invalidPlan = false;
  bool fallbackTwice = false;
  bool imageFallback = false;
  final imageModels = <String>[];

  GenerationGate hold(String step) => settings.gates[step] = GenerationGate();

  static Future<PictureStoryGenerationHarness> create() async {
    final harness = PictureStoryGenerationHarness._(
      await Directory.systemTemp.createTemp('picture_story_background_'),
      await pictureStoryPng(),
    );
    await harness.settings.saveImageGenerationConfig(
      provider: const ImageGenerationProviderConfig(
        name: '测试生图',
        baseUrl: 'https://image.example.com/v1',
        model: 'image',
      ),
      apiKey: '',
    );
    await harness.settings.saveLlmProviderConfig(
      id: 'vision',
      name: '测试看图',
      baseUrl: 'https://chat.example.com/v1',
      model: 'gpt-4o',
      models: ['gpt-4o', 'gpt-4o-mini', 'gpt-4.1'],
      apiKey: '',
    );
    return harness;
  }

  static http.Response completion(Object value) => http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'choices': [
          {
            'message': {'content': jsonEncode(value)},
          },
        ],
      }),
    ),
    200,
  );

  Future<http.Response> _chat(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final model = body['model'] as String;
    models.add(model);
    final content = (body['messages'] as List).last['content'];
    if (content is String) {
      planningCalls++;
      order.add('plan');
      await settings.gates['plan']?.wait();
      if (fallbackTwice && model == 'gpt-4o') return http.Response('', 503);
      if (invalidPlan) return completion(<Object>[]);
      return completion([
        for (var i = 0; i < service.readDraft('default')!.options.count; i++)
          {'imagePrompt': '第 $i 个场景：孩子在公园观察花朵。'},
      ]);
    }
    captionCalls++;
    order.add('caption:$captionCalls');
    await settings.gates['caption:$captionCalls']?.wait();
    if (fallbackTwice && model != 'gpt-4.1') return http.Response('', 503);
    return completion({
      'title': '观察花朵 $captionCalls',
      'questions': ['孩子正在做什么？'],
      'sceneFacts': ['孩子在花朵旁边'],
      'reference': '孩子正在观察花朵。',
    });
  }

  Future<http.Response> _image(http.Request request) async {
    imageCalls++;
    order.add('image:$imageCalls');
    final model = (jsonDecode(request.body) as Map)['model'] as String;
    imageModels.add(model);
    await settings.gates['image:$imageCalls']?.wait();
    if (imageFallback && model != 'backup-good') return http.Response('', 503);
    return http.Response(
      jsonEncode({
        'data': [
          {'b64_json': base64Encode(png)},
        ],
      }),
      200,
    );
  }

  void releaseAll() {
    for (final gate in settings.gates.values) {
      gate.release();
    }
  }

  Future<void> dispose() async {
    releaseAll();
    chat.close();
    imageTransport.close();
    await directory.delete(recursive: true);
  }
}
