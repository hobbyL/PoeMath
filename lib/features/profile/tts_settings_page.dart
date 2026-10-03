// lib/features/profile/tts_settings_page.dart
//
// 层级：features/profile
// 职责：TTS 音频设置子页面 — 音色选择（系统 + 自建云端）+ 语速调节。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';

class TtsSettingsPage extends ConsumerStatefulWidget {
  const TtsSettingsPage({super.key});

  @override
  ConsumerState<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

class _TtsSettingsPageState extends ConsumerState<TtsSettingsPage> {
  late final TtsService _tts;
  List<Map<String, String>>? _voices;
  Map<String, String>? _selectedVoice;
  late double _speed;
  bool _loading = true;
  String? _loadError;

  // ====== 云端朗读（自建 Worker 合成） ======
  bool _workerVerified = false;
  bool _cloudEnabled = false;
  String _cloudVoice = kDefaultWorkerVoice;

  /// 「保存并验证」/ 试听进行中。
  bool _cloudBusy = false;

  /// 修改模式：已验证时重新展开输入表单。
  bool _editingConfig = false;

  /// 验证失败的行内提示（具体原因），下次保存时清除。
  String? _verifyError;

  /// 动态音色目录；null 表示尚未加载。
  List<WorkerTtsVoice>? _cloudVoices;
  bool _cloudVoicesLoading = false;

  /// 拉取失败标志：展示内置精选 + 提示。
  bool _cloudVoicesFailed = false;

  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  bool _obscureApiKey = true;

  static const _previewText = '床前明月光，疑是地上霜。';

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    _selectedVoice = settingsRepo.ttsVoice;
    _speed = settingsRepo.ttsSpeed;
    _cloudEnabled = settingsRepo.ttsCloudEnabled;
    _cloudVoice = settingsRepo.ttsCloudVoice;
    _baseUrlController =
        TextEditingController(text: settingsRepo.ttsCloudBaseUrl);
    _apiKeyController = TextEditingController();
    _loadVoices();
    _loadVerification();
  }

  Future<void> _loadVerification() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    try {
      final verified = await settingsRepo.isWorkerTtsVerified();
      // 回填已保存的 API Key（安全存储，与 ASR 页回填模式一致）。
      final config = await settingsRepo.readWorkerTtsConfig();
      if (!mounted) return;
      setState(() => _workerVerified = verified);
      final savedKey = config?.apiKey ?? '';
      if (savedKey.isNotEmpty) {
        _apiKeyController.text = savedKey;
      }
      if (verified && _cloudEnabled) {
        _loadCloudVoices();
      }
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '读取自建服务验证状态失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _workerVerified = false);
    }
  }

  Future<void> _loadVoices() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final voices = await _tts.getChineseVoices();
      if (mounted) {
        setState(() {
          _voices = voices;
          _loading = false;
        });
      }
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '加载系统音色失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _voices = const [];
          _loading = false;
          _loadError = '音色加载失败，请检查系统语音服务';
        });
      }
    }
  }

  // ====== 系统音色 ======

  Future<void> _selectVoice(Map<String, String>? voice) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await _tts.stop();
      await _tts.setVoice(voice);
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '保存 TTS 音色失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('音色设置失败，请稍后重试')),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _selectedVoice = voice);
    }

    try {
      await _tts.preview(_previewText);
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        'TTS 音色试听失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('音色已保存，但试听失败')),
        );
      }
    }
  }

  Future<void> _onSpeedChanged(double speed) async {
    setState(() => _speed = speed);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.setTtsSpeed(speed);
  }

  // ====== 云端朗读（自建 Worker 合成） ======

  Future<void> _onCloudToggle(bool enabled) async {
    setState(() => _cloudEnabled = enabled);
    await ref.read(settingsRepositoryProvider).setTtsCloudEnabled(enabled);
    if (enabled && _cloudVoices == null && !_cloudVoicesLoading) {
      _loadCloudVoices();
    }
  }

  /// 拉取动态音色目录；失败回退内置精选并提示。
  Future<void> _loadCloudVoices() async {
    if (_cloudVoicesLoading) return;
    setState(() {
      _cloudVoicesLoading = true;
      _cloudVoicesFailed = false;
    });
    try {
      final voices = await _tts.listCloudVoices();
      if (!mounted) return;
      setState(() {
        _cloudVoices = voices;
        _cloudVoicesLoading = false;
      });
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '获取在线音色失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _cloudVoices = kWorkerFallbackVoices;
        _cloudVoicesLoading = false;
        _cloudVoicesFailed = true;
      });
    }
  }

  /// 保存并验证：先零成本探测，通过后才持久化并标记已验证。
  Future<void> _onSaveAndVerify() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      setState(() => _verifyError = '服务地址与 API Key 均需填写');
      return;
    }

    setState(() {
      _cloudBusy = true;
      _verifyError = null;
    });
    try {
      // 先验证后落盘：无效 Key 不写入安全存储。
      final config = WorkerTtsConfig(
        base: WorkerTtsClient.normalizeBaseUrl(baseUrl),
        apiKey: apiKey,
      );
      await _tts.verifyCloud(config);
      await settingsRepo.saveWorkerTtsConfig(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      await settingsRepo.markWorkerTtsVerified();
      if (mounted) {
        setState(() {
          _workerVerified = true;
          _editingConfig = false;
        });
        AppLogger.d('自建语音服务验证成功', tag: 'TtsSettings');
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _verifyError = error.message);
    } on WorkerTtsException catch (error) {
      if (mounted) setState(() => _verifyError = error.message);
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '自建语音服务保存或验证失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _verifyError = '保存或验证失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  /// 删除配置（确认对话框 → 删 Key + 指纹 + 设置并关闭云端开关）。
  Future<void> _confirmDeleteConfig() async {
    final scaffold = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除服务配置？'),
        content: const Text('将删除已保存的服务地址与 API Key，并关闭云端朗读。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final settingsRepo = ref.read(settingsRepositoryProvider);
    try {
      await settingsRepo.deleteWorkerTtsConfig();
      if (!mounted) return;
      setState(() {
        _workerVerified = false;
        _cloudEnabled = false;
        _editingConfig = false;
        _verifyError = null;
        _cloudVoices = null;
        _cloudVoicesFailed = false;
      });
      // 输入框回到默认地址，清除 Key 明文。
      _baseUrlController.text = settingsRepo.ttsCloudBaseUrl;
      _apiKeyController.clear();
      AppLogger.d('自建语音服务配置已删除', tag: 'TtsSettings');
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '删除自建语音服务配置失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('配置删除失败，请稍后重试')),
        );
      }
    }
  }

  /// 选择云端音色：持久化 voice + 最佳风格，随后试听（不回退，展示具体原因）。
  Future<void> _selectCloudVoice(WorkerTtsVoice voice) async {
    if (_cloudBusy) return;
    setState(() => _cloudBusy = true);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await settingsRepo.setTtsCloudVoice(voice.shortName);
      await settingsRepo.setTtsCloudStyle(voice.bestStyle);
      if (mounted) setState(() => _cloudVoice = voice.shortName);
      await _tts.stop();
      await _tts.previewCloud(_previewText);
    } on WorkerTtsException catch (error) {
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '云端音色试听失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('试听失败，请检查网络后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  @override
  void dispose() {
    // 离开页面停止试听
    unawaited(
      _tts.stop().onError(
            (error, stackTrace) => AppLogger.e(
              '退出音频设置页时停止试听失败',
              tag: 'TtsSettings',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
    );
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// locale → 友好标签。
  static String _localeLabel(String locale) {
    if (locale.startsWith('zh-CN') || locale == 'zh_CN') return '普通话';
    if (locale.startsWith('zh-TW') || locale == 'zh_TW') return '台湾';
    if (locale.startsWith('zh-HK') || locale == 'zh_HK') return '粤语';
    if (locale.startsWith('zh')) return '中文';
    return locale;
  }

  /// 将原始 voice name 转为友好显示名。
  ///
  /// Android 上 name 可能只是 "zh"，需要映射为可读名称。
  /// 去重后如果只有一个音色，显示为「中文语音」即可。
  static String _voiceDisplayName(String name, String locale, int index) {
    // 如果 name 是有意义的（不是纯 locale code），直接用
    final lower = name.toLowerCase().replaceAll(RegExp(r'[-_]'), '');
    final isLocaleCode = lower == 'zh' ||
        lower == 'zhcn' ||
        lower == 'zhtw' ||
        lower == 'zhhk' ||
        lower.isEmpty;

    if (!isLocaleCode) return name;

    // name 只是 locale code，生成友好名称
    final label = _localeLabel(locale);
    if (index == 0) return '$label语音';
    return '$label语音 ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('音频设置')),
      body: SafeArea(
        child: AnimatedPageBody(
          children: [
            // ====== 语速调节 ======
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.speed,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Text(
                        '语速调节',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Row(
                    children: [
                      Text(
                        '慢',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _speed,
                          min: 0.1,
                          max: 1.0,
                          divisions: 9,
                          label: _speed.toStringAsFixed(1),
                          onChanged: _onSpeedChanged,
                        ),
                      ),
                      Text(
                        '快',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Center(
                    child: Text(
                      '当前语速：${_speed.toStringAsFixed(1)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: SpacingTokens.lg),

            // ====== 云端朗读音色（自建 Worker 合成） ======
            _buildCloudCard(theme),

            const SizedBox(height: SpacingTokens.lg),

            // ====== 系统音色（离线可用） ======
            Row(
              children: [
                Icon(
                  Icons.record_voice_over_outlined,
                  size: 20,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: SpacingTokens.sm),
                Text(
                  '系统音色（离线可用）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '点击试听',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.sm),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(SpacingTokens.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              Padding(
                padding: const EdgeInsets.all(SpacingTokens.xl),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.record_voice_over_outlined,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: SpacingTokens.sm),
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.md),
                      OutlinedButton.icon(
                        onPressed: _loadVoices,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新加载'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // 系统默认
              _buildVoiceTile(
                theme: theme,
                title: '系统默认',
                subtitle: '使用系统默认中文语音',
                icon: Icons.auto_awesome,
                isSelected: _selectedVoice == null,
                onTap: () => _selectVoice(null),
              ),

              if (_voices!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(SpacingTokens.xl),
                  child: Center(
                    child: Text(
                      '未找到中文语音\n请在系统设置中下载中文语音包',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ..._voices!.asMap().entries.map((entry) {
                  final index = entry.key;
                  final voice = entry.value;
                  final isSelected = _selectedVoice != null &&
                      _selectedVoice!['name'] == voice['name'] &&
                      _selectedVoice!['locale'] == voice['locale'];
                  final name = voice['name'] ?? '';
                  final locale = voice['locale'] ?? '';
                  return _buildVoiceTile(
                    theme: theme,
                    title: _voiceDisplayName(name, locale, index),
                    subtitle: _localeLabel(locale),
                    icon: Icons.record_voice_over,
                    isSelected: isSelected,
                    onTap: () => _selectVoice(voice),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  /// 云端朗读音色卡片：未验证时配置表单；已验证时连接状态 + 开关 + 音色目录。
  Widget _buildCloudCard(ThemeData theme) {
    final showForm = !_workerVerified || _editingConfig;
    final canEnable = _workerVerified && !_cloudBusy;
    final host = Uri.tryParse(_baseUrlController.text.trim())?.host ??
        kDefaultWorkerBaseUrl;

    return ColoredCard(
      color: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: Text(
                  '云端朗读音色（自建服务）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                value: _cloudEnabled,
                onChanged: canEnable ? _onCloudToggle : null,
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.xs),
          if (showForm) ...[
            Text(
              _workerVerified
                  ? '修改服务地址或 API Key 后需重新验证'
                  : '填写自建语音服务地址与 API Key，验证通过后可开启云端朗读',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            TextField(
              controller: _baseUrlController,
              enabled: !_cloudBusy,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '服务地址',
                prefixIcon: Icon(Icons.language_outlined),
                hintText: kDefaultWorkerBaseUrl,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            TextField(
              controller: _apiKeyController,
              enabled: !_cloudBusy,
              obscureText: _obscureApiKey,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'API Key',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  onPressed: _cloudBusy
                      ? null
                      : () => setState(() => _obscureApiKey = !_obscureApiKey),
                  icon: Icon(
                    _obscureApiKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _obscureApiKey ? '显示密钥' : '隐藏密钥',
                ),
              ),
            ),
            if (_verifyError != null) ...[
              const SizedBox(height: SpacingTokens.sm),
              Text(
                _verifyError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: SpacingTokens.sm),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _cloudBusy ? null : _onSaveAndVerify,
                  icon: _cloudBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_done_outlined),
                  label: const Text('保存并验证'),
                ),
                if (_workerVerified) ...[
                  const SizedBox(width: SpacingTokens.md),
                  TextButton(
                    onPressed: _cloudBusy
                        ? null
                        : () => setState(() => _editingConfig = false),
                    child: const Text('取消'),
                  ),
                ],
              ],
            ),
          ] else ...[
            Text(
              '已连接 · $host',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              _cloudEnabled ? '朗读使用云端自然音色，失败自动回退系统音色' : '开启后朗读使用更自然的云端音色',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _cloudBusy
                      ? null
                      : () => setState(() => _editingConfig = true),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('修改'),
                ),
                const SizedBox(width: SpacingTokens.md),
                TextButton.icon(
                  onPressed: _cloudBusy ? null : _confirmDeleteConfig,
                  icon: const Icon(Icons.delete_outlined),
                  label: const Text('删除配置'),
                ),
              ],
            ),
            if (_cloudEnabled) ..._buildCloudVoiceDirectory(theme),
          ],
        ],
      ),
    );
  }

  /// 动态音色目录：标准 Neural / DragonHD 高清分组，trailing 试听即选择。
  List<Widget> _buildCloudVoiceDirectory(ThemeData theme) {
    if (_cloudVoicesLoading) {
      return const [
        SizedBox(height: SpacingTokens.sm),
        Center(child: CircularProgressIndicator()),
      ];
    }
    final voices = _cloudVoices;
    if (voices == null || voices.isEmpty) {
      return const [];
    }

    final standard = voices.where((voice) => !voice.isDragonHd).toList()
      ..sort((a, b) => a.localName.compareTo(b.localName));
    final dragonHd = voices.where((voice) => voice.isDragonHd).toList()
      ..sort((a, b) => a.localName.compareTo(b.localName));

    return [
      if (_cloudVoicesFailed)
        Padding(
          padding: const EdgeInsets.only(top: SpacingTokens.xs),
          child: Text(
            '在线音色获取失败，已展示内置精选',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      const SizedBox(height: SpacingTokens.sm),
      Text(
        '标准音色（Neural）',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      ...standard.map((voice) => _buildCloudVoiceTile(theme, voice)),
      if (dragonHd.isNotEmpty) ...[
        const SizedBox(height: SpacingTokens.sm),
        Text(
          '高清音色（DragonHD）',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        ...dragonHd.map((voice) => _buildCloudVoiceTile(theme, voice)),
      ],
    ];
  }

  Widget _buildCloudVoiceTile(ThemeData theme, WorkerTtsVoice voice) {
    final isSelected = voice.shortName == _cloudVoice;
    final subtitle =
        '${workerGenderLabel(voice.gender)} · ${workerStyleLabel(voice.bestStyle)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
      child: AppTile(
        icon: isSelected ? Icons.check_circle : Icons.graphic_eq,
        iconColor:
            isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
        title: voice.localName,
        subtitle: subtitle,
        // AppTile 在 trailing 非空时忽略 onTap，交互由试听按钮承担。
        trailing: _cloudBusy && isSelected
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: Icon(
                  Icons.play_circle_outline,
                  color: theme.colorScheme.primary,
                ),
                tooltip: '试听',
                onPressed: _cloudBusy ? null : () => _selectCloudVoice(voice),
              ),
      ),
    );
  }

  Widget _buildVoiceTile({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
      child: AppTile(
        icon: isSelected ? Icons.check_circle : icon,
        iconColor:
            isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
        title: title,
        subtitle: subtitle,
        trailing: IconButton(
          icon: Icon(
            Icons.play_circle_outline,
            color: theme.colorScheme.primary,
          ),
          tooltip: '试听',
          onPressed: onTap,
        ),
        onTap: onTap,
      ),
    );
  }
}
