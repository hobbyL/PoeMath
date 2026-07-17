// lib/features/profile/webdav_config_page.dart
//
// 层级：features/profile
// 职责：WebDAV 配置表单页 — 填写服务器地址、账户、密码、远程目录，测试链接后保存。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/webdav_config.dart';
import 'package:poemath/data/providers/repository_providers.dart';

class WebDavConfigPage extends ConsumerStatefulWidget {
  const WebDavConfigPage({super.key, this.existing});

  /// 编辑已有配置时传入；新建时为 null。
  final WebDavConfig? existing;

  @override
  ConsumerState<WebDavConfigPage> createState() => _WebDavConfigPageState();
}

class _WebDavConfigPageState extends ConsumerState<WebDavConfigPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _pathController;
  bool _testing = false;
  bool _saving = false;
  bool _loadingCredentials = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _urlController = TextEditingController(text: e?.url ?? '');
    _usernameController = TextEditingController(text: e?.username ?? '');
    _passwordController = TextEditingController(text: e?.password ?? '');
    _pathController = TextEditingController(
      text: e?.remotePath ?? '/poemath/',
    );

    // 编辑已有配置且凭据为空时，从安全存储加载
    if (e != null && e.username.isEmpty && e.password.isEmpty) {
      _loadCredentials(e);
    }
  }

  Future<void> _loadCredentials(WebDavConfig config) async {
    setState(() => _loadingCredentials = true);
    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final full =
          await settingsRepo.loadWebDavConfigWithCredentials(config);
      if (mounted) {
        _usernameController.text = full.username;
        _passwordController.text = full.password;
      }
    } finally {
      if (mounted) setState(() => _loadingCredentials = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _testing = true);

    final config = _buildConfig();
    final webdav = ref.read(webDavServiceProvider);
    final ok = await webdav.testConnection(config);

    if (!mounted) return;
    setState(() => _testing = false);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '连接成功 ✓' : '连接失败，请检查配置'),
        backgroundColor: ok ? Theme.of(context).semantic.success : null,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final config = _buildConfig();
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.saveWebDavConfig(config);
    ref.invalidate(settingsRepositoryProvider);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  WebDavConfig _buildConfig() {
    return WebDavConfig(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      remotePath: _pathController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑配置' : '添加 WebDAV'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: AnimatedPageBody(
            padding: const EdgeInsets.all(SpacingTokens.lg),
            children: [
              // 名称
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '如：家里 NAS',
                  prefixIcon: Icon(Icons.label_outlined),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入名称' : null,
              ),
              const SizedBox(height: SpacingTokens.md),

              // 服务器地址
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://dav.example.com',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                keyboardType: TextInputType.url,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '请输入服务器地址';
                  final uri = Uri.tryParse(v.trim());
                  if (uri == null || !uri.hasScheme) return '请输入完整地址（含 http/https）';
                  return null;
                },
              ),
              const SizedBox(height: SpacingTokens.md),

              // 账户
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '账户',
                  prefixIcon: Icon(Icons.person_outlined),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入账户' : null,
              ),
              const SizedBox(height: SpacingTokens.md),

              // 密码
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '密码',
                  prefixIcon: Icon(Icons.lock_outlined),
                ),
                obscureText: true,
                validator: (v) =>
                    v == null || v.isEmpty ? '请输入密码' : null,
              ),
              const SizedBox(height: SpacingTokens.md),

              // 远程根目录
              TextFormField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: '远程根目录',
                  hintText: '/poemath/',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入远程目录' : null,
              ),
              const SizedBox(height: SpacingTokens.xl),

              // 按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing || _loadingCredentials
                          ? null
                          : _testConnection,
                      icon: _testing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.wifi_find),
                      label: Text(_testing ? '测试中…' : '测试链接'),
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving || _loadingCredentials
                          ? null
                          : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
