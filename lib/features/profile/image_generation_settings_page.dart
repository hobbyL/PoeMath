import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/image_generation_config.dart';
import 'package:poemath/data/providers/repository_providers.dart';

class ImageGenerationSettingsPage extends ConsumerStatefulWidget {
  const ImageGenerationSettingsPage({super.key});
  @override
  ConsumerState<ImageGenerationSettingsPage> createState() =>
      _ImageGenerationSettingsPageState();
}

class _ImageGenerationSettingsPageState
    extends ConsumerState<ImageGenerationSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  bool _saving = false;
  bool _hasKey = false;
  bool _clearKey = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final config = ref.read(settingsRepositoryProvider).imageGenerationProvider;
    _name.text = config?.name ?? '';
    _baseUrl.text = config?.baseUrl ?? '';
    _model.text = config?.model ?? '';
    _readKeyStatus();
  }

  Future<void> _readKeyStatus() async {
    try {
      final key = await ref
          .read(secureCredentialStoreProvider)
          .readImageGenerationApiKey();
      if (mounted) setState(() => _hasKey = key?.isNotEmpty == true);
    } on Object {
      if (mounted) setState(() => _error = '密钥状态暂时无法读取，请重试');
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(settingsRepositoryProvider).saveImageGenerationConfig(
            provider: ImageGenerationProviderConfig(
              name: _name.text,
              baseUrl: _baseUrl.text,
              model: _model.text,
            ),
            apiKey: _key.text,
            clearApiKey: _clearKey,
          );
      if (!mounted) return;
      _key.clear();
      _clearKey = false;
      await _readKeyStatus();
      if (mounted && ParentAccessService.instance.isUnlocked) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('生图设置已保存')));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : error is ParentAccessDenied
                  ? error.toString()
                  : '生图设置保存失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('图片生成设置')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: AnimatedPageBody(
            children: [
              ColoredCard(
                color: theme.colorScheme.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('生图服务', style: theme.textTheme.titleMedium),
                    const SizedBox(height: SpacingTokens.sm),
                    const Text(
                      '为看图说话生成配图，支持 OpenAI Images 兼容接口。题目内容使用“看图说话出题”场景中的大模型。',
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    TextFormField(
                      controller: _name,
                      enabled: !_saving,
                      maxLength: 80,
                      decoration: const InputDecoration(labelText: '厂商名称（选填）'),
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    TextFormField(
                      controller: _baseUrl,
                      enabled: !_saving,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '服务地址',
                        hintText: 'https://api.example.com/v1',
                      ),
                      validator: (value) {
                        try {
                          ImageGenerationProviderConfig(
                            name: '',
                            baseUrl: value ?? '',
                            model: 'check',
                          ).normalized();
                          return null;
                        } on FormatException catch (error) {
                          return error.message;
                        }
                      },
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    TextFormField(
                      controller: _model,
                      enabled: !_saving,
                      maxLength: 200,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: '生图模型名称'),
                      validator: (value) =>
                          value?.trim().isNotEmpty == true ? null : '请输入生图模型名称',
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    TextFormField(
                      controller: _key,
                      enabled: !_saving && !_clearKey,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        helperText:
                            _hasKey ? '已保存密钥；留空沿用，填写后替换' : '密钥只保存在设备安全存储中',
                      ),
                      validator: (value) =>
                          (value?.length ?? 0) > 8192 ? '密钥过长，请检查输入' : null,
                    ),
                  ],
                ),
              ),
              if (_hasKey) ...[
                const SizedBox(height: SpacingTokens.sm),
                AppTile(
                  icon: Icons.key_off_outlined,
                  iconColor: theme.colorScheme.primary,
                  title: '清除已保存的密钥',
                  subtitle: '保存设置后生效',
                  trailing: Switch(
                    value: _clearKey,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _clearKey = value),
                  ),
                ),
              ],
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
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '正在保存…' : '保存设置'),
          ),
        ),
      ),
    );
  }
}
