// lib/features/profile/tts_settings_page.dart
//
// 层级：features/profile
// 职责：TTS 音频设置子页面 — 音色选择 + 语速调节。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';

class TtsSettingsPage extends ConsumerStatefulWidget {
  const TtsSettingsPage({super.key});

  @override
  ConsumerState<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

class _TtsSettingsPageState extends ConsumerState<TtsSettingsPage> {
  List<Map<String, String>>? _voices;
  Map<String, String>? _selectedVoice;
  late double _speed;
  bool _loading = true;

  static const _previewText = '床前明月光，疑是地上霜。';

  @override
  void initState() {
    super.initState();
    final settingsRepo = ref.read(settingsRepositoryProvider);
    _selectedVoice = settingsRepo.ttsVoice;
    _speed = settingsRepo.ttsSpeed;
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    final tts = ref.read(ttsServiceProvider);
    final voices = await tts.getChineseVoices();
    if (mounted) {
      setState(() {
        _voices = voices;
        _loading = false;
      });
    }
  }

  Future<void> _previewVoice(Map<String, String>? voice) async {
    final tts = ref.read(ttsServiceProvider);
    await tts.stop();
    // 临时应用选中的音色试听
    await tts.setVoice(voice);
    await tts.preview(_previewText);
  }

  Future<void> _onSpeedChanged(double speed) async {
    setState(() => _speed = speed);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.setTtsSpeed(speed);
    ref.invalidate(settingsRepositoryProvider);
  }

  void _selectVoice(Map<String, String>? voice) {
    setState(() => _selectedVoice = voice);
    final tts = ref.read(ttsServiceProvider);
    tts.setVoice(voice);
    ref.invalidate(settingsRepositoryProvider);
    ref.invalidate(ttsServiceProvider);
    _previewVoice(voice);
  }

  @override
  void dispose() {
    // 离开页面停止试听
    ref.read(ttsServiceProvider).stop();
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
        child: ListView(
          padding: const EdgeInsets.all(SpacingTokens.md),
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

            // ====== 音色选择 ======
            Row(
              children: [
                Icon(
                  Icons.record_voice_over_outlined,
                  size: 20,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: SpacingTokens.sm),
                Text(
                  '音色选择',
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
