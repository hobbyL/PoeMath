import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_editor_service.dart';
import 'package:poemath/core/services/picture_story_image_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/repositories/picture_story_repository.dart';
import 'package:poemath/features/chinese/expression/providers/picture_story_providers.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_image_view.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_unavailable_view.dart';

class PictureStoryEditorPage extends ConsumerStatefulWidget {
  const PictureStoryEditorPage({super.key, this.promptId});

  final String? promptId;

  @override
  ConsumerState<PictureStoryEditorPage> createState() =>
      _PictureStoryEditorPageState();
}

class _PictureStoryEditorPageState
    extends ConsumerState<PictureStoryEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <PictureStoryEditorField, TextEditingController>{};
  late final PictureStoryRepository _repository;
  late final PictureStoryEditorService _editor;
  StreamSubscription<String>? _profileChanges;
  PictureStoryEditorDraft? _draft;
  String? _loadError;
  String? _error;
  bool _saving = false;
  bool _leaving = false;
  bool _submitted = false;
  bool _allowPop = false;

  bool get _busy => _saving || _leaving || _editor.isPicking;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(pictureStoryRepositoryProvider);
    _editor = ref.read(pictureStoryEditorServiceProvider);
    _loadDraft();
    _editor.addListener(_editorChanged);
    _profileChanges = ProfileScope.changes.listen((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _draft != null) unawaited(_recoverImage());
    });
  }

  void _loadDraft() {
    try {
      final id = widget.promptId;
      final original = id == null ? null : _repository.findPrompt(id);
      if (id != null && original == null) {
        _loadError = '题目不存在，请返回题库选择其他题目。';
        return;
      }
      final draft = _editor.openDraft(original: original);
      // 保存成功后即使暂存清理失败，也不把已发布的新题恢复成新增表单。
      if (draft.original == null && _repository.findPrompt(draft.id) != null) {
        _draft = PictureStoryEditorDraft.create(
          id: draft.id,
          profileId: draft.profileId,
          original: _repository.findPrompt(draft.id),
        );
      } else {
        _draft = draft;
      }
      _loadError = null;
      for (final field in PictureStoryEditorField.values) {
        _controllers[field]?.dispose();
        _controllers[field] = TextEditingController(
          text: _draft!.fields[field],
        );
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '读取题目编辑内容失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      _loadError = '题目或上次编辑内容暂时无法读取，已保存内容仍保留。请重试。';
    }
  }

  Future<void> _recoverImage() async {
    try {
      await _editor.recoverLostImage();
      _editorChanged();
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '恢复题目选图失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = _message(error));
    }
  }

  void _editorChanged() {
    if (!mounted || _draft == null) return;
    try {
      // 选图开始的通知早于快照写入，不能用旧快照覆盖刚填写的文字。
      if (!_editor.isPicking) {
        final saved = _editor.readDraft();
        if (saved?.id == _draft!.id &&
            saved?.matches(_draft!.profileId, _draft!.original?.id) == true) {
          _draft = saved;
          for (final field in PictureStoryEditorField.values) {
            final text = saved!.fields[field]!;
            if (_controllers[field]!.text != text) {
              _controllers[field]!.text = text;
            }
          }
        }
      }
      setState(() {});
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '读取选图恢复结果失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() => _error = _message(error));
    }
  }

  PictureStoryEditorDraft _currentDraft() => _draft!.copyWith(
        fields: {
          for (final entry in _controllers.entries) entry.key: entry.value.text,
        },
      );

  void _textChanged(String _) {
    setState(() {
      _draft = _currentDraft().copyWith(clearMessage: true);
      _error = null;
    });
  }

  Future<void> _chooseImage(PictureStoryImageSource source) async {
    if (_busy) return;
    try {
      await _editor.chooseImage(_currentDraft(), source);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '启动题目选图失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _chooseBuiltin() async {
    if (_busy) return;
    final image = await showModalBottomSheet<PictureStoryImage>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('选择内置插图', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: SpacingTokens.md),
              for (final prompt in PictureStoryCatalog.prompts)
                AppTile(
                  flat: true,
                  iconColor: Theme.of(context).colorScheme.primary,
                  leading: SizedBox(
                    width: SpacingTokens.xxl + SpacingTokens.md,
                    child: PictureStoryImageView(
                      image: prompt.image,
                      preview: true,
                    ),
                  ),
                  title: prompt.title,
                  subtitle: '',
                  onTap: () => Navigator.pop(context, prompt.image),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || image == null) return;
    setState(() {
      _draft = _currentDraft().copyWith(image: image, clearMessage: true);
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy || _draft == null) return;
    setState(() => _submitted = true);
    final valid = _formKey.currentState!.validate();
    final draft = _currentDraft();
    if (!valid || draft.image == null) {
      setState(() => _error = draft.image == null ? '请选择题目图片' : null);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await _repository.savePrompt(
        prompt: draft.toPrompt(),
        original: draft.original,
        profileId: draft.profileId,
        enableForProfile: draft.enableForProfile,
      );
      try {
        await _editor.discardDraft(draft);
      } on Object catch (error, stackTrace) {
        AppLogger.e(
          '题目已保存，临时表单清理失败',
          tag: 'PictureStory',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      if (widget.promptId != null && context.canPop()) {
        context.pop();
      } else {
        context.replace(AppRoutes.pictureStoryDetailOf(saved.id));
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '保存看图说话题目失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestExit() async {
    if (_busy) return;
    setState(() => _leaving = true);
    try {
      final draft = _draft == null ? null : _currentDraft();
      if (draft?.hasChanges == true) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('放弃未保存的修改？'),
            content: const Text('离开后，本次填写的内容不会保存。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续编辑'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('放弃修改'),
              ),
            ],
          ),
        );
        if (!mounted || discard != true) return;
      }
      if (draft != null) await _editor.discardDraft(draft);
      if (!mounted) return;
      setState(() => _allowPop = true);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.pictureStoryManagement);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '退出题目编辑失败',
        tag: 'PictureStory',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '暂时无法清理编辑内容，请重试');
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  static String _message(Object error) => switch (error) {
        FormatException(:final message) => message,
        PictureStoryImageException(:final message) => message,
        ParentAccessDenied() => error.toString(),
        _ => '保存失败，填写的内容已保留。请检查设备存储空间后重试。',
      };

  @override
  void dispose() {
    _editor.removeListener(_editorChanged);
    _profileChanges?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = _draft;
    final profileChanged =
        draft != null && draft.profileId != ProfileScope.currentId;
    return PopScope<void>(
      canPop: _allowPop || (!_busy && draft?.hasChanges != true),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestExit());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.promptId == null ? '新增题目' : '编辑题目'),
          leading: IconButton(
            tooltip: '返回',
            icon: const BackButtonIcon(),
            onPressed: _busy ? null : _requestExit,
          ),
        ),
        body: draft == null || profileChanged
            ? PictureStoryUnavailableView(
                message: profileChanged ? '孩子档案已切换，请返回题库重新打开编辑。' : _loadError!,
                onRetry: profileChanged ? null : () => setState(_loadDraft),
              )
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: ResponsiveLayout.wideBreakpoint,
                      ),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: _submitted
                            ? AutovalidateMode.onUserInteraction
                            : AutovalidateMode.disabled,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error ?? draft.message
                                case final message?) ...[
                              Text(
                                message,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: SpacingTokens.md),
                            ],
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final image = _imageSection(theme, draft);
                                final basics = _basicSection(theme, draft);
                                if (constraints.maxWidth <
                                    ResponsiveLayout.mediumBreakpoint) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      image,
                                      const SizedBox(height: SpacingTokens.md),
                                      basics,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: image),
                                    const SizedBox(width: SpacingTokens.md),
                                    Expanded(child: basics),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: SpacingTokens.md),
                            ColoredCard(
                              color: theme.colorScheme.primary,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '练习内容',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: SpacingTokens.md),
                                  _field(PictureStoryEditorField.questions),
                                  const SizedBox(height: SpacingTokens.md),
                                  _field(PictureStoryEditorField.sceneFacts),
                                  const SizedBox(height: SpacingTokens.md),
                                  _field(PictureStoryEditorField.goals),
                                  const SizedBox(height: SpacingTokens.md),
                                  _field(PictureStoryEditorField.reference),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        bottomNavigationBar: draft == null || profileChanged
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_saving ? '正在保存…' : '保存题目'),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _imageSection(ThemeData theme, PictureStoryEditorDraft draft) =>
      ColoredCard(
        color: theme.colorScheme.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('题目图片', style: theme.textTheme.titleMedium),
            const SizedBox(height: SpacingTokens.sm),
            if (draft.image != null) ...[
              PictureStoryImageView(image: draft.image!),
              const SizedBox(height: SpacingTokens.sm),
            ] else
              const Text('选择一张图片，让孩子观察后讲一讲。'),
            if (_editor.isPicking) ...[
              const SizedBox(height: SpacingTokens.sm),
              const Text('正在获取图片，返回后可继续编辑。'),
            ],
            AppTile(
              flat: true,
              iconColor: theme.colorScheme.primary,
              icon: Icons.draw_outlined,
              title: '使用内置插图',
              subtitle: '',
              onTap: _busy ? null : _chooseBuiltin,
            ),
            if (_editor.supportsGallery)
              AppTile(
                flat: true,
                iconColor: theme.colorScheme.primary,
                icon: Icons.photo_library_outlined,
                title: '从相册选择',
                subtitle: '',
                onTap: _busy
                    ? null
                    : () => _chooseImage(PictureStoryImageSource.gallery),
              ),
            AppTile(
              flat: true,
              iconColor: theme.colorScheme.primary,
              icon: Icons.folder_open_outlined,
              title: '从文件选择',
              subtitle: '',
              onTap: _busy
                  ? null
                  : () => _chooseImage(PictureStoryImageSource.file),
            ),
            if (_editor.supportsCamera)
              AppTile(
                flat: true,
                iconColor: theme.colorScheme.primary,
                icon: Icons.camera_alt_outlined,
                title: '拍照',
                subtitle: '',
                onTap: _busy
                    ? null
                    : () => _chooseImage(PictureStoryImageSource.camera),
              ),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              '图片保存在本机。使用已配置的 AI 评价时，会发送题图和表达文字。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );

  Widget _basicSection(ThemeData theme, PictureStoryEditorDraft draft) =>
      ColoredCard(
        color: theme.colorScheme.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('基本信息', style: theme.textTheme.titleMedium),
            const SizedBox(height: SpacingTokens.md),
            _field(PictureStoryEditorField.title),
            const SizedBox(height: SpacingTokens.md),
            DropdownButtonFormField<PictureStoryLevel>(
              initialValue: draft.level,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '难度'),
              items: [
                for (final level in PictureStoryLevel.values)
                  DropdownMenuItem(value: level, child: Text(level.label)),
              ],
              onChanged: _busy
                  ? null
                  : (level) {
                      if (level != null) {
                        setState(
                          () => _draft = _currentDraft().copyWith(level: level),
                        );
                      }
                    },
            ),
            const SizedBox(height: SpacingTokens.md),
            _field(PictureStoryEditorField.theme),
            if (draft.original == null) ...[
              const SizedBox(height: SpacingTokens.md),
              AppTile(
                flat: true,
                iconColor: theme.colorScheme.primary,
                title: '为当前孩子启用',
                subtitle: '其他孩子可以在题库中自行开启。',
                trailing: Switch(
                  value: draft.enableForProfile,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _draft = _currentDraft()
                                .copyWith(enableForProfile: value);
                          }),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _field(PictureStoryEditorField field) {
    final (label, maxLength, multiline, required) = switch (field) {
      PictureStoryEditorField.title => (
          '题目标题',
          PictureStoryPrompt.maxTitleLength,
          false,
          true
        ),
      PictureStoryEditorField.theme => (
          '主题（选填）',
          PictureStoryPrompt.maxThemeLength,
          false,
          false
        ),
      PictureStoryEditorField.questions => ('引导问题', null, true, true),
      PictureStoryEditorField.sceneFacts => ('观察提示（选填）', null, true, false),
      PictureStoryEditorField.goals => ('练习目标（选填）', null, true, false),
      PictureStoryEditorField.reference => (
          '参考表达（选填）',
          PictureStoryPrompt.maxReferenceLength,
          true,
          false
        ),
    };
    return TextFormField(
      key: ValueKey('picture-story-${field.name}'),
      controller: _controllers[field],
      enabled: !_busy,
      minLines: multiline ? 3 : 1,
      maxLines: null,
      maxLength: maxLength,
      keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
      textInputAction:
          multiline ? TextInputAction.newline : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        helperText: maxLength == null
            ? '每行一条，最多 ${PictureStoryPrompt.maxLines} 条'
            : null,
      ),
      onChanged: _textChanged,
      validator: (value) {
        try {
          if (maxLength == null) {
            PictureStoryPrompt.checkedLines(
              (value ?? '').split('\n'),
              label: label,
              required: required,
            );
          } else {
            PictureStoryPrompt.checkedText(
              value ?? '',
              label: label,
              maxLength: maxLength,
              required: required,
            );
          }
          return null;
        } on FormatException catch (error) {
          return error.message;
        }
      },
    );
  }
}
