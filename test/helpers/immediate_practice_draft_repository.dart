import 'package:poemath/data/repositories/practice_draft_repository.dart';

/// 已有结算单测的即时存储替身。真实落盘/恢复由 poem_practice_resume_test 覆盖。
class ImmediatePracticeDraftRepository extends PracticeDraftRepository {
  @override
  void assertOwner(String kind, {required String scope}) => assertCurrent();
  @override
  Map<String, dynamic>? get(String kind, {String? scope}) => null;
  @override
  Future<void> save(
    String kind,
    Map<String, dynamic> data, {
    String? scope,
  }) async {}
  @override
  Future<void> remove(String kind, {String? sessionId, String? scope}) async {}
}
