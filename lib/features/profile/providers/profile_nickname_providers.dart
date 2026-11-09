import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/profile_nickname.dart';
import 'package:poemath/data/repositories/profile_nickname_repository.dart';

final profileNicknameRepositoryProvider = Provider(
  (ref) => ProfileNicknameRepository(),
);

final profileNicknameProvider = Provider<String>((ref) {
  final repository = ref.watch(profileNicknameRepositoryProvider);
  final changes = repository.changes.listen((_) => ref.invalidateSelf());
  final profileChanges = ProfileScope.changes.listen(
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(changes.cancel);
  ref.onDispose(profileChanges.cancel);
  return repository.read(ProfileScope.currentId) ?? ProfileNickname.defaultName;
});
