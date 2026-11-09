import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/models/profile_nickname.dart';
import 'package:poemath/features/profile/providers/profile_nickname_providers.dart';

class ProfileNicknameButton extends ConsumerStatefulWidget {
  const ProfileNicknameButton({super.key, required this.foreground});

  final Color foreground;

  @override
  ConsumerState<ProfileNicknameButton> createState() =>
      _ProfileNicknameButtonState();
}

class _ProfileNicknameButtonState extends ConsumerState<ProfileNicknameButton> {
  bool _editing = false;

  Future<void> _edit() async {
    if (_editing) return;
    final profileId = ProfileScope.currentId;
    final repository = ref.read(profileNicknameRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _editing = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => _NicknameDialog(
          initialValue: repository.read(profileId) ?? '',
          onSave: (name) => repository.save(profileId, name),
          onFailure: () {
            if (!messenger.mounted) return;
            messenger.showSnackBar(const SnackBar(content: Text('昵称保存失败，请重试')));
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(profileNicknameProvider);
    return Tooltip(
      message: '修改昵称',
      child: TextButton(
        key: const ValueKey('profile-nickname-edit'),
        onPressed: _editing ? null : _edit,
        style: TextButton.styleFrom(
          foregroundColor: widget.foreground,
          disabledForegroundColor: widget.foreground,
          minimumSize: const Size(0, SpacingTokens.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
          textStyle: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        child: Text(
          name,
          key: const ValueKey('profile-nickname-label'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({
    required this.initialValue,
    required this.onSave,
    required this.onFailure,
  });

  final String initialValue;
  final Future<void> Function(String) onSave;
  final VoidCallback onFailure;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final String name;
    try {
      name = ProfileNickname.normalize(_controller.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await widget.onSave(name);
      if (mounted) Navigator.pop(context);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '昵称保存失败',
        tag: 'ProfileNickname',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败，请重试';
      });
      widget.onFailure();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('修改昵称'),
      content: SingleChildScrollView(
        child: TextField(
          key: const ValueKey('profile-nickname-input'),
          controller: _controller,
          autofocus: true,
          enabled: !_saving,
          maxLength: ProfileNickname.maxLength,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: '昵称',
            hintText: ProfileNickname.defaultName,
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}
