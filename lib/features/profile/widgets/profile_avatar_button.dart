import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/profile_avatar_image_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/features/profile/providers/profile_avatar_providers.dart';

class ProfileAvatarButton extends ConsumerWidget {
  const ProfileAvatarButton({super.key, required this.colors});

  final AnimatedHeroColors colors;

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final changer = ref.read(profileAvatarChangingProvider.notifier);
    final supportsCamera = ref
        .read(profileAvatarImageServiceProvider)
        .supportsCamera;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await changer.change(
        selectSource: () => _selectSource(context, supportsCamera),
      );
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '更换头像失败',
        tag: 'ProfileAvatar',
        error: error,
        stackTrace: stackTrace,
      );
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (error) {
            FormatException(:final message) => message,
            PlatformException(
              code: 'camera_access_denied' ||
                  'camera_access_denied_without_prompt' ||
                  'camera_access_restricted',
            ) =>
              '无法使用相机，请在系统设置中允许相机权限后重试',
            PlatformException(code: 'no_available_camera') =>
              '此设备没有可用相机，请从相册选择图片',
            _ => '头像更换失败，原头像已保留，请重试',
          }),
        ),
      );
    }
  }

  Future<ProfileAvatarSource?> _selectSource(
    BuildContext context,
    bool supportsCamera,
  ) => showModalBottomSheet<ProfileAvatarSource>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .7,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: SpacingTokens.md),
              Text(
                '更换头像',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.sm,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (supportsCamera)
                        AppTile(
                          flat: true,
                          icon: Icons.photo_camera_outlined,
                          iconColor: theme.colorScheme.onSurfaceVariant,
                          title: '拍照',
                          subtitle: '',
                          onTap: () => Navigator.pop(
                            sheetContext,
                            ProfileAvatarSource.camera,
                          ),
                        ),
                      AppTile(
                        flat: true,
                        icon: Icons.photo_library_outlined,
                        iconColor: theme.colorScheme.onSurfaceVariant,
                        title: '从相册选择',
                        subtitle: '',
                        onTap: () => Navigator.pop(
                          sheetContext,
                          ProfileAvatarSource.gallery,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = ref.watch(profileAvatarProvider);
    final changing = ref.watch(profileAvatarChangingProvider);
    final placeholder = Icon(
      Icons.person_rounded,
      color: colors.foreground,
      size: SpacingTokens.xl,
    );
    return Tooltip(
      message: '更换头像',
      child: Semantics(
        label: changing ? '正在更换头像' : '更换头像',
        button: true,
        enabled: !changing,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('profile-avatar-change'),
            onTap: changing ? null : () => _change(context, ref),
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: SpacingTokens.xl,
              backgroundColor: Color.lerp(colors.base, colors.glow, .16),
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  ExcludeSemantics(
                    child: avatar == null
                        ? placeholder
                        : ClipOval(
                            child: Image.memory(
                              avatar.bytes,
                              key: const ValueKey('profile-avatar-image'),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => placeholder,
                            ),
                          ),
                  ),
                  if (changing)
                    Center(
                      child: SizedBox.square(
                        dimension: SpacingTokens.lg,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.foreground,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
