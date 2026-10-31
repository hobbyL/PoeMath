import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';

/// 弹窗、文件选择或排队写入后重新校验，不重复弹出解锁提示。
void assertParentAccess(BuildContext context, {ParentAccessService? service}) {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) {
    throw const ParentAccessDenied();
  }
  (service ?? ParentAccessService.instance).assertAllowed();
}

Future<bool> ensureParentAccess(
  BuildContext context, {
  ParentAccessService? service,
}) async {
  final access = service ?? ParentAccessService.instance;
  if (!_isCurrentPage(context)) return false;
  final route = ModalRoute.of(context);
  final pending = _requests[access];
  if (pending != null &&
      pending.context.mounted &&
      identical(route, pending.route)) {
    final result = await pending.done.future;
    if (!context.mounted || !_isCurrentPage(context)) return false;
    if (result && access.isUnlocked) return true;
    return false;
  }
  final request = _ParentAccessRequest(route, context);
  _requests[access] = request;
  var allowed = false;
  try {
    allowed = await _requestParentAccess(context, access);
    return allowed;
  } on Object {
    if (context.mounted) _showStorageError(context);
    return false;
  } finally {
    if (identical(_requests[access], request)) _requests[access] = null;
    request.done.complete(allowed);
  }
}

final _requests = Expando<_ParentAccessRequest>();

class _ParentAccessRequest {
  _ParentAccessRequest(this.route, this.context);
  final ModalRoute<dynamic>? route;
  final BuildContext context;
  final done = Completer<bool>();
}

bool _isCurrentPage(BuildContext context) =>
    context.mounted &&
    ModalRoute.of(context)?.isCurrent != false &&
    (WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

void _showStorageError(BuildContext context) {
  if (!_isCurrentPage(context)) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text('安全存储暂时无法读取，家长区保持锁定，请稍后重试')),
  );
}

Future<void> _openParentSetup(BuildContext context) async {
  if (!_isCurrentPage(context)) return;
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('设置与管理需要家长密码，请先前往家长设置')),
    );
    return;
  }
  if (router.routerDelegate.currentConfiguration.lastOrNull?.matchedLocation ==
      AppRoutes.parentProtection) {
    return;
  }
  await router.push<void>(AppRoutes.parentProtection, extra: true);
}

Future<bool> _requestParentAccess(
  BuildContext context,
  ParentAccessService access,
) async {
  access.observeLifecycle();
  await access.initialize();
  if (!context.mounted || !_isCurrentPage(context)) return false;
  if (access.needsResetNotice) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('此设备没有原家长验证记录，请重新设置家长密码')),
    );
  }
  if (!access.enabled) {
    if (access.canSetPin) await _openParentSetup(context);
    return false;
  }
  if (access.isUnlocked) return true;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ParentUnlockDialog(access),
  );
  if (!context.mounted || !_isCurrentPage(context)) return false;
  if (!access.enabled && access.canSetPin) {
    await _openParentSetup(context);
    return false;
  }
  return result == true && access.isUnlocked;
}

class _ParentUnlockDialog extends StatefulWidget {
  const _ParentUnlockDialog(this.service);
  final ParentAccessService service;
  @override
  State<_ParentUnlockDialog> createState() => _ParentUnlockDialogState();
}

class _ParentUnlockDialogState extends State<_ParentUnlockDialog> {
  final _input = TextEditingController();
  bool _recovery = false;
  bool _busy = false;
  String? _error;
  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final success = await widget.service.authenticate(
        _input.text.trim(),
        recovery: _recovery,
        isCurrent: () => _isCurrentPage(context),
      );
      // 锁定可先关闭此弹窗；晚到的验证只能关闭自己的当前路由。
      if (!mounted || !_isCurrentPage(context)) return;
      if (success) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _error = _recovery ? '恢复码不正确' : 'PIN 不正确');
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_recovery ? '使用一次性恢复码' : '家长解锁'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _recovery ? '恢复成功后需重新设置家长密码，此恢复码随即失效。' : '解锁有效 2 分钟，切到后台会立即锁定。',
              ),
              const SizedBox(height: SpacingTokens.md),
              TextField(
                controller: _input,
                autofocus: true,
                enabled: !_busy,
                obscureText: !_recovery,
                keyboardType:
                    _recovery ? TextInputType.text : TextInputType.number,
                decoration: InputDecoration(
                  labelText: _recovery ? '恢复码' : '6 位数字 PIN',
                  errorText: _error,
                ),
                onSubmitted: (_) => _unlock(),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _recovery = !_recovery;
                          _input.clear();
                          _error = null;
                        }),
                child: Text(_recovery ? '使用 PIN' : '忘记 PIN，使用恢复码'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _busy ? null : _unlock,
            child: Text(_busy ? '验证中…' : '解锁'),
          ),
        ],
      );
}

/// 同时用于 GoRouter 和 Navigator 页面，短时授权失效时移除可编辑页面。
class ParentAccessBoundary extends StatefulWidget {
  const ParentAccessBoundary({
    super.key,
    required this.child,
    this.service,
    this.allowSetup = false,
  });
  final Widget child;
  final ParentAccessService? service;

  /// 仅独立家长设置路由使用；无 PIN 时只允许建立密码。
  final bool allowSetup;
  @override
  State<ParentAccessBoundary> createState() => _ParentAccessBoundaryState();
}

class _ParentAccessBoundaryState extends State<ParentAccessBoundary> {
  static final _boundaries = <_ParentAccessBoundaryState>[];
  bool _ready = false;
  bool _requesting = false;
  bool _scheduled = false;
  bool _setupAttempted = false;
  bool _storageFailed = false;
  ParentAccessService get _access =>
      widget.service ?? ParentAccessService.instance;

  bool get _canShowChild =>
      _ready &&
      !_requesting &&
      (_access.isUnlocked ||
          (widget.allowSetup && !_access.enabled && _access.canSetPin));

  bool get _mustLock =>
      !_access.isUnlocked &&
      !(widget.allowSetup && _ready && !_access.enabled && _access.canSetPin);
  @override
  void initState() {
    super.initState();
    _boundaries.add(this);
    _access.observeLifecycle();
    _access.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready ||
        (!widget.allowSetup && !_access.enabled && !_setupAttempted)) {
      _scheduleRequest();
    }
  }

  void _scheduleRequest() {
    if (_scheduled || _requesting) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && _isCurrentPage(context)) {
        unawaited(_requestAccess());
      }
    });
  }

  Future<void> _requestAccess() async {
    if (_requesting || !_isCurrentPage(context)) return;
    setState(() {
      _requesting = true;
      _storageFailed = false;
      if (!_access.enabled && !widget.allowSetup) _setupAttempted = true;
    });
    try {
      if (widget.allowSetup) {
        await _access.initialize();
        if (!mounted) return;
        _ready = true;
        if (_access.enabled && !_access.isUnlocked) {
          await ensureParentAccess(context, service: _access);
        }
      } else {
        await ensureParentAccess(context, service: _access);
        if (mounted) {
          _ready = true;
          _storageFailed = _access.hasStorageError;
        }
      }
    } on Object {
      if (mounted) {
        _storageFailed = true;
        _showStorageError(context);
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_access.enabled) {
      _setupAttempted = false;
    } else if (_requesting && !widget.allowSetup) {
      _setupAttempted = true;
    }
    setState(() {});
    if (_mustLock && _boundaries.lastOrNull == this) {
      final route = ModalRoute.of(context);
      if (route?.isActive == true && route?.isCurrent == false) {
        Navigator.of(context)
            .popUntil((candidate) => identical(candidate, route));
      }
    }
    if (_ready &&
        !widget.allowSetup &&
        !_access.enabled &&
        !_setupAttempted &&
        _isCurrentPage(context)) {
      _scheduleRequest();
    }
  }

  void _leave() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(AppRoutes.profile);
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  void dispose() {
    _boundaries.remove(this);
    _access.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_canShowChild) return widget.child;
    final setup = !_access.enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('家长保护')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: SpacingTokens.md),
              Text(
                _storageFailed
                    ? '家长设置暂时无法读取，请稍后重试'
                    : setup
                        ? '设置与管理需要家长密码，请先设置'
                        : '请由家长解锁后继续',
              ),
              const SizedBox(height: SpacingTokens.md),
              FilledButton(
                onPressed: _requesting ? null : _requestAccess,
                child: Text(
                  _storageFailed
                      ? '重试'
                      : setup
                          ? '设置家长密码'
                          : '家长解锁',
                ),
              ),
              TextButton(
                onPressed: _leave,
                child: const Text('返回个人页'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
