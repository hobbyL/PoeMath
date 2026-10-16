import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/assistant_conversation.dart';
import 'package:poemath/data/models/assistant_message.dart';
import 'package:poemath/data/repositories/settings_repository.dart';
import '../../helpers/hive_test_helper.dart';

class _Store extends SecureCredentialStore {
  final keys = <String, String>{};
  final writes = <String>[];
  bool failNextP2 = false;
  bool failP2Undo = false;
  @override
  Future<String?> readLlmApiKeyFor(String id) async => keys[id];
  @override
  Future<String?> readLlmApiKey() async => null;
  @override
  Future<String?> readWorkerTtsApiKey() async => null;
  @override
  Future<TencentAsrCredentials?> readTencentAsrCredentials() async => null;
  @override
  Future<void> saveLlmApiKeyFor(String id, String key) async {
    writes.add('$id:$key');
    keys[id] = key;
    if (id == 'p2' && failNextP2) {
      failNextP2 = false;
      throw StateError('write failed after mutation');
    }
  }

  @override
  Future<void> deleteLlmApiKeyFor(String id) async {
    writes.add('delete:$id');
    if (id == 'p2' && failP2Undo) throw StateError('undo failed');
    keys.remove(id);
  }
}

void main() {
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  Future<void> providers(_Store store) async {
    final settings = SettingsRepository(credentialStore: store);
    for (final id in ['p1', 'p2']) {
      await settings.saveLlmProviderConfig(
        id: id,
        name: id,
        baseUrl: 'https://$id.example.com',
        model: 'test',
        apiKey: 'old-$id',
      );
    }
    store.keys.remove('p2');
    store.writes.clear();
  }

  test('凭据部分写入失败后，已有值与不存在状态均回滚', () async {
    final store = _Store();
    await providers(store);
    final backup = BackupService(secureStore: store);
    final original = HiveBoxes.settings.toMap();
    final data =
        jsonDecode(await backup.exportToJson()) as Map<String, dynamic>;
    (data['settings'] as Map)['theme_mode'] = 'dark';
    data['credentials'] = await encryptCredentials(
      {
        kCredKeyLlmProviderKeys: jsonEncode({'p1': 'new-p1', 'p2': 'new-p2'}),
      },
      'test-passphrase',
    );
    store.failNextP2 = true;
    await expectLater(
      backup.restoreFromJson(jsonEncode(data), passphrase: 'test-passphrase'),
      throwsStateError,
    );
    expect(store.keys, {'p1': 'old-p1'});
    expect(HiveBoxes.settings.toMap(), original);
  });

  test('单条凭据撤销失败仍继续撤销其余凭据', () async {
    final store = _Store();
    await providers(store);
    final backup = BackupService(secureStore: store);
    final data =
        jsonDecode(await backup.exportToJson()) as Map<String, dynamic>;
    data['credentials'] = await encryptCredentials(
      {
        kCredKeyLlmProviderKeys: jsonEncode({'p1': 'new-p1', 'p2': 'new-p2'}),
      },
      'test-passphrase',
    );
    store.failNextP2 = true;
    store.failP2Undo = true;
    await expectLater(
      backup.restoreFromJson(jsonEncode(data), passphrase: 'test-passphrase'),
      throwsA(
        isA<BackupRestoreException>()
            .having((e) => e.rollbackFailed, 'rollbackFailed', true),
      ),
    );
    expect(store.keys['p1'], 'old-p1');
    expect(
      store.writes,
      containsAllInOrder(['p2:new-p2', 'delete:p2', 'p1:old-p1']),
    );
  });

  test('助手会话、工具消息和上下文切点完整往返，旧备份保留本机聊天', () async {
    final time = DateTime(2026);
    await HiveBoxes.conversations.put(
      'default_c1',
      Conversation(
        id: 'c1',
        profileId: 'default',
        title: '测试',
        createdAt: time,
        updatedAt: time,
        contextBaseIndex: 2,
      ),
    );
    for (final entry in [
      (MessageRole.user, '问'),
      (MessageRole.assistant, '答'),
      (MessageRole.assistant, ''),
      (MessageRole.tool, '结果'),
    ].indexed) {
      final i = entry.$1;
      final role = entry.$2.$1;
      await HiveBoxes.messages.put(
        'default_m$i',
        Message(
          id: 'm$i',
          conversationId: 'c1',
          profileId: 'default',
          role: role,
          content: entry.$2.$2,
          createdAt: time.add(Duration(seconds: i)),
          toolName: role == MessageRole.tool ? 'explain_math' : null,
          toolCallId: role == MessageRole.tool ? 'call-1' : null,
        ),
      );
    }
    final backup = BackupService();
    final text = await backup.exportToJson();
    await HiveBoxes.messages.clear();
    await HiveBoxes.conversations.clear();
    await backup.restoreFromJson(text);
    expect(HiveBoxes.conversations.get('default_c1')!.contextBaseIndex, 2);
    expect(HiveBoxes.messages.get('default_m3')!.toolCallId, 'call-1');
    expect(HiveBoxes.messages.get('default_m3')!.toolName, 'explain_math');
    final old = jsonDecode(text) as Map<String, dynamic>;
    old.remove('conversations');
    old.remove('messages');
    await backup.restoreFromJson(jsonEncode(old));
    expect(HiveBoxes.messages.length, 4);
    final invalid = jsonDecode(text) as Map<String, dynamic>;
    (invalid['messages'] as List).first['conversationId'] = 'missing';
    await expectLater(
      backup.restoreFromJson(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect(HiveBoxes.messages.length, 4);
    final empty = jsonDecode(text) as Map<String, dynamic>;
    empty['messages'] = <dynamic>[];
    empty['conversations'] = <dynamic>[];
    await backup.restoreFromJson(jsonEncode(empty));
    expect(HiveBoxes.messages.isEmpty, true);
  });

  test('历史坏设置读取安全回退，合法边界保留，写入越界明确拒绝', () async {
    final repo = SettingsRepository();
    for (final n in [-1, 0, 101, 1000000, 'bad']) {
      await HiveBoxes.settings.put('math_batch_size', n);
      expect(repo.mathBatchSize, 10);
    }
    for (final value in [double.nan, double.infinity, 0.0, 1.1, 'bad']) {
      await HiveBoxes.settings.put('tts_speed', value);
      expect(repo.ttsSpeed, 0.5);
    }
    await HiveBoxes.settings.put('tts_speed', 1);
    expect(repo.ttsSpeed, 1.0);
    await expectLater(repo.setMathBatchSize(-1), throwsArgumentError);
    await repo.setMathBatchSize(100);
    expect(repo.mathBatchSize, 100);
  });
}
