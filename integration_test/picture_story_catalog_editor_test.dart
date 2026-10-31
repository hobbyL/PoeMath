// Android: fvm flutter test integration_test/picture_story_catalog_editor_test.dart
//   -d emulator-5554 --dart-define=POEMATH_INTEGRATION_TEST=true --no-uninstall
// 加 --dart-define=POEMATH_NATIVE_PICKERS=true 后，依次在系统界面选择测试图片、取消相册、完成拍照。
// 独立测试包名与新建 Hive/题图目录共同隔离正常应用的数据和安全凭据。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_editor_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/profile/picture_story_detail_page.dart';
import 'package:poemath/features/profile/picture_story_editor_page.dart';
import 'package:poemath/features/profile/picture_story_management_page.dart';

import '../test/helpers/hive_test_helper.dart';
import '../test/helpers/picture_story_fixture.dart';

class _Access extends ParentAccessService {
  var unlocked = true;
  @override
  bool get enabled => true;
  @override
  bool get isUnlocked => unlocked;
  @override
  Future<void> initialize() async {}
  @override
  void lock() {
    unlocked = false;
    notifyListeners();
  }

  void unlock() {
    unlocked = true;
    notifyListeners();
  }
}

class _Editor extends PictureStoryEditorService {
  _Editor({required super.images, super.pickPath})
      : super(supportsLostData: false);
  Future<void>? lastPick;
  Future<void>? lastDiscard;
  @override
  Future<void> chooseImage(
          PictureStoryEditorDraft draft, PictureStoryImageSource source,) =>
      lastPick = super.chooseImage(draft, source);
  @override
  Future<void> discardDraft(PictureStoryEditorDraft draft) =>
      lastDiscard = super.discardDraft(draft);
}

class _Repository extends PictureStoryRepository {
  _Repository({required super.images, required super.authorize});
  Future<PictureStoryPrompt>? lastSave;
  @override
  Future<PictureStoryPrompt> savePrompt(
          {required PictureStoryPrompt prompt,
          required String profileId,
          PictureStoryPrompt? original,
          bool enableForProfile = true,}) =>
      lastSave = super.savePrompt(
          prompt: prompt,
          profileId: profileId,
          original: original,
          enableForProfile: enableForProfile,);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const nativePickers = bool.fromEnvironment('POEMATH_NATIVE_PICKERS');
  late Directory directory;
  late PictureStoryImageService images;
  late _Access access;
  late _Repository repository;
  late _Editor editor;
  late ProviderContainer container;
  late GoRouter router;
  final captureKey = GlobalKey();

  setUp(() async {
    expect(
      (await PackageInfo.fromPlatform()).packageName,
      'com.poemath.app.integration',
      reason: '必须加 --dart-define=POEMATH_INTEGRATION_TEST=true 隔离测试包',
    );
    ProfileScope.reset();
    await setUpHiveForTesting();
    directory = await Directory.systemTemp.createTemp('picture_story_native_');
    images = PictureStoryImageService(directoryProvider: () async => directory);
    access = _Access();
    repository = _Repository(images: images, authorize: access.assertAllowed);
    final fixture = File('${directory.path}/fixture.png');
    await fixture.writeAsBytes(await pictureStoryPng(width: 240, height: 160));
    editor = _Editor(
        images: images,
        pickPath: nativePickers ? null : (_) async => fixture.path,);
    container = ProviderContainer(overrides: [
      pictureStoryImageServiceProvider.overrideWithValue(images),
      pictureStoryRepositoryProvider.overrideWithValue(repository),
      pictureStoryEditorServiceProvider.overrideWithValue(editor),
    ],);
    Widget protected(Widget child) =>
        ParentAccessBoundary(service: access, child: child);
    router =
        GoRouter(initialLocation: AppRoutes.pictureStoryManagement, routes: [
      GoRoute(
          path: AppRoutes.pictureStoryManagement,
          builder: (_, state) => protected(const PictureStoryManagementPage()),),
      GoRoute(
          path: AppRoutes.pictureStoryCreate,
          builder: (_, state) => protected(const PictureStoryEditorPage()),),
      GoRoute(
          path: AppRoutes.pictureStoryDetail,
          builder: (_, state) => protected(
              PictureStoryDetailPage(promptId: state.pathParameters['id']!),),),
      GoRoute(
          path: AppRoutes.pictureStoryEdit,
          builder: (_, state) => protected(
              PictureStoryEditorPage(promptId: state.pathParameters['id']!),),),
    ],);
  });
  tearDown(() async {
    router.dispose();
    container.dispose();
    editor.dispose();
    access.dispose();
    ProfileScope.reset();
    await tearDownHiveForTesting();
    await directory.delete(recursive: true);
  });

  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
            key: captureKey,
            child: MaterialApp.router(
                theme: AppTheme.resolve(
                    subject: AppSubject.poem, brightness: Brightness.light,),
                routerConfig: router,),),),);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增题目'));
    await tester.pumpAndSettle();
    for (final entry
        in {'title': '小猫的窗前故事', 'questions': '小猫在哪里？\n小猫看到了什么？'}.entries) {
      final field = find.byKey(ValueKey('picture-story-${entry.key}'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, entry.value);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label, String stage) async {
    final control = find.text(label);
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    AppLogger.d(stage, tag: 'PictureStoryNativeTest');
    await tester.tap(control);
    await editor.lastPick!.timeout(const Duration(minutes: 5));
    await tester.pumpAndSettle();
  }

  Future<void> resumeEditor(WidgetTester tester) async {
    expect(access.isUnlocked, isFalse);
    expect(find.text('请由家长解锁后继续'), findsOneWidget);
    expect(repository.storageSnapshot(), isEmpty);
    access.unlock();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('picture-story-title')),)
            .controller!
            .text,
        '小猫的窗前故事',);
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('picture-story-questions')),)
            .controller!
            .text,
        '小猫在哪里？\n小猫看到了什么？',);
  }

  Future<void> saveAndVerify(WidgetTester tester) async {
    await tester.tap(find.text('保存题目'));
    final saved =
        await repository.lastSave!.timeout(const Duration(seconds: 20));
    await editor.lastDiscard!.timeout(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(find.byType(PictureStoryDetailPage), findsOneWidget);
    expect(find.text(saved.title), findsOneWidget);
    expect(saved.image.isLocal, isTrue);
    final bytes = await images.readImage(saved.image.value);
    final backup = BackupService(
        pictureStoryImages: images, pictureStoryRepository: repository,);
    final json = await backup.exportToJson();
    await PictureStoryRepository.exclusive(
        () => repository.restoreStorageSnapshot({}),);
    final targetImages = PictureStoryImageService(
        directoryProvider: () async => Directory('${directory.path}/restore'),);
    await BackupService(pictureStoryImages: targetImages).restoreFromJson(json);
    await tester.pumpAndSettle();
    expect(repository.findPrompt(saved.id)!.toJson(), saved.toJson());
    expect(await targetImages.readImage(saved.image.value), bytes);
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screenshot = await boundary.toImage();
    try {
      final data =
          (await screenshot.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File(
          '${directory.parent.path}/picture-story-native-${DateTime.now().microsecondsSinceEpoch}.png',);
      await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),);
      AppLogger.d('EVIDENCE=${file.path}', tag: 'PictureStoryNativeTest');
    } finally {
      screenshot.dispose();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('Android 新增题图、保存详情与完整离线备份恢复', (tester) async {
    await openEditor(tester);
    if (nativePickers) {
      await choose(tester, '从文件选择', 'SYSTEM_FILE_PICKER');
      await resumeEditor(tester);
      final first = editor.readDraft()!;
      expect(first.image!.isLocal, isTrue);
      await choose(tester, '从相册选择', 'SYSTEM_GALLERY_CANCEL');
      await resumeEditor(tester);
      expect(editor.readDraft()!.image, first.image);
      expect(editor.readDraft()!.fields, first.fields);
      await choose(tester, '拍照', 'SYSTEM_CAMERA');
      await resumeEditor(tester);
      expect(editor.readDraft()!.image!.isLocal, isTrue);
      expect(editor.readDraft()!.image, isNot(first.image));
    } else {
      await choose(tester, '从文件选择', 'LOCAL_IMAGE_IMPORT');
    }
    await saveAndVerify(tester);
  }, timeout: const Timeout(Duration(minutes: 17)),);
}
