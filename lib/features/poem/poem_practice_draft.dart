import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/math/practice_clock.dart';

/// 每个练习页面捕获独立仓储实例，旧页面不能借新页面的所有权写回。
final poemPracticeDraftRepositoryFactoryProvider =
    Provider<PracticeDraftRepository Function()>(
      (ref) => PracticeDraftRepository.new,
    );

/// 诗词草稿的身份包含模式参数，全文听写与错句练习互不覆盖。
class PoemDraftIdentity {
  PoemDraftIdentity({
    required this.kind,
    required Poem poem,
    required this.variant,
    required this.route,
    required this.label,
  }) : poemId = poem.id,
       title = poem.title,
       fingerprint = sha256
           .convert(
             utf8.encode(
               jsonEncode([
                 poem.id,
                 poem.title,
                 poem.author,
                 poem.dynasty,
                 poem.content,
                 poem.pinyin,
               ]),
             ),
           )
           .toString();

  final String kind;
  final String poemId;
  final String title;
  final String variant;
  final String route;
  final String label;
  final String fingerprint;
  String get scope => jsonEncode([poemId, variant]);
}

/// 只管理保存、所有权和前台时钟；随机题组与作答由各模式完整序列化。
class PoemPracticeDraft extends ChangeNotifier {
  PoemPracticeDraft({
    required this.identity,
    required this.capture,
    PracticeDraftRepository? repository,
  }) : repository = repository ?? PracticeDraftRepository() {
    clock.onPause = () {
      unawaited(save());
    };
  }

  final PoemDraftIdentity identity;
  final Map<String, dynamic> Function() capture;
  final PracticeDraftRepository repository;
  final clock = PracticeClock();
  final _profileId = ProfileScope.currentId;
  final _profileRevision = ProfileScope.revision;
  Timer? _timer;
  bool _active = false;
  bool _claimed = false;
  bool _disposed = false;
  bool _exiting = false;
  bool restored = false;
  String? error;

  void assertCurrent() {
    repository.assertCurrent();
    if (_claimed) repository.assertOwner(identity.kind, scope: identity.scope);
    if (_profileId != ProfileScope.currentId ||
        _profileRevision != ProfileScope.revision) {
      throw StateError('孩子档案已切换，请重新进入练习');
    }
  }

  /// 未选择继续时不写入草稿；坏版本/内容变化必须显式重开。
  Future<bool> open(
    BuildContext context,
    void Function(Map<String, dynamic>) restore,
  ) async {
    Map<String, dynamic>? data;
    var invalid = false;
    try {
      data = repository.get(identity.kind, scope: identity.scope);
      if (data != null &&
          (data['poemVersion'] != 1 ||
              data['fingerprint'] != identity.fingerprint ||
              data['state'] is! Map<String, dynamic> ||
              data['sessionId'] is! String ||
              (data['sessionId'] as String).isEmpty ||
              data['elapsedMs'] is! int ||
              (data['elapsedMs'] as int) < 0 ||
              (data['state'] as Map<String, dynamic>)['activityId'] !=
                  data['sessionId'])) {
        throw const FormatException('诗词草稿版本或题目内容已变化');
      }
    } on Object {
      invalid = true;
    }
    while (data != null || invalid) {
      if (!context.mounted) return false;
      final choice = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(invalid ? '这份草稿无法继续' : '继续上次${identity.label}？'),
          content: Text(
            invalid ? '诗词内容已变化或草稿无法读取。可以保留草稿返回，或重新开始。' : '将保留原题、已答内容和练习进度。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('开始新练习'),
            ),
            if (!invalid)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续上次'),
              ),
          ],
        ),
      );
      if (!context.mounted || choice == null) return false;
      if (!choice) {
        try {
          assertCurrent();
          await repository.remove(identity.kind, scope: identity.scope);
        } on Object catch (failure, stack) {
          _report(failure, stack);
          return false;
        }
        data = null;
        break;
      }
      try {
        restore(data!['state'] as Map<String, dynamic>);
        restored = true;
        break;
      } on Object {
        invalid = true;
      }
    }
    assertCurrent();
    repository.claim(identity.kind, scope: identity.scope);
    _claimed = true;
    _active = true;
    clock.start(elapsedMilliseconds: restored ? data!['elapsedMs'] as int : 0);
    return true;
  }

  void changed() {
    if (!_active || _disposed) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 200), () {
      unawaited(save());
    });
  }

  Future<void> saveOrThrow() async {
    _timer?.cancel();
    if (!_active) return;
    assertCurrent();
    // 仓储立即编码冻结，之后的输入或下一句不改变本次快照。
    final state = capture();
    await repository.save(identity.kind, {
      'poemVersion': 1,
      'poemId': identity.poemId,
      'title': identity.title,
      'label': identity.label,
      'route': identity.route,
      'fingerprint': identity.fingerprint,
      'sessionId': state['activityId'],
      'elapsedMs': clock.elapsedMilliseconds,
      'state': state,
    }, scope: identity.scope);
    if (error != null && !_disposed) {
      error = null;
      notifyListeners();
    }
  }

  Future<bool> save() async {
    try {
      await saveOrThrow();
      return true;
    } on Object catch (failure, stack) {
      _report(failure, stack);
      return false;
    }
  }

  void _report(Object failure, StackTrace stack) {
    AppLogger.e(
      '诗词练习草稿保存失败',
      tag: 'PoemDraft',
      error: failure,
      stackTrace: stack,
    );
    if (!_disposed) {
      error = '进度保存失败，请重试后再离开';
      notifyListeners();
    }
  }

  Future<void> exit(BuildContext context) async {
    if (_exiting) return;
    _exiting = true;
    try {
      if (await save() && context.mounted) {
        _active = false;
        Navigator.of(context).pop();
      }
    } finally {
      _exiting = false;
    }
  }

  Future<void> complete(String activityId) async {
    _timer?.cancel();
    assertCurrent();
    _active = false;
    clock.finish();
    try {
      await repository.remove(
        identity.kind,
        scope: identity.scope,
        sessionId: activityId,
      );
    } on Object {
      _active = true;
      rethrow;
    }
  }

  void restart() {
    _claimed = false;
    assertCurrent();
    repository.claim(identity.kind, scope: identity.scope);
    _claimed = true;
    clock.start();
    _active = true;
    changed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // 强制卸载也冻结最后输入；普通返回已 await save，失败则留在页面。
    if (_active) unawaited(save());
    _disposed = true;
    clock.dispose();
    super.dispose();
  }
}

class PoemDraftSaveStatus extends StatelessWidget {
  const PoemDraftSaveStatus({
    super.key,
    required this.draft,
    required this.child,
  });
  final PoemPracticeDraft? draft;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (draft == null) return child;
    return ListenableBuilder(
      listenable: draft!,
      builder: (context, _) => Column(
        children: [
          if (draft!.error != null)
            Padding(
              padding: const EdgeInsets.all(SpacingTokens.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      draft!.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(onPressed: draft!.save, child: const Text('重试保存')),
                ],
              ),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
