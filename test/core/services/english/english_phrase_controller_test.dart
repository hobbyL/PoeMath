import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poemath/core/prompts/generation_prompt_defaults.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/llm/llm_scenario.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/models/textbook.dart';
import 'package:poemath/data/repositories/english_course_repository.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import 'package:poemath/features/english/english_phrase_controller.dart';

import '../../../helpers/english_fixture.dart';
import '../../../helpers/english_phrase_fixture.dart';
import '../../../helpers/hive_test_helper.dart';
import '../../../helpers/parent_access_test_helper.dart';

class _FailSaveOnce extends EnglishCourseRepository {
  _FailSaveOnce(Future<Directory> Function() directory)
    : super(directoryProvider: directory);
  bool fail = true;
  @override
  Future<EnglishCourse> appendPhrases(
    Textbook book, {
    required String lessonId,
    required int expectedRevision,
    required List<EnglishTarget> phrases,
    required void Function() check,
  }) {
    if (fail) {
      fail = false;
      return Future.error(const FileSystemException('disk unavailable'));
    }
    return super.appendPhrases(
      book,
      lessonId: lessonId,
      expectedRevision: expectedRevision,
      phrases: phrases,
      check: check,
    );
  }
}

void main() {
  late Directory root;
  late EnglishCourseRepository courses;
  late SettingsRepository settings;
  final controllers = <EnglishPhraseController>[];
  var changed = 0, promoted = 0, available = true;
  setUp(() async {
    await setUpHiveForTesting();
    await unlockParentForTesting();
    ProfileScope.reset();
    root = await Directory.systemTemp.createTemp('english-phrase-controller-');
    courses = EnglishCourseRepository(directoryProvider: () async => root);
    await courses.seed(englishBook(), phraseCourse(), check: () {});
    settings = SettingsRepository();
    changed = promoted = 0;
    available = true;
  });
  tearDown(() async {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    ProfileScope.reset();
    lockParentForTesting();
    await tearDownHiveForTesting();
    await root.delete(recursive: true);
  });
  Future<void> configure({bool fallback = false}) async {
    for (final id in fallback ? ['a', 'b'] : ['a']) {
      await settings.saveLlmProviderConfig(
        id: id,
        name: id,
        baseUrl: 'https://$id.example.com/v1',
        model: 'model-$id',
        apiKey: '',
      );
    }
  }

  EnglishPhraseController make(
    MockClient http, {
    EnglishCourseRepository? repository,
  }) {
    addTearDown(http.close);
    final controller = EnglishPhraseController(
      book: englishBook(),
      lessonId: phraseCourse().lessons.single.id,
      courses: repository ?? courses,
      settings: settings,
      httpClient: http,
      isBookAvailable: () => available,
      onChanged: () => changed++,
      onSelectionChanged: () => promoted++,
    );
    controllers.add(controller);
    return controller;
  }

  http.Response reply(String text, {int status = 200}) => http.Response(
    phraseChatResponse(text),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test('未配置不发请求；配置返回后复用默认，生成与再次打开只补缺项', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map;
      final messages = body['messages'] as List;
      expect(messages.first['content'], contains('2～4'));
      final input = jsonDecode(messages.last['content'] as String) as Map;
      expect(input['grade'], englishBook().grade);
      expect(input['semester'], englishBook().semester);
      expect(input['unit'], phraseCourse().lessons.single.unitTitle);
      expect(input['lesson'], 'Lesson 1');
      expect(input.keys.toSet(), {
        'grade',
        'semester',
        'unit',
        'lesson',
        'words',
        'excluded',
      });
      final words = input['words'] as List;
      expect(words.first['meaning'], calls == 1 ? '爸爸' : '妈妈');
      expect(
        words.map((dynamic w) => w['id']),
        calls == 1 ? ['father', 'mother'] : ['mother'],
      );
      if (calls == 2) expect(input['excluded'], contains('my father'));
      return reply(phraseResponse(word: calls == 1 ? 'father' : 'mother'));
    });
    final controller = make(client);
    await controller.generate();
    expect(controller.needsConfiguration, isTrue);
    expect(calls, 0);
    await configure();
    controller.settingsReturned();
    await controller.generate();
    expect(controller.busy, isFalse);
    expect(
      (await courses.load(englishBook()))!.lessons.single.phrases
          .map((p) => p.text),
      ['my father', 'a kind father'],
    );
    expect(controller.message, '已保存可用短语，可继续补齐');
    final reopened = make(client);
    await reopened.generate();
    await reopened.generate();
    expect(calls, 2);
    expect(changed, 2);
    expect(
      (await courses.load(englishBook()))!.lessons.single.phrases,
      hasLength(4),
    );
    expect(settings.providerIdForScenario(LlmScenario.englishPhrase), isNull);
  });

  test('保存的英语提示词进入真实请求，恢复默认后下一次生成使用内置要求', () async {
    await configure();
    await settings.setWordProblemGenerationPrompt('仅用于数学应用题');
    await settings.setEnglishPhraseGenerationPrompt('优先选择自然的家庭成员搭配');
    var calls = 0;
    final controller = make(
      MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = (body['messages'] as List)
            .cast<Map<String, dynamic>>();
        final prompt = messages.first['content'] as String;
        expect(
          prompt,
          startsWith(
            calls == 1 ? '优先选择自然的家庭成员搭配' : kEnglishPhraseGenerationSystemPrompt,
          ),
        );
        expect(prompt, isNot(contains('仅用于数学应用题')));
        // 自定义教学要求不能移除输出契约或原词约束。
        expect(prompt, contains('"sourceId"'));
        expect(prompt, contains('不能用变形代替'));
        return reply(phraseResponse(word: calls == 1 ? 'father' : 'mother'));
      }),
    );
    await controller.generate();
    final saved = (await courses.load(englishBook()))!.lessons.single.phrases
        .map((p) => p.toJson())
        .toList();
    await settings.resetEnglishPhraseGenerationPrompt();
    await controller.generate();
    final finalPhrases = (await courses.load(englishBook()))!
        .lessons
        .single
        .phrases;
    expect(finalPhrases, hasLength(4));
    expect(finalPhrases.take(2).map((p) => p.toJson()).toList(), saved);
    expect(calls, 2);
  });

  test('格式错误仅回退已配置厂商，成功回写英语绑定，不动数学绑定', () async {
    await configure(fallback: true);
    await settings.setScenarioSelection(
      LlmScenario.englishPhrase,
      providerId: 'a',
      model: 'model-a',
    );
    await settings.setScenarioSelection(
      LlmScenario.wordProblem,
      providerId: 'a',
      model: 'model-a',
    );
    final hosts = <String>[];
    final controller = make(
      MockClient((request) async {
        hosts.add(request.url.host);
        return reply(hosts.length == 1 ? '{"items":[]}' : phraseResponse());
      }),
    );
    await controller.generate();
    expect(hosts, ['a.example.com', 'b.example.com']);
    expect(settings.providerIdForScenario(LlmScenario.englishPhrase), 'b');
    expect(settings.providerIdForScenario(LlmScenario.wordProblem), 'a');
    expect(promoted, 1);
    expect(CloudUsageService.instance.used(CloudUsageKind.llm), 1);
  });

  test('保存失败重试已验证内容，不再次请求模型', () async {
    await configure();
    var calls = 0;
    final repository = _FailSaveOnce(() async => root);
    final controller = make(
      MockClient((_) async {
        calls++;
        return reply(phraseResponse());
      }),
      repository: repository,
    );
    await controller.generate();
    expect(controller.hasUnsaved, isTrue);
    expect(controller.message, '短语尚未保存，请重试保存');
    expect(
      (await courses.load(englishBook()))!.lessons.single.phrases,
      isEmpty,
    );
    await controller.generate();
    expect(controller.hasUnsaved, isFalse);
    expect(calls, 1);
    expect(
      (await courses.load(englishBook()))!.lessons.single.phrases,
      hasLength(2),
    );
  });

  test('多批处理中后续请求失败，已保存首批保留且重试只请求剩余词', () async {
    await configure();
    await settings.setEnglishPhraseGenerationPrompt('本轮使用的教学要求');
    final words = {
      'father': '爸爸',
      'mother': '妈妈',
      'sister': '姐姐',
      'brother': '哥哥',
      'grandmother': '奶奶',
      'grandfather': '爷爷',
      'uncle': '叔叔',
      'aunt': '阿姨',
    };
    await courses.saveGenerated(
      englishBook(),
      englishLesson(
        targets: [
          for (final e in words.entries)
            englishWord(
              id: e.key,
              text: e.key,
              meaning: e.value,
              approved: false,
            ),
        ],
      ),
      check: () {},
    );
    final batches = <List<String>>[];
    final controller = make(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final input = jsonDecode(
          (body['messages'] as List).last['content'] as String,
        ) as Map;
        final requested = (input['words'] as List).cast<Map<String, dynamic>>();
        batches.add(requested.map((word) => word['word'] as String).toList());
        expect(
          (body['messages'] as List).first['content'],
          startsWith(batches.length <= 2 ? '本轮使用的教学要求' : '下轮使用的新要求'),
        );
        if (batches.length == 1) {
          await settings.setEnglishPhraseGenerationPrompt('下轮使用的新要求');
        }
        if (batches.length == 2) return http.Response('unavailable', 503);
        return reply(
          jsonEncode({
            'items': [
              for (final word in requested)
                {
                  'sourceId': word['id'],
                  'phrases': [
                    {
                      'text': 'my ${word['word']}',
                      'meaning': '我的${word['meaning']}',
                    },
                    {
                      'text': 'your ${word['word']}',
                      'meaning': '你的${word['meaning']}',
                    },
                  ],
                },
            ],
          }),
        );
      }),
    );
    await controller.generate();
    final saved = (await courses.load(englishBook()))!.lessons.single.phrases
        .toList();
    expect(saved, hasLength(12));
    expect(controller.message, isNotNull);
    await controller.generate();
    expect(batches, [
      words.keys.take(6).toList(),
      ['uncle', 'aunt'],
      ['uncle', 'aunt'],
    ]);
    final finalPhrases = (await courses.load(englishBook()))!
        .lessons
        .single
        .phrases
        .toList();
    expect(finalPhrases, hasLength(16));
    expect(
      finalPhrases.take(12).map((t) => t.toJson()),
      saved.map((t) => t.toJson()),
    );
  });

  for (final invalidation in [
    'cancel',
    'profile',
    'restore',
    'delete',
    'edit',
    'leave',
    'delete-reseed',
  ]) {
    test('$invalidation 在响应之前发生，迟到结果不写课程', () async {
      await configure();
      final entered = Completer<void>(), release = Completer<void>();
      var calls = 0;
      final controller = make(
        MockClient((_) async {
          calls++;
          entered.complete();
          await release.future;
          return reply(phraseResponse());
        }),
      );
      final run = controller.generate();
      await entered.future;
      switch (invalidation) {
        case 'cancel':
          controller.cancel();
        case 'profile':
          ProfileScope.switchTo('another');
        case 'restore':
          await PracticeDraftRepository.whileRestoring(() async {
            await HiveBoxes.meta.put('practice_draft_epoch', 1);
          });
        case 'delete':
          available = false;
          await courses.clear(englishBook(), check: () {});
        case 'edit':
          await courses.saveLesson(
            englishBook(),
            phraseCourse().lessons.single,
            expectedRevision: 0,
            check: () {},
          );
        case 'leave':
          controller.dispose();
          controllers.remove(controller);
        case 'delete-reseed':
          await courses.clear(englishBook(), check: () {});
          await courses.seed(englishBook(), phraseCourse(), check: () {});
      }
      release.complete();
      await run;
      final current = await courses.load(englishBook());
      expect(current?.lessons.single.phrases ?? [], isEmpty);
      expect(changed, 0);
      expect(calls, 1);
    });
  }

  test('双击只运行一批；额度耗尽不发请求，已有内容保留', () async {
    await configure();
    final entered = Completer<void>(), release = Completer<void>();
    var calls = 0;
    final controller = make(
      MockClient((_) async {
        calls++;
        entered.complete();
        await release.future;
        return reply(phraseResponse());
      }),
    );
    final run = controller.generate();
    await entered.future;
    await controller.generate();
    expect(calls, 1);
    release.complete();
    await run;
    await CloudUsageService.instance.setLimit(CloudUsageKind.llm, 1);
    await controller.generate();
    expect(calls, 1);
    expect(controller.message, contains('上限'));
    expect(
      (await courses.load(englishBook()))!.lessons.single.phrases,
      hasLength(2),
    );
  });
}
