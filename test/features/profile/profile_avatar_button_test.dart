import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/core/services/profile_avatar_image_service.dart';
import 'package:poemath/core/services/profile_avatar_camera_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/profile_avatar.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/profile_avatar_repository.dart';
import 'package:poemath/features/profile/providers/profile_avatar_providers.dart';
import 'package:poemath/features/profile/widgets/profile_avatar_button.dart';

import '../../helpers/hive_test_helper.dart';
import '../../helpers/picture_story_fixture.dart';

class _Picker extends ProfileAvatarImageService {
  int calls = 0;
  ProfileAvatarSource? lastSource;
  Object? error;
  Completer<ProfileAvatar?> result = Completer();
  @override
  Future<ProfileAvatar?> pick({
    ProfileAvatarSource source = ProfileAvatarSource.gallery,
  }) {
    calls++;
    lastSource = source;
    if (error != null) throw error!;
    return result.future;
  }
}

class _FailingRepository extends ProfileAvatarRepository {
  @override
  Future<void> save(String profileId, ProfileAvatar avatar) async =>
      throw StateError('save failed');
}

void main() {
  late ProfileAvatar avatar;
  late _Picker picker;
  setUp(() async {
    await setUpHiveForTesting();
    ProfileScope.reset();
    avatar = ProfileAvatar(await pictureStoryPng(width: 256, height: 256));
    picker = _Picker();
  });
  tearDown(() async {
    ProfileScope.reset();
    await tearDownHiveForTesting();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    ProfileAvatarRepository? repository,
  }) async {
    final container = ProviderContainer(
      overrides: [
        profileAvatarImageServiceProvider.overrideWithValue(picker),
        if (repository != null)
          profileAvatarRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final theme = AppTheme.resolve(
      subject: AppSubject.poem,
      brightness: Brightness.light,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            bottomNavigationBar: const SizedBox(height: 64),
            body: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => Center(
                  child: ProfileAvatarButton(
                    colors: AnimatedHeroColors(
                      theme,
                      style: AnimatedHeroStyle.starlight,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  Future<void> finish(WidgetTester tester, ProviderContainer container) async {
    for (
      var i = 0;
      i < 50 && container.read(profileAvatarChangingProvider);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(container.read(profileAvatarChangingProvider), isFalse);
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> openSources(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('profile-avatar-change'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> choose(WidgetTester tester, String title) async {
    await tester.runAsync(() => tester.tap(find.text(title)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('点击头像只打开一次选图，完成后显示图片且保持头像尺寸', (tester) async {
    final container = await pump(tester);
    final button = find.byKey(const ValueKey('profile-avatar-change'));
    final before = tester.getRect(find.byType(CircleAvatar));
    await tester.runAsync(() async {
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(picker.calls, 0);
    await choose(tester, '从相册选择');
    expect(picker.calls, 1);
    expect(picker.lastSource, ProfileAvatarSource.gallery);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    picker.result.complete(avatar);
    await tester.pump();
    await finish(tester, container);
    expect(
      container.read(profileAvatarRepositoryProvider).read('default')!.bytes,
      avatar.bytes,
    );
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('profile-avatar-image')),
    );
    expect((image.image as MemoryImage).bytes, avatar.bytes);
    expect(tester.getRect(find.byType(CircleAvatar)), before);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('取消选图保留原头像，保存失败提示并恢复可点击状态', (tester) async {
    final container = await pump(tester, repository: _FailingRepository());
    await tester.runAsync(
      () => ProfileAvatarRepository().save('default', avatar),
    );
    await tester.pump();
    final button = find.byKey(const ValueKey('profile-avatar-change'));
    await openSources(tester);
    await choose(tester, '从相册选择');
    picker.result.complete(null);
    await tester.pump();
    await finish(tester, container);
    expect(find.byKey(const ValueKey('profile-avatar-image')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    picker.result = Completer();
    await openSources(tester);
    await choose(tester, '从相册选择');
    picker.result.complete(avatar);
    await tester.pump();
    await finish(tester, container);
    expect(find.text('头像更换失败，原头像已保留，请重试'), findsOneWidget);
    expect(ProfileAvatarRepository().read('default')!.bytes, avatar.bytes);
    expect(tester.widget<InkWell>(button).onTap, isNotNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('离开页面与切换档案后返回选图，只更新发起时的档案', (tester) async {
    final container = await pump(tester);
    await openSources(tester);
    await choose(tester, '从相册选择');
    await tester.pumpWidget(const SizedBox());
    ProfileScope.switchTo('another-child');
    picker.result.complete(avatar);
    await tester.pump();
    await finish(tester, container);
    final repository = container.read(profileAvatarRepositoryProvider);
    expect(repository.read('default')!.bytes, avatar.bytes);
    expect(repository.read('another-child'), isNull);
    expect(tester.takeException(), isNull);
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('关闭来源面板不打开选择器，原头像保持可点击', (tester) async {
    final container = await pump(tester);
    await openSources(tester);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从相册选择'), findsOneWidget);
    // 弹层属于根导航器，必须覆盖 Shell 的底部栏。
    expect(
      tester.getBottomRight(find.byType(BottomSheet)).dy,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await finish(tester, container);
    expect(picker.calls, 0);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('拍照权限失败提示后可重试，拍摄成功显示头像并清除恢复标记', (tester) async {
    final container = await pump(tester);
    picker.error = PlatformException(code: 'camera_access_denied');
    await openSources(tester);
    await choose(tester, '拍照');
    await finish(tester, container);
    expect(picker.lastSource, ProfileAvatarSource.camera);
    expect(find.text('无法使用相机，请在系统设置中允许相机权限后重试'), findsOneWidget);
    expect(
      HiveBoxes.settings.containsKey(ProfileAvatarCameraService.pendingKey),
      isFalse,
    );
    picker.error = null;
    await openSources(tester);
    await choose(tester, '拍照');
    picker.result.complete(avatar);
    await finish(tester, container);
    expect(picker.calls, 2);
    expect(
      container.read(profileAvatarRepositoryProvider).read('default')!.bytes,
      avatar.bytes,
    );
    expect(find.byKey(const ValueKey('profile-avatar-image')), findsOneWidget);
    expect(
      HiveBoxes.settings.containsKey(ProfileAvatarCameraService.pendingKey),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
