import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:poemath/app_bootstrap.dart';
import 'package:poemath/core/services/picture_story_editor_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _FailingDraftBox extends Fake implements Box<dynamic> {
  _FailingDraftBox(this.delegate);
  final Box<dynamic> delegate;

  @override
  bool containsKey(dynamic key) => delegate.containsKey(key);
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) async =>
      throw HiveError('模拟暂存写入失败');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File source;
  late PictureStoryImageService images;

  setUp(() async {
    ProfileScope.reset();
    await setUpHiveForTesting();
    directory = await Directory.systemTemp.createTemp('picture_story_editor_');
    source = File('${directory.path}/selected.png');
    await source.writeAsBytes(await pictureStoryPng(width: 11, height: 7));
    images = PictureStoryImageService(directoryProvider: () async => directory);
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  PictureStoryEditorService editor({
    PictureStoryPickPath? pickPath,
    PictureStoryRecoverPath? recoverPath,
    bool supportsLostData = false,
    Box<dynamic>? settings,
  }) {
    final service = PictureStoryEditorService(
      settings: settings,
      images: images,
      pickPath: pickPath,
      recoverPath: recoverPath,
      supportsLostData: supportsLostData,
    );
    addTearDown(service.dispose);
    return service;
  }

  PictureStoryEditorDraft filled(PictureStoryEditorService service) {
    final original = PictureStoryCatalog.prompts.first;
    final draft = service.openDraft(original: original);
    return draft.copyWith(
      level: PictureStoryLevel.storyteller,
      fields: {
        ...draft.fields,
        PictureStoryEditorField.title: '还没保存的风筝故事',
        PictureStoryEditorField.questions: '风筝飞到哪里？\n小狗在做什么？',
        PictureStoryEditorField.reference: '这是家长刚刚填写的参考表达。',
      },
    );
  }

  test('外部选图前落盘完整表单，取消后原图与所有文字保持一致', () async {
    final reached = Completer<void>();
    final selected = Completer<String?>();
    final service = editor(
      pickPath: (source) {
        expect(source, PictureStoryImageSource.gallery);
        reached.complete();
        return selected.future;
      },
    );
    final draft = filled(service);
    final choosing =
        service.chooseImage(draft, PictureStoryImageSource.gallery);
    await reached.future;
    final pending = service.readDraft()!;
    expect(pending.fields, draft.fields);
    expect(pending.original!.toJson(), draft.original!.toJson());
    expect(pending.image, draft.image);
    expect(pending.pendingRequest, startsWith('pick-'));
    expect(service.isPicking, isTrue);
    selected.complete(null);
    await choosing;
    expect(service.readDraft()!.toJson(), draft.toJson());
    expect(service.isPicking, isFalse);
    expect(PictureStoryRepository().storageSnapshot(), isEmpty);
  });

  test('超长临时字段在打开选图前拒绝，原快照和未保存文字保留', () async {
    var calls = 0;
    final service = editor(pickPath: (_) async {
      calls++;
      return source.path;
    },);
    final previous = filled(service);
    final snapshot = previous.encode();
    await HiveBoxes.settings.put(PictureStoryEditorService.draftKey, snapshot);
    final text =
        List.filled(PictureStoryEditorDraft.maxRawFieldLength + 1, '字').join();
    final draft = previous.copyWith(
        fields: {...previous.fields, PictureStoryEditorField.questions: text},);
    await expectLater(
        service.chooseImage(draft, PictureStoryImageSource.file),
        throwsA(isA<FormatException>()
            .having((error) => error.message, 'message', '编辑内容无法暂存，请精简文字后重试'),),);
    expect(calls, 0);
    expect(
        HiveBoxes.settings.get(PictureStoryEditorService.draftKey), snapshot,);
    expect(service.readDraft()!.toJson(), previous.toJson());
    expect(service.isPicking, isFalse);
    expect(draft.fields[PictureStoryEditorField.questions], text);
  });

  test('合法多行内容含代理对时仍能完整暂存和恢复', () async {
    final service = editor();
    final line = List.filled(PictureStoryPrompt.maxLineLength, '🌳').join();
    final text = List.filled(PictureStoryPrompt.maxLines, line).join('\n');
    final previous = filled(service);
    final draft = previous.copyWith(
        fields: {...previous.fields, PictureStoryEditorField.questions: text},);
    expect(draft.toPrompt().questions,
        List.filled(PictureStoryPrompt.maxLines, line),);
    await service.chooseImage(draft, PictureStoryImageSource.file);
    expect(
        service.readDraft()!.fields[PictureStoryEditorField.questions], text,);
    expect(service.readDraft()!.toPrompt().toJson(), draft.toPrompt().toJson());
  });

  test('拍照权限失败保留原图与文字，并解除选图忙碌状态', () async {
    final service = editor(
      pickPath: (source) async {
        expect(source, PictureStoryImageSource.camera);
        throw PlatformException(code: 'camera_access_denied');
      },
    );
    final draft = filled(service);
    await service.chooseImage(draft, PictureStoryImageSource.camera);
    final restored = service.readDraft()!;
    expect(restored.fields, draft.fields);
    expect(restored.image, draft.image);
    expect(restored.pendingRequest, isNull);
    expect(restored.message, '无法获取图片，请检查相册或相机权限后重试');
    expect(service.isPicking, isFalse);
  });

  test('坏文件不会替换原图，表单保留并提供可重试反馈', () async {
    final bad = File('${directory.path}/bad.jpg');
    await bad.writeAsString('not an image');
    final service = editor(pickPath: (_) async => bad.path);
    final draft = filled(service);
    await service.chooseImage(draft, PictureStoryImageSource.file);
    final restored = service.readDraft()!;
    expect(restored.fields, draft.fields);
    expect(restored.image, draft.image);
    expect(restored.message, '图片无法读取或保存，请重新选择并检查存储空间');
    expect(restored.pendingRequest, isNull);
    expect(service.isPicking, isFalse);
    expect(await bad.readAsString(), 'not an image');
  });

  test('临时表单写入失败时不打开选择器，不丢原输入或卡住守卫', () async {
    var calls = 0;
    final service = editor(
      settings: _FailingDraftBox(HiveBoxes.settings),
      pickPath: (_) async {
        calls++;
        return source.path;
      },
    );
    final draft = filled(service);
    await expectLater(
      service.chooseImage(draft, PictureStoryImageSource.file),
      throwsA(isA<HiveError>()),
    );
    expect(calls, 0);
    expect(service.isPicking, isFalse);
    expect(service.readDraft(), isNull);
    expect(draft.fields[PictureStoryEditorField.title], '还没保存的风筝故事');
    expect(draft.image, PictureStoryCatalog.prompts.first.image);
  });

  test('重复选图只启动一次，放弃后晚到结果不导入图片或复活表单', () async {
    var calls = 0;
    final reached = Completer<void>();
    final selected = Completer<String?>();
    final service = editor(
      pickPath: (_) {
        calls++;
        reached.complete();
        return selected.future;
      },
    );
    final draft = filled(service);
    final choosing = service.chooseImage(draft, PictureStoryImageSource.file);
    await reached.future;
    await service.chooseImage(draft, PictureStoryImageSource.camera);
    expect(calls, 1);
    await service.discardDraft(draft);
    selected.complete(source.path);
    await choosing;
    expect(service.readDraft(), isNull);
    expect(service.isPicking, isFalse);
    expect(
      await Directory('${directory.path}/picture_story/images').exists(),
      isFalse,
    );
    expect(await source.exists(), isTrue);
    expect(PictureStoryRepository().storageSnapshot(), isEmpty);
  });

  test('Android 重建后消费真实选图快照，恢复题图与文字但不自动发布', () async {
    final reached = Completer<void>();
    final selected = Completer<String?>();
    final first = editor(
      pickPath: (_) {
        reached.complete();
        return selected.future;
      },
    );
    final draft = filled(first);
    final choosing = first.chooseImage(draft, PictureStoryImageSource.gallery);
    await reached.future;
    final snapshot = HiveBoxes.settings.get(PictureStoryEditorService.draftKey);
    // 结束旧进程代表的 Future，再用生产者写出的原始快照模拟重启后的磁盘。
    await first.discardDraft(draft);
    selected.complete(null);
    await choosing;
    await HiveBoxes.settings.put(PictureStoryEditorService.draftKey, snapshot);
    await HiveBoxes.close();
    await HiveBoxes.init();
    var recoveredCalls = 0;
    final reopened = editor(
      supportsLostData: true,
      recoverPath: () async {
        recoveredCalls++;
        return source.path;
      },
    );
    await reopened.recoverLostImage();
    await reopened.recoverLostImage();
    final restored = reopened.openDraft(original: draft.original);
    expect(recoveredCalls, 1);
    expect(restored.fields, draft.fields);
    expect(restored.level, draft.level);
    expect(restored.original!.toJson(), draft.original!.toJson());
    expect(restored.image!.isLocal, isTrue);
    expect(restored.pendingRequest, isNull);
    final expected = await images.importPath(source.path);
    expect(restored.image, expected);
    expect(
      await images.readImage(restored.image!.value),
      await images.readImage(expected.value),
    );
    expect(PictureStoryRepository().storageSnapshot(), isEmpty);
    expect(PictureStoryRepository().listPrompts(), isEmpty);
  });

  test('档案切换后晚到图片仍归原表单，新档案与所有启用键保持原状', () async {
    ProfileScope.switchTo('child-a');
    final reached = Completer<void>();
    final selected = Completer<String?>();
    final service = editor(
      pickPath: (_) {
        reached.complete();
        return selected.future;
      },
    );
    final draft = filled(service);
    final choosing =
        service.chooseImage(draft, PictureStoryImageSource.gallery);
    await reached.future;
    ProfileScope.switchTo('child-b');
    selected.complete(source.path);
    await choosing;
    expect(service.readDraft()!.profileId, 'child-a');
    expect(service.readDraft()!.fields, draft.fields);
    final forB = service.openDraft(original: draft.original);
    expect(forB.profileId, 'child-b');
    expect(forB.fields[PictureStoryEditorField.title], draft.original!.title);
    expect(forB.image, draft.original!.image);
    expect(PictureStoryRepository().storageSnapshot(), isEmpty);
  });

  test('Android 没有待恢复表单仍在启动时查询一次丢失结果', () async {
    var calls = 0;
    final service = editor(
      supportsLostData: true,
      recoverPath: () async {
        calls++;
        return null;
      },
    );
    await service.recoverLostImage();
    await service.recoverLostImage();
    expect(calls, 1);
    expect(service.readDraft(), isNull);
    expect(service.isPicking, isFalse);
  });

  test('通知初始化失败不能跳过语音清理和题目选图恢复', () async {
    final events = <String>[];
    await initializeOptionalServices(
      notificationInitializer: () async {
        events.add('notification');
        throw StateError('模拟通知不可用');
      },
      speechCleanup: () async {
        events.add('cleanup');
      },
      pictureStoryRecovery: () async {
        events.add('recovery');
      },
    );
    expect(events, ['notification', 'cleanup', 'recovery']);
  });
}
