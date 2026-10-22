import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/services/llm/llm_client.dart';
import 'package:poemath/core/services/llm/llm_config.dart';
import 'package:poemath/core/services/llm/llm_models.dart';
import 'package:poemath/features/math/word_problem/word_problem_generation_service.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

const config =
    LlmConfig(baseUrl: 'https://example.com', apiKey: 'secret', model: 'test');

http.Response response(Object content) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': content is String ? content : jsonEncode(content),
              },
            }
          ],
        }),
      ),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

WordProblemGenerationService service(
  http.Client httpClient, {
  Future<void> Function(LlmConfig, String)? onModelSucceeded,
}) =>
    WordProblemGenerationService(
      client:
          LlmClient(httpClient: httpClient, onModelSucceeded: onModelSucceeded),
      skeletonFactory: ({
        required grade,
        required semester,
        required topic,
        required count,
      }) =>
          List.filled(
        count,
        const ProblemSkeleton(
          operands: [12, 4],
          operators: [Operator.add],
          answer: 16,
          unitHint: '支',
          difficulty: 1,
        ),
      ),
    );

void main() {
  const crossProvider = LlmConfig(
    baseUrl: 'https://first.example',
    apiKey: 'first',
    model: 'A',
    models: ['A', 'B'],
    fallbacks: [
      LlmConfig(
        baseUrl: 'https://second.example',
        apiKey: 'second',
        model: 'A',
        models: ['A', 'C'],
      ),
    ],
  );

  test('跨供应商共用N+2预算，全部无效时本地补齐不提升', () async {
    final attempts = <String>[];
    final promoted = <String>[];
    final generation = service(
      MockClient((request) async {
        attempts.add(
          '${request.url.host}:${(jsonDecode(request.body) as Map)['model']}',
        );
        return response('invalid JSON');
      }),
      onModelSucceeded: (_, model) async => promoted.add(model),
    );
    addTearDown(generation.client.close);
    final items = await generation.generate(
      config: crossProvider,
      grade: 2,
      semester: '上',
      topic: WordProblemTopic.addition,
      count: 2,
      isActive: () => true,
    );
    expect(attempts, [
      'first.example:A',
      'first.example:B',
      'second.example:A',
      'second.example:C',
      'second.example:C',
      'second.example:C',
    ]);
    expect(
      items.map((item) => item.source),
      everyElement(WordProblemSource.localTemplate),
    );
    expect(promoted, isEmpty);
  });

  for (final lastFails in [false, true]) {
    test('跨供应商保留有效位置，仅请求缺失题；末供应商${lastFails ? '失败也保留' : '成功后提升'}', () async {
      final attempts = <String>[];
      final indexes = <List<int>>[];
      final promoted = <String>[];
      final generation = service(
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          final model = body['model'] as String;
          attempts.add('${request.url.host}:$model');
          final prompt = body['messages'].last['content'] as String;
          indexes.add(
            (jsonDecode(prompt.substring(prompt.indexOf('['))) as List)
                .map((item) => item['index'] as int)
                .toList(),
          );
          if (request.url.host == 'first.example' && model == 'B') {
            return http.Response('', 401);
          }
          if (request.url.host == 'second.example' && lastFails) {
            return http.Response('', 503);
          }
          return response([
            {
              'index': request.url.host == 'first.example' ? 1 : 2,
              'sceneId': 'books',
              'variantId': 'standard',
            }
          ]);
        }),
        onModelSucceeded: (provider, model) async =>
            promoted.add('${Uri.parse(provider.baseUrl).host}:$model'),
      );
      addTearDown(generation.client.close);
      final items = await generation.generate(
        config: crossProvider,
        grade: 2,
        semester: '上',
        topic: WordProblemTopic.addition,
        count: 2,
        isActive: () => true,
      );
      expect(
        attempts,
        lastFails
            ? [
                'first.example:A',
                'first.example:B',
                'second.example:A',
                'second.example:C',
              ]
            : ['first.example:A', 'first.example:B', 'second.example:A'],
      );
      expect(
        indexes,
        lastFails
            ? [
                [1, 2],
                [2],
                [2],
                [2],
              ]
            : [
                [1, 2],
                [2],
                [2],
              ],
      );
      expect(items.map((item) => item.source), [
        WordProblemSource.aiScene,
        lastFails ? WordProblemSource.localTemplate : WordProblemSource.aiScene,
      ]);
      expect(promoted, lastFails ? isEmpty : ['second.example:A']);
    });
  }

  const multi = LlmConfig(
    baseUrl: 'https://example.com',
    apiKey: 'secret',
    model: 'A',
    models: ['A', 'B', 'C'],
  );

  test('多模型共享N+2预算，完全本地补齐不提升默认', () async {
    final models = <String>[];
    final promoted = <String>[];
    final generation = service(
      MockClient((request) async {
        models.add((jsonDecode(request.body) as Map)['model'] as String);
        return response('invalid JSON');
      }),
      onModelSucceeded: (_, model) async => promoted.add(model),
    );
    addTearDown(generation.client.close);
    final items = await generation.generate(
      config: multi,
      grade: 2,
      semester: '上',
      topic: WordProblemTopic.addition,
      count: 2,
      isActive: () => true,
    );
    expect(models, ['A', 'B', 'C', 'C', 'C']);
    expect(
      items.map((item) => item.source),
      everyElement(WordProblemSource.localTemplate),
    );
    expect(promoted, isEmpty);
  });

  test('HTTP失败切换，保留有效素材且后续模型只补缺失题', () async {
    final models = <String>[];
    final indexes = <List<int>>[];
    final promoted = <String>[];
    final generation = service(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final model = body['model'] as String;
        models.add(model);
        final prompt = body['messages'].last['content'] as String;
        indexes.add(
          (jsonDecode(prompt.substring(prompt.indexOf('['))) as List)
              .map((item) => item['index'] as int)
              .toList(),
        );
        if (model == 'A') return http.Response('', 503);
        return response([
          {
            'index': model == 'B' ? 1 : 2,
            'sceneId': model == 'B' ? 'books' : 'pencils',
            'variantId': 'standard',
          }
        ]);
      }),
      onModelSucceeded: (_, model) async => promoted.add(model),
    );
    addTearDown(generation.client.close);
    final items = await generation.generate(
      config: multi,
      grade: 2,
      semester: '上',
      topic: WordProblemTopic.addition,
      count: 2,
      isActive: () => true,
    );
    expect(models, ['A', 'B', 'C']);
    expect(indexes, [
      [1, 2],
      [1, 2],
      [2],
    ]);
    expect(items.map((item) => item.plan.sceneId), ['books', 'pencils']);
    expect(
      items.map((item) => item.source),
      everyElement(WordProblemSource.aiScene),
    );
    expect(promoted, ['C']);
  });

  test('候选失败后取消，不请求下一模型', () async {
    var active = true;
    var calls = 0;
    final generation = service(
      MockClient((_) async {
        calls++;
        active = false;
        return http.Response('', 503);
      }),
    );
    addTearDown(generation.client.close);
    await expectLater(
      generation.generate(
        config: multi,
        grade: 2,
        semester: '上',
        topic: WordProblemTopic.addition,
        count: 1,
        isActive: () => active,
      ),
      throwsA(isA<LlmGenerationCancelled>()),
    );
    expect(calls, 1);
  });

  test('模型只选素材，题面数字和完整讲解由本地生成', () async {
    late http.Request request;
    final generation = service(
      MockClient((r) async {
        request = r;
        return response([
          {'index': '1', 'sceneId': 'pencils', 'variantId': 'alternate'},
        ]);
      }),
    );
    final items = await generation.generate(
      config: config,
      grade: 2,
      semester: '上',
      topic: WordProblemTopic.addition,
      count: 1,
      isActive: () => true,
    );
    expect(items.single.source, WordProblemSource.aiScene);
    expect(items.single.text, startsWith('活动准备时，'));
    expect(items.single.text, contains('12支铅笔'));
    expect(items.single.text, contains('4支'));
    expect(items.single.explanation, contains('12 + 4 = 16'));
    expect(
      WordProblemMetadata.decode(items.single.metadataJson)!
          .plan
          .skeleton
          .answer,
      16,
    );
    expect(request.body, isNot(contains('secret')));
    final body = jsonDecode(request.body) as Map;
    expect(body['max_tokens'], 500);
    expect(body['messages'].last['content'], contains('小学2年级上学期'));
    generation.client.close();
  });

  test('有效部分保留，缺题和重复index有限重试后本地补齐并标注', () async {
    var calls = 0;
    final requestedIndexes = <List<int>>[];
    final generation = service(
      MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map;
        final content = body['messages'].last['content'] as String;
        requestedIndexes.add(
          (jsonDecode(content.substring(content.indexOf('['))) as List)
              .map((item) => item['index'] as int)
              .toList(),
        );
        return response([
          if (calls == 1)
            {'index': 1, 'sceneId': 'books', 'variantId': 'standard'},
          {'index': 2, 'sceneId': 'pencils', 'variantId': 'standard'},
          {'index': 2, 'sceneId': 'cards', 'variantId': 'alternate'},
          {
            'index': 3,
            'sceneId': ['water'],
            'variantId': 'standard',
          },
        ]);
      }),
    );
    final items = await generation.generate(
      config: config,
      grade: 2,
      semester: '上',
      topic: WordProblemTopic.addition,
      count: 3,
      isActive: () => true,
    );
    expect(calls, 3);
    expect(requestedIndexes, [
      [1, 2, 3],
      [2, 3],
      [2, 3],
    ]);
    expect(items.map((i) => i.source), [
      WordProblemSource.aiScene,
      WordProblemSource.localTemplate,
      WordProblemSource.localTemplate,
    ]);
    expect(items.first.plan.sceneId, 'books');
    expect(items.every((i) => i.validation.canSave), isTrue);
    generation.client.close();
  });

  test('自由题面注入及错误格式不被采用，三次后使用本地合法题', () async {
    var calls = 0;
    final generation = service(
      MockClient((_) async {
        calls++;
        return calls == 1
            ? response('not JSON')
            : response([
                {
                  'index': 1,
                  'sceneId': 'pencils',
                  'variantId': 'standard',
                  'text': '送给同学4支却做加法',
                },
              ]);
      }),
    );
    final item = (await generation.generate(
      config: config,
      grade: 2,
      semester: '上',
      topic: WordProblemTopic.addition,
      count: 1,
      isActive: () => true,
    ))
        .single;
    expect(calls, 3);
    expect(item.source, WordProblemSource.localTemplate);
    expect(item.text, isNot(contains('送给同学')));
    expect(item.validation.canSave, isTrue);
    generation.client.close();
  });

  test('鉴权错误不重试或本地伪装成功，取消晚到响应不再请求', () async {
    var calls = 0;
    var generation = service(
      MockClient((_) async {
        calls++;
        return http.Response('', 401);
      }),
    );
    await expectLater(
      generation.generate(
        config: config,
        grade: 2,
        semester: '上',
        topic: WordProblemTopic.addition,
        count: 1,
        isActive: () => true,
      ),
      throwsA(isA<LlmAuthError>()),
    );
    expect(calls, 1);
    generation.client.close();
    var active = true;
    calls = 0;
    generation = service(
      MockClient((_) async {
        calls++;
        active = false;
        return response('bad JSON');
      }),
    );
    await expectLater(
      generation.generate(
        config: config,
        grade: 2,
        semester: '上',
        topic: WordProblemTopic.addition,
        count: 1,
        isActive: () => active,
      ),
      throwsA(isA<LlmGenerationCancelled>()),
    );
    expect(calls, 1);
    generation.client.close();
  });
}
