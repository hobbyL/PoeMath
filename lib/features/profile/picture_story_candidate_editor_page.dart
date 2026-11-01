import 'dart:async';

import 'package:flutter/material.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_generation_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/profile/widgets/picture_story_text_field.dart';

class PictureStoryCandidateEditorPage extends StatefulWidget {
  const PictureStoryCandidateEditorPage({
    super.key,
    required this.service,
    required this.session,
  });
  final PictureStoryGenerationService service;
  final PictureStoryGenerationEditSession session;
  @override
  State<PictureStoryCandidateEditorPage> createState() =>
      _PictureStoryCandidateEditorPageState();
}

class _PictureStoryCandidateEditorPageState
    extends State<PictureStoryCandidateEditorPage> {
  final _form = GlobalKey<FormState>();
  final _controllers = <PictureStoryEditorField, TextEditingController>{};
  late PictureStoryLevel _level;
  late final PictureStoryEditorDraft _baseEdit;
  bool _available = true;
  late final int _profileRevision;
  StreamSubscription<String>? _profileChanges;
  Future<void> _pending = Future<void>.value();
  String? _error;
  bool _saving = false;
  bool _allowPop = false;
  bool get _sameProfile =>
      ProfileScope.currentId == widget.session.candidate.edit.profileId &&
      ProfileScope.revision == _profileRevision;

  @override
  void initState() {
    super.initState();
    PictureStoryEditorDraft? saved;
    try {
      saved = widget.service.readEdit(widget.session);
    } on Object {
      saved = null;
    }
    _available = saved != null;
    _baseEdit = saved ?? widget.session.candidate.edit;
    if (!_available) _error = '草稿已变化，请返回预览页';
    final edit = _baseEdit;
    _level = edit.level;
    _profileRevision = ProfileScope.revision;
    for (final field in PictureStoryEditorField.values) {
      _controllers[field] = TextEditingController(text: edit.fields[field]);
    }
    _profileChanges = ProfileScope.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  PictureStoryEditorDraft _snapshot() => _baseEdit.copyWith(
        level: _level,
        fields: {for (final e in _controllers.entries) e.key: e.value.text},
      );

  Future<void> _persist(PictureStoryEditorDraft snapshot) {
    final service = widget.service;
    final session = widget.session;
    final operation = _pending.then((_) => service.saveEdit(session, snapshot));
    _pending = operation.then<void>(
      (_) {
        if (mounted) setState(() => _error = null);
      },
      onError: (Object _) {
        if (mounted) setState(() => _error = '修改暂未保存，请重试并检查存储空间');
      },
    );
    return operation;
  }

  void _changed(String _) {
    unawaited(_persist(_snapshot()).catchError((Object _) {}));
  }

  Future<void> _leave({bool validate = false}) async {
    if (_saving) return;
    if (!_available) {
      setState(() => _allowPop = true);
      Navigator.pop(context);
      return;
    }
    if (validate && !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (validate) {
        ParentAccessService.instance.assertAllowed();
        if (!_sameProfile) throw const FormatException('孩子档案已切换，请返回题库');
      }
      await _persist(_snapshot());
      if (!mounted) return;
      if (validate) ParentAccessService.instance.assertAllowed();
      setState(() => _allowPop = true);
      Navigator.pop(context);
    } on Object {
      if (mounted) setState(() => _error = '修改暂未保存，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    // 家长保护移除页面时仍可暂存已经输入的原始内容，不发布题目。
    if (_available) unawaited(_persist(_snapshot()).catchError((Object _) {}));
    unawaited(_profileChanges?.cancel());
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final edit = _baseEdit;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('编辑生成题目')),
        body: SafeArea(
          child: Form(
            key: _form,
            child: AnimatedPageBody(
              children: [
                if (!_sameProfile) ...[
                  Text(
                    '孩子档案已切换，请返回题库。',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                ],
                ColoredCard(
                  color: theme.colorScheme.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PictureStoryImageView(image: edit.image!),
                      const SizedBox(height: SpacingTokens.md),
                      PictureStoryTextField(
                        field: PictureStoryEditorField.title,
                        controller:
                            _controllers[PictureStoryEditorField.title]!,
                        enabled: !_saving && _sameProfile && _available,
                        onChanged: _changed,
                      ),
                      const SizedBox(height: SpacingTokens.md),
                      DropdownButtonFormField<PictureStoryLevel>(
                        initialValue: _level,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '难度'),
                        items: [
                          for (final level in PictureStoryLevel.values)
                            DropdownMenuItem(
                              value: level,
                              child: Text(level.label),
                            ),
                        ],
                        onChanged: _saving || !_sameProfile || !_available
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _level = value);
                                  _changed('');
                                }
                              },
                      ),
                      for (final field in PictureStoryEditorField.values.where(
                        (f) => f != PictureStoryEditorField.title,
                      )) ...[
                        const SizedBox(height: SpacingTokens.md),
                        PictureStoryTextField(
                          field: field,
                          controller: _controllers[field]!,
                          enabled: !_saving && _sameProfile && _available,
                          onChanged: _changed,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: SpacingTokens.md),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: FilledButton(
              onPressed: _saving || !_sameProfile || !_available
                  ? null
                  : () => _leave(validate: true),
              child: Text(_saving ? '正在保存…' : '保存修改'),
            ),
          ),
        ),
      ),
    );
  }
}
