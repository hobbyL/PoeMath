// test/data/models/llm_provider_config_test.dart
//
// LlmProviderConfig 序列化与解码防御测试：
// encodeList/decodeList 往返、空输入、四类坏输入（JSON 语法坏 /
// 条目非对象 / 条目缺 id / 字段类型错）一律回退空列表不抛。
//
// 防御要点：条目硬 cast 失败抛的是 TypeError（Error 非 Exception），
// `on Exception` 捕不住——会穿透 llmProviders getter 打穿设置页与
// 讲解链路，故 decodeList 捕 Object 兜全。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/models/llm_provider_config.dart';

void main() {
  group('encodeList / decodeList 往返', () {
    test('两条配置往返后字段全等、顺序保持', () {
      final configs = [
        LlmProviderConfig(
          id: 'p1',
          name: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com/v1',
          model: 'deepseek-chat',
        ),
        LlmProviderConfig(
          id: 'p2',
          name: '',
          baseUrl: 'https://second.example.com',
          model: 'qwen-plus',
        ),
      ];

      final decoded = LlmProviderConfig.decodeList(
        LlmProviderConfig.encodeList(configs),
      );

      expect(decoded.length, 2);
      expect(decoded[0].id, 'p1');
      expect(decoded[0].name, 'DeepSeek');
      expect(decoded[0].baseUrl, 'https://api.deepseek.com/v1');
      expect(decoded[0].model, 'deepseek-chat');
      expect(decoded[1].id, 'p2');
      expect(decoded[1].name, '');
      expect(decoded[1].model, 'qwen-plus');
    });

    test('name 缺失读作空串（展示层兜底「配置 N」）', () {
      final json = jsonEncode([
        <String, dynamic>{
          'id': 'p1',
          'baseUrl': 'https://api.example.com',
          'model': 'm1',
        },
      ]);

      final decoded = LlmProviderConfig.decodeList(json);
      expect(decoded.length, 1);
      expect(decoded[0].name, '');
    });

    test('null / 空串输入返回空列表', () {
      expect(LlmProviderConfig.decodeList(null), isEmpty);
      expect(LlmProviderConfig.decodeList(''), isEmpty);
    });

    test('空数组返回空列表', () {
      expect(LlmProviderConfig.decodeList('[]'), isEmpty);
    });

    test('generateId 生成唯一且以 p 开头', () {
      final a = LlmProviderConfig.generateId();
      final b = LlmProviderConfig.generateId();
      expect(a, startsWith('p'));
      expect(a.length, greaterThan(4));
      expect(a, isNot(b));
    });
  });

  group('坏输入防御：一律返回空列表不抛', () {
    test('JSON 语法坏（不是 JSON）', () {
      expect(LlmProviderConfig.decodeList('not-json'), isEmpty);
      expect(LlmProviderConfig.decodeList('{"id":'), isEmpty);
    });

    test('顶层不是数组（对象 / 字符串 / 数字）', () {
      expect(LlmProviderConfig.decodeList('{"id":"p1"}'), isEmpty);
      expect(LlmProviderConfig.decodeList('"a string"'), isEmpty);
      expect(LlmProviderConfig.decodeList('42'), isEmpty);
    });

    test('条目非对象（字符串 / 数字 / null / 嵌套数组）', () {
      expect(LlmProviderConfig.decodeList('["p1"]'), isEmpty);
      expect(LlmProviderConfig.decodeList('[1, 2]'), isEmpty);
      expect(LlmProviderConfig.decodeList('[null]'), isEmpty);
      expect(LlmProviderConfig.decodeList('[[]]'), isEmpty);
    });

    test('条目缺 id（硬 cast null → String 抛 TypeError）', () {
      final json = jsonEncode([
        <String, dynamic>{
          'name': '无 id 配置',
          'baseUrl': 'https://api.example.com',
          'model': 'm1',
        },
      ]);
      expect(LlmProviderConfig.decodeList(json), isEmpty);
    });

    test('条目缺 baseUrl / model', () {
      expect(
        LlmProviderConfig.decodeList(
          jsonEncode([
            <String, dynamic>{'id': 'p1', 'name': 'n', 'model': 'm1'},
          ]),
        ),
        isEmpty,
      );
      expect(
        LlmProviderConfig.decodeList(
          jsonEncode([
            <String, dynamic>{
              'id': 'p1',
              'name': 'n',
              'baseUrl': 'https://api.example.com',
            },
          ]),
        ),
        isEmpty,
      );
    });

    test('字段类型错（id 为数字 / baseUrl 为对象 / name 为数字）', () {
      expect(
        LlmProviderConfig.decodeList(
          jsonEncode([
            <String, dynamic>{
              'id': 123,
              'name': 'n',
              'baseUrl': 'https://api.example.com',
              'model': 'm1',
            },
          ]),
        ),
        isEmpty,
      );
      expect(
        LlmProviderConfig.decodeList(
          jsonEncode([
            <String, dynamic>{
              'id': 'p1',
              'name': 'n',
              'baseUrl': <String, dynamic>{'host': 'evil'},
              'model': 'm1',
            },
          ]),
        ),
        isEmpty,
      );
      expect(
        LlmProviderConfig.decodeList(
          jsonEncode([
            <String, dynamic>{
              'id': 'p1',
              'name': 7,
              'baseUrl': 'https://api.example.com',
              'model': 'm1',
            },
          ]),
        ),
        isEmpty,
      );
    });

    test('整列表回退：首条合法但第二条坏 → 整体空列表（而非部分解码）', () {
      final json = jsonEncode([
        <String, dynamic>{
          'id': 'p1',
          'name': 'DeepSeek',
          'baseUrl': 'https://api.deepseek.com/v1',
          'model': 'deepseek-chat',
        },
        <String, dynamic>{'name': '坏条目'},
      ]);
      expect(LlmProviderConfig.decodeList(json), isEmpty);
    });
  });
}
