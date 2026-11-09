import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/profile_avatar_image_service.dart';
import 'package:poemath/core/services/profile_avatar_camera_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/profile_avatar.dart';
import 'package:poemath/data/repositories/profile_avatar_repository.dart';

final profileAvatarRepositoryProvider = Provider(
  (ref) => ProfileAvatarRepository(),
);
final profileAvatarImageServiceProvider = Provider(
  (ref) => ProfileAvatarImageService(),
);
final profileAvatarCameraServiceProvider = Provider(
  (ref) => ProfileAvatarCameraService(
    images: ref.watch(profileAvatarImageServiceProvider),
    repository: ref.watch(profileAvatarRepositoryProvider),
  ),
);

final profileAvatarProvider = Provider<ProfileAvatar?>((ref) {
  final repository = ref.watch(profileAvatarRepositoryProvider);
  final changes = repository.changes.listen((_) => ref.invalidateSelf());
  final profileChanges = ProfileScope.changes.listen(
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(changes.cancel);
  ref.onDispose(profileChanges.cancel);
  return repository.read(ProfileScope.currentId);
});

final profileAvatarChangingProvider =
    NotifierProvider<ProfileAvatarChanger, bool>(ProfileAvatarChanger.new);

/// 操作跨页面存活，写入始终归属发起选图时的档案。
class ProfileAvatarChanger extends Notifier<bool> {
  bool _disposed = false;

  @override
  bool build() {
    ref.onDispose(() => _disposed = true);
    return false;
  }

  Future<void> change({
    ProfileAvatarSource source = ProfileAvatarSource.gallery,
    Future<ProfileAvatarSource?> Function()? selectSource,
  }) async {
    if (state) return;
    final profileId = ProfileScope.currentId;
    final images = ref.read(profileAvatarImageServiceProvider);
    final repository = ref.read(profileAvatarRepositoryProvider);
    final camera = ref.read(profileAvatarCameraServiceProvider);
    state = true;
    try {
      final selected = selectSource == null ? source : await selectSource();
      if (selected == null) return;
      if (selected == ProfileAvatarSource.camera) {
        await camera.capture(profileId);
      } else {
        await camera.recoverPending();
        final avatar = await images.pick();
        if (avatar != null) await repository.save(profileId, avatar);
      }
    } finally {
      if (!_disposed) state = false;
    }
  }
}
