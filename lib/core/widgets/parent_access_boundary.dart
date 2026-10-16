import 'package:flutter/material.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';

Future<bool> ensureParentAccess(BuildContext context,
    {ParentAccessService? service,}) async {
  final access = service ?? ParentAccessService.instance;
  access.observeLifecycle();
  try {
    await access.initialize();
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('安全存储暂时无法读取，家长区保持锁定，请稍后重试')),);
    }
    return false;
  }
  if (!context.mounted) return false;
  if (access.needsResetNotice) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此设备没有原家长验证记录，保护已重设，请重新设置 PIN')),);
  }
  if (access.isUnlocked) return true;
  final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ParentUnlockDialog(access),);
  return result == true && context.mounted && access.isUnlocked;
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
      final success = await widget.service
          .authenticate(_input.text.trim(), recovery: _recovery);
      if (!mounted) return;
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_recovery
              ? '恢复成功将关闭保护并使此恢复码失效，请随后重新设置 PIN。'
              : '解锁有效 2 分钟，切到后台会立即锁定。',),
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
                  errorText: _error,),
              onSubmitted: (_) => _unlock(),),
          TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _recovery = !_recovery;
                        _input.clear();
                        _error = null;
                      }),
              child: Text(_recovery ? '使用 PIN' : '忘记 PIN，使用恢复码'),),
        ],),),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('取消'),),
          FilledButton(
              onPressed: _busy ? null : _unlock,
              child: Text(_busy ? '验证中…' : '解锁'),),
        ],
      );
}

/// 同时用于 GoRouter 和 Navigator 页面，短时授权失效时移除可编辑页面。
class ParentAccessBoundary extends StatefulWidget {
  const ParentAccessBoundary({super.key, required this.child, this.service});
  final Widget child;
  final ParentAccessService? service;
  @override
  State<ParentAccessBoundary> createState() => _ParentAccessBoundaryState();
}

class _ParentAccessBoundaryState extends State<ParentAccessBoundary> {
  static final _boundaries = <_ParentAccessBoundaryState>[];
  ParentAccessService get _access =>
      widget.service ?? ParentAccessService.instance;
  @override
  void initState() {
    super.initState();
    _boundaries.add(this);
    _access.observeLifecycle();
    _access.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_access.isUnlocked) {
        ensureParentAccess(context, service: _access);
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!_access.isUnlocked && _boundaries.lastOrNull == this) {
      final route = ModalRoute.of(context);
      if (route != null) {
        Navigator.of(context)
            .popUntil((candidate) => identical(candidate, route));
      }
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
    if (_access.isUnlocked) return widget.child;
    return Scaffold(
        appBar: AppBar(title: const Text('家长保护')),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.lg),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: SpacingTokens.md),
                  const Text('请由家长解锁后继续'),
                  const SizedBox(height: SpacingTokens.md),
                  FilledButton(
                      onPressed: () =>
                          ensureParentAccess(context, service: _access),
                      child: const Text('家长解锁'),),
                ],),),),);
  }
}
