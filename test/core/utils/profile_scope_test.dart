// test/core/utils/profile_scope_test.dart
//
// 单元测试：ProfileScope 工具类。

import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/utils/profile_scope.dart';

void main() {
  group('ProfileScope', () {
    setUp(() {
      ProfileScope.reset();
    });

    test('默认 profileId 是 default', () {
      expect(ProfileScope.currentId, 'default');
    });

    test('key() 构造正确的 profile-scoped key', () {
      expect(ProfileScope.key('poem_001'), 'default_poem_001');
      expect(ProfileScope.key('stats'), 'default_stats');
    });

    test('switchTo 切换 profile 后 key 前缀变化', () {
      ProfileScope.switchTo('kid2');
      expect(ProfileScope.currentId, 'kid2');
      expect(ProfileScope.key('poem_001'), 'kid2_poem_001');
    });

    test('reset 恢复到默认 profile', () {
      ProfileScope.switchTo('kid2');
      ProfileScope.reset();
      expect(ProfileScope.currentId, 'default');
    });

    test('不同 profile 的 key 不冲突', () {
      final key1 = ProfileScope.key('poem_001');
      ProfileScope.switchTo('kid2');
      final key2 = ProfileScope.key('poem_001');
      expect(key1, isNot(equals(key2)));
    });
  });
}
