// lib/core/utils/profile_scope.dart
//
// 层级：core/utils
// 职责：Profile 隔离 key 构造工具。
//       MVP 恒返回 'default'，V2 变为动态多档案。

import 'dart:async';

class ProfileScope {
  const ProfileScope._();

  static const String defaultProfileId = 'default';
  static String _currentProfileId = defaultProfileId;
  static int _revision = 0;
  static final _changes = StreamController<String>.broadcast(sync: true);
  static int get revision => _revision;
  static Stream<String> get changes => _changes.stream;

  /// 当前活跃的 profileId。MVP 阶段恒为 'default'。
  static String get currentId => _currentProfileId;

  /// 切换当前 profile（V2 扩展用）。
  static void switchTo(String profileId) {
    if (profileId == _currentProfileId) return;
    _currentProfileId = profileId;
    _revision++;
    _changes.add(profileId);
    // TODO(V2): 触发全局 Provider 刷新
  }

  /// 构造 profile-scoped key。
  /// 例: key('poem_001') => 'default_poem_001'
  static String key(String suffix) => '${currentId}_$suffix';

  /// 重置为默认 profile（仅测试用）。
  static void reset() {
    switchTo(defaultProfileId);
  }
}
