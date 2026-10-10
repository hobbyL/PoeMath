// test/data/repositories/assistant_conversation_repository_test.dart
//
// AI 助手会话仓储测试：CRUD、首条 user 自动标题（截断/兜底/不覆盖）、
// 消息往返与升序、updatedAt 倒序、重启持久化、profile 隔离、级联删除。

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/assistant_conversation.dart';
import 'package:poemath/data/models/assistant_message.dart';
import 'package:poemath/data/repositories/assistant_conversation_repository.dart';

import '../../helpers/hive_test_helper.dart';

Message _msg({
  required String id,
  required String conversationId,
  required MessageRole role,
  required String content,
  String? profileId,
  DateTime? createdAt,
}) =>
    Message(
      id: id,
      conversationId: conversationId,
      profileId: profileId ?? ProfileScope.currentId,
      role: role,
      content: content,
      createdAt: createdAt ?? DateTime(2026, 10, 1),
    );

/// 关闭并按同一临时目录重开两 box，模拟 App 重启。
Future<void> _restart() async {
  await HiveBoxes.conversations.close();
  await HiveBoxes.messages.close();
  HiveBoxes.conversations =
      await Hive.openBox<Conversation>(HiveKeys.conversationBox);
  HiveBoxes.messages = await Hive.openBox<Message>(HiveKeys.messageBox);
}

void main() {
  late ConversationRepository repo;

  setUp(() async {
    await setUpHiveForTesting();
    repo = ConversationRepository();
  });

  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  test('create 入库后命中 getById/getAll；默认标题「新对话」', () async {
    final c = await repo.create();

    expect(repo.getById(c.id)?.id, c.id);
    expect(c.title, '新对话');
    expect(repo.getAll().map((x) => x.id), [c.id]);
    expect(repo.getById('missing'), isNull);
  });

  test('首条 user 消息自动生成标题（取首行、截断 ≤16 加…）', () async {
    final c = await repo.create();
    await repo.appendMessage(_msg(
      id: 'm1',
      conversationId: c.id,
      role: MessageRole.user,
      content: '一二三四五六七八九十一二三四五六七八九十',
    ),);

    final title = repo.getById(c.id)!.title;
    expect(title, '一二三四五六七八九十一二三四五六…');
    expect(title.length, 17); // 16 字 + 省略号
  });

  test('短首行作标题；多行只取首行', () async {
    final c = await repo.create();
    await repo.appendMessage(_msg(
      id: 'm1',
      conversationId: c.id,
      role: MessageRole.user,
      content: '帮我讲这道题\n还有后面这些都忽略',
    ),);
    expect(repo.getById(c.id)!.title, '帮我讲这道题');
  });

  test('空白首行兜底「新对话」', () async {
    final c = await repo.create();
    await repo.appendMessage(_msg(
      id: 'm1',
      conversationId: c.id,
      role: MessageRole.user,
      content: '   \n真正内容在第二行',
    ),);
    expect(repo.getById(c.id)!.title, '新对话');
  });

  test('user+assistant 往返；messagesOf 按 createdAt 升序', () async {
    final c = await repo.create();
    await repo.appendMessage(_msg(
      id: 'm2',
      conversationId: c.id,
      role: MessageRole.assistant,
      content: '你好呀',
      createdAt: DateTime(2026, 10, 1, 12, 0, 1),
    ),);
    await repo.appendMessage(_msg(
      id: 'm1',
      conversationId: c.id,
      role: MessageRole.user,
      content: '在吗',
      createdAt: DateTime(2026, 10, 1, 12, 0, 0),
    ),);

    final msgs = repo.messagesOf(c.id);
    expect(msgs.map((m) => m.id), ['m1', 'm2']);
    expect(msgs.map((m) => m.role), [MessageRole.user, MessageRole.assistant]);
  });

  test('getAll 按 updatedAt 倒序；追加消息刷新到最前', () async {
    final c1 = await repo.create();
    c1.updatedAt = DateTime(2026, 1, 1);
    await c1.save();
    final c2 = await repo.create();
    c2.updatedAt = DateTime(2026, 1, 2);
    await c2.save();
    expect(repo.getAll().map((x) => x.id), [c2.id, c1.id]);

    // 向较旧的 c1 追加消息 → updatedAt 刷新为 now()，跃到最前。
    await repo.appendMessage(_msg(
      id: 'm1',
      conversationId: c1.id,
      role: MessageRole.user,
      content: '新消息',
    ),);
    expect(repo.getAll().first.id, c1.id);
  });

  test('自动标题仅首条 user 触发；后续 user 不覆盖；rename 后不被改写', () async {
    final c = await repo.create();
    await repo.appendMessage(_msg(
      id: 'm1',
      conversationId: c.id,
      role: MessageRole.user,
      content: '第一个问题',
    ),);
    expect(repo.getById(c.id)!.title, '第一个问题');

    await repo.appendMessage(_msg(
      id: 'm2',
      conversationId: c.id,
      role: MessageRole.user,
      content: '第二个问题',
    ),);
    expect(repo.getById(c.id)!.title, '第一个问题'); // 不被第二条覆盖

    await repo.rename(c.id, '我的标题');
    await repo.appendMessage(_msg(
      id: 'm3',
      conversationId: c.id,
      role: MessageRole.user,
      content: '第三个问题',
    ),);
    expect(repo.getById(c.id)!.title, '我的标题'); // 重命名后不被自动改写
  });

  test('rename 覆盖标题；空输入兜底「新对话」', () async {
    final c = await repo.create();
    await repo.rename(c.id, '  自定义名字  ');
    expect(repo.getById(c.id)!.title, '自定义名字');

    await repo.rename(c.id, '   ');
    expect(repo.getById(c.id)!.title, '新对话');
  });

  test('重启（close + 重开 box）后会话与消息仍在', () async {
    final c = await repo.create();
    await repo.appendMessage(_msg(
      id: 'm1',
      conversationId: c.id,
      role: MessageRole.user,
      content: '持久化问题',
    ),);
    await repo.appendMessage(_msg(
      id: 'm2',
      conversationId: c.id,
      role: MessageRole.assistant,
      content: '持久化回答',
      createdAt: DateTime(2026, 10, 1, 12),
    ),);

    await _restart();
    final fresh = ConversationRepository();

    expect(fresh.getById(c.id)?.title, '持久化问题');
    expect(fresh.messagesOf(c.id).map((m) => m.content),
        ['持久化问题', '持久化回答'],);
  });

  test('profile 隔离：切 profile 后 getAll/messagesOf 不含他人数据', () async {
    final mine = await repo.create();
    await repo.appendMessage(_msg(
      id: 'm1',
      conversationId: mine.id,
      role: MessageRole.user,
      content: '我的消息',
    ),);

    ProfileScope.switchTo('other');
    expect(repo.getAll(), isEmpty);
    expect(repo.messagesOf(mine.id), isEmpty);

    final theirs = await repo.create();
    expect(repo.getAll().map((x) => x.id), [theirs.id]);

    ProfileScope.reset();
    expect(repo.getAll().map((x) => x.id), [mine.id]);
    expect(repo.messagesOf(mine.id), hasLength(1));
  });

  test('级联删除：delete 清空该会话 messages，其他会话不受影响', () async {
    final c1 = await repo.create();
    final c2 = await repo.create();
    await repo.appendMessage(_msg(
      id: 'a1', conversationId: c1.id, role: MessageRole.user, content: 'x',),);
    await repo.appendMessage(_msg(
      id: 'a2',
      conversationId: c1.id,
      role: MessageRole.assistant,
      content: 'y',
      createdAt: DateTime(2026, 10, 1, 12),
    ),);
    await repo.appendMessage(_msg(
      id: 'b1', conversationId: c2.id, role: MessageRole.user, content: 'z',),);

    await repo.delete(c1.id);

    expect(repo.getById(c1.id), isNull);
    expect(repo.messagesOf(c1.id), isEmpty);
    expect(repo.getById(c2.id)?.id, c2.id);
    expect(repo.messagesOf(c2.id), hasLength(1));
  });



}
